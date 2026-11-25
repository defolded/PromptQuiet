#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP_DIR="$ROOT_DIR/dist/PromptQuiet.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
BIN_PATH="$BIN_DIR/PromptQuiet"

OLD_HASH=""
if [[ -f "$MACOS_DIR/PromptQuiet" ]]; then
    OLD_HASH="$(shasum -a 256 "$MACOS_DIR/PromptQuiet" | awk '{print $1}')"
fi
NEW_HASH="$(shasum -a 256 "$BIN_PATH" | awk '{print $1}')"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$BIN_PATH" "$MACOS_DIR/PromptQuiet"
chmod +x "$MACOS_DIR/PromptQuiet"

cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>PromptQuiet</string>
    <key>CFBundleDisplayName</key>
    <string>PromptQuiet</string>
    <key>CFBundleIdentifier</key>
    <string>com.promptquiet.app</string>
    <key>CFBundleExecutable</key>
    <string>PromptQuiet</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.1</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>PromptQuiet uses a minimal 2x2 stream when ScreenCaptureKit mode is selected to suppress notification banners while typing.</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_DIR"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$APP_DIR"
fi
if [[ "$OLD_HASH" != "$NEW_HASH" ]]; then
    tccutil reset All com.promptquiet.app >/dev/null 2>&1 || true
fi
echo "Built $APP_DIR"
