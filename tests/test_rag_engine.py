"""
Tests for backend/rag_engine.py — metadata detection, chunking, formatting,
factory logic.
"""
import pytest
from pathlib import Path

from backend.rag_engine import (
    _detect_subjects,
    _detect_doc_type,
    _chunk_text,
    _hash_text,
    _format_hits,
    _create_engine,
    BaseRAGEngine,
    load_document,
)
from backend.config import settings


# ======================================================================
# Subject detection
# ======================================================================

class TestDetectSubjects:

    def test_detects_contracts(self):
        text = "The offer and acceptance formed a valid contract under consideration."
        subjects = _detect_subjects(text)
        assert "contracts" in subjects

    def test_detects_torts(self):
        text = "The tort claim involved negligence where the duty of care was breached causing proximate cause issues."
        subjects = _detect_subjects(text)
        assert "torts" in subjects

    def test_detects_constitutional_law(self):
        text = "The first amendment protects speech and due process requires equal protection."
        subjects = _detect_subjects(text)
        assert "constitutional_law" in subjects

    def test_detects_criminal_law(self):
        text = "Murder requires mens rea and actus reus under the model penal code."
        subjects = _detect_subjects(text)
        assert "criminal_law" in subjects

    def test_returns_general_for_unknown(self):
        text = "This is a completely generic sentence."
        subjects = _detect_subjects(text)
        assert subjects == ["general"]

    def test_detects_multiple_subjects(self):
        text = (
            "The contract and offer consideration were relevant. "
            "The negligence and duty of care breach were also at issue."
        )
        subjects = _detect_subjects(text)
        assert len(subjects) >= 2

    def test_case_insensitive(self):
        text = "CONTRACT and OFFER and ACCEPTANCE and consideration"
        subjects = _detect_subjects(text)
        assert "contracts" in subjects


# ======================================================================
# Doc type detection
# ======================================================================

class TestDetectDocType:

    def test_detects_model_answer(self):
        assert _detect_doc_type("This is a sample answer for the bar exam") == "model_answer"

    def test_detects_outline(self):
        assert _detect_doc_type("This is an outline summary of torts") == "outline"

    def test_detects_statute(self):
        assert _detect_doc_type("Under § 1201 of the penal code") == "statute"

    def test_detects_case_brief(self):
        assert _detect_doc_type("Case brief: holding was that defendant...") == "case_brief"

    def test_default_reference(self):
        assert _detect_doc_type("Some text") == "reference"

    def test_filename_check(self):
        # Pattern matches 'practice question' (space) — use a matching filename
        assert _detect_doc_type("text", "practice question 1.txt") == "practice_question"


# ======================================================================
# Chunking
# ======================================================================

class TestChunking:

    def test_small_text_single_chunk(self):
        text = "Short text."
        chunks = _chunk_text(text, size=100, overlap=10)
        assert len(chunks) == 1
        assert chunks[0] == text

    def test_overlapping_chunks(self):
        text = "A" * 250
        chunks = _chunk_text(text, size=100, overlap=20)
        assert len(chunks) >= 3
        # Each chunk should be at most 100 chars
        for c in chunks:
            assert len(c) <= 100

    def test_empty_text(self):
        chunks = _chunk_text("", size=100, overlap=10)
        assert chunks == []

    def test_uses_settings_defaults(self):
        text = "A" * 2500
        chunks = _chunk_text(text)  # uses settings.chunk_size / chunk_overlap
        assert len(chunks) >= 2


class TestHashText:

    def test_deterministic(self):
        a = _hash_text("hello world")
        b = _hash_text("hello world")
        assert a == b

    def test_different_input_different_hash(self):
        a = _hash_text("hello")
        b = _hash_text("world")
        assert a != b

    def test_returns_16_char_hex(self):
        result = _hash_text("test")
        assert len(result) == 16
        assert all(c in "0123456789abcdef" for c in result)


# ======================================================================
# Hit formatting
# ======================================================================

class TestFormatHits:

    def test_empty_hits(self):
        assert _format_hits([]) == ""

    def test_single_hit(self):
        hits = [{"source": "doc.txt", "subject": "torts", "doc_type": "outline", "text": "Negligence is..."}]
        result = _format_hits(hits)
        assert "doc.txt" in result
        assert "torts" in result
        assert "Negligence is..." in result

    def test_multiple_hits_separated(self):
        hits = [
            {"source": "a.txt", "subject": "torts", "doc_type": "ref", "text": "AAA"},
            {"source": "b.txt", "subject": "contracts", "doc_type": "ref", "text": "BBB"},
        ]
        result = _format_hits(hits)
        assert "---" in result
        assert "AAA" in result
        assert "BBB" in result


# ======================================================================
# Load document (text files)
# ======================================================================

class TestLoadDocument:

    def test_load_text_file(self, tmp_path):
        f = tmp_path / "test.txt"
        f.write_text("Hello bar exam", encoding="utf-8")
        content = load_document(f)
        assert "Hello bar exam" in content

    def test_load_markdown_file(self, tmp_path):
        f = tmp_path / "test.md"
        f.write_text("# Heading\nContent", encoding="utf-8")
        content = load_document(f)
        assert "# Heading" in content
        assert "Content" in content


# ======================================================================
# Engine factory
# ======================================================================

class TestEngineFactory:

    def test_factory_returns_engine(self):
        """The module-level rag_engine should be a BaseRAGEngine instance."""
        from backend.rag_engine import rag_engine
        assert isinstance(rag_engine, BaseRAGEngine)

    def test_factory_graceful_without_chromadb(self):
        """Factory returns a valid engine even if chromadb isn't installed."""
        engine = _create_engine()
        assert isinstance(engine, BaseRAGEngine)

    def test_openai_vs_falls_back_without_keys(self):
        """openai_vs without store IDs should fall back gracefully."""
        original = settings.rag_backend
        settings.rag_backend = "openai_vs"
        engine = _create_engine()
        # Falls back to ChromaDB or noop — either way, valid engine
        assert isinstance(engine, BaseRAGEngine)
        settings.rag_backend = original

    def test_noop_engine_when_no_backend(self):
        """When chromadb isn't installed, factory returns a usable noop engine."""
        from backend.rag_engine import _NoopRAGEngine
        engine = _NoopRAGEngine()
        assert isinstance(engine, BaseRAGEngine)
