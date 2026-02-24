#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────
# Bartender – Xcode Project Update Script  (v2 — 2026-02-24)
#
# Run after pulling the latest code. Verifies everything is wired
# correctly for a real-device build on a FREE Apple Developer account.
#
# Features covered:
#   • Voice stop commands ("stop bartender", "I'm done", "submit")
#   • Wake word detection ("hey bartender")
#   • Siri Shortcuts (manual trigger via Shortcuts app — free account)
#   • Audio interruption recovery (phone calls, alarms)
#   • Asset catalog (app icon + accent color #E94560)
#   • Background modes (audio, BT, fetch, processing)
#   • USB-C / Bluetooth microphone auto-detection
#   • Apple Watch companion app (WatchConnectivity)
#   • On-device LLM (offline mode via LLM.swift)
#   • Silence detection (0–10s, 0 = manual stop)
#
# Usage:  ./update_xcode.sh
# ────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

XCODE_PROJECT="ios/BarGrader/BarGrader.xcodeproj"
APP_DIR="ios/BarGrader/BarGrader"
WATCH_DIR="ios/BarGrader/BarGrader Watch App"
TEAM_ID="K66F2V436N"
BUNDLE_ID="com.bargrader.app"

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
manual() { echo -e "  ${YELLOW}→ MANUAL:${NC} $1"; }

WARNINGS=0
ERRORS=0
track_warn() { ((WARNINGS++)) || true; warn "$1"; }
track_fail() { ((ERRORS++)) || true; fail "$1"; }

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════"
echo " Bartender – Xcode Project Updater  (v2)"
echo " Free Apple Developer Account Compatible"
echo "═══════════════════════════════════════════════════${NC}"

# ═══════════════════════════════════════════════════
header "1. Pre-flight Checks"
# ═══════════════════════════════════════════════════

if xcode-select -p &>/dev/null; then
    XCODE_PATH=$(xcode-select -p)
    pass "Xcode CLI tools: $XCODE_PATH"
else
    track_fail "Xcode command-line tools not found"
    echo "    Install with: xcode-select --install"
    exit 1
fi

if [ -d "$XCODE_PROJECT" ]; then
    pass "Project found: $XCODE_PROJECT"
else
    track_fail "Xcode project not found at $XCODE_PROJECT"
    echo "    Run setup_xcode.sh first, or create the project in Xcode."
    exit 1
fi

SWIFT_COUNT=$(find "$APP_DIR" -name "*.swift" | wc -l | tr -d ' ')
pass "Swift source files (iPhone): $SWIFT_COUNT"

WATCH_SWIFT=$(find "$WATCH_DIR" -name "*.swift" 2>/dev/null | wc -l | tr -d ' ')
pass "Swift source files (Watch):  $WATCH_SWIFT"

# ═══════════════════════════════════════════════════
header "2. Asset Catalog"
# ═══════════════════════════════════════════════════

ASSETS_DIR="$APP_DIR/Assets.xcassets"
if [ -d "$ASSETS_DIR" ]; then
    pass "Assets.xcassets exists"
else
    track_warn "Assets.xcassets missing — creating..."
    mkdir -p "$ASSETS_DIR/AppIcon.appiconset" "$ASSETS_DIR/AccentColor.colorset"
    cat > "$ASSETS_DIR/Contents.json" << 'EOF'
{"info":{"version":1,"author":"xcode"}}
EOF
    cat > "$ASSETS_DIR/AppIcon.appiconset/Contents.json" << 'EOF'
{"images":[{"idiom":"universal","platform":"ios","size":"1024x1024","filename":"app-icon.png"}],"info":{"version":1,"author":"xcode"}}
EOF
    cat > "$ASSETS_DIR/AccentColor.colorset/Contents.json" << 'EOF'
{"colors":[{"idiom":"universal","color":{"color-space":"srgb","components":{"red":"0.914","green":"0.271","blue":"0.376","alpha":"1.000"}}}],"info":{"version":1,"author":"xcode"}}
EOF
    pass "Created with brand red accent color (#E94560)"
fi

if ls "$ASSETS_DIR/AppIcon.appiconset/"*.png &>/dev/null 2>&1; then
    pass "App icon image found"
else
    track_warn "No app icon PNG in AppIcon.appiconset/"
    manual "Add a 1024×1024 PNG named 'app-icon.png' to $ASSETS_DIR/AppIcon.appiconset/"
fi

# ═══════════════════════════════════════════════════
header "3. Info.plist"
# ═══════════════════════════════════════════════════

