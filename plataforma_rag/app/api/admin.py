from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, File, HTTPException, Query, UploadFile
from starlette.concurrency import run_in_threadpool

from app.core.config import obtener_configuracion
from app.core.security import requerir_administrador
from app.models.schemas import ActualizacionAlerta, ActualizacionUsuario, UsuarioAdministracion
from app.services.analytics_service import ServicioAnalitica, obtener_servicio_analitica
from app.services.ingestion_service import ServicioIngestion, obtener_servicio_ingestion
from app.services.supabase_service import ServicioSupabase, UsuarioAutenticado, obtener_supabase


router = APIRouter(prefix="/admin", tags=["Administracion"])


@router.get("/overview")
async def overview(
    days: int = Query(default=30, ge=1, le=365),
    _user: UsuarioAutenticado = Depends(requerir_administrador),
    analytics: ServicioAnalitica = Depends(obtener_servicio_analitica),
) -> dict:
    return await run_in_threadpool(analytics.resumen, days)


@router.post("/documents/upload", status_code=202)
async def upload_document(
    tareas: BackgroundTasks,
    file: UploadFile = File(...),
    user: UsuarioAutenticado = Depends(requerir_administrador),
    ingestion: ServicioIngestion = Depends(obtener_servicio_ingestion),
) -> dict:
    """Valida el archivo y responde al instante; los embeddings se generan aparte.

    Antes esta ruta hacia una llamada a Gemini por chunk dentro de la peticion:
    con un documento grande se agotaba el tiempo del proxy y la carga se perdia.
    Ahora devuelve 202 con un job_id y el panel consulta el progreso.
    """
    settings = obtener_configuracion()
    limite = settings.max_upload_mb * 1024 * 1024
    data = await file.read(limite + 1)
    if len(data) > limite:
        raise HTTPException(status_code=413, detail=f"El archivo supera {settings.max_upload_mb} MB")

    try:
        trabajo = await run_in_threadpool(
            ingestion.preparar, data, file.filename or "chunks.jsonl", user.id
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=503, detail="No se pudo registrar la carga") from exc

    tareas.add_task(ingestion.procesar, trabajo, user.id)
    return {
        "job_id": str(trabajo.job_id),
        "document_id": trabajo.document_id,
        "filename": trabajo.filename,
        "chunks_total": len(trabajo.chunks),
        "status": "processing",
    }


