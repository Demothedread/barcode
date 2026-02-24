#!/usr/bin/env bash
# ────────────────────────────────────────────────────────
# Bartender – Server Startup Script
# Starts the FastAPI backend that the iOS app connects to
# ────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "╔══════════════════════════════════════════════════╗"
echo "║          Bartender – CA Bar Exam AI Tutor        ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Check Python ──
PYTHON=""
for cmd in python3.11 python3.12 python3.10 python3; do
    if command -v "$cmd" &> /dev/null; then
        PYTHON="$cmd"
        break
    fi
done

if [ -z "$PYTHON" ]; then
    echo "[✗] Python 3.10+ not found. Install it:"
    echo "    brew install python@3.11"
    exit 1
fi
echo "[✓] Python: $($PYTHON --version)"

# ── Virtual environment ──
if [ ! -d "venv" ]; then
    echo "[…] Creating virtual environment..."
    $PYTHON -m venv venv
    echo "[✓] Virtual environment created"
fi
source venv/bin/activate

# ── Install dependencies ──
echo "[…] Installing/updating dependencies..."
pip install -q --upgrade pip
pip install -q -r requirements.txt
echo "[✓] Dependencies installed"

# ── .env check ──
if [ ! -f ".env" ]; then
    echo ""
    echo "[!] No .env file found!"
    echo "    Copying .env.example → .env"
    cp .env.example .env
    echo ""
    echo "    ⚠️  IMPORTANT: Edit .env and set your API keys:"
    echo "    - OPENAI_API_KEY (required for GPT-4 + Whisper + TTS)"
    echo "    - Or GEMINI_API_KEY if using Gemini"
    echo ""
    echo "    Then re-run this script."
    exit 0
fi

# ── Show local IP for iPhone connection ──
LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || echo "unknown")
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Your server will be available at:               ║"
echo "║  → http://$LOCAL_IP:8080                     ║"
echo "║                                                  ║"
echo "║  Set this URL in the iOS app Settings            ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Check for bar exam docs ──
DOC_COUNT=$(find data/bar_exam_docs -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$DOC_COUNT" = "0" ]; then
    echo "[!] No documents in data/bar_exam_docs/"
    echo "    Add your CA bar exam study materials (.pdf, .txt, .docx, .md)"
    echo "    The RAG system will index them on first startup."
    echo ""
fi

# ── Start server ──
echo "[▶] Starting Bartender server..."
echo ""
exec uvicorn backend.app:app \
    --host 0.0.0.0 \
    --port 8080 \
    --reload \
    --log-level info
