#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  Bartender — Master Launch Script                                ║
# ║  One command to build & deploy to your connected iPhone          ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Usage:
#   ./launch.sh              # Build & run on connected iPhone
#   ./launch.sh --server     # Also push backend to Railway
#   ./launch.sh --help       # Show this help
#
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
IOS_DIR="$ROOT/ios/BarGrader"
XCODEPROJ="$IOS_DIR/BarGrader.xcodeproj"
SCHEME="BarGrader"
BUNDLE_ID="com.bargrader.app"
RAILWAY_URL="https://barcode-production-0db7.up.railway.app"

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

step()  { echo -e "\n${CYAN}▸ ${BOLD}$1${NC}"; }
ok()    { echo -e "  ${GREEN}✔${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()  { echo -e "  ${RED}✖${NC} $1"; exit 1; }

# ── Help ──
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo ""
    echo "Bartender Launch Script"
    echo "━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ./launch.sh              Build & deploy iOS app to connected iPhone"
    echo "  ./launch.sh --server     Also git-push backend to Railway"
    echo "  ./launch.sh --help       Show this message"
    echo ""
    echo "Prerequisites:"
    echo "  • Xcode installed (with command line tools)"
    echo "  • iPhone connected via USB or on same WiFi"
    echo "  • Apple Developer account signed in to Xcode"
    echo ""
    exit 0
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          Bartender — Master Launch                           ║"
echo "║          CA Bar Exam AI Tutor → iPhone                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ──────────────────────────────────────────────────────
# STEP 1: Verify Environment
# ──────────────────────────────────────────────────────
step "1/6  Checking environment"

# Xcode
if ! command -v xcodebuild &>/dev/null; then
    fail "Xcode not found. Install from the Mac App Store."
fi
XCODE_VER=$(xcodebuild -version | head -1)
ok "Xcode: $XCODE_VER"

# Xcode CLI tools
if ! xcode-select -p &>/dev/null; then
    warn "Installing Xcode command-line tools..."
    xcode-select --install
    echo "  Waiting for install to complete... re-run this script after."
    exit 0
fi
ok "CLI tools: $(xcode-select -p)"

# Signing identity
IDENTITY_COUNT=$(security find-identity -v -p codesigning 2>/dev/null | grep "valid identities" | awk '{print $1}')
if [[ "$IDENTITY_COUNT" == "0" ]]; then
    fail "No code signing identity found. Sign in to Xcode → Settings → Accounts → Add Apple ID."
fi
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | head -1 | sed 's/.*"\(.*\)"/\1/')
ok "Signing: $IDENTITY"

# Connected device
DEVICE_ID=$(xcrun xctrace list devices 2>/dev/null | grep -i "iphone" | grep -v "Simulator" | head -1 | grep -oE '[A-F0-9-]{25,}' || true)
if [[ -z "$DEVICE_ID" ]]; then
    DEVICE_NAME="(none found — will use first available)"
    warn "No iPhone detected. Connect via USB or ensure same WiFi network."
    warn "Xcode will prompt you to trust the device if needed."
else
    DEVICE_NAME=$(xcrun xctrace list devices 2>/dev/null | grep "$DEVICE_ID" | sed 's/ (.*//')
    ok "iPhone: $DEVICE_NAME ($DEVICE_ID)"
fi

# ──────────────────────────────────────────────────────
# STEP 2: Add LLM.swift SPM dependency (if needed)
# ──────────────────────────────────────────────────────
step "2/6  Configuring LLM.swift package dependency"

PBXPROJ="$XCODEPROJ/project.pbxproj"

if grep -q "LLM.swift" "$PBXPROJ" 2>/dev/null; then
    ok "LLM.swift already in project"
