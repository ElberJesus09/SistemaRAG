# Transformacion de PDF para RAG

Aplicacion local que extrae el texto de uno o varios PDF, lo divide en chunks y crea un archivo JSONL listo para que otro sistema genere embeddings.

## Recomendacion elegida

- Modelo: `gemini-embedding-2`.
- Dimensiones: `768` para un buen equilibrio entre calidad, almacenamiento y velocidad.
- Chunk: `700` tokens estimados.
- Solapamiento: `80` tokens.
- Formato: JSONL, una linea independiente por chunk.

Cada registro incluye el texto original y `embedding_text` con la estructura documental recomendada por Gemini:

```text
title: {titulo} | text: {contenido}
```

El sistema que genere embeddings debe enviar **un solo `embedding_text` por solicitud o por objeto `Content`**. No debe enviar una lista de strings como una sola entrada a Gemini Embedding 2, porque el modelo puede agregarlos en un único vector.

## Instalacion

Requiere Python 3.10 o posterior.

```powershell
cd D:\SistemaRAG\transformacion
python -m pip install -r requirements.txt
python app.py
```

También se puede abrir `iniciar.bat` con doble clic después de instalar las dependencias.

## Uso

1. Pulsa **Agregar PDF**.
2. Elige la carpeta de salida.
3. Conserva 700/80 salvo que el sistema receptor requiera otros límites.
4. Pulsa **Convertir PDF**.
5. Carga el archivo `*.chunks.jsonl` en el sistema de embeddings.

Se crea también un `*.manifest.json` con el modelo recomendado, dimensiones, configuración y páginas que podrían necesitar OCR.

Antes de guardar, la aplicación realiza una validación automática: detecta títulos aunque estén divididos en varias líneas, separa cambios de tema, elimina fragmentos de formulario sin información útil y asigna a cada chunk un `quality_score` de 0 a 100 junto con `validation_warnings`.

## Esquema JSONL

```json
{
  "schema_version": "1.0",
  "document_id": "identificador estable",
  "chunk_id": "identificador del fragmento",
  "source_file": "documento.pdf",
  "title": "titulo detectado",
  "page_start": 1,
  "page_end": 1,
  "text": "texto limpio",
  "embedding_text": "title: titulo detectado | text: texto limpio",
  "estimated_tokens": 320,
  "quality_score": 100,
  "validation_warnings": [],
  "embedding_model": "gemini-embedding-2",
  "output_dimensions": 768
}
```

## PDF escaneados

La aplicacion detecta páginas con poco o ningún texto y las informa al finalizar. Esta primera versión procesa PDF con texto digital; los PDF compuestos únicamente por imágenes necesitan una etapa OCR antes de convertirlos.
