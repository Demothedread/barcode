"""
BarGrader – Main FastAPI Application
WebSocket-based real-time bar exam essay tutor.
"""
import asyncio
import json
import base64
import os
from pathlib import Path
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, UploadFile, File, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware

from backend.config import settings, BASE_DIR
from backend.rag_engine import rag_engine
from backend.prompts import (
    build_prompt,
    build_essay_from_outline_prompt,
    detect_mode_command,
    strip_outline_trigger,
    strip_mbe_trigger,
)
from backend.llm_client import stream_llm_response, transcribe_audio, generate_tts, expand_shorthand, preload_local_model


# ---------------------------------------------------------------------------
# Lifespan – ingest docs on startup, pre-load local model
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    print("[BarGrader] Starting up...")
    doc_count = await rag_engine.doc_count()
    if doc_count == 0:
        print("[BarGrader] No docs in vector store – ingesting from data/bar_exam_docs/...")
        await rag_engine.ingest_directory()
    else:
        print(f"[BarGrader] Vector store has {doc_count} chunks ready.")
    # Pre-load local GGUF model so offline fallback has no cold-start delay
    preload_local_model()
    print(f"[BarGrader] Server: {settings.server_url}")
    print(f"[BarGrader] LLM chain: {settings.llm_fallback_chain}")
    print(f"[BarGrader] RAG backend: {settings.rag_backend}")
    yield
    print("[BarGrader] Shutting down.")


app = FastAPI(
    title="BarGrader",
    description="California Bar Exam Essay AI Tutor with IRAC",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS for iPhone access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serve frontend (skip if directory missing — e.g. cloud deploy)
FRONTEND_DIR = BASE_DIR / "frontend"
if FRONTEND_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(FRONTEND_DIR)), name="static")


# ---------------------------------------------------------------------------
# REST Endpoints
# ---------------------------------------------------------------------------

@app.get("/", response_class=HTMLResponse)
async def root():
    index = FRONTEND_DIR / "index.html"
    if index.exists():
        return HTMLResponse(content=index.read_text())
    return HTMLResponse(content="<h1>BarGrader API</h1><p>Server is running. Connect via the iOS app.</p>")


@app.get("/manifest.json")
async def manifest():
    return FileResponse(FRONTEND_DIR / "manifest.json")


@app.get("/sw.js")
async def service_worker():
    return FileResponse(FRONTEND_DIR / "sw.js", media_type="application/javascript")


@app.get("/api/health")
async def health():
    return {
        "status": "ok",
        "docs_loaded": await rag_engine.doc_count(),
        "rag_backend": settings.rag_backend,
        "llm_chain": settings.llm_fallback_chain,
        "tts_speed": settings.tts_speed,
        "tts_voice": settings.tts_voice,
    }


@app.get("/api/settings")
async def get_settings():
    return {
        "tts_speed": settings.tts_speed,
        "tts_voice": settings.tts_voice,
        "silence_threshold": settings.silence_threshold_seconds,
        "wake_word": settings.wake_word,
        "llm_chain": settings.llm_fallback_chain,
        "rag_backend": settings.rag_backend,
    }


@app.post("/api/settings")
async def update_settings(body: dict):
    """Update runtime settings (non-persistent, session only)."""
    if "tts_speed" in body:
        settings.tts_speed = float(body["tts_speed"])
    if "tts_voice" in body:
        settings.tts_voice = body["tts_voice"]
    if "silence_threshold" in body:
        settings.silence_threshold_seconds = float(body["silence_threshold"])
    if "wake_word" in body:
        settings.wake_word = body["wake_word"]
    return {"status": "updated"}


@app.post("/api/ingest")
async def ingest_docs():
    """Re-ingest all documents from data/bar_exam_docs/."""
    count = await rag_engine.ingest_directory()
    return {"status": "ok", "chunks_ingested": count}


@app.post("/api/ingest-text")
async def ingest_text(body: dict):
    """Ingest raw text directly."""
    text = body.get("text", "")
    source = body.get("source", "manual")
    if not text.strip():
        raise HTTPException(400, "No text provided")
    count = await rag_engine.ingest_text(text, source)
    return {"status": "ok", "chunks_ingested": count}


