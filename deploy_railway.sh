#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────
# Bartender – Railway Deployment Update Script  (2026-02-24)
#
# Verifies and deploys the FastAPI backend to Railway.
# Run this after making code changes to push to production.
#
# Backend features:
#   • FastAPI + Uvicorn (async, production-grade)
#   • WebSocket /ws — real-time streaming answers
#   • REST endpoints: /api/health, /api/transcribe, /api/tts,
#     /api/ingest, /api/ingest-text, /api/settings
#   • LLM fallback chain: OpenAI → Gemini → Groq → GitHub → local
#   • RAG pipeline: OpenAI Vector Stores (3 stores) + ChromaDB fallback
#   • TTS via OpenAI TTS-1
#   • Whisper transcription
#   • PWA frontend served at /
#
# Railway URL: https://barcode-production-0db7.up.railway.app
#
# Usage:  ./deploy_railway.sh
# ────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
header() { echo -e "\n${CYAN}${BOLD}── $1 ──${NC}"; }

RAILWAY_URL="https://barcode-production-0db7.up.railway.app"

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════"
echo " Bartender – Railway Deployment Update"
echo "═══════════════════════════════════════════════════${NC}"

# ═══════════════════════════════════════════════════
header "1. Pre-flight Checks"
# ═══════════════════════════════════════════════════

# Git status
if git rev-parse --is-inside-work-tree &>/dev/null; then
    BRANCH=$(git branch --show-current)
    pass "Git repo: branch '$BRANCH'"
    
    UNCOMMITTED=$(git status --porcelain | wc -l | tr -d ' ')
    if [ "$UNCOMMITTED" -gt 0 ]; then
        warn "$UNCOMMITTED uncommitted file(s)"
        git status --short | head -10
        echo ""
        read -p "  Commit all changes before deploying? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            read -p "  Commit message: " COMMIT_MSG
            git add -A && git commit -m "${COMMIT_MSG:-Update Bartender backend}"
            pass "Changes committed"
        fi
    else
        pass "Working tree clean"
    fi
else
    fail "Not in a git repository"
    exit 1
fi

# ═══════════════════════════════════════════════════
header "2. Backend File Inventory"
# ═══════════════════════════════════════════════════

BACKEND_FILES=(
    "backend/__init__.py"
    "backend/app.py"
    "backend/config.py"
    "backend/llm_client.py"
    "backend/prompts.py"
    "backend/rag_engine.py"
    "backend/instructions/essay_instruct.md"
    "backend/instructions/outline_instruct.md"
)

for f in "${BACKEND_FILES[@]}"; do
    if [ -f "$f" ]; then
        pass "$f"
    else
        fail "$f MISSING"
    fi
done

# ═══════════════════════════════════════════════════
header "3. Configuration Files"
# ═══════════════════════════════════════════════════

CONFIG_FILES=(
    "requirements.txt"
    "nixpacks.toml"
    "railway.json"
    "Procfile"
)

for f in "${CONFIG_FILES[@]}"; do
    if [ -f "$f" ]; then
        pass "$f"
    else
        fail "$f MISSING — Railway needs this!"
    fi
done

# Show key configs
echo ""
echo -e "  ${CYAN}nixpacks.toml:${NC}"
grep -E "^cmd|^providers|PYTHON_VERSION" nixpacks.toml 2>/dev/null | sed 's/^/    /'
echo ""
echo -e "  ${CYAN}Procfile:${NC}"
cat Procfile 2>/dev/null | sed 's/^/    /'
echo ""
echo -e "  ${CYAN}railway.json start:${NC}"
grep -o '"startCommand".*' railway.json 2>/dev/null | sed 's/^/    /'

# ═══════════════════════════════════════════════════
header "4. Environment Variables"
# ═══════════════════════════════════════════════════

echo "  Railway environment variables (set in Railway dashboard):"
echo ""

ENV_VARS=(
    "OPENAI_API_KEY|Required — LLM, TTS, Whisper, RAG vector stores"
    "GEMINI_API_KEY|Optional — Gemini fallback LLM"
    "GROQ_API_KEY|Optional — Groq fallback LLM"
    "GITHUB_TOKEN|Optional — GitHub Models fallback LLM"
    "PORT|Auto-set by Railway (default 8080)"
    "BARTENDER_MODE|Default: essay (essay/outline/mbe)"
    "WAKE_WORD|Default: hey bartender"
    "TTS_VOICE|Default: nova (alloy/echo/fable/onyx/nova/shimmer)"
    "TTS_SPEED|Default: 0.55"
)

for entry in "${ENV_VARS[@]}"; do
    KEY=$(echo "$entry" | cut -d'|' -f1)
    DESC=$(echo "$entry" | cut -d'|' -f2)
    echo -e "    ${BOLD}$KEY${NC} — $DESC"
done

echo ""
echo "  Set these at: https://railway.app → Project → Variables"

# ═══════════════════════════════════════════════════
header "5. Frontend (PWA)"
# ═══════════════════════════════════════════════════

