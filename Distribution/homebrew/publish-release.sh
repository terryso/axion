#!/usr/bin/env bash
# publish-release.sh — Build, package, and publish a new Axion release.
#
# Usage:
#   bash publish-release.sh [version] [--sign [--sign-identity <identity>]] [--tap-repo <repo>]
#
# Options:
#   version                   Version string (default: read from VERSION file)
#   --sign                    Codesign with ad-hoc or Apple Developer identity
#   --sign-identity <id>      Apple Developer signing identity
#   --tap-repo <repo>         Homebrew tap repository (default: terryso/homebrew-tap)
#
# Requirements:
#   - gh (GitHub CLI) authenticated
#   - git
#   - swift (SPM build)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Parse arguments
VERSION=""
SIGN_FLAG=""
SIGN_IDENTITY_FLAG=""
TAP_REPO="terryso/homebrew-tap"

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
        --tap-repo)
            TAP_REPO="$2"
            shift
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

echo "==> Publishing Axion v$VERSION..."

# 1. Build release package
echo "==> Step 1: Building release package..."
"$SCRIPT_DIR/build-release.sh" "$VERSION" $SIGN_FLAG $SIGN_IDENTITY_FLAG

TAR_PATH="$PROJECT_ROOT/.build/dist/axion-$VERSION.tar.gz"

if [ ! -f "$TAR_PATH" ]; then
    echo "Error: Release archive not found at $TAR_PATH" >&2
    exit 1
fi

SHA256=$(shasum -a 256 "$TAR_PATH" | cut -d' ' -f1)

# 2. Create GitHub Release
echo "==> Step 2: Creating GitHub Release..."
REPO=$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null | sed -E 's|.*github.com[:/]([^/]+/[^/]+)(\.git)?|\1|' || echo "terryso/axion")

echo "    Repository: $REPO"
echo "    Tag: v$VERSION"
echo "    Asset: $TAR_PATH"
echo "    SHA256: $SHA256"

# Check if tag already exists
if git -C "$PROJECT_ROOT" tag -l "v$VERSION" | grep -q "v$VERSION"; then
    echo "Warning: Tag v$VERSION already exists. Skipping release creation."
else
    gh release create "v$VERSION" "$TAR_PATH" \
        --repo "$REPO" \
        --title "Axion v$VERSION" \
        --notes "## Axion v$VERSION

SHA256: \`$SHA256\`

### Installation

\`\`\`bash
brew tap terryso/tap
brew install axion
\`\`\`

### What's Changed

See commit history for details."
    echo "==> GitHub Release created: v$VERSION"
fi

# 3. Update Homebrew tap repository
echo "==> Step 3: Updating Homebrew tap formula..."

GENERATED_FORMULA="$SCRIPT_DIR/axion.rb"
if [ ! -f "$GENERATED_FORMULA" ]; then
    echo "Error: Generated formula not found at $GENERATED_FORMULA" >&2
    exit 1
fi

# Clone tap repo, update formula, push
TAP_CLONE_DIR=$(mktemp -d)
trap 'rm -rf "$TAP_CLONE_DIR"' EXIT

echo "    Cloning $TAP_REPO..."
git clone "https://github.com/$TAP_REPO.git" "$TAP_CLONE_DIR" 2>/dev/null

mkdir -p "$TAP_CLONE_DIR/Formula"
cp "$GENERATED_FORMULA" "$TAP_CLONE_DIR/Formula/axion.rb"

cd "$TAP_CLONE_DIR"
git add Formula/axion.rb
if git diff --cached --quiet; then
    echo "    Formula unchanged, no commit needed."
else
    git commit -m "axion $VERSION"
    git push origin main || git push origin master
    echo "    Formula updated in $TAP_REPO"
fi

echo ""
echo "==> Release v$VERSION published successfully!"
TAP_NAME="${TAP_REPO#*/}"
TAP_NAME="${TAP_NAME#homebrew-}"
echo "    Install with: brew install ${TAP_REPO%%/*}/${TAP_NAME}/axion"
