"""
Tests for backend/config.py — Settings, fallback chain, vector store map.
"""
import os
import pytest


class TestSettings:
    """Core settings loading and properties."""

    def test_settings_loads(self):
        from backend.config import settings
        assert settings is not None
        assert settings.openai_api_key == "sk-test-key-000"
        assert settings.port == 8080

    def test_fallback_chain_parsing(self):
        from backend.config import settings
        chain = settings.fallback_chain
        assert isinstance(chain, list)
        assert chain == ["openai", "gemini", "groq", "github", "local"]

    def test_fallback_chain_custom(self):
        """Changing the raw string should change the parsed chain."""
        from backend.config import settings
        original = settings.llm_fallback_chain
        settings.llm_fallback_chain = "groq,local"
        assert settings.fallback_chain == ["groq", "local"]
        settings.llm_fallback_chain = original  # restore

    def test_openai_vs_store_map_empty(self):
        """When no VS IDs set, store map is empty dict."""
        from backend.config import settings
        assert settings.openai_vs_store_map == {}

    def test_openai_vs_store_map_populated(self):
        from backend.config import settings
        original = settings.openai_vector_essay_exemplary
        settings.openai_vector_essay_exemplary = "vs_test_123"
        store_map = settings.openai_vs_store_map
        assert "Essay Exemplary" in store_map
        assert store_map["Essay Exemplary"] == "vs_test_123"
        settings.openai_vector_essay_exemplary = original

    def test_tts_defaults(self):
        from backend.config import settings
        # tts_speed may have been mutated by POST /api/settings tests;
        # just verify it's a valid float in range
        assert 0.1 <= settings.tts_speed <= 2.0
        assert settings.tts_voice == "nova"

    def test_rag_backend_value(self):
        from backend.config import settings
        assert settings.rag_backend == "chromadb"

    def test_stores_for_mode_essay(self):
        from backend.config import settings
        orig_ex = settings.openai_vector_essay_exemplary
        orig_at = settings.openai_vector_essay_attack
        orig_src = settings.openai_vector_source
        settings.openai_vector_essay_exemplary = "vs_ex"
        settings.openai_vector_essay_attack = "vs_at"
        settings.openai_vector_source = "vs_src"
        stores = settings.stores_for_mode("essay")
        assert len(stores) == 3
        assert stores[0] == ("Essay Exemplary", "vs_ex")
        assert stores[1] == ("Essay Attack", "vs_at")
        assert stores[2] == ("Source Material", "vs_src")
        settings.openai_vector_essay_exemplary = orig_ex
        settings.openai_vector_essay_attack = orig_at
        settings.openai_vector_source = orig_src

    def test_stores_for_mode_outline(self):
        from backend.config import settings
        orig_ex = settings.openai_vector_essay_exemplary
        orig_at = settings.openai_vector_essay_attack
        orig_src = settings.openai_vector_source
        settings.openai_vector_essay_exemplary = "vs_ex"
        settings.openai_vector_essay_attack = "vs_at"
        settings.openai_vector_source = "vs_src"
        stores = settings.stores_for_mode("outline")
        assert len(stores) == 2
        labels = [s[0] for s in stores]
        assert "Source Material" not in labels
        settings.openai_vector_essay_exemplary = orig_ex
        settings.openai_vector_essay_attack = orig_at
        settings.openai_vector_source = orig_src

    def test_stores_for_mode_mbe(self):
        from backend.config import settings
        orig_src = settings.openai_vector_source
        settings.openai_vector_source = "vs_src"
        stores = settings.stores_for_mode("mbe")
        assert len(stores) == 1
        assert stores[0] == ("Source Material", "vs_src")
        settings.openai_vector_source = orig_src
