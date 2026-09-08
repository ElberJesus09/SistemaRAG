from __future__ import annotations

import json
import time
from datetime import UTC, datetime
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4

from pydantic import ValidationError

from app.core.config import obtener_configuracion
from app.core.registro import obtener_logger
from app.models.schemas import ChunkEntrada
from app.services.gemini_service import ServicioGemini, obtener_gemini
from app.services.supabase_service import ServicioSupabase, obtener_supabase


registro = obtener_logger(__name__)


@dataclass(frozen=True)
class ResultadoIngestion:
    job_id: UUID
    document_id: str
    filename: str
    chunks_received: int
    chunks_stored: int


@dataclass(frozen=True)
class TrabajoPreparado:
    """Lo que se sabe antes de empezar a generar embeddings."""

    job_id: UUID
    document_id: str
    filename: str
    chunks: list[ChunkEntrada]


def interpretar_archivo_chunks(data: bytes, filename: str) -> list[ChunkEntrada]:
    if not filename.lower().endswith((".jsonl", ".json")):
        raise ValueError("Solo se aceptan archivos .jsonl o .json")
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ValueError("El archivo debe usar codificacion UTF-8") from exc
    if not text.strip():
        raise ValueError("El archivo esta vacio")

    try:
        if filename.lower().endswith(".json"):
            parsed = json.loads(text)
            raw_items = parsed if isinstance(parsed, list) else parsed.get("chunks", [])
        else:
            raw_items = [json.loads(line) for line in text.splitlines() if line.strip()]
        chunks = [ChunkEntrada.model_validate(item) for item in raw_items]
    except (json.JSONDecodeError, ValidationError, AttributeError, TypeError) as exc:
        raise ValueError(f"Formato de chunks invalido: {exc}") from exc

    if not chunks:
        raise ValueError("No se encontraron chunks")
    document_ids = {chunk.document_id for chunk in chunks}
    source_files = {chunk.source_file for chunk in chunks}
    chunk_ids = [chunk.chunk_id for chunk in chunks]
    if len(document_ids) != 1 or len(source_files) != 1:
        raise ValueError("Cada carga debe contener chunks de un solo documento")
    if len(set(chunk_ids)) != len(chunk_ids):
        raise ValueError("El archivo contiene chunk_id duplicados")
    return chunks


class ServicioIngestion:
    def __init__(self) -> None:
        self.supabase: ServicioSupabase = obtener_supabase()
        self.gemini: ServicioGemini = obtener_gemini()

    def preparar(self, data: bytes, filename: str, user_id: UUID) -> TrabajoPreparado:
        """Valida el archivo y registra el trabajo. Rapido: corre dentro de la peticion.

        Los errores de formato se devuelven al administrador al instante; lo que
        tarda (un embedding por chunk) queda para `procesar`.
        """
        chunks = interpretar_archivo_chunks(data, filename)
        job_id = uuid4()
        source_file = chunks[0].source_file
        self.supabase.admin.table("ingestion_jobs").insert(
            {
                "id": str(job_id),
                "filename": source_file,
                "status": "processing",
                "created_by": str(user_id),
                "chunks_total": len(chunks),
                "chunks_processed": 0,
            }
        ).execute()
        registro.info(
            "ingesta encolada",
            extra={"job": str(job_id), "archivo": source_file, "chunks": len(chunks)},
        )
        return TrabajoPreparado(
            job_id=job_id,
            document_id=chunks[0].document_id,
            filename=source_file,
            chunks=chunks,
        )

    def procesar(self, trabajo: TrabajoPreparado, user_id: UUID) -> ResultadoIngestion:
        """Genera los embeddings. Se ejecuta en segundo plano, fuera de la peticion."""
        settings = obtener_configuracion()
        cada = max(1, settings.ingestion_progress_every)
        chunks = trabajo.chunks
        job_id = trabajo.job_id
        source_file = trabajo.filename
        comenzado = time.perf_counter()

        try:
            document_response = self.supabase.admin.table("documents").upsert(
                {
                    "source_document_id": trabajo.document_id,
                    "filename": source_file,
                    "title": Path(source_file).stem,
                    "status": "processing",
                    "created_by": str(user_id),
                    "metadata": {"schema_version": chunks[0].schema_version},
                },
                on_conflict="source_document_id",
            ).execute()
            if not document_response.data:
                raise RuntimeError("No se pudo crear el documento")
            database_document_id = document_response.data[0]["id"]

            stored = 0
            for indice, chunk in enumerate(chunks, start=1):
                vector = self.gemini.generar_embedding_documento(chunk.texto_para_embedding())
                metadata = dict(chunk.metadata)
                metadata["validation_warnings"] = chunk.validation_warnings
                self.supabase.admin.table("chunks").upsert(
                    {
                        "document_id": database_document_id,
                        "chunk_id": chunk.chunk_id,
                        "title": chunk.title,
                        "content": chunk.text,
                        "embedding_text": chunk.texto_para_embedding(),
                        "page_start": chunk.page_start,
                        "page_end": chunk.page_end,
                        "estimated_tokens": chunk.estimated_tokens,
                        "quality_score": chunk.quality_score,
                        "metadata": metadata,
                        "embedding": vector,
                    },
                    on_conflict="chunk_id",
                ).execute()
                stored += 1
                # Una escritura por chunk multiplicaba por dos las idas a la base:
                # basta con avisar del progreso cada `cada` chunks y al terminar.
                if indice % cada == 0 or indice == len(chunks):
                    self.supabase.admin.table("ingestion_jobs").update(
                        {"chunks_processed": stored}
                    ).eq("id", str(job_id)).execute()

            self.supabase.admin.table("documents").update(
                {"status": "active", "chunk_count": stored}
            ).eq("id", database_document_id).execute()
            self.supabase.admin.table("ingestion_jobs").update(
                {
                    "status": "completed",
                    "chunks_processed": stored,
                    "completed_at": datetime.now(UTC).isoformat(),
                }
            ).eq("id", str(job_id)).execute()
            self._audit(user_id, "document.ingest", "document", database_document_id, {"chunks": stored})
            registro.info(
                "ingesta completada",
                extra={
                    "job": str(job_id),
                    "archivo": source_file,
                    "chunks": stored,
                    "segundos": round(time.perf_counter() - comenzado, 1),
                },
            )
            return ResultadoIngestion(job_id, trabajo.document_id, source_file, len(chunks), stored)
        except Exception as exc:
            registro.exception(
                "fallo la ingesta", extra={"job": str(job_id), "archivo": source_file}
            )
            self.supabase.admin.table("ingestion_jobs").update(
                {
                    "status": "failed",
                    "error_message": str(exc)[:1000],
                    "completed_at": datetime.now(UTC).isoformat(),
                }
            ).eq("id", str(job_id)).execute()
            self.supabase.admin.table("alerts").insert(
                {
                    "type": "ingestion_error",
                    "severity": "error",
                    "title": "Fallo al cargar documento",
                    "message": f"{source_file}: {str(exc)[:500]}",
                    "metadata": {"job_id": str(job_id)},
                }
            ).execute()
            raise

    def _audit(self, user_id: UUID, action: str, entity_type: str, entity_id: str, details: dict[str, Any]) -> None:
        self.supabase.admin.table("audit_logs").insert(
            {
                "user_id": str(user_id),
                "action": action,
                "entity_type": entity_type,
                "entity_id": entity_id,
                "details": details,
            }
        ).execute()


@lru_cache
def obtener_servicio_ingestion() -> ServicioIngestion:
    return ServicioIngestion()
