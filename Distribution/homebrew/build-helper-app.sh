#!/usr/bin/env bash
# build-helper-app.sh — Package SPM-built AxionHelper into a macOS App Bundle.
#
# Usage:
#   bash build-helper-app.sh [debug|release] [--sign]
#
# Options:
#   debug|release   Build configuration (default: debug)
#   --sign          Ad-hoc codesign the resulting App Bundle
#
# Outputs:
#   .build/AxionHelper.app/  (standard macOS App Bundle)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_CONFIG="${1:-debug}"
SIGN="${2:-}"

# Normalize: first arg might be the config, second might be --sign
# Support: build-helper-app.sh release --sign
# Support: build-helper-app.sh --sign (defaults to debug)
if [ "$BUILD_CONFIG" = "--sign" ]; then
    BUILD_CONFIG="debug"
    SIGN="--sign"
fi

ARCH="$(uname -m)"

echo "==> Building AxionHelper (${BUILD_CONFIG}) for ${ARCH}..."

# 1. Compile AxionHelper
if [ "$BUILD_CONFIG" = "release" ]; then
    swift build -c release --package-path "$PROJECT_ROOT"
    BUILD_DIR="$PROJECT_ROOT/.build/$ARCH-apple-macosx/release"
else
    swift build --package-path "$PROJECT_ROOT"
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
VERSION=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "0.1.0")
sed "s|{{VERSION}}|$VERSION|g" "$SCRIPT_DIR/Info.plist" > "$CONTENTS/Info.plist"

echo "    Version: $VERSION"
echo "    Binary:  $MACOS/$APP_NAME"

# 5. Ad-hoc codesign (optional)
if [ "$SIGN" = "--sign" ]; then
    echo "==> Signing $APP_BUNDLE (ad-hoc)..."
    codesign --force --sign - "$APP_BUNDLE"
fi

echo "==> Done: $APP_BUNDLE"