@app.post("/api/transcribe")
async def transcribe_endpoint(file: UploadFile = File(...)):
    """Transcribe uploaded audio file."""
    audio_bytes = await file.read()
    text = await transcribe_audio(audio_bytes, file.filename or "audio.webm")
    return {"text": text}


@app.post("/api/tts")
async def tts_endpoint(body: dict):
    """Generate TTS audio, return base64-encoded MP3."""
    text = body.get("text", "")
    if not text.strip():
        raise HTTPException(400, "No text provided")
    voice = body.get("voice", settings.tts_voice)
    speed = float(body.get("speed", settings.tts_speed))
    audio = await generate_tts(text, voice, speed)
    b64 = base64.b64encode(audio).decode()
    return {"audio_base64": b64, "format": "mp3"}


# ---------------------------------------------------------------------------
# WebSocket – Main interaction loop (with per-session state)
# ---------------------------------------------------------------------------

class SessionState:
    """Per-WebSocket-connection state. Tracks mode, last outline, and question."""
    __slots__ = ("mode", "last_question", "last_outline", "last_rag_context",
                 "awaiting_essay_confirm")

    def __init__(self):
        self.mode: str = "essay"          # "essay", "outline", or "mbe"
        self.last_question: str = ""
        self.last_outline: str = ""
        self.last_rag_context: str = ""
        self.awaiting_essay_confirm: bool = False

    def reset(self):
        """Clear all session memory — triggered by 'Next Question' / 'start over'."""
        self.mode = "essay"
        self.last_question = ""
        self.last_outline = ""
        self.last_rag_context = ""
        self.awaiting_essay_confirm = False


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await ws.accept()
    print("[WS] Client connected")
    session = SessionState()

    try:
        while True:
            data = await ws.receive_text()
            msg = json.loads(data)
            msg_type = msg.get("type")

            if msg_type == "audio":
                # Receive base64 audio, transcribe, then route
                audio_b64 = msg.get("audio", "")
                audio_bytes = base64.b64decode(audio_b64)
                await ws.send_text(json.dumps({"type": "status", "text": "Transcribing..."}))

                transcript = await transcribe_audio(audio_bytes)
                await ws.send_text(json.dumps({
                    "type": "transcript",
                    "text": transcript,
                }))

                await _route_question(ws, session, transcript)

            elif msg_type == "text":
                question = msg.get("text", "").strip()
                if question:
                    await _route_question(ws, session, question)

            elif msg_type == "repeat":
                section = msg.get("section", "")
                await ws.send_text(json.dumps({
                    "type": "status",
                    "text": f"Repeating: {section}...",
                }))
                tts_audio = await generate_tts(section)
                b64 = base64.b64encode(tts_audio).decode()
                await ws.send_text(json.dumps({
                    "type": "tts",
                    "audio_base64": b64,
                }))

            elif msg_type == "reset":
                # Explicit reset from UI button
                session.reset()
                await ws.send_text(json.dumps({
                    "type": "reset_ack",
                    "text": "Session cleared. Ready for a new question.",
                }))

            elif msg_type == "ping":
                await ws.send_text(json.dumps({"type": "pong"}))

    except WebSocketDisconnect:
        print("[WS] Client disconnected")
    except Exception as e:
        print(f"[WS] Error: {e}")
        try:
            await ws.send_text(json.dumps({"type": "error", "text": str(e)}))
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Command router — detects mode triggers before answering
# ---------------------------------------------------------------------------

