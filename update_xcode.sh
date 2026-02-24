#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────
# Bartender – Xcode Project Update Script
#
# Run this after pulling the latest code to verify and update
# the Xcode project for all new features:
#
#   • Siri Shortcuts (AppIntents)
#   • Audio interruption recovery
#   • Asset catalog (app icon + accent color)
#   • Proper code signing for device deployment
#   • Background modes (audio, BT, fetch, processing)
#   • USB-C / Bluetooth microphone detection
#   • Watch companion app
#   • On-device LLM (offline mode)
#
# Usage:  ./update_xcode.sh
# ────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

XCODE_PROJECT="ios/BarGrader/BarGrader.xcodeproj"
APP_DIR="ios/BarGrader/BarGrader"
TEAM_ID="K66F2V436N"
BUNDLE_ID="com.bargrader.app"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
header() { echo -e "\n${CYAN}${BOLD}── $1 ──${NC}"; }
manual() { echo -e "  ${YELLOW}→ MANUAL:${NC} $1"; }

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════"
echo " Bartender – Xcode Project Updater"
echo "═══════════════════════════════════════════════${NC}"

# ─────────────────────────────────────────
header "1. Pre-flight Checks"
# ─────────────────────────────────────────

# Check Xcode CLI tools
if xcode-select -p &>/dev/null; then
    XCODE_PATH=$(xcode-select -p)
    pass "Xcode CLI tools: $XCODE_PATH"
else
    fail "Xcode command-line tools not found"
    echo "    Install with: xcode-select --install"
    exit 1
fi

# Check .xcodeproj exists
if [ -d "$XCODE_PROJECT" ]; then
    pass "Project found: $XCODE_PROJECT"
else
    fail "Xcode project not found at $XCODE_PROJECT"
    echo "    Run setup_xcode.sh first, or open Xcode and create the project."
    exit 1
fi

# Check Swift source files
SWIFT_COUNT=$(find "$APP_DIR" -name "*.swift" | wc -l | tr -d ' ')
pass "Swift source files: $SWIFT_COUNT"

# ─────────────────────────────────────────
header "2. Asset Catalog"
# ─────────────────────────────────────────

ASSETS_DIR="$APP_DIR/Assets.xcassets"
if [ -d "$ASSETS_DIR" ]; then
    pass "Assets.xcassets exists"
else
    warn "Assets.xcassets missing — creating..."
    mkdir -p "$ASSETS_DIR/AppIcon.appiconset" "$ASSETS_DIR/AccentColor.colorset"
    echo '{"info":{"version":1,"author":"xcode"}}' > "$ASSETS_DIR/Contents.json"
    echo '{"images":[{"idiom":"universal","platform":"ios","size":"1024x1024","filename":"app-icon.png"}],"info":{"version":1,"author":"xcode"}}' > "$ASSETS_DIR/AppIcon.appiconset/Contents.json"
    echo '{"colors":[{"idiom":"universal","color":{"color-space":"srgb","components":{"red":"0.914","green":"0.271","blue":"0.376","alpha":"1.000"}}}],"info":{"version":1,"author":"xcode"}}' > "$ASSETS_DIR/AccentColor.colorset/Contents.json"
    pass "Assets.xcassets created with brand red accent color (#E94560)"
fi

# Check for app icon image
if ls "$ASSETS_DIR/AppIcon.appiconset/"*.png &>/dev/null 2>&1; then
    pass "App icon image found"
else
    warn "No app icon image (PNG) in AppIcon.appiconset/"
    manual "Add a 1024x1024 PNG named 'app-icon.png' to:"
    echo "         $ASSETS_DIR/AppIcon.appiconset/"
    echo "         (Or drag it into the AppIcon slot in Xcode's asset catalog editor)"
fi

# ─────────────────────────────────────────
header "3. Info.plist Verification"
# ─────────────────────────────────────────

