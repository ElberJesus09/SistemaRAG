from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


DIRECTORIO_API = Path(__file__).resolve().parents[2]


class Configuracion(BaseSettings):
    # La configuración pertenece a la API, independientemente de dónde se ejecute.
    model_config = SettingsConfigDict(
        env_file=DIRECTORIO_API / ".env", env_file_encoding="utf-8", extra="ignore"
    )
    web_directory: Path = DIRECTORIO_API.parent / "web" / "public"

    app_name: str = "Plataforma RAG"
    app_env: str = "development"
    login_aliases: dict[str, str] = Field(default_factory=dict)
    api_prefix: str = "/api/v1"
    # Puertos habituales de "flutter run -d chrome --web-port ...". En produccion
    # deja solo el dominio real, o sirve la app web desde esta misma API.
    cors_origins: str = (
        "http://localhost:3000,http://localhost:8080,http://localhost:5000,"
        "http://127.0.0.1:3000,http://127.0.0.1:8080,http://127.0.0.1:5000"
    )

    supabase_url: str
    supabase_anon_key: str
    supabase_service_role_key: str
    gemini_api_key: str

    gemini_generation_model: str = "gemini-3.6-flash"
    gemini_embedding_model: str = "gemini-embedding-2"
    gemini_embedding_dimensions: int = 768
    max_upload_mb: int = 20
    retrieval_match_count: int = 6
    retrieval_threshold: float = 0.55
    slow_request_ms: int = 5000
    conversation_max_messages: int = 20
    conversation_memory_messages: int = 6

    # Autenticacion: cuantos segundos se reutiliza un perfil ya validado antes de
    # volver a preguntarle a Supabase. Evita dos viajes de red en cada peticion.
    # Un token revocado sigue siendo valido como maximo este tiempo.
    auth_cache_seconds: int = 300
    auth_cache_max_entries: int = 2048

    # Limite de preguntas por usuario y hora. 0 lo desactiva.
    ask_rate_limit_per_hour: int = 60

    # Ingesta: cada cuantos chunks se actualiza el progreso en la base de datos.
    ingestion_progress_every: int = 5

    log_level: str = "INFO"
    log_json: bool = False

    @property
    def lista_origenes(self) -> list[str]:
        return [item.strip() for item in self.cors_origins.split(",") if item.strip()]


@lru_cache
def obtener_configuracion() -> Configuracion:
    return Configuracion()
