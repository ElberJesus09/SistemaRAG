import json

import pytest
from supabase_auth.errors import AuthApiError

from app.api.auth import _error_registro
from app.services.gemini_service import construir_prompt, formatear_memoria, normalizar_markdown
from app.services.ingestion_service import interpretar_archivo_chunks
from app.services.rag_service import normalizar_pregunta


def ejemplo_chunk(indice: int = 1) -> dict:
    return {
        "document_id": "documento-1234",
        "chunk_id": f"documento-1234-{indice:04d}",
        "source_file": "manual.pdf",
        "title": "Matricula",
        "page_start": 1,
        "page_end": 1,
        "text": "Informacion completa para realizar el tramite de matricula.",
        "embedding_text": "title: Matricula | text: Informacion completa para realizar el tramite.",
        "estimated_tokens": 20,
        "quality_score": 100,
    }


def test_acepta_jsonl_valido() -> None:
    datos = "\n".join(json.dumps(ejemplo_chunk(i)) for i in range(1, 3)).encode()
    resultado = interpretar_archivo_chunks(datos, "manual.chunks.jsonl")
    assert len(resultado) == 2
    assert resultado[0].document_id == "documento-1234"


def test_rechaza_identificadores_duplicados() -> None:
    linea = json.dumps(ejemplo_chunk()).encode()
    with pytest.raises(ValueError, match="duplicados"):
        interpretar_archivo_chunks(linea + b"\n" + linea, "manual.jsonl")


def test_normaliza_pregunta_para_analitica() -> None:
    assert normalizar_pregunta("¿Cómo hago la MATRÍCULA?") == "como hago la matricula"


def test_formatea_memoria_del_chat() -> None:
    memoria = [
        {"question": "Que documentos necesito?", "answer": "Necesitas DNI."},
        {"question": "Y el costo?", "answer": "No hay informacion suficiente."},
    ]
    assert formatear_memoria(memoria) == (
        "Usuario: Que documentos necesito?\n"
        "Asistente: Necesitas DNI.\n\n"
        "Usuario: Y el costo?\n"
        "Asistente: No hay informacion suficiente."
    )


def test_explica_limite_de_correo_de_supabase() -> None:
    error = AuthApiError("rate limit", 429, "over_email_send_rate_limit")
    respuesta = _error_registro(error)
    assert respuesta.status_code == 429
    assert "limite temporal" in respuesta.detail


def test_normaliza_encabezados_y_vinetas_a_subconjunto_soportado() -> None:
    crudo = "### Requisitos\n\n* Constancia de egresado\n+ Copia del DNI\n\n1) Presenta el expediente"
    assert normalizar_markdown(crudo) == (
        "**Requisitos**\n\n"
        "- Constancia de egresado\n"
        "- Copia del DNI\n\n"
        "1. Presenta el expediente"
    )


def test_convierte_enfasis_simple_en_negrita() -> None:
    assert normalizar_markdown("El plazo es de *15 dias habiles*.") == (
        "El plazo es de **15 dias habiles**."
    )
    assert normalizar_markdown("Debes pagar _S/ 450.00_ antes.") == "Debes pagar **S/ 450.00** antes."


def test_elimina_enlaces_citas_y_bloques_de_codigo() -> None:
    crudo = "> Nota: escribe a [grados](mailto:grados@u.pe).\n\n```\ntarifa: 120\n```"
    assert normalizar_markdown(crudo) == "Nota: escribe a grados.\n\ntarifa: 120"


def test_no_deja_asteriscos_sueltos_en_la_respuesta() -> None:
    crudo = "***Fuente:*** manual.pdf, pagina 4"
    limpio = normalizar_markdown(crudo)
    assert limpio == "**Fuente:** manual.pdf, pagina 4"
    assert "***" not in limpio


def contexto_de_ejemplo() -> list[dict]:
    return [
        {
            "document_filename": "manual.pdf",
            "title": "Matricula",
            "page_start": 3,
            "page_end": 4,
            "content": "El tramite de matricula cuesta S/ 120.",
        }
    ]


def test_prompt_con_contexto_incluye_las_fuentes() -> None:
    prompt = construir_prompt("Cuanto cuesta?", contexto_de_ejemplo())
    assert "[FUENTE 1] Documento: manual.pdf" in prompt
    assert "Paginas: 3-4" in prompt
    assert "El tramite de matricula cuesta S/ 120." in prompt
    assert "INSTRUCCION PARA ESTA RESPUESTA" not in prompt


def test_prompt_sin_contexto_pide_usar_solo_el_historial() -> None:
    memoria = [{"question": "Cuanto cuesta la matricula?", "answer": "Cuesta S/ 120."}]
    prompt = construir_prompt("Cual fue mi ultima pregunta?", [], memoria)
    assert "INSTRUCCION PARA ESTA RESPUESTA" in prompt
    assert "(no se recupero ningun fragmento)" in prompt
    # El historial tiene que llegar al modelo: es lo unico con lo que puede responder.
    assert "Cuanto cuesta la matricula?" in prompt
    assert "Cuesta S/ 120." in prompt


def test_prompt_sin_contexto_ni_historial_sigue_siendo_valido() -> None:
    prompt = construir_prompt("Hola", [])
    assert "Sin historial previo." in prompt
    assert "PREGUNTA DEL USUARIO:\nHola" in prompt
