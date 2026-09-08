from __future__ import annotations

import importlib.util
import shutil
import sys
from pathlib import Path
from types import SimpleNamespace
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.core.config import DIRECTORIO_API
from app.core.security import obtener_usuario_actual
from app.main import app
from app.services.rag_service import LimiteDeUso, obtener_servicio_rag
from app.services.supabase_service import UsuarioAutenticado, obtener_supabase

USUARIO = UUID("10000000-0000-0000-0000-000000000001")
CONVERSACION = UUID("20000000-0000-0000-0000-000000000001")
PREGUNTA = UUID("30000000-0000-0000-0000-000000000001")


@pytest.fixture
def cliente():
    app.dependency_overrides[obtener_supabase] = lambda: SimpleNamespace()
    with TestClient(app) as cliente:
        yield cliente
    app.dependency_overrides.clear()


def test_configuracion_sigue_al_proyecto_tras_moverlo(tmp_path, monkeypatch):
    """Reproduce un traslado con espacios y un CWD completamente distinto."""
    destino = tmp_path / "proyecto trasladado" / "plataforma_rag"
    archivo = destino / "app" / "core" / "config.py"
    archivo.parent.mkdir(parents=True)
    shutil.copy2(DIRECTORIO_API / "app" / "core" / "config.py", archivo)
    variables = {"SUPABASE_URL": "https://trasladado.supabase.co", "SUPABASE_ANON_KEY": "anon", "SUPABASE_SERVICE_ROLE_KEY": "servicio", "GEMINI_API_KEY": "gemini"}
    (destino / ".env").write_text("\n".join(f"{clave}={valor}" for clave, valor in variables.items()), encoding="utf-8")
    for clave in variables:
        monkeypatch.delenv(clave, raising=False)
    monkeypatch.chdir(tmp_path)
    especificacion = importlib.util.spec_from_file_location("configuracion_trasladada", archivo)
    modulo = importlib.util.module_from_spec(especificacion)
    monkeypatch.setitem(sys.modules, especificacion.name, modulo)
    especificacion.loader.exec_module(modulo)
    configuracion = modulo.Configuracion()
    assert configuracion.supabase_url == variables["SUPABASE_URL"]
    assert configuracion.web_directory == destino.parent / "web" / "public"


@pytest.mark.parametrize("ruta", ["/", "/admin", "/docs", "/web/", "/web/estilos.css", "/web/favicon.svg", "/web/js/aplicacion.js", "/web/js/cliente_api.js", "/web/js/vistas.js", "/web/js/herramientas.js"])
def test_recursos_responden_desde_otra_carpeta(cliente, tmp_path, monkeypatch, ruta):
    monkeypatch.chdir(tmp_path)
    respuesta = cliente.get(ruta)
    assert respuesta.status_code == 200
    assert respuesta.headers["X-Request-ID"]


def test_configuracion_web_no_expone_secretos(cliente):
    assert cliente.get("/web/configuracion.json").json() == {"url_api": "/api/v1"}


@pytest.mark.parametrize("ruta", ["/web/.env", "/web/package.json", "/web/tests/cliente_api.test.js", "/web/%2e%2e/plataforma_rag/.env"])
def test_solo_se_publica_el_directorio_publico(cliente, ruta):
    assert cliente.get(ruta).status_code == 404


@pytest.mark.parametrize("ruta", ["/api/v1/auth/me", "/api/v1/chat/conversations", "/api/v1/admin/overview"])
def test_rutas_privadas_exigen_sesion(cliente, ruta):
    assert cliente.get(ruta).status_code == 401


def test_rol_usuario_no_puede_acceder_a_administracion(cliente):
    app.dependency_overrides[obtener_usuario_actual] = lambda: UsuarioAutenticado(USUARIO, "alumno@example.com", "user", "Alumno")
    assert cliente.get("/api/v1/admin/overview").status_code == 403


def test_contrato_de_pregunta_con_fuentes(cliente):
    app.dependency_overrides[obtener_usuario_actual] = lambda: UsuarioAutenticado(USUARIO, "alumno@example.com", "user", "Alumno")

    def preguntar(usuario, pregunta, conversacion):
        assert usuario == USUARIO and conversacion == CONVERSACION
        assert pregunta == "Qué documentos necesito?"
        return SimpleNamespace(question_id=PREGUNTA, conversation_id=conversacion, answer="Presenta tu **DNI**.", sources=[{"chunk_id": "manual-1", "document": "manual.pdf", "title": "Requisitos", "page_start": 1, "page_end": 1, "similarity": .9}], latency_ms=20, tareas=[])

    app.dependency_overrides[obtener_servicio_rag] = lambda: SimpleNamespace(preguntar=preguntar)
    respuesta = cliente.post("/api/v1/chat/ask", json={"question": "Qué documentos necesito?", "conversation_id": str(CONVERSACION)})
    assert respuesta.status_code == 200
    assert respuesta.json()["answer_format"] == "markdown"
    assert respuesta.json()["sources"][0]["document"] == "manual.pdf"


def test_limite_de_preguntas_devuelve_429(cliente):
    app.dependency_overrides[obtener_usuario_actual] = lambda: UsuarioAutenticado(USUARIO, "alumno@example.com", "user")

    def preguntar(*args):
        raise LimiteDeUso("Alcanzaste el limite")

    app.dependency_overrides[obtener_servicio_rag] = lambda: SimpleNamespace(preguntar=preguntar)
    respuesta = cliente.post("/api/v1/chat/ask", json={"question": "Cómo me matriculo?"})
    assert respuesta.status_code == 429
    assert respuesta.headers["retry-after"] == "600"
