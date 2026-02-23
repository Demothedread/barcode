"""
BarGrader – LLM Client
Streaming responses with automatic fallback chain:
  OpenAI → Gemini → Groq → GitHub Models (Claude) → local llama.cpp

Includes shorthand/abbreviation preprocessing for voice-transcribed input.
Groq also provides fallback TTS and STT capabilities.
"""
import json
import re
import asyncio
from typing import AsyncGenerator

from backend.config import settings


# ---------------------------------------------------------------------------
# Legal shorthand / abbreviation expansion
# ---------------------------------------------------------------------------

# Common bar-exam shorthand that Whisper or hurried dictation may produce
_SHORTHAND_MAP = {
    r'\bK\b': 'contract',
    r'\bKs\b': 'contracts',
    r'\bD\b': 'defendant',
    r'\bDs\b': 'defendants',
    r'\bP\b': 'plaintiff',
    r'\bPs\b': 'plaintiffs',
    r'\bΔ\b': 'defendant',
    r'\bπ\b': 'plaintiff',
    r'\bR\b(?!\s*:)': 'rule',       # avoid R: header
    r'\bSOF\b': 'Statute of Frauds',
    r'\bSOL\b': 'Statute of Limitations',
    r'\bUCC\b': 'Uniform Commercial Code',
    r'\bBFP\b': 'bona fide purchaser',
    r'\bNeg\b': 'negligence',
    r'\bConLaw\b': 'Constitutional Law',
    r'\bCrimLaw\b': 'Criminal Law',
    r'\bCiv\s*Pro\b': 'Civil Procedure',
    r'\bCrim\s*Pro\b': 'Criminal Procedure',
    r'\bJ/X\b': 'jurisdiction',
    r'\bDP\b': 'due process',
    r'\bEP\b': 'equal protection',
    r'\bRIL\b': 'res ipsa loquitur',
    r'\bMP[CS]?\b': 'Model Penal Code',
    r'\bCP\b': 'community property',
    r'\bSP\b': 'separate property',
    r'\bJT\b': 'joint tenancy',
    r'\bTIC\b': 'tenancy in common',
    r'\bFRE\b': 'Federal Rules of Evidence',
    r'\bMBE\b': 'Multistate Bar Examination',
    r'\bI/C\b': 'independent contractor',
    r'\bC/A\b': 'cause of action',
    r'\bR/E\b': 'real estate',
    r'\bTF\b': 'transferred intent',
    r'\bPER\b': 'parol evidence rule',
}

_SHORTHAND_COMPILED = [(re.compile(k, re.IGNORECASE), v) for k, v in _SHORTHAND_MAP.items()]


def expand_shorthand(text: str) -> str:
    """Expand legal abbreviations/shorthand in user input."""
    result = text
    for pattern, replacement in _SHORTHAND_COMPILED:
        result = pattern.sub(replacement, result)
    return result


# ---------------------------------------------------------------------------
# Provider credential / reachability helpers
# ---------------------------------------------------------------------------

_PROVIDER_CHECK_URLS = {
    "openai":  "https://api.openai.com/v1/models",
    "gemini":  "https://generativelanguage.googleapis.com/",
    "groq":    "https://api.groq.com/openai/v1/models",
    "github":  "https://models.github.ai/inference",
}


def _has_credentials(provider: str) -> bool:
    """Return True if the required API key / path is configured."""
    if provider == "openai":  return bool(settings.openai_api_key)
    if provider == "gemini":  return bool(settings.gemini_api_key)
    if provider == "groq":    return bool(settings.groq_api_key)
    if provider == "github":  return bool(settings.github_token)
    if provider == "local":   return bool(settings.local_model_path)
    return False


async def _is_provider_reachable(provider: str, timeout: float = 3.0) -> bool:
    """Quick connectivity check (HEAD request, 3-second timeout)."""
    url = _PROVIDER_CHECK_URLS.get(provider)
    if not url:
        return False
    try:
        import httpx
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.head(url)
            return resp.status_code < 500
    except Exception:
        return False


# ---------------------------------------------------------------------------
# LLM Streaming — fallback chain
# ---------------------------------------------------------------------------

