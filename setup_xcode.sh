#!/usr/bin/env bash
# ────────────────────────────────────────────────────────
# BarGrader – Xcode Project Generator
# Run this to create the .xcodeproj so you can open in Xcode
# ────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

PROJECT_DIR="ios/BarGrader"
PROJ_NAME="BarGrader"
BUNDLE_ID="com.bargrader.app"
TEAM_ID=""  # Set your Apple Developer Team ID here

echo "=== BarGrader Xcode Project Setup ==="
echo ""

# Check for xcodegen
if command -v xcodegen &> /dev/null; then
    echo "[✓] xcodegen found, generating project..."
    
    # Create project.yml for xcodegen
    cat > "$PROJECT_DIR/project.yml" << 'XCODEGEN_YML'
name: BarGrader
settings:
  base:
    PRODUCT_BUNDLE_IDENTIFIER: com.bargrader.app
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"
    SWIFT_VERSION: "5.9"
    IPHONEOS_DEPLOYMENT_TARGET: "16.0"
    INFOPLIST_FILE: BarGrader/Info.plist
    CODE_SIGN_ENTITLEMENTS: BarGrader/BarGrader.entitlements
    DEVELOPMENT_TEAM: ""
    TARGETED_DEVICE_FAMILY: "1"
    SUPPORTS_MACCATALYST: false
    
targets:
  BarGrader:
    type: application
    platform: iOS
    deploymentTarget: "16.0"
    sources:
      - path: BarGrader
        type: group
    settings:
      base:
        INFOPLIST_FILE: BarGrader/Info.plist
        CODE_SIGN_ENTITLEMENTS: BarGrader/BarGrader.entitlements
    info:
      path: BarGrader/Info.plist
      properties:
        UIBackgroundModes: [audio, fetch]
        NSMicrophoneUsageDescription: "BarGrader needs your microphone to listen to your bar exam questions."
        NSSpeechRecognitionUsageDescription: "BarGrader uses speech recognition for wake word detection."
XCODEGEN_YML
    
    cd "$PROJECT_DIR"
    xcodegen generate
    echo "[✓] Xcode project generated at $PROJECT_DIR/$PROJ_NAME.xcodeproj"

else
    echo "[!] xcodegen not found. Install it with:"
    echo "    brew install xcodegen"
    echo ""
    echo "Alternatively, create the project manually in Xcode:"
    echo "  1. Open Xcode → File → New → Project → iOS App"
    echo "  2. Name: BarGrader, Interface: SwiftUI, Language: Swift"  
    echo "  3. Save to: $(pwd)/$PROJECT_DIR/"
    echo "  4. Delete the auto-generated files"
    echo "  5. Drag all files from BarGrader/ folder into the project"
    echo "  6. In Signing & Capabilities:"
    echo "     - Add 'Background Modes' → enable 'Audio, AirPlay, and Picture in Picture'"
    echo "     - Add 'Background Modes' → enable 'Background fetch'"
    echo "  7. Build and run on your iPhone"
    echo ""
    echo "Quick Xcode setup (no xcodegen):"
fi

echo ""
echo "=== Done ==="
echo "Next steps:"
echo "  1. Open $PROJECT_DIR/$PROJ_NAME.xcodeproj in Xcode"
echo "  2. Set your Team ID in Signing & Capabilities"
echo "  3. Connect your iPhone and build (Cmd+R)"
echo "  4. Start the backend server: ./start_server.sh"
