from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, field_validator, model_validator


class SolicitudRegistro(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    full_name: str = Field(min_length=2, max_length=120)


class SolicitudInicioSesion(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)

    @field_validator("email", mode="before")
    @classmethod
    def resolver_alias(cls, valor: Any) -> Any:
        from app.core.config import obtener_configuracion

        if isinstance(valor, str):
            valor = valor.strip()
            aliases = obtener_configuracion().login_aliases
            return aliases.get(valor.lower(), valor)
        return valor


class SolicitudRenovacion(BaseModel):
    refresh_token: str


class RespuestaAutenticacion(BaseModel):
    access_token: str | None = None
    refresh_token: str | None = None
    expires_in: int | None = None
    token_type: str = "bearer"
    requires_email_confirmation: bool = False


class PerfilUsuario(BaseModel):
    id: UUID
    email: EmailStr
    full_name: str | None = None
    role: str = "user"


class SolicitudPregunta(BaseModel):
    question: str = Field(min_length=3, max_length=2000)
    conversation_id: UUID | None = None

    @field_validator("question")
    @classmethod
    def clean_question(cls, value: str) -> str:
        return " ".join(value.split())


class SolicitudConversacion(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=120)
    max_messages: int | None = Field(default=None, ge=1, le=100)

    @field_validator("title")
    @classmethod
    def clean_title(cls, value: str | None) -> str | None:
        return " ".join(value.split()) if value else None


class SolicitudActualizarConversacion(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=120)
    status: str | None = Field(default=None, pattern="^(active|closed)$")

    @field_validator("title")
    @classmethod
    def clean_title(cls, value: str | None) -> str | None:
        return " ".join(value.split()) if value else None

    @model_validator(mode="after")
    def al_menos_un_campo(self) -> "SolicitudActualizarConversacion":
        if self.title is None and self.status is None:
            raise ValueError("Indica un titulo o un estado")
        return self


class RespuestaConversacion(BaseModel):
    id: UUID
    title: str | None = None
    message_count: int
    max_messages: int
    status: str
    created_at: datetime | None = None
    updated_at: datetime | None = None


class FuenteRespuesta(BaseModel):
    chunk_id: str
    document: str
    title: str
    page_start: int | None = None
    page_end: int | None = None
    similarity: float


class RespuestaPregunta(BaseModel):
    question_id: UUID
    conversation_id: UUID | None = None
    answer: str
    # Subconjunto acotado de Markdown: parrafos, listas con "- ", listas "1. " y **negrita**.
    # El cliente debe renderizarlo; la API nunca devuelve HTML.
    answer_format: str = "markdown"
    sources: list[FuenteRespuesta]
    latency_ms: int
    model: str


class MensajeConversacion(BaseModel):
    id: UUID
    question: str
    answer: str | None = None
    answer_format: str = "markdown"
    sources: list[FuenteRespuesta] = Field(default_factory=list)
    status: str
    latency_ms: int | None = None
    created_at: datetime


class SolicitudActualizarPerfil(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)

    @field_validator("full_name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        limpio = " ".join(value.split())
        if len(limpio) < 2:
            raise ValueError("El nombre es demasiado corto")
        return limpio


class SolicitudCambioContrasena(BaseModel):
    current_password: str = Field(min_length=8, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)

    @model_validator(mode="after")
    def contrasena_distinta(self) -> "SolicitudCambioContrasena":
        if self.current_password == self.new_password:
            raise ValueError("La contrasena nueva debe ser distinta de la actual")
        return self


class SolicitudValoracion(BaseModel):
    rating: int = Field(ge=-1, le=1)
    comment: str | None = Field(default=None, max_length=1000)


class ChunkEntrada(BaseModel):
    schema_version: str = "1.0"
    document_id: str = Field(min_length=4, max_length=128)
    chunk_id: str = Field(min_length=4, max_length=180)
    source_file: str = Field(min_length=1, max_length=255)
    title: str = Field(min_length=1, max_length=500)
    page_start: int | None = Field(default=None, ge=1)
    page_end: int | None = Field(default=None, ge=1)
    text: str = Field(min_length=10)
    embedding_text: str | None = None
    estimated_tokens: int | None = Field(default=None, ge=1)
    quality_score: int | None = Field(default=None, ge=0, le=100)
    validation_warnings: list[str] = Field(default_factory=list)
    metadata: dict[str, Any] = Field(default_factory=dict)

    @field_validator("embedding_text", mode="before")
    @classmethod
    def empty_embedding_text(cls, value: object) -> object:
        return value or None

    def texto_para_embedding(self) -> str:
        return self.embedding_text or f"title: {self.title} | text: {self.text}"


class UsuarioAdministracion(BaseModel):
    id: UUID
    email: EmailStr | None = None
    full_name: str | None = None
    role: str = "user"
    is_active: bool = True
    created_at: datetime | None = None
    last_sign_in_at: datetime | None = None
    preguntas: int = 0
    ultima_pregunta: datetime | None = None
    activo: bool = False
    votos_positivos: int = 0
    votos_negativos: int = 0


class ActualizacionUsuario(BaseModel):
    role: str | None = Field(default=None, pattern="^(user|admin)$")
    is_active: bool | None = None

    @model_validator(mode="after")
    def al_menos_un_campo(self) -> "ActualizacionUsuario":
        if self.role is None and self.is_active is None:
            raise ValueError("Indica un rol o el estado de la cuenta")
        return self


class ActualizacionAlerta(BaseModel):
    status: str = Field(pattern="^(open|acknowledged|resolved)$")


class RespuestaEstado(BaseModel):
    status: str
    app: str
    environment: str
    generation_model: str
    embedding_model: str
    # Estado de cada dependencia: {"supabase": "ok", "gemini": "error"}
    checks: dict[str, str] = Field(default_factory=dict)
    timestamp: datetime