async def stream_llm_response(messages: list) -> AsyncGenerator[str, None]:
    """Stream tokens from the first reachable provider in the fallback chain.

    Chain order is defined by ``settings.llm_fallback_chain``
    (default: openai,gemini,grok,github,local).
    Providers that lack credentials are skipped silently.
    """
    chain = settings.fallback_chain
    last_error: Exception | None = None

    for provider in chain:
        if not _has_credentials(provider):
            continue

        # Local doesn't need a reachability check
        if provider != "local":
            if not await _is_provider_reachable(provider):
                print(f"[LLM] {provider} unreachable — trying next provider")
                continue

        try:
            print(f"[LLM] Using provider: {provider}")
            tokens_yielded = False
            async for token in _stream_for_provider(provider, messages):
                tokens_yielded = True
                yield token
            if tokens_yielded:
                return  # success — stop the chain
        except Exception as e:
            print(f"[LLM] {provider} error: {e} — trying next provider")
            last_error = e
            continue

    yield f"[ERROR] All LLM providers failed. Last error: {last_error}"


async def _stream_for_provider(provider: str, messages: list) -> AsyncGenerator[str, None]:
    """Dispatch to the correct streaming function."""
    if provider == "openai":
        async for t in _stream_openai(messages): yield t
    elif provider == "gemini":
        async for t in _stream_gemini(messages): yield t
    elif provider == "groq":
        async for t in _stream_groq(messages): yield t
    elif provider == "github":
        async for t in _stream_github(messages): yield t
    elif provider == "local":
        async for t in _stream_local(messages): yield t
    else:
        yield f"[ERROR] Unknown LLM provider: {provider}"


# ---------------------------------------------------------------------------
# Provider implementations
# ---------------------------------------------------------------------------

async def _stream_openai_compatible(
    api_key: str,
    model: str,
    messages: list,
    base_url: str | None = None,
) -> AsyncGenerator[str, None]:
    """Shared streaming helper for all OpenAI-compatible endpoints."""
    from openai import AsyncOpenAI

    kwargs = {"api_key": api_key}
    if base_url:
        kwargs["base_url"] = base_url
    client = AsyncOpenAI(**kwargs)

    stream = await client.chat.completions.create(
        model=model,
        messages=messages,
        stream=True,
        temperature=0.3,
        max_tokens=4096,
    )
    async for chunk in stream:
        delta = chunk.choices[0].delta
        if delta.content:
            yield delta.content


async def _stream_openai(messages: list) -> AsyncGenerator[str, None]:
    async for t in _stream_openai_compatible(
        api_key=settings.openai_api_key,
        model=settings.openai_model,
        messages=messages,
    ):
        yield t


async def _stream_gemini(messages: list) -> AsyncGenerator[str, None]:
    """Google Gemini via its OpenAI-compatible endpoint.
    Gemini doesn't natively support system role — convert to user/assistant pair.
    """
    converted, system_parts = [], []
    for m in messages:
        if m["role"] == "system":
            system_parts.append(m["content"])
        else:
            converted.append(m)
    if system_parts:
        converted.insert(0, {"role": "user", "content": "SYSTEM INSTRUCTIONS:\n" + "\n\n".join(system_parts)})
        converted.insert(1, {"role": "assistant", "content": "Understood. I will follow these instructions precisely."})

    async for t in _stream_openai_compatible(
        api_key=settings.gemini_api_key,
        model=settings.gemini_model,
        messages=converted,
        base_url="https://generativelanguage.googleapis.com/v1beta/openai/",
    ):
        yield t


async def _stream_groq(messages: list) -> AsyncGenerator[str, None]:
    """Groq (fast inference) via its OpenAI-compatible endpoint."""
    async for t in _stream_openai_compatible(
        api_key=settings.groq_api_key,
        model=settings.groq_model,
        messages=messages,
        base_url=settings.groq_endpoint,
    ):
        yield t


async def _stream_github(messages: list) -> AsyncGenerator[str, None]:
    """GitHub Models (Claude, etc.) via its OpenAI-compatible inference endpoint.
    Requires a GitHub PAT with the `models` scope. Set GITHUB_TOKEN in .env.
    """
    async for t in _stream_openai_compatible(
        api_key=settings.github_token,
        model=settings.github_model,
        messages=messages,
        base_url="https://models.github.ai/inference",
    ):
        yield t


