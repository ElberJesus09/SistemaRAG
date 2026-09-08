FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    LOG_JSON=true
WORKDIR /aplicacion
COPY plataforma_rag/requirements.txt ./plataforma_rag/requirements.txt
RUN python -m pip install -r plataforma_rag/requirements.txt \
    && useradd --create-home --uid 10001 aplicacion
COPY plataforma_rag/app ./plataforma_rag/app
COPY web/public ./web/public
COPY iniciar.py ./iniciar.py
USER aplicacion
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=8)" || exit 1
CMD ["python", "iniciar.py", "--host", "0.0.0.0", "--port", "8000"]
