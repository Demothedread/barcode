"""
Tests for backend/llm_client.py — shorthand expansion, credential checks,
streaming fallback chain (mocked).
"""
import pytest
import asyncio
from unittest.mock import patch, AsyncMock, MagicMock

from backend.llm_client import (
    expand_shorthand,
    _has_credentials,
    _is_provider_reachable,
    stream_llm_response,
)
from backend.config import settings


# ======================================================================
# Shorthand expansion
# ======================================================================

class TestExpandShorthand:

    def test_basic_abbreviations(self):
        assert "contract" in expand_shorthand("K")
        assert "defendant" in expand_shorthand("D")
        assert "plaintiff" in expand_shorthand("P")

    def test_legal_abbreviations(self):
        assert "Statute of Frauds" in expand_shorthand("SOF")
        assert "Statute of Limitations" in expand_shorthand("SOL")
        assert "Uniform Commercial Code" in expand_shorthand("UCC")
        assert "bona fide purchaser" in expand_shorthand("BFP")

    def test_compound_abbreviations(self):
        assert "due process" in expand_shorthand("DP")
        assert "equal protection" in expand_shorthand("EP")
        assert "community property" in expand_shorthand("CP")
        assert "joint tenancy" in expand_shorthand("JT")

    def test_multi_word_abbreviations(self):
        assert "Civil Procedure" in expand_shorthand("Civ Pro")
        assert "Criminal Procedure" in expand_shorthand("Crim Pro")
        assert "Constitutional Law" in expand_shorthand("ConLaw")

    def test_preserves_non_shorthand(self):
        text = "The judge ruled in favor of the motion."
        assert expand_shorthand(text) == text

    def test_contextual_expansion(self):
        result = expand_shorthand("The D filed a motion against P under SOF")
        assert "defendant" in result
        assert "plaintiff" in result
        assert "Statute of Frauds" in result

    def test_case_insensitivity(self):
        assert "negligence" in expand_shorthand("Neg")
        assert "res ipsa loquitur" in expand_shorthand("RIL")

    def test_empty_string(self):
        assert expand_shorthand("") == ""


# ======================================================================
# Credential checking
# ======================================================================

class TestHasCredentials:

    def test_openai_configured(self):
        assert _has_credentials("openai") is True

    def test_gemini_configured(self):
        assert _has_credentials("gemini") is True

    def test_groq_configured(self):
        assert _has_credentials("groq") is True

    def test_github_configured(self):
        assert _has_credentials("github") is True

    def test_local_not_configured(self):
        # LOCAL_MODEL_PATH is empty in test env
        assert _has_credentials("local") is False

    def test_unknown_provider(self):
        assert _has_credentials("nonexistent") is False


# ======================================================================
# Reachability check (mocked)
# ======================================================================

class TestIsProviderReachable:

    @pytest.mark.asyncio
    async def test_reachable_returns_true(self):
        """Mock a successful HEAD request."""
        mock_response = MagicMock()
        mock_response.status_code = 200

        mock_client = AsyncMock()
        mock_client.head.return_value = mock_response
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("httpx.AsyncClient", return_value=mock_client):
            result = await _is_provider_reachable("openai")
            assert result is True

    @pytest.mark.asyncio
    async def test_unreachable_returns_false(self):
        """Mock a connection failure."""
        mock_client = AsyncMock()
        mock_client.head.side_effect = Exception("Connection refused")
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("httpx.AsyncClient", return_value=mock_client):
            result = await _is_provider_reachable("openai")
            assert result is False

    @pytest.mark.asyncio
    async def test_unknown_provider_no_url(self):
        result = await _is_provider_reachable("nonexistent")
        assert result is False


# ======================================================================
# Stream LLM fallback (mocked providers)
# ======================================================================

class TestStreamLLMFallback:

    @pytest.mark.asyncio
    async def test_yields_error_when_all_fail(self):
        """When every provider is unreachable, expect error message."""
        with patch("backend.llm_client._has_credentials", return_value=True), \
             patch("backend.llm_client._is_provider_reachable", return_value=False):

            # local also needs to fail
            original_chain = settings.llm_fallback_chain
            settings.llm_fallback_chain = "openai,gemini"  # no local in chain
            tokens = []
            async for tok in stream_llm_response([{"role": "user", "content": "test"}]):
                tokens.append(tok)
            settings.llm_fallback_chain = original_chain

            assert any("ERROR" in t for t in tokens)

    @pytest.mark.asyncio
    async def test_first_provider_success(self):
        """When first provider works, don't try the rest."""
        async def mock_openai_stream(messages):
            yield "Hello"
            yield " world"

        with patch("backend.llm_client._has_credentials", return_value=True), \
             patch("backend.llm_client._is_provider_reachable", return_value=True), \
             patch("backend.llm_client._stream_openai", side_effect=mock_openai_stream):

            original_chain = settings.llm_fallback_chain
            settings.llm_fallback_chain = "openai"
            tokens = []
            async for tok in stream_llm_response([{"role": "user", "content": "test"}]):
                tokens.append(tok)
            settings.llm_fallback_chain = original_chain

            assert "".join(tokens) == "Hello world"

    @pytest.mark.asyncio
    async def test_skips_unconfigured_provider(self):
        """Providers without credentials are silently skipped."""
        def fake_creds(provider):
            return provider == "groq"

        async def mock_groq_stream(messages):
            yield "Groq response"

        with patch("backend.llm_client._has_credentials", side_effect=fake_creds), \
             patch("backend.llm_client._is_provider_reachable", return_value=True), \
             patch("backend.llm_client._stream_groq", side_effect=mock_groq_stream):

            original_chain = settings.llm_fallback_chain
            settings.llm_fallback_chain = "openai,gemini,groq"
            tokens = []
            async for tok in stream_llm_response([{"role": "user", "content": "test"}]):
                tokens.append(tok)
            settings.llm_fallback_chain = original_chain

            assert "".join(tokens) == "Groq response"