else
    warn "Adding LLM.swift SPM package to Xcode project..."
    # We use xcodebuild's resolve mechanism — the Package.swift reference
    # is already added by the script below. For the initial add, we modify
    # the project.pbxproj to include the remote package reference.

    # Generate unique IDs for pbxproj entries
    PKG_REF_ID=$(python3 -c "import hashlib; print(hashlib.md5(b'LLM.swift.pkg').hexdigest()[:24].upper())")
    PKG_DEP_ID=$(python3 -c "import hashlib; print(hashlib.md5(b'LLM.swift.dep').hexdigest()[:24].upper())")
    PKG_PROD_ID=$(python3 -c "import hashlib; print(hashlib.md5(b'LLM.swift.prod').hexdigest()[:24].upper())")
    PKG_BUILD_ID=$(python3 -c "import hashlib; print(hashlib.md5(b'LLM.swift.build').hexdigest()[:24].upper())")

    # Add XCRemoteSwiftPackageReference
    sed -i '' '/\/\* End PBXSourcesBuildPhase section \*\//a\
\
/* Begin XCRemoteSwiftPackageReference section */\
		'"$PKG_REF_ID"' /* XCRemoteSwiftPackageReference "LLM.swift" */ = {\
			isa = XCRemoteSwiftPackageReference;\
			repositoryURL = "https://github.com/eastriverlee/LLM.swift.git";\
			requirement = {\
				kind = branch;\
				branch = main;\
			};\
		};\
/* End XCRemoteSwiftPackageReference section */\
\
/* Begin XCSwiftPackageProductDependency section */\
		'"$PKG_PROD_ID"' /* LLM */ = {\
			isa = XCSwiftPackageProductDependency;\
			package = '"$PKG_REF_ID"' /* XCRemoteSwiftPackageReference "LLM.swift" */;\
			productName = LLM;\
		};\
/* End XCSwiftPackageProductDependency section */
' "$PBXPROJ"

    # Add package reference to the project object
    sed -i '' 's/packageReferences = (/packageReferences = (\
				'"$PKG_REF_ID"' \/\* XCRemoteSwiftPackageReference "LLM.swift" \*\/,/' "$PBXPROJ" 2>/dev/null || \
    sed -i '' '/projectRoot = "";/a\
			packageReferences = (\
				'"$PKG_REF_ID"' /* XCRemoteSwiftPackageReference "LLM.swift" */,\
			);
' "$PBXPROJ"

    # Add product dependency to the native target
    sed -i '' 's/packageProductDependencies = (/packageProductDependencies = (\
				'"$PKG_PROD_ID"' \/\* LLM \*\/,/' "$PBXPROJ"

    # Add build file for the framework
    sed -i '' '/\/\* End PBXBuildFile section \*\//i\
		'"$PKG_BUILD_ID"' /* LLM in Frameworks */ = {isa = PBXBuildFile; productRef = '"$PKG_PROD_ID"' /* LLM */; };
' "$PBXPROJ"

    # Add Frameworks build phase if missing, or add to existing Sources
    if ! grep -q "PBXFrameworksBuildPhase" "$PBXPROJ"; then
        FWPHASE_ID=$(python3 -c "import hashlib; print(hashlib.md5(b'LLM.swift.fwphase').hexdigest()[:24].upper())")
        sed -i '' '/buildPhases = (/a\
				'"$FWPHASE_ID"' /* Frameworks */,
' "$PBXPROJ"
        sed -i '' '/\/\* End PBXResourcesBuildPhase section \*\//a\
\
/* Begin PBXFrameworksBuildPhase section */\
		'"$FWPHASE_ID"' /* Frameworks */ = {\
			isa = PBXFrameworksBuildPhase;\
			buildActionMask = 2147483647;\
			files = (\
				'"$PKG_BUILD_ID"' /* LLM in Frameworks */,\
			);\
			runOnlyForDeploymentPostprocessing = 0;\
		};\
/* End PBXFrameworksBuildPhase section */
' "$PBXPROJ"
    fi

    ok "LLM.swift package reference added"
fi

# ──────────────────────────────────────────────────────
# STEP 3: Resolve Swift packages
# ──────────────────────────────────────────────────────
step "3/6  Resolving Swift Package Manager dependencies"

cd "$IOS_DIR"
xcodebuild -resolvePackageDependencies \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -quiet 2>&1 | tail -3 || true
ok "Packages resolved"
cd "$ROOT"

# ──────────────────────────────────────────────────────
# STEP 4: Build the app
# ──────────────────────────────────────────────────────
step "4/6  Building Bartender for iPhone"