@router.get("/jobs")
def jobs(
    limit: int = Query(default=20, ge=1, le=200),
    _user: UsuarioAutenticado = Depends(requerir_administrador),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> list[dict]:
    return (
        supabase.admin.table("ingestion_jobs")
        .select("*")
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
        .data
        or []
    )


@router.get("/jobs/{job_id}")
def job(
    job_id: UUID,
    _user: UsuarioAutenticado = Depends(requerir_administrador),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> dict:
    respuesta = (
        supabase.admin.table("ingestion_jobs")
        .select("*")
        .eq("id", str(job_id))
        .limit(1)
        .execute()
    )
    if not respuesta.data:
        raise HTTPException(status_code=404, detail="Carga no encontrada")
    return respuesta.data[0]


@router.get("/documents")
def documents(
    _user: UsuarioAutenticado = Depends(requerir_administrador),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> list[dict]:
    response = (
        supabase.admin.table("documents")
        .select("id,source_document_id,filename,title,status,chunk_count,created_at,updated_at")
        .order("created_at", desc=True)
        .limit(500)
        .execute()
    )
    return response.data or []


@router.get("/users", response_model=list[UsuarioAdministracion])
def users(
    minutes: int = Query(default=15, ge=1, le=1440, description="Ventana para considerar activo"),
    limit: int = Query(default=500, ge=1, le=2000),
    _user: UsuarioAutenticado = Depends(requerir_administrador),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> list[UsuarioAdministracion]:
    """Quien usa el asistente, cuando entro por ultima vez y cuanto pregunta.

    "Activo" no significa conectado: una API REST no mantiene sesion abierta,
    asi que lo observable es haber preguntado algo dentro de `minutes`.
    """
    try:
        filas = supabase.usuarios_con_actividad(minutes, limit)
    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail="No se pudo leer la lista de usuarios. ¿Ejecutaste la migracion 005?",
        ) from exc
    return [UsuarioAdministracion(**fila) for fila in filas]


@router.patch("/users/{user_id}", response_model=UsuarioAdministracion)
def update_user(
    user_id: UUID,
    payload: ActualizacionUsuario,
    user: UsuarioAutenticado = Depends(requerir_administrador),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> UsuarioAdministracion:
    cambios = payload.model_dump(exclude_none=True)
    if user_id == user.id and (
        cambios.get("role") == "user" or cambios.get("is_active") is False
    ):
        raise HTTPException(
            status_code=409,
            detail="No puedes quitarte a ti mismo el rol de administrador ni desactivarte",
        )
    supabase.actualizar_usuario(user_id, cambios)
    _auditar(supabase, user, "user.update", str(user_id), cambios)
    actualizados = supabase.usuarios_con_actividad(15, 2000)
    for fila in actualizados:
        if str(fila.get("id")) == str(user_id):
            return UsuarioAdministracion(**fila)
    raise HTTPException(status_code=404, detail="Usuario no encontrado")


def _auditar(supabase, actor, accion: str, entidad: str, detalles: dict) -> None:
    supabase.admin.table("audit_logs").insert(
        {
            "user_id": str(actor.id),
            "action": accion,
            "entity_type": "user",
            "entity_id": entidad,
            "details": detalles,
        }
    ).execute()


def _correo_de(supabase, user_id: UUID) -> str:
    for fila in supabase.usuarios_con_actividad(15, 2000):
        if str(fila.get("id")) == str(user_id):
            correo = fila.get("email")
            if not correo:
                raise HTTPException(status_code=409, detail="El usuario no tiene correo registrado")
            return str(correo)
    raise HTTPException(status_code=404, detail="Usuario no encontrado")


@router.post("/users/{user_id}/reset-link")
def reset_link(
    user_id: UUID,
    user: UsuarioAutenticado = Depends(requerir_administrador),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> dict:
    """Enlace para que el estudiante elija su propia contrasena.

    Preferible a fijarsela: asi el administrador no llega a conocerla y no
    puede suplantarlo. El enlace se entrega por el canal que se quiera.
    """
    correo = _correo_de(supabase, user_id)
    try:
        enlace = supabase.enlace_de_recuperacion(correo)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=503, detail="Supabase no pudo generar el enlace de recuperacion"
        ) from exc
    _auditar(supabase, user, "user.reset_link", str(user_id), {"email": correo})
    return {"email": correo, "action_link": enlace}


@router.post("/users/{user_id}/temporary-password")
def temporary_password(
    user_id: UUID,
    user: UsuarioAutenticado = Depends(requerir_administrador),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> dict:
    """Contrasena aleatoria, para cuando el estudiante no puede entrar a su correo.

    Se devuelve una sola vez y no se guarda en ningun sitio. Queda registrado
    en auditoria quien la genero y para quien.
    """
    correo = _correo_de(supabase, user_id)
    try:
        nueva = supabase.asignar_contrasena_temporal(user_id)
    except Exception as exc:
        raise HTTPException(
            status_code=503, detail="Supabase rechazo el cambio de contrasena"
        ) from exc
    _auditar(supabase, user, "user.temporary_password", str(user_id), {"email": correo})
    return {"email": correo, "password": nueva}


@router.get("/chunks/{chunk_id}")
def chunk_detail(
    chunk_id: str,
    _user: UsuarioAutenticado = Depends(requerir_administrador),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> dict:
    """El texto exacto que se le paso al modelo como contexto.

    Sin esto, ante una respuesta rara no hay forma de saber si el problema fue
    la busqueda o la redaccion.
    """
    respuesta = (
        supabase.admin.table("chunks")
        .select("chunk_id,title,content,page_start,page_end,quality_score,estimated_tokens")
        .eq("chunk_id", chunk_id)
        .limit(1)
        .execute()
    )
    if not respuesta.data:
        raise HTTPException(status_code=404, detail="Fragmento no encontrado")
    return respuesta.data[0]


@router.get("/questions/{question_id}")
def question_detail(
    question_id: UUID,
    _user: UsuarioAutenticado = Depends(requerir_administrador),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> dict:
    """La respuesta completa y los fragmentos que la sustentaron.

    Sin esto no se podia auditar una queja del tipo "me respondio mal" sin
    entrar a la base de datos a mano.
    """
    respuesta = (
        supabase.admin.table("questions")
        .select("*, feedback(rating,comment,created_at)")
        .eq("id", str(question_id))
        .limit(1)
        .execute()
    )
    if not respuesta.data:
        raise HTTPException(status_code=404, detail="Pregunta no encontrada")
    return respuesta.data[0]


@router.get("/questions")
def questions(
    limit: int = Query(default=100, ge=1, le=1000),
    status_filter: str | None = Query(default=None, alias="status"),
    _user: UsuarioAutenticado = Depends(requerir_administrador),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> list[dict]:
    query = (
        supabase.admin.table("questions")
        .select("id,user_id,question,status,latency_ms,retrieval_ms,generation_ms,top_similarity,error_code,created_at, feedback(rating)")
        .order("created_at", desc=True)
        .limit(limit)
    )
    if status_filter:
        query = query.eq("status", status_filter)
    return query.execute().data or []


@router.get("/alerts")
def alerts(
    status_filter: str = Query(default="open", alias="status"),
    _user: UsuarioAutenticado = Depends(requerir_administrador),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> list[dict]:
    query = supabase.admin.table("alerts").select("*").order("created_at", desc=True).limit(500)
    if status_filter != "all":
        query = query.eq("status", status_filter)
    return query.execute().data or []


@router.patch("/alerts/{alert_id}")
def update_alert(
    alert_id: UUID,
    payload: ActualizacionAlerta,
    user: UsuarioAutenticado = Depends(requerir_administrador),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> dict:
    values: dict = {"status": payload.status}
    if payload.status == "resolved":
        values.update({"resolved_at": datetime.now(UTC).isoformat(), "resolved_by": str(user.id)})
    response = supabase.admin.table("alerts").update(values).eq("id", str(alert_id)).execute()
    if not response.data:
        raise HTTPException(status_code=404, detail="Alerta no encontrada")
    supabase.admin.table("audit_logs").insert(
        {
            "user_id": str(user.id),
            "action": "alert.update",
            "entity_type": "alert",
            "entity_id": str(alert_id),
            "details": {"status": payload.status},
        }
    ).execute()
    return response.data[0]


@router.get("/audit")
def audit(
    limit: int = Query(default=100, ge=1, le=1000),
    _user: UsuarioAutenticado = Depends(requerir_administrador),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> list[dict]:
    return (
        supabase.admin.table("audit_logs")
        .select("*")
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
        .data
        or []
    )
