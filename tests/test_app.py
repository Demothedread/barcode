"""
Tests for backend/app.py — REST endpoints, SessionState, WebSocket flow.

Uses httpx + FastAPI TestClient for HTTP, and websocket_connect for WS.
"""
import json
import base64
import pytest
import asyncio
from unittest.mock import patch, AsyncMock, MagicMock

from fastapi.testclient import TestClient

from backend.app import app, SessionState


# ======================================================================
# SessionState
# ======================================================================

class TestSessionState:

    def test_initial_state(self):
        s = SessionState()
        assert s.mode == "essay"
        assert s.last_question == ""
        assert s.last_outline == ""
        assert s.last_rag_context == ""
        assert s.awaiting_essay_confirm is False

    def test_reset(self):
        s = SessionState()
        s.mode = "outline"
        s.last_question = "What is negligence?"
        s.last_outline = "I. Duty\nII. Breach"
        s.awaiting_essay_confirm = True
        s.reset()
        assert s.mode == "essay"
        assert s.last_question == ""
        assert s.last_outline == ""
        assert s.awaiting_essay_confirm is False


# ======================================================================
# REST endpoints
# ======================================================================

class TestRESTEndpoints:

    @pytest.fixture(autouse=True)
    def client(self):
        """TestClient that patches lifespan to skip doc ingestion."""
        self.test_client = TestClient(app, raise_server_exceptions=False)
        return self.test_client

    def test_health_endpoint(self):
        with patch("backend.app.rag_engine") as mock_rag:
            mock_rag.doc_count = AsyncMock(return_value=42)
            resp = self.test_client.get("/api/health")
            assert resp.status_code == 200
            data = resp.json()
            assert data["status"] == "ok"
            assert "rag_backend" in data
            assert "llm_chain" in data

    def test_get_settings_endpoint(self):
        resp = self.test_client.get("/api/settings")
        assert resp.status_code == 200
        data = resp.json()
        assert "tts_speed" in data
        assert "tts_voice" in data
        assert "wake_word" in data

    def test_post_settings_endpoint(self):
        resp = self.test_client.post("/api/settings", json={"tts_speed": 0.7})
        assert resp.status_code == 200
        assert resp.json()["status"] == "updated"

    def test_ingest_endpoint(self):
        with patch("backend.app.rag_engine") as mock_rag:
            mock_rag.ingest_directory = AsyncMock(return_value=10)
            resp = self.test_client.post("/api/ingest")
            assert resp.status_code == 200
            assert resp.json()["chunks_ingested"] == 10

    def test_ingest_text_endpoint(self):
        with patch("backend.app.rag_engine") as mock_rag:
            mock_rag.ingest_text = AsyncMock(return_value=3)
            resp = self.test_client.post("/api/ingest-text", json={"text": "Some legal text"})
            assert resp.status_code == 200
            assert resp.json()["chunks_ingested"] == 3

    def test_ingest_text_empty_rejected(self):
        resp = self.test_client.post("/api/ingest-text", json={"text": ""})
        assert resp.status_code == 400

    def test_tts_endpoint(self):
        with patch("backend.app.generate_tts", new_callable=AsyncMock) as mock_tts:
            mock_tts.return_value = b"fake-mp3-bytes"
            resp = self.test_client.post("/api/tts", json={"text": "Hello"})
            assert resp.status_code == 200
            data = resp.json()
            assert "audio_base64" in data
            assert data["format"] == "mp3"

    def test_tts_endpoint_empty_rejected(self):
        resp = self.test_client.post("/api/tts", json={"text": ""})
        assert resp.status_code == 400

    def test_transcribe_endpoint(self):
        with patch("backend.app.transcribe_audio", new_callable=AsyncMock) as mock_stt:
            mock_stt.return_value = "Hello world"
            resp = self.test_client.post(
                "/api/transcribe",
                files={"file": ("audio.webm", b"fake-audio-bytes", "audio/webm")},
            )
            assert resp.status_code == 200
            assert resp.json()["text"] == "Hello world"


# ======================================================================
# WebSocket — basic handshake and ping/pong
# ======================================================================

class TestWebSocket:

    def test_ping_pong(self):
        client = TestClient(app)
        with client.websocket_connect("/ws") as ws:
            ws.send_text(json.dumps({"type": "ping"}))
            data = json.loads(ws.receive_text())
            assert data["type"] == "pong"

    def test_reset_command(self):
        client = TestClient(app)
        with client.websocket_connect("/ws") as ws:
            ws.send_text(json.dumps({"type": "reset"}))
            data = json.loads(ws.receive_text())
            assert data["type"] == "reset_ack"
            assert "cleared" in data["text"].lower()

    def test_text_message_triggers_answer(self):
        """A text message should trigger the full answer pipeline (mocked)."""
        async def fake_stream(msgs):
            yield "Test answer."

        client = TestClient(app)
        with patch("backend.app.rag_engine") as mock_rag, \
             patch("backend.app.stream_llm_response", side_effect=fake_stream), \
             patch("backend.app.generate_tts", new_callable=AsyncMock) as mock_tts:

            mock_rag.get_context_block = AsyncMock(return_value="context")
            mock_tts.return_value = b"fake-mp3"

            with client.websocket_connect("/ws") as ws:
                ws.send_text(json.dumps({"type": "text", "text": "What is negligence?"}))

                # Collect messages until "done"
                messages = []
                for _ in range(20):
                    try:
                        raw = ws.receive_text()
                        msg = json.loads(raw)
                        messages.append(msg)
                        if msg["type"] == "done":
                            break
                    except Exception:
                        break

                types = [m["type"] for m in messages]
                assert "status" in types
                assert "done" in types