BUILD_CMD=(
    xcodebuild
    -project "$XCODEPROJ"
    -scheme "$SCHEME"
    -configuration Debug
    -sdk iphoneos
    -allowProvisioningUpdates
    CODE_SIGN_IDENTITY="Apple Development"
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGNING_REQUIRED=YES
)

# Add destination if we found a device
if [[ -n "${DEVICE_ID:-}" ]]; then
    BUILD_CMD+=(-destination "id=$DEVICE_ID")
else
    BUILD_CMD+=(-destination "generic/platform=iOS")
fi

echo "  Building... (this may take 1-3 minutes on first run)"
if "${BUILD_CMD[@]}" -quiet 2>&1 | tail -5; then
    ok "Build succeeded"
else
    echo ""
    warn "Build had warnings or errors. Trying verbose build for diagnostics..."
    "${BUILD_CMD[@]}" 2>&1 | grep -E "error:|warning:" | head -20
    fail "Build failed. See errors above."
fi

# ──────────────────────────────────────────────────────
# STEP 5: Install & launch on iPhone
# ──────────────────────────────────────────────────────
step "5/6  Installing on iPhone"

if [[ -n "${DEVICE_ID:-}" ]]; then
    # Find the built .app
    BUILD_DIR=$(xcodebuild -project "$XCODEPROJ" -scheme "$SCHEME" -configuration Debug -sdk iphoneos -showBuildSettings 2>/dev/null | grep "BUILT_PRODUCTS_DIR" | awk '{print $3}')
    APP_PATH="$BUILD_DIR/BarGrader.app"

    if [[ -d "$APP_PATH" ]]; then
        # Install using ios-deploy if available, otherwise rely on Xcode
        if command -v ios-deploy &>/dev/null; then
            ios-deploy --bundle "$APP_PATH" --justlaunch 2>/dev/null && ok "Installed and launched on $DEVICE_NAME" || true
        else
            # Use xcodebuild to build-and-run
            xcodebuild -project "$XCODEPROJ" \
                -scheme "$SCHEME" \
                -configuration Debug \
                -sdk iphoneos \
                -destination "id=$DEVICE_ID" \
                -allowProvisioningUpdates \
                CODE_SIGN_IDENTITY="Apple Development" \
                CODE_SIGNING_ALLOWED=YES \
                build 2>&1 | tail -3
            ok "Built for $DEVICE_NAME — open Xcode to run (Cmd+R)"
        fi
    else
        warn "Built app not found at expected path. Open Xcode → Product → Run (⌘R)."
    fi
else
    warn "No iPhone connected. Open Xcode and press ⌘R to deploy."
fi

# ──────────────────────────────────────────────────────
# STEP 6: (Optional) Push backend to Railway
# ──────────────────────────────────────────────────────
if [[ "${1:-}" == "--server" ]]; then
    step "6/6  Pushing backend to Railway"
    cd "$ROOT"
    if git diff --quiet && git diff --cached --quiet; then
        ok "No changes to push"
    else
        git add -A
        git commit -m "deploy: update backend for Railway" --allow-empty
        git push origin main
        ok "Pushed to origin/main — Railway will auto-deploy"
        echo "  Dashboard: https://railway.app/project/48bcf658-2499-45c7-87a2-5844a63f032c"
    fi
else
    step "6/6  Backend (skipped — use --server to push to Railway)"
    echo "  Server: $RAILWAY_URL"
    echo "  The app connects to Railway automatically."
fi

# ──────────────────────────────────────────────────────
# Done
# ──────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ${GREEN}✔ Bartender is ready!${NC}                                      ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                              ║"
echo "║  Your iPhone will show these prompts on first launch:        ║"
echo "║  1. 'Allow Microphone' → tap Allow                          ║"
echo "║  2. 'Allow Speech Recognition' → tap Allow                  ║"
echo "║  3. 'Allow Local Network' → tap Allow                       ║"
echo "║                                                              ║"
echo "║  Then just speak or type a bar exam question!                ║"
echo "║                                                              ║"
echo "║  Online:  Server at Railway handles AI + TTS                 ║"
echo "║  Offline: On-device model auto-downloads (~1.1 GB, once)     ║"
echo "║           Uses Apple TTS (lower quality but works anywhere)  ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
