import json
from pathlib import Path

import pytest

from chunker import transform_pdf
from app.services.ingestion_service import interpretar_archivo_chunks

RAIZ = Path(__file__).resolve().parents[2]


def test_pdf_real_produce_jsonl_aceptado_por_la_api(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    pdf = RAIZ / "transformacion" / "entrada" / "INFORMACION-CHATBOT.pdf"
    salida = tmp_path / "salida con espacios"
    jsonl, manifiesto, cantidad, _ = transform_pdf(pdf, salida)
    registros = interpretar_archivo_chunks(jsonl.read_bytes(), jsonl.name)
    detalle = json.loads(manifiesto.read_text(encoding="utf-8"))
    assert cantidad == len(registros) == detalle["chunk_count"]
    assert cantidad > 0
    assert len({registro.chunk_id for registro in registros}) == cantidad
    assert all(registro.page_start >= 1 for registro in registros)
    assert detalle["output_file"] == jsonl.name
    assert jsonl.parent == salida


def test_archivo_inexistente_da_error_claro(tmp_path):
    with pytest.raises(ValueError, match="PDF valido"):
        transform_pdf(tmp_path / "ausente.pdf", tmp_path / "salida")
