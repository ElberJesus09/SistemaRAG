from __future__ import annotations

import re
import time
import unicodedata
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from functools import lru_cache
from typing import Any
from uuid import UUID, uuid4

from app.core.config import obtener_configuracion
from app.core.registro import obtener_logger
from app.models.schemas import FuenteRespuesta
from app.services.gemini_service import ServicioGemini, obtener_gemini
from app.services.supabase_service import ServicioSupabase, obtener_supabase


registro = obtener_logger(__name__)


class LimiteDeUso(Exception):
    """El usuario supero su cuota de preguntas por hora."""


def normalizar_pregunta(question: str) -> str:
    value = unicodedata.normalize("NFKD", question.casefold())
    value = "".join(char for char in value if not unicodedata.combining(char))
    return re.sub(r"[^a-z0-9]+", " ", value).strip()


@dataclass(frozen=True)
class ResultadoRAG:
    question_id: UUID
    conversation_id: UUID | None
    answer: str
    sources: list[FuenteRespuesta]
    latency_ms: int
    # Trabajo que no hace falta terminar antes de contestar: la capa HTTP lo
    # ejecuta en segundo plano para no sumarlo a lo que espera el estudiante.
    tareas: list[Callable[[], None]] = field(default_factory=list)


class ServicioRAG:
    def __init__(self) -> None:
        self.settings = obtener_configuracion()
        self.supabase: ServicioSupabase = obtener_supabase()
        self.gemini: ServicioGemini = obtener_gemini()
        # Las consultas previas a una pregunta son independientes entre si;
        # lanzarlas a la vez ahorra varias idas y vueltas de red en serie.
        self._piscina = ThreadPoolExecutor(max_workers=8, thread_name_prefix="rag")

    # --------------------------------------------------------------------

    def preguntar(self, user_id: UUID, question: str, conversation_id: UUID | None = None) -> ResultadoRAG:
        started = time.perf_counter()
        question_id = uuid4()
        retrieval_ms = 0
        generation_ms = 0
        espera_ms = 0
        contexts: list[dict[str, Any]] = []
        memory: list[dict[str, str]] = []
        tareas: list[Callable[[], None]] = []

        try:
            # ---- 1. Todo lo que no depende de nada mas, en paralelo ----
            preparacion = time.perf_counter()
            limite = self.settings.ask_rate_limit_per_hour

            futuro_vector = self._piscina.submit(self.gemini.generar_embedding_pregunta, question)
            futuro_uso = (
                self._piscina.submit(self.supabase.contar_preguntas_recientes, user_id, 60)
                if limite > 0
                else None
            )
            futuro_conversacion = (
                self._piscina.submit(self._cargar_conversacion, user_id, conversation_id)
                if conversation_id
                else None
            )
            futuro_memoria = (
                self._piscina.submit(self._obtener_memoria, conversation_id)
                if conversation_id
                else None
            )

            # El limite se resuelve primero: corta antes de gastar la busqueda
            # y, sobre todo, antes de la generacion, que es lo caro.
            if futuro_uso is not None and futuro_uso.result() >= limite:
                raise LimiteDeUso(
                    "Alcanzaste el limite de preguntas por hora. Intenta mas tarde."
                )
            if futuro_conversacion is not None:
                self._validar_conversacion(futuro_conversacion.result())
            if futuro_memoria is not None:
                memory = futuro_memoria.result()
            query_vector = futuro_vector.result()
            espera_ms = round((time.perf_counter() - preparacion) * 1000)

            # ---- 2. Busqueda vectorial ----
            retrieval_started = time.perf_counter()
            match_response = self.supabase.admin.rpc(
                "match_chunks",
                {
                    "query_embedding": query_vector,
                    "match_threshold": self.settings.retrieval_threshold,
                    "match_count": self.settings.retrieval_match_count,
                },
            ).execute()
            contexts = match_response.data or []
            retrieval_ms = round((time.perf_counter() - retrieval_started) * 1000)

            # ---- 3. Generacion ----
            if contexts or memory:
                generation_started = time.perf_counter()
                generation = self.gemini.generar_respuesta(question, contexts, memory)
                generation_ms = round((time.perf_counter() - generation_started) * 1000)
                answer = generation.text
                input_tokens = generation.input_tokens
                output_tokens = generation.output_tokens
            else:
                answer = "No encontre informacion suficiente en los documentos cargados para responder esa pregunta."
                input_tokens = None
                output_tokens = None

            latency_ms = round((time.perf_counter() - started) * 1000)
            sources = [
                FuenteRespuesta(
                    chunk_id=item["chunk_id"],
                    document=item["document_filename"],
                    title=item["title"],
                    page_start=item.get("page_start"),
                    page_end=item.get("page_end"),
                    similarity=float(item["similarity"]),
                )
                for item in contexts
            ]

            # ---- 4. Guardar. La fila de la pregunta si se espera: el feedback
            # y la memoria del siguiente turno la necesitan enseguida. ----
            self.supabase.admin.table("questions").insert(
                {
                    "id": str(question_id),
                    "user_id": str(user_id),
                    "conversation_id": str(conversation_id) if conversation_id else None,
                    "question": question,
                    "normalized_question": normalizar_pregunta(question),
                    "answer": answer,
                    "status": "answered" if contexts else "no_results",
                    "latency_ms": latency_ms,
                    "retrieval_ms": retrieval_ms,
                    "generation_ms": generation_ms,
                    "top_similarity": float(contexts[0]["similarity"]) if contexts else None,
                    "sources": [source.model_dump() for source in sources],
                    "input_tokens": input_tokens,
                    "output_tokens": output_tokens,
                    "generation_model": self.settings.gemini_generation_model,
                }
            ).execute()

            # ---- 5. Lo demas puede esperar a que el estudiante ya tenga su
            # respuesta: son dos o tres viajes mas a la base. ----
            if conversation_id:
                tareas.append(lambda: self._incrementar_conversacion(conversation_id))
            if not contexts:
                tareas.append(
                    lambda: self._crear_alerta(
                        "no_results", "warning", "Pregunta sin resultados", question, question_id
                    )
                )
            if latency_ms >= self.settings.slow_request_ms:
                tareas.append(
                    lambda: self._crear_alerta(
                        "slow_request",
                        "warning",
                        "Respuesta lenta",
                        f"La respuesta demoro {latency_ms} ms",
                        question_id,
                    )
                )

            registro.info(
                "pregunta respondida",
                extra={
                    "pregunta": str(question_id),
                    "ms": latency_ms,
                    "espera_ms": espera_ms,
                    "busqueda_ms": retrieval_ms,
                    "generacion_ms": generation_ms,
                    "fuentes": len(sources),
                },
            )
            return ResultadoRAG(
                question_id, conversation_id, answer, sources, latency_ms, tareas
            )

        except (ValueError, LimiteDeUso):
            raise
        except Exception as exc:
            latency_ms = round((time.perf_counter() - started) * 1000)
            registro.exception("fallo al responder", extra={"pregunta": str(question_id)})
            self.supabase.admin.table("questions").insert(
                {
                    "id": str(question_id),
                    "user_id": str(user_id),
                    "conversation_id": str(conversation_id) if conversation_id else None,
                    "question": question,
                    "normalized_question": normalizar_pregunta(question),
                    "status": "error",
                    "latency_ms": latency_ms,
                    "retrieval_ms": retrieval_ms,
                    "generation_ms": generation_ms,
                    "error_code": type(exc).__name__,
                }
            ).execute()
            self._crear_alerta("question_error", "error", "Error al responder", str(exc)[:500], question_id)
            raise

    # ----------------------------- Auxiliares -----------------------------

    def _cargar_conversacion(self, user_id: UUID, conversation_id: UUID) -> dict | None:
        response = (
            self.supabase.admin.table("conversations")
            .select("id,message_count,max_messages,status")
            .eq("id", str(conversation_id))
            .eq("user_id", str(user_id))
            .limit(1)
            .execute()
        )
        return response.data[0] if response.data else None

    @staticmethod
    def _validar_conversacion(conversation: dict | None) -> None:
        if not conversation:
            raise ValueError("Conversacion no encontrada")
        if conversation["status"] != "active":
            raise ValueError("Conversacion cerrada")
        if conversation["message_count"] >= conversation["max_messages"]:
            raise ValueError("La conversacion alcanzo el limite de mensajes")

    def _obtener_memoria(self, conversation_id: UUID) -> list[dict[str, str]]:
        response = (
            self.supabase.admin.table("questions")
            .select("question,answer")
            .eq("conversation_id", str(conversation_id))
            .in_("status", ["answered", "no_results"])
            .order("created_at", desc=True)
            .limit(self.settings.conversation_memory_messages)
            .execute()
        )
        rows = response.data or []
        return [
            {"question": item["question"], "answer": item["answer"]}
            for item in reversed(rows)
            if item.get("answer")
        ]

    def _incrementar_conversacion(self, conversation_id: UUID) -> None:
        self.supabase.admin.rpc(
            "increment_conversation_message_count",
            {"conversation_uuid": str(conversation_id)},
        ).execute()

    def _crear_alerta(self, alert_type: str, severity: str, title: str, message: str, question_id: UUID) -> None:
        self.supabase.admin.table("alerts").insert(
            {
                "type": alert_type,
                "severity": severity,
                "title": title,
                "message": message[:1000],
                "question_id": str(question_id),
            }
        ).execute()


@lru_cache
def obtener_servicio_rag() -> ServicioRAG:
    return ServicioRAG()
