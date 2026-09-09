from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Response
from supabase_auth.errors import AuthApiError

from app.core.security import obtener_usuario_actual
from app.models.schemas import (
    PerfilUsuario,
    RespuestaAutenticacion,
    SolicitudActualizarPerfil,
    SolicitudCambioContrasena,
    SolicitudInicioSesion,
    SolicitudRegistro,
    SolicitudRenovacion,
)
from app.services.supabase_service import ServicioSupabase, UsuarioAutenticado, obtener_supabase


router = APIRouter(prefix="/auth", tags=["Autenticacion"])


def _error_registro(error: AuthApiError) -> HTTPException:
    codigo = str(error.code or "unexpected_failure")
    mensajes = {
        "email_exists": (409, "El correo ya esta registrado"),
        "user_already_exists": (409, "El correo ya esta registrado"),
        "over_email_send_rate_limit": (429, "Se alcanzo el limite temporal de correos. Espera unos minutos e intenta otra vez"),
        "over_request_rate_limit": (429, "Demasiados intentos. Espera unos minutos e intenta otra vez"),
        "email_address_invalid": (422, "Supabase considera que el correo no es valido"),
        "email_address_not_authorized": (403, "El dominio de correo no esta autorizado en Supabase"),
        "weak_password": (422, "La contrasena no cumple los requisitos de seguridad"),
        "signup_disabled": (503, "El registro de usuarios esta desactivado en Supabase"),
        "email_provider_disabled": (503, "El acceso mediante correo esta desactivado en Supabase"),
    }
    estado, detalle = mensajes.get(codigo, (400, f"Supabase rechazo el registro (codigo: {codigo})"))
    return HTTPException(status_code=estado, detail=detalle)


def _respuesta_autenticacion(response: object) -> RespuestaAutenticacion:
    session = getattr(response, "session", None)
    return RespuestaAutenticacion(
        access_token=getattr(session, "access_token", None),
        refresh_token=getattr(session, "refresh_token", None),
        expires_in=getattr(session, "expires_in", None),
        requires_email_confirmation=session is None,
    )


@router.post("/register", response_model=RespuestaAutenticacion, status_code=201)
def registrar(payload: SolicitudRegistro, supabase: ServicioSupabase = Depends(obtener_supabase)) -> RespuestaAutenticacion:
    try:
        return _respuesta_autenticacion(supabase.registrar(payload.email, payload.password, payload.full_name))
    except AuthApiError as exc:
        raise _error_registro(exc) from exc
    except Exception as exc:
        raise HTTPException(status_code=400, detail="No se pudo registrar el usuario") from exc


@router.post("/login", response_model=RespuestaAutenticacion)
def iniciar_sesion(payload: SolicitudInicioSesion, supabase: ServicioSupabase = Depends(obtener_supabase)) -> RespuestaAutenticacion:
    try:
        return _respuesta_autenticacion(supabase.iniciar_sesion(payload.email, payload.password))
    except AuthApiError as exc:
        if exc.code == "email_not_confirmed":
            raise HTTPException(status_code=403, detail="Debes confirmar tu correo antes de iniciar sesion") from exc
        if exc.code in {"over_request_rate_limit", "over_email_send_rate_limit"}:
            raise HTTPException(status_code=429, detail="Demasiados intentos. Espera unos minutos") from exc
        raise HTTPException(status_code=401, detail="Usuario, correo o contrasena incorrectos") from exc
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Usuario, correo o contrasena incorrectos") from exc


@router.post("/refresh", response_model=RespuestaAutenticacion)
def renovar_sesion(payload: SolicitudRenovacion, supabase: ServicioSupabase = Depends(obtener_supabase)) -> RespuestaAutenticacion:
    try:
        return _respuesta_autenticacion(supabase.renovar_sesion(payload.refresh_token))
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Sesion vencida") from exc


@router.get("/me", response_model=PerfilUsuario)
def mi_perfil(user: UsuarioAutenticado = Depends(obtener_usuario_actual)) -> PerfilUsuario:
    return PerfilUsuario(id=user.id, email=user.email, full_name=user.full_name, role=user.role)


@router.patch("/me", response_model=PerfilUsuario)
def actualizar_perfil(
    payload: SolicitudActualizarPerfil,
    user: UsuarioAutenticado = Depends(obtener_usuario_actual),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> PerfilUsuario:
    try:
        perfil = supabase.actualizar_nombre(user.id, payload.full_name)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail="No se pudo actualizar el perfil") from exc
    return PerfilUsuario(
        id=user.id,
        email=user.email,
        full_name=perfil.get("full_name"),
        role=perfil.get("role", user.role),
    )


@router.post("/password", status_code=204)
def cambiar_contrasena(
    payload: SolicitudCambioContrasena,
    user: UsuarioAutenticado = Depends(obtener_usuario_actual),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> Response:
    if not supabase.verificar_contrasena(user.email, payload.current_password):
        raise HTTPException(status_code=401, detail="La contrasena actual no es correcta")
    try:
        supabase.cambiar_contrasena(user.id, payload.new_password)
    except AuthApiError as exc:
        if exc.code == "weak_password":
            raise HTTPException(
                status_code=422, detail="La contrasena nueva no cumple los requisitos de seguridad"
            ) from exc
        raise HTTPException(status_code=400, detail="Supabase rechazo el cambio de contrasena") from exc
    except Exception as exc:
        raise HTTPException(status_code=503, detail="No se pudo cambiar la contrasena") from exc
    supabase.admin.table("audit_logs").insert(
        {
            "user_id": str(user.id),
            "action": "auth.password_change",
            "entity_type": "user",
            "entity_id": str(user.id),
            "details": {},
        }
    ).execute()
    return Response(status_code=204)
