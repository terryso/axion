#!/usr/bin/env bash
# build-helper-app.sh — Package SPM-built AxionHelper into a macOS App Bundle.
#
# Usage:
#   bash build-helper-app.sh [debug|release] [--sign [--sign-identity <identity>]] [--arch <arch>]
#
# Options:
#   debug|release              Build configuration (default: debug)
#   --sign                     Codesign the resulting App Bundle (ad-hoc if no identity given)
#   --sign-identity <identity> Apple Developer signing identity (e.g. "Developer ID Application: ...")
#   --arch <arch>              Target architecture (default: auto-detect)
#
# Outputs:
#   .build/AxionHelper.app/  (standard macOS App Bundle)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_CONFIG="debug"
SIGN=false
SIGN_IDENTITY=""
ARCH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        debug|release)
            BUILD_CONFIG="$1"
            ;;
        --sign)
            SIGN=true
            ;;
        --sign-identity)
            SIGN=true
            SIGN_IDENTITY="$2"
            shift
            ;;
        --arch)
            ARCH="$2"
            shift
            ;;
        *)
            echo "Warning: Unknown argument '$1'" >&2
            ;;
    esac
    shift
done

# Auto-detect architecture if not specified
if [ -z "$ARCH" ]; then
    ARCH="$(uname -m)"
fi

echo "==> Building AxionHelper (${BUILD_CONFIG}) for ${ARCH}..."

# 1. Compile AxionHelper
BUILD_FLAGS=()
if [ "$BUILD_CONFIG" = "release" ]; then
    BUILD_FLAGS+=(-c release)
fi
if [ -n "$ARCH" ] && [ "$ARCH" != "$(uname -m)" ]; then
    echo "Note: Cross-compilation for $ARCH requested. Ensure Swift toolchain supports it."
fi

swift build "${BUILD_FLAGS[@]}" --package-path "$PROJECT_ROOT"

if [ "$BUILD_CONFIG" = "release" ]; then
    BUILD_DIR="$PROJECT_ROOT/.build/$ARCH-apple-macosx/release"
else
    BUILD_DIR="$PROJECT_ROOT/.build/$ARCH-apple-macosx/debug"
fi

# Verify the binary exists
if [ ! -f "$BUILD_DIR/AxionHelper" ]; then
    echo "Error: AxionHelper binary not found at $BUILD_DIR/AxionHelper" >&2
    exit 1
fi

# 2. Create App Bundle directory structure
APP_NAME="AxionHelper"
APP_BUNDLE="$PROJECT_ROOT/.build/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"

echo "==> Creating App Bundle at $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"

# 3. Copy executable
cp "$BUILD_DIR/AxionHelper" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

# 4. Generate Info.plist (replace {{VERSION}} placeholder)
VERSION=$(head -1 "$PROJECT_ROOT/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "0.1.0")
sed "s|{{VERSION}}|$VERSION|g" "$SCRIPT_DIR/Info.plist" > "$CONTENTS/Info.plist"

echo "    Version: $VERSION"
echo "    Binary:  $MACOS/$APP_NAME"

# 5. Codesign (optional)
if [ "$SIGN" = true ]; then
    ENTITLEMENTS="$SCRIPT_DIR/AxionHelper.entitlements"
    if [ -n "$SIGN_IDENTITY" ]; then
        echo "==> Signing $APP_BUNDLE with identity '$SIGN_IDENTITY'..."
        codesign --force --sign "$SIGN_IDENTITY" \
            --entitlements "$ENTITLEMENTS" \
            "$APP_BUNDLE"
    else
        echo "==> Signing $APP_BUNDLE (ad-hoc)..."
        codesign --force --sign - \
            --entitlements "$ENTITLEMENTS" \
            "$APP_BUNDLE"
    fi
fi

echo "==> Done: $APP_BUNDLE"
