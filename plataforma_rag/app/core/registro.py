"""Logging estructurado en JSON con identificador de peticion.

El middleware de `main.py` genera un X-Request-ID por peticion y lo deja aqui;
cualquier log emitido durante esa peticion lo lleva, asi se puede seguir el
rastro completo de una pregunta lenta o de una carga fallida.
"""
from __future__ import annotations

import json
import logging
import sys
from contextvars import ContextVar
from typing import Any


_peticion_actual: ContextVar[str | None] = ContextVar("peticion_actual", default=None)

_CAMPOS_ESTANDAR = {
    "args", "asctime", "created", "exc_info", "exc_text", "filename", "funcName",
    "levelname", "levelno", "lineno", "module", "msecs", "message", "msg", "name",
    "pathname", "process", "processName", "relativeCreated", "stack_info",
    "thread", "threadName", "taskName",
}


def establecer_peticion(request_id: str | None) -> None:
    _peticion_actual.set(request_id)


def peticion_actual() -> str | None:
    return _peticion_actual.get()


class FormatoJson(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        datos: dict[str, Any] = {
            "hora": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "nivel": record.levelname,
            "origen": record.name,
            "mensaje": record.getMessage(),
        }
        peticion = _peticion_actual.get()
        if peticion:
            datos["peticion"] = peticion
        for clave, valor in record.__dict__.items():
            if clave not in _CAMPOS_ESTANDAR and not clave.startswith("_"):
                datos[clave] = valor
        if record.exc_info:
            datos["excepcion"] = self.formatException(record.exc_info)
        return json.dumps(datos, ensure_ascii=False, default=str)


class FormatoTexto(logging.Formatter):
    """Formato legible para desarrollo."""

    def format(self, record: logging.LogRecord) -> str:
        peticion = _peticion_actual.get()
        marca = f" [{peticion[:8]}]" if peticion else ""
        extras = {
            clave: valor
            for clave, valor in record.__dict__.items()
            if clave not in _CAMPOS_ESTANDAR and not clave.startswith("_")
        }
        cola = f"  {extras}" if extras else ""
        base = f"{record.levelname:<8}{marca} {record.getMessage()}{cola}"
        if record.exc_info:
            base = f"{base}\n{self.formatException(record.exc_info)}"
        return base


def configurar_logging(nivel: str = "INFO", en_json: bool = False) -> None:
    manejador = logging.StreamHandler(sys.stdout)
    manejador.setFormatter(FormatoJson() if en_json else FormatoTexto())

    raiz = logging.getLogger()
    raiz.handlers.clear()
    raiz.addHandler(manejador)
    raiz.setLevel(nivel.upper())

    # Uvicorn ya imprime su propia linea de acceso; la nuestra es mas completa.
    logging.getLogger("uvicorn.access").disabled = True
    for ruidoso in ("httpx", "hpack", "httpcore"):
        logging.getLogger(ruidoso).setLevel(logging.WARNING)


def obtener_logger(nombre: str) -> logging.Logger:
    return logging.getLogger(nombre)
