"""Extraccion y fragmentacion de PDF para un sistema RAG."""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Callable, Iterable

import pdfplumber


MODEL_NAME = "gemini-embedding-2"
OUTPUT_DIMENSIONS = 768
SCHEMA_VERSION = "1.0"


@dataclass(frozen=True)
class TextBlock:
    page: int
    title: str
    text: str


@dataclass(frozen=True)
class Chunk:
    schema_version: str
    document_id: str
    chunk_id: str
    source_file: str
    title: str
    page_start: int
    page_end: int
    text: str
    embedding_text: str
    estimated_tokens: int
    quality_score: int
    validation_warnings: list[str]
    embedding_model: str
    output_dimensions: int


def estimate_tokens(text: str) -> int:
    """Estimacion conservadora para espanol sin depender de un tokenizador remoto."""
    return max(1, (len(text) + 3) // 4)


def _clean_line(line: str) -> str:
    line = re.sub(r"[\t ]+", " ", line).strip()
    return line.replace("–", "-").replace("—", "-")


def _is_heading(line: str) -> bool:
    normalized = line.rstrip(".:").strip().casefold()
    if normalized in {"nota importante", "alta direccion", "alta dirección"}:
        return True
    letters = [char for char in line if char.isalpha()]
    if (
        not letters
        or (len(line.split()) == 1 and len(letters) <= 4)
        or len(line) > 140
        or re.match(r"^\d", line)
        or "@" in line
        or line.endswith(":")
    ):
        return False
    uppercase_ratio = sum(char.isupper() for char in letters) / len(letters)
    return uppercase_ratio >= 0.82


def _clean_heading(line: str) -> str:
    return line.strip().rstrip(".").strip()


def _quality_check(title: str, text: str, estimated_tokens: int) -> tuple[int, list[str]]:
    warnings: list[str] = []
    score = 100
    normalized = re.sub(r"\s+", " ", text).strip()
    if estimated_tokens < 35:
        warnings.append("contenido_muy_corto")
        score -= 35
    if len(title) > 170:
        warnings.append("titulo_muy_largo")
        score -= 15
    if normalized.endswith((":", ",", ";", "-")):
        warnings.append("final_posiblemente_incompleto")
        score -= 15
    if len(re.findall(r"_{3,}", text)) >= 2:
        warnings.append("campos_de_formulario")
        score -= 35
    return max(0, score), warnings


def _is_discardable_form_fragment(text: str) -> bool:
    normalized = text.casefold()
    return (
        estimate_tokens(text) < 35
        and len(re.findall(r"_{3,}", text)) >= 2
        and ("firma" in normalized or "dia:" in normalized or "día:" in normalized)
    )


def extract_blocks(pdf_path: Path) -> tuple[list[TextBlock], list[int]]:
    """Extrae bloques con pagina y titulo. Devuelve paginas posiblemente escaneadas."""
    blocks: list[TextBlock] = []
    low_text_pages: list[int] = []
    current_title = pdf_path.stem.replace("_", " ").replace("-", " ")

    with pdfplumber.open(pdf_path) as document:
        for page_number, page in enumerate(document.pages, start=1):
            raw_text = page.extract_text() or ""
            if len(raw_text.strip()) < 40:
                low_text_pages.append(page_number)
            lines = [_clean_line(line) for line in raw_text.splitlines()]
            lines = [line for line in lines if line]
            buffer: list[str] = []
            pending_heading: list[str] = []

            def flush() -> None:
                if buffer:
                    text = "\n".join(buffer).strip()
                    if text:
                        blocks.append(TextBlock(page_number, current_title, text))
                    buffer.clear()

            def apply_heading() -> None:
                nonlocal current_title
                if pending_heading:
                    current_title = " ".join(_clean_heading(line) for line in pending_heading)
                    buffer.append(current_title)
                    pending_heading.clear()

            for line in lines:
                if _is_heading(line):
                    if buffer:
                        flush()
                    pending_heading.append(line)
                else:
                    apply_heading()
                    buffer.append(line)
            apply_heading()
            flush()

    # Une encabezados aislados con la seccion siguiente de la misma pagina y
    # descarta encabezados sin contenido que quedaron al final de una pagina.
    normalized_blocks: list[TextBlock] = []
    index = 0
    while index < len(blocks):
        block = blocks[index]
        title_only = block.text.strip() == block.title.strip()
        if title_only and index + 1 < len(blocks) and blocks[index + 1].page == block.page:
            following = blocks[index + 1]
            merged_title = f"{block.title} - {following.title}"
            normalized_blocks.append(
                TextBlock(following.page, merged_title, f"{block.text}\n{following.text}")
            )
            index += 2
            continue
        if not title_only:
            normalized_blocks.append(block)
        index += 1

    compact_blocks: list[TextBlock] = []
    index = 0
    while index < len(normalized_blocks):
        block = normalized_blocks[index]
        if (
            len(block.text) < 120
            and index + 1 < len(normalized_blocks)
            and normalized_blocks[index + 1].page == block.page
        ):
            following = normalized_blocks[index + 1]
            compact_blocks.append(
                TextBlock(
                    block.page,
                    f"{block.title} - {following.title}",
                    f"{block.text}\n{following.text}",
                )
            )
            index += 2
            continue
        compact_blocks.append(block)
        index += 1

    return compact_blocks, low_text_pages


def _split_long_text(text: str, max_chars: int) -> list[str]:
    if len(text) <= max_chars:
        return [text]
    sentences = re.split(r"(?<=[.!?])\s+|\n(?=\d+[.)]?\s|[\u25cf*-]\s)", text)
    parts: list[str] = []
    current = ""
    for sentence in sentences:
        sentence = sentence.strip()
        if not sentence:
            continue
        if len(sentence) > max_chars:
            words = sentence.split()
            for word in words:
                proposal = f"{current} {word}".strip()
                if current and len(proposal) > max_chars:
                    parts.append(current)
                    current = word
                else:
                    current = proposal
            continue
        proposal = f"{current}\n{sentence}".strip()
        if current and len(proposal) > max_chars:
            parts.append(current)
            current = sentence
        else:
            current = proposal
    if current:
        parts.append(current)
    return parts


def build_chunks(
    blocks: Iterable[TextBlock],
    pdf_path: Path,
    max_tokens: int = 700,
    overlap_tokens: int = 80,
) -> list[Chunk]:
    if max_tokens < 100:
        raise ValueError("El tamano maximo debe ser de al menos 100 tokens.")
    if overlap_tokens < 0 or overlap_tokens >= max_tokens:
        raise ValueError("El solapamiento debe ser menor que el tamano del chunk.")

    max_chars = max_tokens * 4
    overlap_chars = overlap_tokens * 4
    expanded: list[TextBlock] = []
    for block in blocks:
        for part in _split_long_text(block.text, max_chars):
            expanded.append(TextBlock(block.page, block.title, part))

    groups: list[list[TextBlock]] = []
    current: list[TextBlock] = []
    current_chars = 0
    current_title = ""
    for block in expanded:
        extra = len(block.text) + (2 if current else 0)
        title_changed = bool(current and block.title != current_title)
        if current and (current_chars + extra > max_chars or title_changed):
            groups.append(current)
            current = []
            current_chars = 0
        current.append(block)
        current_chars += extra
        current_title = block.title
    if current:
        groups.append(current)

    # Aplica solapamiento textual solo entre chunks de una misma seccion.
    texts: list[tuple[str, str, int, int]] = []
    previous_text = ""
    previous_title = ""
    for group in groups:
        title = group[0].title
        body = "\n\n".join(block.text for block in group).strip()
        if _is_discardable_form_fragment(body):
            continue
        if previous_text and title == previous_title and overlap_chars:
            prefix = previous_text[-overlap_chars:].lstrip()
            body = f"{prefix}\n\n{body}"
        texts.append((title, body, group[0].page, group[-1].page))
        previous_text = body
        previous_title = title

    document_id = hashlib.sha256(pdf_path.read_bytes()).hexdigest()[:16]
    chunks: list[Chunk] = []
    for index, (title, text, page_start, page_end) in enumerate(texts, start=1):
        safe_title = title or pdf_path.stem
        token_count = estimate_tokens(text)
        quality_score, validation_warnings = _quality_check(safe_title, text, token_count)
        chunks.append(
            Chunk(
                schema_version=SCHEMA_VERSION,
                document_id=document_id,
                chunk_id=f"{document_id}-{index:04d}",
                source_file=pdf_path.name,
                title=safe_title,
                page_start=page_start,
                page_end=page_end,
                text=text,
                embedding_text=f"title: {safe_title} | text: {text}",
                estimated_tokens=token_count,
                quality_score=quality_score,
                validation_warnings=validation_warnings,
                embedding_model=MODEL_NAME,
                output_dimensions=OUTPUT_DIMENSIONS,
            )
        )
    return chunks


def transform_pdf(
    pdf_path: Path,
    output_dir: Path,
    max_tokens: int = 700,
    overlap_tokens: int = 80,
    progress: Callable[[str], None] | None = None,
) -> tuple[Path, Path, int, list[int]]:
    pdf_path = Path(pdf_path)
    output_dir = Path(output_dir)
    if pdf_path.suffix.lower() != ".pdf" or not pdf_path.is_file():
        raise ValueError(f"No es un PDF valido: {pdf_path}")
    output_dir.mkdir(parents=True, exist_ok=True)
    notify = progress or (lambda _message: None)

    notify(f"Extrayendo: {pdf_path.name}")
    blocks, low_text_pages = extract_blocks(pdf_path)
    if not blocks:
        raise ValueError("No se encontro texto. El PDF puede requerir OCR.")
    chunks = build_chunks(blocks, pdf_path, max_tokens, overlap_tokens)

    base_name = re.sub(r"[^\w.-]+", "_", pdf_path.stem, flags=re.UNICODE).strip("_")
    jsonl_path = output_dir / f"{base_name}.chunks.jsonl"
    manifest_path = output_dir / f"{base_name}.manifest.json"

    with jsonl_path.open("w", encoding="utf-8", newline="\n") as stream:
        for chunk in chunks:
            stream.write(json.dumps(asdict(chunk), ensure_ascii=False) + "\n")

    manifest = {
        "schema_version": SCHEMA_VERSION,
        "source_file": pdf_path.name,
        "document_id": chunks[0].document_id,
        "chunk_count": len(chunks),
        "max_tokens": max_tokens,
        "overlap_tokens": overlap_tokens,
        "embedding_model": MODEL_NAME,
        "output_dimensions": OUTPUT_DIMENSIONS,
        "low_text_pages": low_text_pages,
        "automatic_validation": {
            "enabled": True,
            "minimum_quality_score": min(chunk.quality_score for chunk in chunks),
            "chunks_with_warnings": sum(bool(chunk.validation_warnings) for chunk in chunks),
        },
        "output_file": jsonl_path.name,
    }
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    notify(f"Listo: {len(chunks)} chunks -> {jsonl_path.name}")
    return jsonl_path, manifest_path, len(chunks), low_text_pages
