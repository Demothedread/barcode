"""
Shared fixtures for Bartender tests.

Patches environment variables BEFORE importing any backend modules
so Settings() never touches real API keys or .env files.
"""
import os
import sys
import pytest

# ---------------------------------------------------------------------------
# Environment isolation — set BEFORE any backend import
# ---------------------------------------------------------------------------
_TEST_ENV = {
    "OPENAI_API_KEY": "sk-test-key-000",
    "OPENAI_MODEL": "gpt-4o-test",
    "GEMINI_API_KEY": "gem-test-key",
    "GEMINI_MODEL": "gemini-test",
    "GROQ_API_KEY": "gsk-test-key",
    "GROQ_MODEL": "llama-test",
    "GROQ_TTS_MODEL": "playai-tts",
    "GROQ_STT_MODEL": "whisper-large-v3-turbo",
    "GROQ_ENDPOINT": "https://api.groq.com/openai/v1",
    "GITHUB_TOKEN": "ghp-test-token",
    "GITHUB_MODEL": "test/claude",
    "LOCAL_MODEL_PATH": "",
    "LLM_PROVIDER": "openai",
    "LLM_FALLBACK_CHAIN": "openai,gemini,groq,github,local",
    "RAG_BACKEND": "chromadb",
    "OPENAI_VECTOR_ESSAY_EXEMPLARY": "",
    "OPENAI_VECTOR_SOURCE": "",
    "OPENAI_VECTOR_ESSAY_ATTACK": "",
    "TTS_SPEED": "0.55",
    "TTS_VOICE": "nova",
    "HOST": "0.0.0.0",
    "PORT": "8080",
    "SERVER_URL": "http://localhost:8080",
    "CHROMA_PERSIST_DIR": "/tmp/bargrader_test_chroma",
}

for k, v in _TEST_ENV.items():
    os.environ[k] = v


# ---------------------------------------------------------------------------
# Async test default mode
# ---------------------------------------------------------------------------
@pytest.fixture
def anyio_backend():
    return "asyncio"