FRONTEND_FILES=("frontend/index.html" "frontend/manifest.json" "frontend/sw.js")
for f in "${FRONTEND_FILES[@]}"; do
    if [ -f "$f" ]; then
        pass "$f"
    else
        warn "$f missing (PWA won't work in browser)"
    fi
done

# ═══════════════════════════════════════════════════
header "6. RAG Data"
# ═══════════════════════════════════════════════════

if [ -d "data/bar_exam_docs" ]; then
    DOC_COUNT=$(find data/bar_exam_docs -type f \( -name "*.md" -o -name "*.txt" \) | wc -l | tr -d ' ')
    pass "RAG documents: $DOC_COUNT files in data/bar_exam_docs/"
else
    warn "No data/bar_exam_docs/ — RAG context will be limited"
fi

# ═══════════════════════════════════════════════════
header "7. Tests"
# ═══════════════════════════════════════════════════

if [ -d "tests" ]; then
    TEST_COUNT=$(find tests -name "test_*.py" | wc -l | tr -d ' ')
    pass "Test files: $TEST_COUNT"
    
    if command -v python3 &>/dev/null && python3 -c "import pytest" 2>/dev/null; then
        read -p "  Run tests before deploying? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            python3 -m pytest tests/ -v --tb=short || warn "Some tests failed"
        fi
    else
        echo "  (pytest not installed locally — skip)"
    fi
else
    warn "No tests/ directory"
fi

# ═══════════════════════════════════════════════════
header "8. Deploy to Railway"
# ═══════════════════════════════════════════════════

echo ""
echo "  Railway deploys automatically when you push to GitHub."
echo "  The pipeline: git push → GitHub → Railway webhook → Nixpacks build → deploy"
echo ""

# Check if Railway CLI is available
if command -v railway &>/dev/null; then
    pass "Railway CLI installed"
    echo ""
    read -p "  Deploy via Railway CLI now? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        echo "  Pushing to GitHub (triggers Railway auto-deploy)..."
        git push origin "$BRANCH"
        pass "Pushed to origin/$BRANCH"
        echo ""
        echo "  Deploying via Railway CLI..."
        railway up
        pass "Railway deploy triggered"
    fi
else
    echo "  No Railway CLI found. Deploying via git push instead."
    echo ""
    read -p "  Push to GitHub (triggers Railway auto-deploy)? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        git push origin "$BRANCH"
        pass "Pushed to origin/$BRANCH — Railway will auto-deploy"
    fi
fi

# ═══════════════════════════════════════════════════
header "9. Post-Deploy Health Check"
# ═══════════════════════════════════════════════════

echo ""
echo "  Waiting 30s for Railway to redeploy..."
sleep 5
echo "  ...(5s)"
sleep 5
echo "  ...(10s)"
sleep 5
echo "  ...(15s)"
sleep 5
echo "  ...(20s)"
sleep 5
echo "  ...(25s)"
sleep 5
echo "  ...(30s)"

echo ""
echo "  Checking $RAILWAY_URL/api/health ..."
if command -v curl &>/dev/null; then
    RESPONSE=$(curl -s --max-time 15 "$RAILWAY_URL/api/health" 2>/dev/null || echo '{"error":"unreachable"}')
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$RAILWAY_URL/api/health" 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" = "200" ]; then
        pass "Backend is LIVE (HTTP 200)"
        echo "  Response: $RESPONSE"
    elif [ "$HTTP_CODE" = "000" ]; then
        warn "Backend unreachable — may still be deploying"
        echo "  Check: https://railway.app → Deployments"
    else
        warn "Backend returned HTTP $HTTP_CODE"
        echo "  Response: $RESPONSE"
    fi
else
    echo "  (curl not found — check manually at $RAILWAY_URL/api/health)"
fi

# ═══════════════════════════════════════════════════
header "10. Summary"
# ═══════════════════════════════════════════════════

echo ""
echo -e "${BOLD}Endpoints:${NC}"
echo "  Web app:    $RAILWAY_URL"
echo "  Health:     $RAILWAY_URL/api/health"
echo "  WebSocket:  wss://barcode-production-0db7.up.railway.app/ws"
echo "  Transcribe: POST $RAILWAY_URL/api/transcribe"
echo "  TTS:        POST $RAILWAY_URL/api/tts"
echo "  Ingest:     POST $RAILWAY_URL/api/ingest"
echo "  Settings:   GET/POST $RAILWAY_URL/api/settings"
echo ""
echo -e "${BOLD}LLM Fallback Chain:${NC}"
echo "  1. OpenAI (GPT-4o / GPT-4o-mini)"
echo "  2. Google Gemini"
echo "  3. Groq (Llama)"
echo "  4. GitHub Models"
echo "  5. On-device (iOS only, via LLM.swift)"
echo ""
echo -e "${BOLD}iOS App Connection:${NC}"
echo "  The iPhone app connects via WebSocket to the /ws endpoint."
echo "  Default server URL in the app: $RAILWAY_URL"
echo "  Change in: Settings → Server URL"
echo ""
echo -e "${GREEN}${BOLD}Done.${NC}"
echo ""
