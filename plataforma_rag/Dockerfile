FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    LOG_JSON=true

WORKDIR /aplicacion

# curl lo necesita el HEALTHCHECK de abajo.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Nunca como root: si alguien escapa del proceso, no manda en el contenedor.
RUN useradd --create-home --uid 10001 aplicacion \
 && chown -R aplicacion:aplicacion /aplicacion
USER aplicacion

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl --fail --silent http://localhost:8000/health || exit 1

# Dos procesos por defecto: el trabajo pesado (embeddings, Gemini) es de
# entrada/salida y ya corre en un threadpool. Ajusta WEB_CONCURRENCY al desplegar.
ENV WEB_CONCURRENCY=2
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
