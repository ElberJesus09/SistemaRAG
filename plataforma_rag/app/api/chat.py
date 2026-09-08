from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response
from starlette.concurrency import run_in_threadpool

from app.core.config import obtener_configuracion
from app.core.security import obtener_usuario_actual
from app.models.schemas import (
    MensajeConversacion,
    RespuestaConversacion,
    RespuestaPregunta,
    SolicitudActualizarConversacion,
    SolicitudConversacion,
    SolicitudPregunta,
    SolicitudValoracion,
)
from app.services.rag_service import LimiteDeUso, ServicioRAG, obtener_servicio_rag
from app.services.supabase_service import ServicioSupabase, UsuarioAutenticado, obtener_supabase


router = APIRouter(prefix="/chat", tags=["Chat RAG"])


@router.post("/conversations", response_model=RespuestaConversacion)
def crear_conversacion(
    payload: SolicitudConversacion,
    user: UsuarioAutenticado = Depends(obtener_usuario_actual),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> RespuestaConversacion:
    max_messages = payload.max_messages or obtener_configuracion().conversation_max_messages
    response = (
        supabase.admin.table("conversations")
        .insert(
            {
                "user_id": str(user.id),
                "title": payload.title,
                "max_messages": max_messages,
            }
        )
        .execute()
    )
    if not response.data:
        raise HTTPException(status_code=503, detail="No se pudo crear la conversacion")
    return RespuestaConversacion(**response.data[0])


def _conversacion_del_usuario(supabase: ServicioSupabase, user_id, conversation_id) -> dict:
    """Toda ruta de conversacion filtra por user_id: la API usa service_role y evita RLS."""
    respuesta = (
        supabase.admin.table("conversations")
        .select("*")
        .eq("id", str(conversation_id))
        .eq("user_id", str(user_id))
        .limit(1)
        .execute()
    )
    if not respuesta.data:
        raise HTTPException(status_code=404, detail="Conversacion no encontrada")
    return respuesta.data[0]


@router.get("/conversations", response_model=list[RespuestaConversacion])
def listar_conversaciones(
    limit: int = Query(default=50, ge=1, le=200),
    include_closed: bool = Query(default=True),
    user: UsuarioAutenticado = Depends(obtener_usuario_actual),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> list[RespuestaConversacion]:
    consulta = (
        supabase.admin.table("conversations")
        .select("id,title,message_count,max_messages,status,created_at,updated_at")
        .eq("user_id", str(user.id))
        .order("updated_at", desc=True)
        .limit(limit)
    )
    if not include_closed:
        consulta = consulta.eq("status", "active")
    return [RespuestaConversacion(**fila) for fila in consulta.execute().data or []]


@router.get("/conversations/{conversation_id}/messages", response_model=list[MensajeConversacion])
def mensajes_de_conversacion(
    conversation_id: UUID,
    user: UsuarioAutenticado = Depends(obtener_usuario_actual),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> list[MensajeConversacion]:
    _conversacion_del_usuario(supabase, user.id, conversation_id)
    filas = (
        supabase.admin.table("questions")
        .select("id,question,answer,sources,status,latency_ms,created_at")
        .eq("conversation_id", str(conversation_id))
        .eq("user_id", str(user.id))
        .order("created_at", desc=False)
        .limit(200)
        .execute()
        .data
        or []
    )
    return [MensajeConversacion(**fila) for fila in filas]


@router.patch("/conversations/{conversation_id}", response_model=RespuestaConversacion)
def actualizar_conversacion(
    conversation_id: UUID,
    payload: SolicitudActualizarConversacion,
    user: UsuarioAutenticado = Depends(obtener_usuario_actual),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> RespuestaConversacion:
    _conversacion_del_usuario(supabase, user.id, conversation_id)
    cambios = payload.model_dump(exclude_none=True)
    respuesta = (
        supabase.admin.table("conversations")
        .update(cambios)
        .eq("id", str(conversation_id))
        .eq("user_id", str(user.id))
        .execute()
    )
    if not respuesta.data:
        raise HTTPException(status_code=503, detail="No se pudo actualizar la conversacion")
    return RespuestaConversacion(**respuesta.data[0])


@router.delete("/conversations/{conversation_id}", status_code=204)
def eliminar_conversacion(
    conversation_id: UUID,
    user: UsuarioAutenticado = Depends(obtener_usuario_actual),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> Response:
    _conversacion_del_usuario(supabase, user.id, conversation_id)
    # Las preguntas se conservan para la analitica: la FK las deja con conversation_id nulo.
    supabase.admin.table("conversations").delete().eq("id", str(conversation_id)).eq(
        "user_id", str(user.id)
    ).execute()
    return Response(status_code=204)


@router.post("/ask", response_model=RespuestaPregunta)
async def preguntar(
    payload: SolicitudPregunta,
    tareas: BackgroundTasks,
    user: UsuarioAutenticado = Depends(obtener_usuario_actual),
    rag: ServicioRAG = Depends(obtener_servicio_rag),
) -> RespuestaPregunta:
    try:
        result = await run_in_threadpool(
            rag.preguntar, user.id, payload.question, payload.conversation_id
        )
    except LimiteDeUso as exc:
        raise HTTPException(
            status_code=429, detail=str(exc), headers={"Retry-After": "600"}
        ) from exc
    except ValueError as exc:
        message = str(exc)
        if "no encontrada" in message:
            raise HTTPException(status_code=404, detail=message) from exc
        if "limite" in message:
            raise HTTPException(status_code=409, detail=message) from exc
        raise HTTPException(status_code=400, detail=message) from exc
    except Exception as exc:
        raise HTTPException(status_code=503, detail="No fue posible responder en este momento") from exc

    # Contabilidad y alertas: se ejecutan despues de enviar la respuesta.
    for tarea in result.tareas:
        tareas.add_task(tarea)

    return RespuestaPregunta(
        question_id=result.question_id,
        conversation_id=result.conversation_id,
        answer=result.answer,
        answer_format="markdown",
        sources=result.sources,
        latency_ms=result.latency_ms,
        model=obtener_configuracion().gemini_generation_model,
    )


@router.post("/questions/{question_id}/feedback", status_code=204)
def valorar_respuesta(
    question_id: UUID,
    payload: SolicitudValoracion,
    user: UsuarioAutenticado = Depends(obtener_usuario_actual),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> None:
    question = (
        supabase.admin.table("questions")
        .select("id")
        .eq("id", str(question_id))
        .eq("user_id", str(user.id))
        .limit(1)
        .execute()
    )
    if not question.data:
        raise HTTPException(status_code=404, detail="Pregunta no encontrada")
    supabase.admin.table("feedback").upsert(
        {
            "question_id": str(question_id),
            "user_id": str(user.id),
            "rating": payload.rating,
            "comment": payload.comment,
        },
        on_conflict="question_id,user_id",
    ).execute()
