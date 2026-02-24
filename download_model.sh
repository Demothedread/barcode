#!/usr/bin/env bash
# ============================================================================
# download_model.sh — Download a lightweight GGUF model for on-device inference
#
# This script downloads a small quantised LLM suitable for running on iPhone
# via llama.cpp (SwiftLlama). The model is placed in the iOS app's bundle
# resources directory so Xcode picks it up automatically.
#
# Usage:
#   ./download_model.sh              # Download default model (SmolLM2-1.7B)
#   ./download_model.sh phi3          # Download Phi-3.5-mini instead
#   ./download_model.sh llama3        # Download Llama-3.2-1B instead
#
# Models are Q4_K_M quantised (4-bit) for optimal size/quality on mobile.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$SCRIPT_DIR/ios/BarGrader/BarGrader"
DATA_DIR="$SCRIPT_DIR/data/models"
TARGET_NAME="bargrader-model.gguf"

# ── Model URLs (HuggingFace) ──
# These are Q4_K_M quantisations — good balance of size and quality for mobile.
declare -A MODELS=(
    ["smollm"]="https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q4_K_M.gguf"
    ["phi3"]="https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf"
    ["llama3"]="https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
)

declare -A SIZES=(
    ["smollm"]="~1.1 GB"
    ["phi3"]="~2.3 GB"
    ["llama3"]="~0.8 GB"
)

declare -A DESCRIPTIONS=(
    ["smollm"]="SmolLM2-1.7B-Instruct — Best quality/size ratio for iPhone"
    ["phi3"]="Phi-3.5-mini-Instruct — Strongest reasoning but larger (2.3GB)"
    ["llama3"]="Llama-3.2-1B-Instruct — Smallest and fastest, lower quality"
)

# ── Parse arguments ──
MODEL_KEY="${1:-smollm}"

if [[ ! -v "MODELS[$MODEL_KEY]" ]]; then
    echo "❌ Unknown model: $MODEL_KEY"
    echo ""
    echo "Available models:"
    for key in "${!MODELS[@]}"; do
        echo "  $key  — ${DESCRIPTIONS[$key]} (${SIZES[$key]})"
    done
    exit 1
fi

URL="${MODELS[$MODEL_KEY]}"
DESC="${DESCRIPTIONS[$MODEL_KEY]}"
SIZE="${SIZES[$MODEL_KEY]}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Bartender — On-Device Model Download                       ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Model: $DESC"
echo "║  Size:  $SIZE"
echo "║  Quant: Q4_K_M (4-bit)"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Create directories ──
mkdir -p "$DATA_DIR"

# ── Download ──
DOWNLOAD_PATH="$DATA_DIR/$TARGET_NAME"

if [[ -f "$DOWNLOAD_PATH" ]]; then
    echo "⚠️  Model already exists at $DOWNLOAD_PATH"
    read -p "   Overwrite? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping download."
        echo ""
    else
        rm "$DOWNLOAD_PATH"
    fi
fi

if [[ ! -f "$DOWNLOAD_PATH" ]]; then
    echo "⬇️  Downloading..."
    if command -v curl &>/dev/null; then
        curl -L --progress-bar -o "$DOWNLOAD_PATH" "$URL"
    elif command -v wget &>/dev/null; then
        wget --show-progress -O "$DOWNLOAD_PATH" "$URL"
    else
        echo "❌ Need curl or wget. Install with: brew install curl"
        exit 1
    fi
    echo "✅ Downloaded to $DOWNLOAD_PATH"
fi

# ── Copy to iOS bundle ──
IOS_MODEL_PATH="$IOS_DIR/$TARGET_NAME"
echo ""
echo "📱 Copying to iOS app bundle..."
cp "$DOWNLOAD_PATH" "$IOS_MODEL_PATH"
echo "✅ Copied to $IOS_MODEL_PATH"

# ── Also set the server-side LOCAL_MODEL_PATH ──
echo ""
echo "🖥️  Setting LOCAL_MODEL_PATH for backend server..."
ENV_LOCAL="$SCRIPT_DIR/.env.local"
if [[ -f "$ENV_LOCAL" ]]; then
    if grep -q "^LOCAL_MODEL_PATH=" "$ENV_LOCAL"; then
        sed -i '' "s|^LOCAL_MODEL_PATH=.*|LOCAL_MODEL_PATH=$DOWNLOAD_PATH|" "$ENV_LOCAL"
    else
        echo "LOCAL_MODEL_PATH=$DOWNLOAD_PATH" >> "$ENV_LOCAL"
    fi
    echo "✅ Updated .env.local"
else
    echo "⚠️  .env.local not found — set LOCAL_MODEL_PATH=$DOWNLOAD_PATH manually"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Done! Next steps:                                          ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  1. Open Xcode → BarGrader target                          ║"
echo "║  2. Add $TARGET_NAME to 'Copy Bundle Resources'   ║"
echo "║     (drag from Finder or File → Add Files to BarGrader)    ║"
echo "║  3. Add SwiftLlama SPM dependency:                          ║"
echo "║     https://github.com/ShenghaiWang/SwiftLlama.git ≥0.3.0  ║"
echo "║  4. Build & run on your iPhone                              ║"
echo "║  5. Test offline mode: disconnect WiFi → ask a question     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
