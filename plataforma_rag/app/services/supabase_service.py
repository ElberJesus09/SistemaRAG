from __future__ import annotations

import hashlib
import secrets
import string
import threading
import time
from datetime import UTC, datetime, timedelta
from collections import OrderedDict
from dataclasses import dataclass
from functools import lru_cache
from typing import Any
from uuid import UUID

from fastapi import HTTPException, status
from supabase import Client, create_client

from app.core.config import obtener_configuracion
from app.core.registro import obtener_logger


registro = obtener_logger(__name__)


@dataclass(frozen=True)
class UsuarioAutenticado:
    id: UUID
    email: str
    role: str
    full_name: str | None = None


@dataclass
class _PerfilCacheado:
    usuario: UsuarioAutenticado
    expira: float


class ServicioSupabase:
    def __init__(self) -> None:
        settings = obtener_configuracion()
        self.settings = settings
        self.url = settings.supabase_url
        self.anon_key = settings.supabase_anon_key
        self.admin: Client = create_client(settings.supabase_url, settings.supabase_service_role_key)
        # Cache de tokens ya validados: sin esto cada peticion autenticada
        # cuesta dos viajes de red a Supabase (get_user + select profiles).
        self._cache: "OrderedDict[str, _PerfilCacheado]" = OrderedDict()
        self._candado = threading.Lock()

    # ------------------------------ Cache ------------------------------

    @staticmethod
    def _clave(access_token: str) -> str:
        return hashlib.sha256(access_token.encode("utf-8")).hexdigest()

    def _leer_cache(self, clave: str) -> UsuarioAutenticado | None:
        if self.settings.auth_cache_seconds <= 0:
            return None
        ahora = time.monotonic()
        with self._candado:
            entrada = self._cache.get(clave)
            if entrada is None:
                return None
            if entrada.expira <= ahora:
                self._cache.pop(clave, None)
                return None
            self._cache.move_to_end(clave)
            return entrada.usuario

    def _guardar_cache(self, clave: str, usuario: UsuarioAutenticado) -> None:
        if self.settings.auth_cache_seconds <= 0:
            return
        expira = time.monotonic() + self.settings.auth_cache_seconds
        with self._candado:
            self._cache[clave] = _PerfilCacheado(usuario=usuario, expira=expira)
            self._cache.move_to_end(clave)
            while len(self._cache) > self.settings.auth_cache_max_entries:
                self._cache.popitem(last=False)

    def invalidar_usuario(self, user_id: UUID) -> None:
        """Tras cambiar nombre o contrasena, el perfil cacheado deja de servir."""
        with self._candado:
            for clave in [c for c, e in self._cache.items() if e.usuario.id == user_id]:
                self._cache.pop(clave, None)

    def cliente_publico(self) -> Client:
        # El cliente de Auth conserva sesion; uno nuevo evita compartir estado entre solicitudes.
        return create_client(self.url, self.anon_key)

    def registrar(self, email: str, password: str, full_name: str) -> Any:
        return self.cliente_publico().auth.sign_up(
            {"email": email, "password": password, "options": {"data": {"full_name": full_name}}}
        )

    def iniciar_sesion(self, email: str, password: str) -> Any:
        return self.cliente_publico().auth.sign_in_with_password({"email": email, "password": password})

    def renovar_sesion(self, refresh_token: str) -> Any:
        return self.cliente_publico().auth.refresh_session(refresh_token)

    def verificar_contrasena(self, email: str, password: str) -> bool:
        """Confirma la contrasena actual antes de permitir cambiarla."""
        try:
            respuesta = self.cliente_publico().auth.sign_in_with_password(
                {"email": email, "password": password}
            )
            return getattr(respuesta, "session", None) is not None
        except Exception:
            return False

    def cambiar_contrasena(self, user_id: UUID, nueva: str) -> None:
        """Usa la API de administracion: la sesion del usuario vive en el cliente, no aqui."""
        self.admin.auth.admin.update_user_by_id(str(user_id), {"password": nueva})
        self.invalidar_usuario(user_id)

    def contar_preguntas_recientes(self, user_id: UUID, minutos: int = 60) -> int:
        """Preguntas del usuario en la ultima ventana, para el limite de uso."""
        desde = datetime.now(UTC) - timedelta(minutes=minutos)
        respuesta = (
            self.admin.table("questions")
            .select("id", count="exact")
            .eq("user_id", str(user_id))
            .gte("created_at", desde.isoformat())
            .limit(1)
            .execute()
        )
        return respuesta.count or 0

    def usuarios_con_actividad(self, minutos: int = 15, limite: int = 500) -> list[dict[str, Any]]:
        """Perfiles con su actividad. Requiere la migracion 005."""
        respuesta = self.admin.rpc(
            "usuarios_con_actividad",
            {"minutos_activo": minutos, "limite": limite},
        ).execute()
        return respuesta.data or []

    def actualizar_usuario(self, user_id: UUID, cambios: dict[str, Any]) -> dict[str, Any]:
        respuesta = (
            self.admin.table("profiles").update(cambios).eq("id", str(user_id)).execute()
        )
        if not respuesta.data:
            raise HTTPException(status_code=404, detail="Usuario no encontrado")
        self.invalidar_usuario(user_id)
        return respuesta.data[0]

    # ------------------------ Restablecer contrasenas ------------------------

    # Alfabeto sin caracteres que se confunden al dictar o copiar a mano:
    # nada de O/0, l/1/I. El administrador va a leer esto en voz alta.
    _ALFABETO = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"

    @classmethod
    def generar_contrasena(cls, longitud: int = 14) -> str:
        return "".join(secrets.choice(cls._ALFABETO) for _ in range(longitud))

    def enlace_de_recuperacion(self, email: str) -> str:
        """Enlace para que el propio usuario elija su contrasena.

        Se genera con la API de administracion en lugar de enviar el correo,
        para no depender de que Supabase tenga SMTP configurado: el enlace se
        entrega por el canal que el administrador prefiera.
        """
        respuesta = self.admin.auth.admin.generate_link(
            {"type": "recovery", "email": email}
        )
        propiedades = getattr(respuesta, "properties", None)
        enlace = getattr(propiedades, "action_link", None)
        if not enlace and isinstance(respuesta, dict):
            enlace = (respuesta.get("properties") or {}).get("action_link")
        if not enlace:
            raise RuntimeError("Supabase no devolvio el enlace de recuperacion")
        return str(enlace)

    def asignar_contrasena_temporal(self, user_id: UUID) -> str:
        """Genera y aplica una contrasena aleatoria. Devuelve la contrasena en claro
        una sola vez: no se guarda en ningun sitio."""
        nueva = self.generar_contrasena()
        self.admin.auth.admin.update_user_by_id(str(user_id), {"password": nueva})
        self.invalidar_usuario(user_id)
        return nueva

    def comprobar_conexion(self) -> None:
        """Lectura minima para saber si Supabase responde. La usa /health."""
        self.admin.table("profiles").select("id", count="exact").limit(1).execute()

    def actualizar_nombre(self, user_id: UUID, full_name: str) -> dict[str, Any]:
        respuesta = (
            self.admin.table("profiles")
            .update({"full_name": full_name})
            .eq("id", str(user_id))
            .execute()
        )
        if not respuesta.data:
            raise HTTPException(status_code=404, detail="Perfil no encontrado")
        self.invalidar_usuario(user_id)
        return respuesta.data[0]

    def autenticar(self, access_token: str) -> UsuarioAutenticado:
        clave = self._clave(access_token)
        cacheado = self._leer_cache(clave)
        if cacheado is not None:
            return cacheado

        try:
            response = self.cliente_publico().auth.get_user(access_token)
            auth_user = response.user
            if auth_user is None:
                raise ValueError("Usuario no encontrado")
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token invalido o vencido",
                headers={"WWW-Authenticate": "Bearer"},
            ) from exc

        try:
            profile_response = (
                self.admin.table("profiles")
                .select("id,full_name,role,is_active")
                .eq("id", str(auth_user.id))
                .limit(1)
                .execute()
            )
            profile = profile_response.data[0] if profile_response.data else {}
            # El esquema tenia `is_active` desde el principio y nadie lo miraba:
            # desactivar a un estudiante no lo bloqueaba en absoluto.
            if profile.get("is_active") is False:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Tu cuenta esta desactivada. Contacta con la administracion.",
                )
            usuario = UsuarioAutenticado(
                id=UUID(str(auth_user.id)),
                email=auth_user.email or "",
                role=profile.get("role", "user"),
                full_name=profile.get("full_name"),
            )
            self._guardar_cache(clave, usuario)
            return usuario
        except HTTPException:
            raise
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="No se pudo consultar el perfil del usuario en Supabase",
            ) from exc


@lru_cache
def obtener_supabase() -> ServicioSupabase:
    return ServicioSupabase()