PLIST="$APP_DIR/Info.plist"
if [ -f "$PLIST" ]; then
    check_plist_key() {
        if /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" &>/dev/null; then
            VALUE=$(/usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null)
            pass "$1 = $VALUE"
        else
            track_fail "$1 MISSING"
            manual "$2"
            return 1
        fi
    }
    
    check_plist_key "CFBundleDisplayName" "Set to 'Bartender'" || true
    check_plist_key "NSMicrophoneUsageDescription" "Add microphone usage string" || true
    check_plist_key "NSSpeechRecognitionUsageDescription" "Add speech recognition string" || true
    check_plist_key "ITSAppUsesNonExemptEncryption" "Set to NO" || true
    
    # Background modes
    if /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST" &>/dev/null; then
        MODES=$(/usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST" 2>/dev/null)
        for mode in audio fetch bluetooth-central processing; do
            if echo "$MODES" | grep -q "$mode"; then
                pass "  Background: $mode"
            else
                track_warn "Missing background mode: $mode"
            fi
        done
    else
        track_fail "UIBackgroundModes not set"
    fi
else
    track_fail "Info.plist not found"
fi

# ═══════════════════════════════════════════════════
header "4. Entitlements (Free Account)"
# ═══════════════════════════════════════════════════

ENTITLEMENTS="$APP_DIR/BarGrader.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
    pass "Entitlements file found"
    
    # These work on free accounts:
    for key in "com.apple.security.app-sandbox" \
               "com.apple.security.network.client" \
               "com.apple.security.device.audio-input" \
               "com.apple.security.device.bluetooth"; do
        if /usr/libexec/PlistBuddy -c "Print :$key" "$ENTITLEMENTS" &>/dev/null; then
            pass "  $key"
        else
            track_warn "Missing: $key"
        fi
    done
    
    # Siri requires PAID account — should NOT be active
    if /usr/libexec/PlistBuddy -c "Print :com.apple.developer.siri" "$ENTITLEMENTS" &>/dev/null; then
        track_warn "com.apple.developer.siri is ACTIVE — will fail on free account!"
        manual "Remove or comment out the Siri entitlement in BarGrader.entitlements"
    else
        pass "  Siri entitlement correctly disabled (free account)"
    fi
else
    track_fail "Entitlements file not found"
fi

# ═══════════════════════════════════════════════════
header "5. Source File Inventory"
# ═══════════════════════════════════════════════════

EXPECTED_FILES=(
    "BarGraderApp.swift"
    "Models/AppState.swift"
    "Views/ContentView.swift"
    "Views/SettingsView.swift"
    "Services/AudioRecorderService.swift"
    "Services/SpeechRecognitionService.swift"
    "Services/TTSPlaybackService.swift"
    "Services/WakeWordService.swift"
    "Services/StopWordService.swift"
    "Services/WebSocketService.swift"
    "Services/LocalLLMService.swift"
    "Services/RemoteCommandService.swift"
    "Services/BartenderIntents.swift"
)

for f in "${EXPECTED_FILES[@]}"; do
    if [ -f "$APP_DIR/$f" ]; then
        pass "$f"
    else
        track_fail "$f MISSING"
    fi
done

# Watch app
WATCH_FILES=("BarGraderWatchApp.swift" "Models/WatchState.swift" "Views/ContentView.swift")
for f in "${WATCH_FILES[@]}"; do
    if [ -f "$WATCH_DIR/$f" ]; then
        pass "Watch: $f"
    else
        track_warn "Watch: $f missing"
    fi
done

# ═══════════════════════════════════════════════════
header "6. Code Signing (pbxproj)"
# ═══════════════════════════════════════════════════

PBXPROJ="$XCODE_PROJECT/project.pbxproj"
if [ -f "$PBXPROJ" ]; then
    pass "project.pbxproj exists"
    
    # Auto-fix deprecated identity
    if grep -q 'CODE_SIGN_IDENTITY = "iPhone Developer"' "$PBXPROJ"; then
        track_warn "Fixing deprecated 'iPhone Developer' → 'Apple Development'"
        sed -i '' 's/CODE_SIGN_IDENTITY = "iPhone Developer"/CODE_SIGN_IDENTITY = "Apple Development"/g' "$PBXPROJ"
        pass "Signing identity updated automatically"
    else
        pass "No deprecated signing identities"
    fi
    
    if grep -q "CODE_SIGN_STYLE = Automatic" "$PBXPROJ"; then
        pass "Automatic code signing"
    else
        track_warn "CODE_SIGN_STYLE not Automatic"
        manual "Xcode → Target → Signing & Capabilities → 'Automatically manage signing'"
    fi
    
    if grep -q "DEVELOPMENT_TEAM" "$PBXPROJ"; then
        pass "Development team is set"
    else
        track_warn "No DEVELOPMENT_TEAM in pbxproj"
        manual "Xcode → Target → Signing & Capabilities → select your team"
    fi
    
    # Check new files are in the build
    for item in "Assets.xcassets" "BartenderIntents.swift" "StopWordService.swift"; do
        if grep -q "$item" "$PBXPROJ"; then
            pass "$item in build"
        else
            track_warn "$item not in pbxproj"
            manual "Drag $item into the project navigator in Xcode (check 'Add to target')"
        fi
    done
else
    track_warn "No project.pbxproj (run xcodegen or create project in Xcode)"
fi

# xcodegen offer
if command -v xcodegen &> /dev/null; then
    echo ""
    read -p "  Regenerate .xcodeproj from project.yml? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pushd ios/BarGrader > /dev/null
        xcodegen generate
        popd > /dev/null
        pass "Regenerated .xcodeproj from project.yml"
    fi
else
    echo "  Tip: brew install xcodegen to auto-regenerate .xcodeproj from project.yml"
fi

# ═══════════════════════════════════════════════════
header "7. LLM Model (Offline Mode)"
# ═══════════════════════════════════════════════════

MODEL_FILE="$APP_DIR/bargrader-model.gguf"
if [ -f "$MODEL_FILE" ]; then
    SIZE=$(du -h "$MODEL_FILE" | cut -f1)
    pass "LLM model found ($SIZE)"
else
    echo "  ℹ  No bundled LLM model — app downloads on first offline use (~1.1 GB)"
fi

# ═══════════════════════════════════════════════════
header "8. Railway Backend Status"
# ═══════════════════════════════════════════════════

RAILWAY_URL="https://barcode-production-0db7.up.railway.app"
echo "  Checking $RAILWAY_URL/api/health ..."
if command -v curl &>/dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$RAILWAY_URL/api/health" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        pass "Railway backend is LIVE (HTTP 200)"
    elif [ "$HTTP_CODE" = "000" ]; then
        track_warn "Railway backend unreachable (timeout or network error)"
    else
        track_warn "Railway backend returned HTTP $HTTP_CODE"
    fi
else
    echo "  (curl not found — skip health check)"
fi

# ═══════════════════════════════════════════════════
header "9. Summary"
# ═══════════════════════════════════════════════════

echo ""
echo -e "${BOLD}After this script, open Xcode and do:${NC}"
echo ""
echo -e "  ${CYAN}A. Signing & Capabilities:${NC}"
echo "     • 'Automatically manage signing' → CHECK"
echo "     • Team → your Apple ID (free is fine)"
echo "     • Bundle ID → $BUNDLE_ID"
echo "     • Do NOT add Siri capability (requires \$99/yr)"
echo ""
echo -e "  ${CYAN}B. Drag missing files into Xcode navigator:${NC}"
echo "     • Assets.xcassets → BarGrader group"
echo "     • StopWordService.swift → Services group"
echo "     • BartenderIntents.swift → Services group"
echo "     • Check 'Add to target: BarGrader' for each"
echo ""
echo -e "  ${CYAN}C. App Icon (optional):${NC}"
echo "     • Open Assets.xcassets → AppIcon → drag 1024×1024 PNG"
echo ""
echo -e "  ${CYAN}D. Build & Run (⌘R):${NC}"
echo "     • Connect iPhone via USB-C"
echo "     • Select device in scheme picker"
echo "     • First run: Settings → General → VPN & Device Mgmt → Trust"
echo "     • Free account: re-deploy from Xcode every 7 days"
echo ""
echo -e "  ${CYAN}E. All features (free account):${NC}"
echo "     ✓ Wake word — \"hey bartender\" (on-device Speech framework)"
echo "     ✓ Voice stop — \"stop bartender\", \"I'm done\", \"submit\""
echo "     ✓ Silence auto-stop (0–10s slider, 0 = manual only)"
echo "     ✓ Shortcuts app (manual trigger, Home Screen widget, Back Tap)"
echo "     ✓ USB-C / BT mic auto-detection + priority routing"
echo "     ✓ Apple Watch companion (start/stop/mode from wrist)"
echo "     ✓ Offline LLM (on-device, ~1.1 GB download)"
echo "     ✓ Background audio recording"
echo "     ✓ Audio interruption recovery (phone calls, alarms)"
echo "     ✗ \"Hey Siri, Hey Bartender\" (requires \$99/yr program)"
echo ""

# ═══════════════════════════════════════════════════
header "10. Open Xcode"
# ═══════════════════════════════════════════════════

TOTAL_CHECKED=$((${#EXPECTED_FILES[@]} + ${#WATCH_FILES[@]}))
PASSED=$((TOTAL_CHECKED - ERRORS))
echo ""
echo -e "  Results: ${GREEN}${PASSED} passed${NC}, ${YELLOW}${WARNINGS} warnings${NC}, ${RED}${ERRORS} errors${NC}"
echo ""

read -p "  Open project in Xcode now? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    open "$XCODE_PROJECT"
    pass "Opened in Xcode"
else
    echo "  Later:  open $XCODE_PROJECT"
fi

echo ""
echo -e "${GREEN}${BOLD}Done.${NC} Build & run with ⌘R."
echo ""