PLIST="$APP_DIR/Info.plist"
if [ -f "$PLIST" ]; then
    # Check critical keys
    check_plist_key() {
        if /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" &>/dev/null; then
            VALUE=$(/usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null)
            pass "$1 = $VALUE"
        else
            fail "$1 missing"
            return 1
        fi
    }
    
    check_plist_key "CFBundleDisplayName" || manual "Set CFBundleDisplayName to 'Bartender' in Info.plist"
    check_plist_key "NSMicrophoneUsageDescription" || manual "Add microphone usage description"
    check_plist_key "NSSpeechRecognitionUsageDescription" || manual "Add speech recognition usage description"
    check_plist_key "ITSAppUsesNonExemptEncryption" || manual "Set ITSAppUsesNonExemptEncryption to NO (avoids App Store compliance delay)"
    
    # Check background modes
    if /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST" &>/dev/null; then
        MODES=$(/usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST" 2>/dev/null)
        pass "UIBackgroundModes configured"
        # Check for individual modes
        for mode in audio fetch bluetooth-central processing; do
            if echo "$MODES" | grep -q "$mode"; then
                pass "  Background mode: $mode"
            else
                warn "  Missing background mode: $mode"
            fi
        done
    else
        fail "UIBackgroundModes not set"
        manual "Add background modes: audio, fetch, bluetooth-central, processing"
    fi
else
    fail "Info.plist not found at $PLIST"
fi

# ─────────────────────────────────────────
header "4. Entitlements"
# ─────────────────────────────────────────

ENTITLEMENTS="$APP_DIR/BarGrader.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
    pass "Entitlements file found"
    
    for key in "com.apple.security.app-sandbox" \
               "com.apple.security.network.client" \
               "com.apple.security.device.audio-input" \
               "com.apple.security.device.bluetooth" \
               "com.apple.developer.siri"; do
        if /usr/libexec/PlistBuddy -c "Print :$key" "$ENTITLEMENTS" &>/dev/null; then
            pass "  $key"
        else
            warn "  Missing: $key"
        fi
    done
else
    fail "Entitlements file not found"
fi

# ─────────────────────────────────────────
header "5. Source File Inventory"
# ─────────────────────────────────────────

EXPECTED_FILES=(
    "BarGraderApp.swift"
    "Models/AppState.swift"
    "Views/ContentView.swift"
    "Views/SettingsView.swift"
    "Services/AudioRecorderService.swift"
    "Services/SpeechRecognitionService.swift"
    "Services/TTSPlaybackService.swift"
    "Services/WakeWordService.swift"
    "Services/WebSocketService.swift"
    "Services/LocalLLMService.swift"
    "Services/RemoteCommandService.swift"
    "Services/BartenderIntents.swift"
)

for f in "${EXPECTED_FILES[@]}"; do
    if [ -f "$APP_DIR/$f" ]; then
        pass "$f"
    else
        fail "$f missing!"
    fi
done

# ─────────────────────────────────────────
header "6. Code Signing"
# ─────────────────────────────────────────

PBXPROJ="$XCODE_PROJECT/project.pbxproj"
if [ -f "$PBXPROJ" ]; then
    pass "project.pbxproj exists"
    
    # Fix deprecated signing identity
    if grep -q 'CODE_SIGN_IDENTITY = "iPhone Developer"' "$PBXPROJ"; then
        warn "Fixing deprecated 'iPhone Developer' → 'Apple Development'"
        sed -i '' 's/CODE_SIGN_IDENTITY = "iPhone Developer"/CODE_SIGN_IDENTITY = "Apple Development"/g' "$PBXPROJ"
        pass "Signing identity updated"
    else
        pass "No deprecated signing identities"
    fi
    
    # Ensure CODE_SIGN_STYLE = Automatic
    if grep -q "CODE_SIGN_STYLE = Automatic" "$PBXPROJ"; then
        pass "Automatic code signing enabled"
    else
        warn "CODE_SIGN_STYLE not set to Automatic in pbxproj"
        manual "In Xcode → target → Signing & Capabilities → check 'Automatically manage signing'"
    fi
    
    # Check development team
    if grep -q "DEVELOPMENT_TEAM = $TEAM_ID" "$PBXPROJ"; then
        pass "Development team: $TEAM_ID"
    else
        warn "Development team may not be set in pbxproj"
        manual "In Xcode → target → Signing & Capabilities → select your team"
    fi
    
    # Check Assets.xcassets is in build
    if grep -q "Assets.xcassets" "$PBXPROJ"; then
        pass "Assets.xcassets referenced in build"
    else
        warn "Assets.xcassets not found in pbxproj build phases"
        manual "Drag Assets.xcassets from Finder into the BarGrader group in Xcode's project navigator"
    fi
    
    # Check BartenderIntents.swift is in build
    if grep -q "BartenderIntents.swift" "$PBXPROJ"; then
        pass "BartenderIntents.swift in build"
    else
        warn "BartenderIntents.swift not in pbxproj"
        manual "Drag BartenderIntents.swift into the Services group in Xcode and ensure 'Add to target: BarGrader' is checked"
    fi
else
    warn "No project.pbxproj found (project may need to be regenerated)"
fi

# Check if xcodegen can regenerate the project from project.yml
if command -v xcodegen &> /dev/null; then
    echo ""
    read -p "  Regenerate .xcodeproj from project.yml using xcodegen? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pushd ios/BarGrader > /dev/null
        xcodegen generate
        popd > /dev/null
        pass "Regenerated .xcodeproj from project.yml"
    fi
else
    echo ""
    echo "  Tip: install xcodegen (brew install xcodegen) to auto-regenerate"
    echo "  the .xcodeproj from project.yml — useful after pulling new code."
fi

# ─────────────────────────────────────────
header "7. LLM Model (Offline Mode)"
# ─────────────────────────────────────────

MODEL_FILE="$APP_DIR/bargrader-model.gguf"
if [ -f "$MODEL_FILE" ]; then
    SIZE=$(du -h "$MODEL_FILE" | cut -f1)
    pass "LLM model found: $MODEL_FILE ($SIZE)"
else
    warn "No offline LLM model bundled"
    echo "         The app will download it on first use (~1.1 GB)."
    echo "         To pre-bundle: copy a .gguf model to $APP_DIR/"
fi

# ─────────────────────────────────────────
header "8. Summary of Manual Steps"
# ─────────────────────────────────────────

echo ""
echo -e "${BOLD}After running this script, open Xcode and verify:${NC}"
echo ""
echo -e "  ${CYAN}A. Signing & Capabilities tab:${NC}"
echo "     1. 'Automatically manage signing' is CHECKED"
echo "     2. Team is set to your Apple Developer account"
echo "     3. Bundle Identifier is: $BUNDLE_ID"
echo "     4. These capabilities are listed:"
echo "        • App Sandbox"
echo "        • Background Modes (audio, fetch, bluetooth-central, processing)"
echo "        • Siri (required for Shortcuts)"
echo ""
echo -e "  ${CYAN}B. If Siri capability is not listed:${NC}"
echo "     1. Click '+' button in Signing & Capabilities"
echo "     2. Search for 'Siri' and add it"
echo "     3. This enables the AppIntents framework"
echo ""
echo -e "  ${CYAN}C. App Icon:${NC}"
echo "     1. Open Assets.xcassets in the navigator"
echo "     2. Select 'AppIcon'"
echo "     3. Drag a 1024×1024 PNG into the 'iOS App 1024pt' slot"
echo "     4. Xcode auto-generates all required sizes"
echo ""
echo -e "  ${CYAN}D. Build & Run on Device:${NC}"
echo "     1. Connect your iPhone via USB-C or Wi-Fi"
echo "     2. Select your device in the scheme picker (top bar)"
echo "     3. Press ⌘R to build and run"
echo "     4. If 'Untrusted Developer' appears on the phone:"
echo "        Settings → General → VPN & Device Management → Trust"
echo ""
echo -e "  ${CYAN}E. USB-C Microphone:${NC}"
echo "     • No special Xcode configuration needed"
echo "     • The app auto-detects USB-C, Bluetooth, and built-in mics"
echo "     • Priority: USB-C > BT HFP > BT LE > Wired > Built-in"
echo "     • Plug in the mic BEFORE starting a recording"
echo "     • Check Settings → Connected Devices to verify detection"
echo ""
echo -e "  ${CYAN}F. Apple Watch:${NC}"
echo "     • The Watch app target is included in the project"
echo "     • Build to your paired Apple Watch via the scheme picker"
echo "     • Watch ↔ iPhone communicate via WatchConnectivity"
echo ""

# ─────────────────────────────────────────
header "9. Opening Xcode"
# ─────────────────────────────────────────

read -p "Open the project in Xcode now? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    open "$XCODE_PROJECT"
    pass "Opened $XCODE_PROJECT in Xcode"
else
    echo "  To open later:  open $XCODE_PROJECT"
fi

echo ""
echo -e "${GREEN}${BOLD}Done.${NC} Review the manual steps above, then build & run (⌘R)."
echo ""
