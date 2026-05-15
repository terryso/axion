#!/bin/bash
# Build AxionBar .app bundle for development/testing
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_DIR="$PROJECT_DIR/.build/AxionBar.app"

echo "Building AxionBar..."
swift build --target AxionBar

echo "Creating .app bundle..."
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$PROJECT_DIR/.build/debug/AxionBar" "$BUNDLE_DIR/Contents/MacOS/AxionBar"

if [ ! -f "$BUNDLE_DIR/Contents/Info.plist" ]; then
    cat > "$BUNDLE_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>AxionBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.axion.AxionBar</string>
    <key>CFBundleName</key>
    <string>AxionBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST
fi

echo "Bundle ready: $BUNDLE_DIR"
echo "Launch with: open $BUNDLE_DIR"
