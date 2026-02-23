#!/usr/bin/env bash
# ────────────────────────────────────────────────────────
# BarGrader – Full Setup Script (one-time)
# Run this once to install everything and prepare the system
# ────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "╔══════════════════════════════════════════════════╗"
echo "║     BarGrader – One-Time Setup                   ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── 1. System deps ──
echo "=== Step 1: System Dependencies ==="
if command -v brew &> /dev/null; then
    echo "[✓] Homebrew found"
    
    # Python
    if ! command -v python3 &> /dev/null; then
        echo "[…] Installing Python..."
        brew install python@3.11
    fi
    echo "[✓] Python: $(python3 --version)"
    
    # xcodegen (for Xcode project generation)
    if ! command -v xcodegen &> /dev/null; then
        echo "[…] Installing xcodegen..."
        brew install xcodegen
    fi
    echo "[✓] xcodegen available"
else
    echo "[!] Homebrew not found. Install it from https://brew.sh"
fi

# ── 2. Python venv + deps ──
echo ""
echo "=== Step 2: Python Environment ==="
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
echo "[✓] Python environment ready"

# ── 3. .env ──
echo ""
echo "=== Step 3: Configuration ==="
if [ ! -f ".env" ]; then
    cp .env.example .env
    echo "[✓] .env created from .env.example"
    echo ""
    echo "    ⚠️  You MUST edit .env to add your API keys!"
    echo "    Required: OPENAI_API_KEY"
    echo ""
else
    echo "[✓] .env already exists"
fi

# ── 4. Data directory ──
echo ""
echo "=== Step 4: Knowledge Base ==="
mkdir -p data/bar_exam_docs
echo "[✓] data/bar_exam_docs/ directory ready"
echo "    Add your CA bar exam study materials here:"
echo "    - PDF outlines, IRAC examples, practice essays"
echo "    - Barbri/Themis notes, rule summaries"
echo "    - California Evidence Code, Civil Code excerpts"
echo ""

# ── 5. Generate sample docs ──
if [ ! -f "data/bar_exam_docs/README.txt" ]; then
    echo "    Creating sample reference doc..."
    python3 -c "
import asyncio, os
from backend.rag_engine import rag_engine
sample_dir = 'data/bar_exam_docs'
count = sum(1 for f in os.listdir(sample_dir) if not f.startswith('.'))
if count > 0:
    n = asyncio.run(rag_engine.ingest_directory())
    print(f'[✓] Indexed {n} chunks from {count} documents')
else:
    print('[!] No documents found yet. Add files to data/bar_exam_docs/')
" 2>/dev/null || true
fi

# ── 6. Xcode project ──
echo ""
echo "=== Step 5: iOS App ==="
bash setup_xcode.sh 2>/dev/null || true

# ── 7. Network info ──
LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || echo "unknown")
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║              Setup Complete!                     ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║                                                  ║"
echo "║  1. Edit .env — add your OPENAI_API_KEY          ║"
echo "║  2. Add bar exam docs to data/bar_exam_docs/     ║"
echo "║  3. Run: ./start_server.sh                       ║"
echo "║  4. Open Xcode project, build to iPhone          ║"
echo "║  5. In iOS app Settings, set server URL:         ║"
echo "║     → http://$LOCAL_IP:8080                  ║"
echo "║                                                  ║"
echo "╚══════════════════════════════════════════════════╝"