async def _stream_local(messages: list) -> AsyncGenerator[str, None]:
    """Stream from a local GGUF model via llama-cpp-python (offline fallback)."""
    try:
        from llama_cpp import Llama
    except ImportError:
        yield "[ERROR] llama-cpp-python not installed. Run: pip install llama-cpp-python"
        return

    if not settings.local_model_path:
        yield "[ERROR] LOCAL_MODEL_PATH not configured in .env"
        return

    # Lazy-load model (expensive; cached as module-level singleton)
    global _llama_model
    if "_llama_model" not in globals() or _llama_model is None:
        print(f"[LLM] Loading local model: {settings.local_model_path}")
        _llama_model = Llama(
            model_path=settings.local_model_path,
            n_ctx=settings.local_model_n_ctx,
            n_gpu_layers=settings.local_model_n_gpu_layers,
            verbose=False,
        )

    # Build a single prompt string from messages (chat-ML style)
    prompt_parts = []
    for m in messages:
        role = m["role"]
        content = m["content"]
        if role == "system":
            prompt_parts.append(f"<|im_start|>system\n{content}<|im_end|>")
        elif role == "user":
            prompt_parts.append(f"<|im_start|>user\n{content}<|im_end|>")
        elif role == "assistant":
            prompt_parts.append(f"<|im_start|>assistant\n{content}<|im_end|>")
    prompt_parts.append("<|im_start|>assistant\n")
    full_prompt = "\n".join(prompt_parts)

    # Stream via llama_cpp (synchronous generator → yield via asyncio)
    loop = asyncio.get_event_loop()

    def _generate():
        return _llama_model(
            full_prompt,
            max_tokens=4096,
            temperature=0.3,
            stream=True,
            stop=["<|im_end|>"],
        )

    stream = await loop.run_in_executor(None, _generate)

    for output in stream:
        choices = output.get("choices", [])
        if choices:
            text = choices[0].get("text", "")
            if text:
                yield text
                await asyncio.sleep(0)  # yield control to event loop

_llama_model = None  # module-level singleton for local model


async def transcribe_audio(audio_bytes: bytes, filename: str = "audio.webm") -> str:
    """Transcribe audio — tries OpenAI Whisper first, falls back to Groq Whisper."""
    import io

    # --- Try OpenAI first ---
    if settings.openai_api_key:
        try:
            from openai import AsyncOpenAI
            client = AsyncOpenAI(api_key=settings.openai_api_key)
            audio_file = io.BytesIO(audio_bytes)
            audio_file.name = filename
            transcript = await client.audio.transcriptions.create(
                model="whisper-1",
                file=audio_file,
                language="en",
                prompt="California bar exam essay question legal terminology",
            )
            return transcript.text
        except Exception as e:
            print(f"[STT] OpenAI Whisper failed: {e} — trying Groq")

    # --- Fallback to Groq Whisper ---
    if settings.groq_api_key:
        try:
            from openai import AsyncOpenAI
            client = AsyncOpenAI(
                api_key=settings.groq_api_key,
                base_url=settings.groq_endpoint,
            )
            audio_file = io.BytesIO(audio_bytes)
            audio_file.name = filename
            transcript = await client.audio.transcriptions.create(
                model=settings.groq_stt_model,
                file=audio_file,
                language="en",
                prompt="California bar exam essay question legal terminology",
            )
            return transcript.text
        except Exception as e:
            print(f"[STT] Groq Whisper failed: {e}")

    return "[ERROR] No STT provider available"


async def generate_tts(text: str, voice: str = None, speed: float = None) -> bytes:
    """Generate TTS audio — tries OpenAI TTS first, falls back to Groq TTS.
    Returns mp3 bytes."""

    voice = voice or settings.tts_voice
    speed = speed or settings.tts_speed

    # --- Try OpenAI TTS first ---
    if settings.openai_api_key:
        try:
            from openai import AsyncOpenAI
            client = AsyncOpenAI(api_key=settings.openai_api_key)
            response = await client.audio.speech.create(
                model="tts-1",
                voice=voice,
                input=text,
                speed=speed,
                response_format="mp3",
            )
            return response.content
        except Exception as e:
            print(f"[TTS] OpenAI TTS failed: {e} — trying Groq")

    # --- Fallback to Groq TTS ---
    if settings.groq_api_key:
        try:
            from openai import AsyncOpenAI
            client = AsyncOpenAI(
                api_key=settings.groq_api_key,
                base_url=settings.groq_endpoint,
            )
            response = await client.audio.speech.create(
                model=settings.groq_tts_model,
                voice=voice,
                input=text,
                speed=speed,
                response_format="mp3",
            )
            return response.content
        except Exception as e:
            print(f"[TTS] Groq TTS failed: {e}")

    raise RuntimeError("No TTS provider available")
