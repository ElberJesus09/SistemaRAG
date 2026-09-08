from __future__ import annotations

from fastapi import Depends, Header, HTTPException, status

from app.services.supabase_service import ServicioSupabase, UsuarioAutenticado, obtener_supabase


def obtener_usuario_actual(
    authorization: str | None = Header(default=None),
    supabase: ServicioSupabase = Depends(obtener_supabase),
) -> UsuarioAutenticado:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Se requiere Bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return supabase.autenticar(authorization.split(" ", 1)[1].strip())


def requerir_administrador(user: UsuarioAutenticado = Depends(obtener_usuario_actual)) -> UsuarioAutenticado:
    if user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Se requiere rol administrador")
    return user
