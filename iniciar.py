"""Inicia la API y la web desde cualquier directorio de trabajo."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
DIRECTORIO_API = RAIZ / "plataforma_rag"


def main() -> None:
    argumentos = argparse.ArgumentParser(description=__doc__)
    argumentos.add_argument("--host", default="127.0.0.1")
    argumentos.add_argument("--port", type=int, default=8000)
    argumentos.add_argument("--reload", action="store_true", help="Recargar al editar Python")
    opciones = argumentos.parse_args()
    sys.path.insert(0, str(DIRECTORIO_API))
    try:
        import uvicorn
    except ImportError:
        argumentos.exit(1, "Faltan dependencias. Ejecuta instalar.bat.\n")
    print(f"Web: http://{opciones.host}:{opciones.port}/web/", flush=True)
    print(f"Administración: http://{opciones.host}:{opciones.port}/admin", flush=True)
    uvicorn.run(
        "app.main:app", host=opciones.host, port=opciones.port,
        reload=opciones.reload,
        reload_dirs=[str(DIRECTORIO_API / "app")] if opciones.reload else None,
    )


if __name__ == "__main__":
    main()