async def _route_question(ws: WebSocket, session: SessionState, raw_text: str):
    """Parse commands (reset / outline / yes / normal) and route accordingly."""

    # 0. Expand shorthand first
    expanded = expand_shorthand(raw_text)
    if expanded != raw_text:
        print(f"[Shorthand] '{raw_text}' → '{expanded}'")
        await ws.send_text(json.dumps({
            "type": "status",
            "text": f"Interpreted: {expanded}",
        }))
        raw_text = expanded

    # 1. Detect command type
    command = detect_mode_command(raw_text)

    # --- RESET ---
    if command == "reset":
        session.reset()
        await ws.send_text(json.dumps({
            "type": "reset_ack",
            "text": "Session cleared. Ready for a new question.",
        }))
        return

    # --- YES (confirm outline → essay) ---
    if command == "yes" and session.awaiting_essay_confirm and session.last_outline:
        session.awaiting_essay_confirm = False
        await ws.send_text(json.dumps({
            "type": "mode_change",
            "mode": "essay",
            "text": "Generating full essay from outline...",
        }))
        await _answer_essay_from_outline(ws, session)
        return

    # --- OUTLINE ONLY ---
    if command == "outline":
        question = strip_outline_trigger(raw_text)
        if not question.strip():
            await ws.send_text(json.dumps({
                "type": "error",
                "text": "Please include a question after 'outline only'.",
            }))
            return
        session.mode = "outline"
        await ws.send_text(json.dumps({
            "type": "mode_change",
            "mode": "outline",
            "text": "Outline mode — generating issue outline...",
        }))
        await _answer_question(ws, session, question, mode="outline")
        return

    # --- MBE / EXAM MODE ---
    if command == "mbe":
        question = strip_mbe_trigger(raw_text)
        if not question.strip():
            await ws.send_text(json.dumps({
                "type": "error",
                "text": "Please include a question after 'exam mode' or 'question mode'.",
            }))
            return
        session.mode = "mbe"
        await ws.send_text(json.dumps({
            "type": "mode_change",
            "mode": "mbe",
            "text": "MBE mode — concise bar exam answer...",
        }))
        await _answer_question(ws, session, question, mode="mbe")
        return

    # --- NORMAL QUESTION (essay mode) ---
    session.mode = "essay"
    session.awaiting_essay_confirm = False
    await _answer_question(ws, session, raw_text, mode="essay")


# ---------------------------------------------------------------------------
# Core answer pipeline
# ---------------------------------------------------------------------------

async def _answer_question(ws: WebSocket, session: SessionState, question: str, mode: str = "essay"):
    """RAG retrieve → build prompt → stream LLM → send TTS chunks with section pauses."""
    session.last_question = question

    # 1. RAG retrieval
    await ws.send_text(json.dumps({"type": "status", "text": "Searching knowledge base..."}))
    rag_context = await rag_engine.get_context_block(question, mode=mode)
    session.last_rag_context = rag_context

    # 2. Build prompt
    messages = build_prompt(question, rag_context, mode=mode)
    if mode == "mbe":
        status_msg = "Answering bar exam question..."
    elif mode == "outline":
        status_msg = "Generating IRAC outline..."
    else:
        status_msg = "Generating IRAC answer..."
    await ws.send_text(json.dumps({"type": "status", "text": status_msg}))

    # 3. Stream LLM tokens (MBE uses simple streaming — no section breaks)
    if mode == "mbe":
        complete_text = await _stream_simple(ws, messages)
    else:
        complete_text = await _stream_with_tts(ws, messages)

    # 4. Store outline for potential essay expansion
    if mode == "outline":
        session.last_outline = complete_text
        session.awaiting_essay_confirm = True
        await ws.send_text(json.dumps({
            "type": "done",
            "text": complete_text,
        }))
        # Prompt user: would you like the full essay?
        await ws.send_text(json.dumps({
            "type": "outline_prompt",
            "text": "Would you like me to write the full essay from this outline?",
        }))
    elif mode == "mbe":
        session.last_outline = ""
        session.awaiting_essay_confirm = False
        await ws.send_text(json.dumps({
            "type": "done",
            "text": complete_text,
        }))
    else:
        session.last_outline = ""
        session.awaiting_essay_confirm = False
        await ws.send_text(json.dumps({
            "type": "done",
            "text": complete_text,
        }))
        await ws.send_text(json.dumps({
            "type": "tts_prompt",
            "text": "Would you like me to repeat any section?",
        }))


