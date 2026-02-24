"""
Bartender – California Bar Exam Essay AI Tutor
Configuration module

LLM fallback chain:  OpenAI → Gemini → Groq → GitHub Models (Claude) → local llama.cpp
RAG backends:        OpenAI Vector Stores (primary) | ChromaDB (offline fallback)
"""
from pydantic_settings import BaseSettings
from pathlib import Path
from typing import List, Tuple
import os

BASE_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    # ------------------------------------------------------------------
    # LLM — provider fallback chain (tried in order; skips unconfigured)
    # ------------------------------------------------------------------
    llm_provider: str = "openai"  # primary: openai | gemini | grok | github | local
    llm_fallback_chain: str = "openai,gemini,groq,github,local"

    # OpenAI (primary)
    openai_api_key: str = ""
    openai_model: str = "gpt-4o"

    # Google Gemini (backup 1) — OpenAI-compatible endpoint
    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.5-pro"

    # Groq (backup 2 — fast inference, free tier available)
    groq_api_key: str = ""
    groq_model: str = "llama-3.3-70b-versatile"
    groq_tts_model: str = "playai-tts"
    groq_stt_model: str = "whisper-large-v3-turbo"
    groq_endpoint: str = "https://api.groq.com/openai/v1"

    # GitHub Models → Claude (optional, needs a GitHub PAT w/ models scope)
    github_token: str = ""
    github_model: str = "anthropic/claude-sonnet-4-20250514"

    # ------------------------------------------------------------------
    # Offline / Local LLM (llama.cpp — final fallback & explicit offline)
    # ------------------------------------------------------------------
    local_model_path: str = ""          # path to .gguf model file
    local_model_n_ctx: int = 4096       # context window
    local_model_n_gpu_layers: int = 0   # 0 = CPU-only, -1 = all GPU
    offline_fallback: bool = True       # auto-fallback to local when all APIs fail

    # ------------------------------------------------------------------
    # Speech
    # ------------------------------------------------------------------
    tts_speed: float = 0.55             # ~80 WPM (TTS-1 baseline ~150 WPM at 1.0x)
    tts_voice: str = "nova"
    silence_threshold_seconds: float = 2.0
    wake_word: str = "hey bartender"
    section_pause_seconds: float = 5.0  # pause between IRAC sections

    # ------------------------------------------------------------------
    # Server
    # ------------------------------------------------------------------
    host: str = "0.0.0.0"
    port: int = 8080
    server_url: str = "http://localhost:8080"

    # ------------------------------------------------------------------
    # RAG — backend selector
    # ------------------------------------------------------------------
    rag_backend: str = "openai_vs"      # openai_vs | chromadb

    # OpenAI Vector Stores (primary RAG)
    openai_vector_essay_exemplary: str = ""
    openai_vector_source: str = ""
    openai_vector_essay_attack: str = ""

    # ChromaDB (offline / local RAG fallback)
    chroma_persist_dir: str = str(BASE_DIR / "data" / "chromadb")
    embedding_model: str = "all-MiniLM-L6-v2"
    chunk_size: int = 1000
    chunk_overlap: int = 200
    top_k_results: int = 5

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    @property
    def fallback_chain(self) -> List[str]:
        """Parsed fallback chain as a list."""
        return [p.strip() for p in self.llm_fallback_chain.split(",") if p.strip()]

    @property
    def openai_vs_store_map(self) -> dict:
        """Mapping of label → vector-store ID (deduplicated, non-empty only)."""
        raw = {
            "Essay Exemplary": self.openai_vector_essay_exemplary,
            "Source Material": self.openai_vector_source,
            "Essay Attack":   self.openai_vector_essay_attack,
        }
        return {k: v for k, v in raw.items() if v}

    def stores_for_mode(self, mode: str) -> List[Tuple[str, str]]:
        """Return ordered (label, vector-store-id) tuples for the given mode.

        Pipeline ordering:
          essay   → Exemplary → Attack → Source  (full depth)
          outline → Exemplary → Attack           (skip Source for speed)
          mbe     → Source only                   (bar materials compendium)
        """
        exemplary = ("Essay Exemplary", self.openai_vector_essay_exemplary)
        attack    = ("Essay Attack",    self.openai_vector_essay_attack)
        source    = ("Source Material",  self.openai_vector_source)

        if mode == "mbe":
            stages = [source]
        elif mode == "outline":
            stages = [exemplary, attack]
        else:  # essay (default)
            stages = [exemplary, attack, source]

        return [(label, vs_id) for label, vs_id in stages if vs_id]

    class Config:
        env_file = (str(BASE_DIR / ".env"), str(BASE_DIR / ".env.local"))
        env_file_encoding = "utf-8"


settings = Settings()
