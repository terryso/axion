#!/usr/bin/env bash
# build-release.sh — Full release build: CLI + Helper App + tar.gz + Homebrew formula.
#
# Usage:
#   bash build-release.sh [version] [--sign [--sign-identity <identity>]]
#
# Options:
#   version                   Version string (default: read from VERSION file)
#   --sign                    Codesign with ad-hoc or Apple Developer identity
#   --sign-identity <id>      Apple Developer signing identity
#
# Outputs:
#   .build/dist/axion-{version}.tar.gz
#   Distribution/homebrew/axion.rb  (generated from template)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Parse arguments
VERSION=""
SIGN_FLAG=""
SIGN_IDENTITY_FLAG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign-identity)
            SIGN_FLAG="--sign"
            SIGN_IDENTITY_FLAG="--sign-identity $2"
            shift
            ;;
        --sign)
            SIGN_FLAG="--sign"
            ;;
        *)
            [ -z "$VERSION" ] && VERSION="$1"
            ;;
    esac
    shift
done

# Default version from VERSION file
if [ -z "$VERSION" ]; then
    VERSION=$(head -1 "$PROJECT_ROOT/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "0.1.0")
fi

ARCH="$(uname -m)"
DIST_DIR="$PROJECT_ROOT/.build/dist/axion-$VERSION"

echo "==> Building Axion release v$VERSION for $ARCH..."

# 1. Release build
echo "==> Compiling release binaries..."
swift build -c release --package-path "$PROJECT_ROOT"
BUILD_DIR="$PROJECT_ROOT/.build/$ARCH-apple-macosx/release"

# 2. Build Helper App Bundle
echo "==> Building Helper App Bundle..."
"$SCRIPT_DIR/build-helper-app.sh" release $SIGN_FLAG $SIGN_IDENTITY_FLAG

# 3. Assemble distribution directory
echo "==> Assembling distribution package..."
[ -n "$DIST_DIR" ] && [ "$DIST_DIR" != "/" ] && rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/bin"
mkdir -p "$DIST_DIR/libexec/axion"

cp "$BUILD_DIR/AxionCLI" "$DIST_DIR/bin/axion"
cp -R "$PROJECT_ROOT/.build/AxionHelper.app" "$DIST_DIR/libexec/axion/"
chmod +x "$DIST_DIR/bin/axion"

echo "    bin/axion          -> $(du -h "$DIST_DIR/bin/axion" | cut -f1)"
echo "    libexec/axion/AxionHelper.app -> $(du -sh "$DIST_DIR/libexec/axion/AxionHelper.app" | cut -f1)"

# 4. Package as tar.gz
TAR_PATH="$PROJECT_ROOT/.build/dist/axion-$VERSION.tar.gz"
mkdir -p "$(dirname "$TAR_PATH")"

# tar from parent dir so archive root is axion-{version}/
tar -czf "$TAR_PATH" -C "$DIST_DIR/.." "axion-$VERSION"

# 5. Compute sha256
SHA256=$(shasum -a 256 "$TAR_PATH" | cut -d' ' -f1)

# 6. Generate Homebrew formula from template
if [ -f "$SCRIPT_DIR/axion.rb.template" ]; then
    sed -e "s|{{VERSION}}|$VERSION|g" \
        -e "s|{{SHA256}}|$SHA256|g" \
        -e "s|{{URL}}|https://github.com/terryso/axion/releases/download/v$VERSION/axion-$VERSION.tar.gz|g" \
        "$SCRIPT_DIR/axion.rb.template" > "$SCRIPT_DIR/axion.rb"
    echo "==> Generated Distribution/homebrew/axion.rb"
fi

echo ""
echo "==> Release package ready:"
echo "    Archive:  $TAR_PATH"
echo "    SHA256:   $SHA256"
echo "    Version:  $VERSION"