async def _answer_essay_from_outline(ws: WebSocket, session: SessionState):
    """Generate a full essay using the stored outline as blueprint."""
    await ws.send_text(json.dumps({
        "type": "status",
        "text": "Writing full essay from outline...",
    }))

    messages = build_essay_from_outline_prompt(
        original_question=session.last_question,
        outline_text=session.last_outline,
        rag_context=session.last_rag_context,
    )

    complete_text = await _stream_with_tts(ws, messages)

    session.awaiting_essay_confirm = False
    await ws.send_text(json.dumps({
        "type": "done",
        "text": complete_text,
    }))
    await ws.send_text(json.dumps({
        "type": "tts_prompt",
        "text": "Would you like me to repeat any section?",
    }))


# ---------------------------------------------------------------------------
# Shared streaming + TTS helper
# ---------------------------------------------------------------------------

async def _stream_simple(ws: WebSocket, messages: list) -> str:
    """Lightweight streamer for MBE mode — no section breaks, single TTS at end."""
    full_answer = []
    async for token in stream_llm_response(messages):
        full_answer.append(token)
        await ws.send_text(json.dumps({"type": "token", "text": token}))

    complete = "".join(full_answer).strip()
    if complete:
        try:
            tts_audio = await generate_tts(complete)
            b64 = base64.b64encode(tts_audio).decode()
            await ws.send_text(json.dumps({"type": "tts", "audio_base64": b64}))
        except Exception as e:
            print(f"[TTS] Error: {e}")
    return complete


async def _stream_with_tts(ws: WebSocket, messages: list) -> str:
    """Stream LLM tokens to the client, detect [SECTION_BREAK] markers, batch TTS.
    Returns the complete answer text."""
    full_answer = []
    buffer = []
    sentence_end_chars = {'.', '!', '?', ':'}
    section_break_marker = "[SECTION_BREAK]"
    section_break_buffer = ""

    async for token in stream_llm_response(messages):
        section_break_buffer += token
        if section_break_marker in section_break_buffer:
            before, _, after = section_break_buffer.partition(section_break_marker)
            section_break_buffer = after

            if before.strip():
                full_answer.append(before)
                buffer.append(before)
                await ws.send_text(json.dumps({"type": "token", "text": before}))

            joined = "".join(buffer).strip()
            if joined:
                try:
                    tts_audio = await generate_tts(joined)
                    b64 = base64.b64encode(tts_audio).decode()
                    await ws.send_text(json.dumps({"type": "tts", "audio_base64": b64}))
                except Exception as e:
                    print(f"[TTS] Error: {e}")
                buffer = []

            pause_secs = settings.section_pause_seconds
            await ws.send_text(json.dumps({
                "type": "section_pause",
                "seconds": pause_secs,
            }))
            full_answer.append(f"\n\n[{pause_secs}s pause]\n\n")

            if after.strip():
                full_answer.append(after)
                buffer.append(after)
                await ws.send_text(json.dumps({"type": "token", "text": after}))
            continue

        if len(section_break_buffer) > len(section_break_marker) + 5:
            safe = section_break_buffer[: -(len(section_break_marker))]
            section_break_buffer = section_break_buffer[-(len(section_break_marker)):]

            full_answer.append(safe)
            buffer.append(safe)
            await ws.send_text(json.dumps({"type": "token", "text": safe}))

            joined = "".join(buffer)
            if any(joined.rstrip().endswith(c) for c in sentence_end_chars) and len(joined) > 40:
                try:
                    tts_audio = await generate_tts(joined.strip())
                    b64 = base64.b64encode(tts_audio).decode()
                    await ws.send_text(json.dumps({"type": "tts", "audio_base64": b64}))
                except Exception as e:
                    print(f"[TTS] Error: {e}")
                buffer = []

    # Flush remaining section_break_buffer
    remaining_sb = section_break_buffer.strip()
    if remaining_sb and section_break_marker not in remaining_sb:
        full_answer.append(remaining_sb)
        buffer.append(remaining_sb)
        await ws.send_text(json.dumps({"type": "token", "text": remaining_sb}))

    # Flush remaining TTS buffer
    remaining = "".join(buffer).strip()
    if remaining:
        try:
            tts_audio = await generate_tts(remaining)
            b64 = base64.b64encode(tts_audio).decode()
            await ws.send_text(json.dumps({"type": "tts", "audio_base64": b64}))
        except Exception as e:
            print(f"[TTS] Error: {e}")

    return "".join(full_answer)
