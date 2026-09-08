from __future__ import annotations

import time
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

from fastapi import FastAPI, Query, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from starlette.concurrency import run_in_threadpool

from app.api import admin, auth, chat
from app.core.config import obtener_configuracion
from app.core.registro import configurar_logging, establecer_peticion, obtener_logger
from app.models.schemas import RespuestaEstado
from app.services.gemini_service import obtener_gemini
from app.services.supabase_service import obtener_supabase


settings = obtener_configuracion()
configurar_logging(settings.log_level, settings.log_json)
registro = obtener_logger("app.peticiones")

app = FastAPI(
    title=settings.app_name,
    version="1.1.0",
    description="API RAG para clientes web y móviles con Supabase y Gemini",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.lista_origenes,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
    expose_headers=["X-Request-ID", "X-Process-Time-Ms"],
)

static_dir = Path(__file__).resolve().parent / "static"
app.mount("/static", StaticFiles(directory=static_dir), name="static")
app.include_router(auth.router, prefix=settings.api_prefix)
app.include_router(chat.router, prefix=settings.api_prefix)
app.include_router(admin.router, prefix=settings.api_prefix)


@app.get("/web/configuracion.json", include_in_schema=False)
def configuracion_web() -> dict[str, str]:
    """Expone exclusivamente la ruta pública de la API, nunca credenciales."""
    return {"url_api": settings.api_prefix}


if settings.web_directory.is_dir():
    app.mount("/web", StaticFiles(directory=settings.web_directory, html=True), name="web")


@app.middleware("http")
async def request_context(request: Request, call_next):
    started = time.perf_counter()
    request_id = request.headers.get("X-Request-ID") or str(uuid4())
    establecer_peticion(request_id)
    try:
        response = await call_next(request)
    except Exception:
        duracion = round((time.perf_counter() - started) * 1000)
        registro.exception(
            "peticion fallida",
            extra={
                "metodo": request.method,
                "ruta": request.url.path,
                "ms": duracion,
            },
        )
        establecer_peticion(None)
        raise

    duracion = round((time.perf_counter() - started) * 1000)
    response.headers["X-Request-ID"] = request_id
    response.headers["X-Process-Time-Ms"] = str(duracion)

    if request.url.path not in {"/health", "/favicon.ico"} and not request.url.path.startswith("/static"):
        nivel = registro.warning if duracion >= settings.slow_request_ms else registro.info
        nivel(
            "peticion",
            extra={
                "metodo": request.method,
                "ruta": request.url.path,
                "estado": response.status_code,
                "ms": duracion,
            },
        )
    establecer_peticion(None)
    return response


@app.get("/", include_in_schema=False)
@app.get("/admin", include_in_schema=False)
def dashboard() -> FileResponse:
    return FileResponse(static_dir / "index.html")


@app.get("/health", response_model=RespuestaEstado, tags=["Sistema"])
async def estado(
    response: Response,
    full: bool = Query(default=False, description="Comprueba tambien Gemini"),
) -> RespuestaEstado:
    """Comprueba de verdad las dependencias, no solo que el proceso este vivo.

    Sin `full`, solo consulta Supabase (barato, apto para un balanceador).
    Con `full=true` gasta una llamada de embedding contra Gemini.
    """
    comprobaciones: dict[str, str] = {}

    try:
        await run_in_threadpool(obtener_supabase().comprobar_conexion)
        comprobaciones["supabase"] = "ok"
    except Exception as exc:
        comprobaciones["supabase"] = "error"
        registro.error("supabase no responde", extra={"detalle": str(exc)[:200]})

    if full:
        try:
            await run_in_threadpool(obtener_gemini().comprobar_conexion)
            comprobaciones["gemini"] = "ok"
        except Exception as exc:
            comprobaciones["gemini"] = "error"
            registro.error("gemini no responde", extra={"detalle": str(exc)[:200]})

    saludable = all(valor == "ok" for valor in comprobaciones.values())
    if not saludable:
        response.status_code = 503

    return RespuestaEstado(
        status="ok" if saludable else "degraded",
        app=settings.app_name,
        environment=settings.app_env,
        generation_model=settings.gemini_generation_model,
        embedding_model=settings.gemini_embedding_model,
        checks=comprobaciones,
        timestamp=datetime.now(UTC),
    )
