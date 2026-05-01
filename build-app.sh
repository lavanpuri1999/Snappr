#!/bin/bash
# Builds Snappr and wraps it into a .app bundle so macOS Accessibility permission
# attaches to a stable bundle identifier instead of a moving binary path.
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Building (release)..."
swift build -c release

BIN=".build/release/Snappr"
APP="Snappr.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

echo "==> Wrapping into $APP..."
rm -rf "$APP"
mkdir -p "$MACOS"
cp "$BIN" "$MACOS/Snappr"

cat > "$CONTENTS/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Snappr</string>
    <key>CFBundleDisplayName</key><string>Snappr</string>
    <key>CFBundleExecutable</key><string>Snappr</string>
    <key>CFBundleIdentifier</key><string>com.lavan.snappr</string>
    <key>CFBundleVersion</key><string>0.1</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# Ad-hoc sign so AX permission can attach.
codesign --force --sign - "$APP"

echo "==> Done. Run with: open $APP"
echo "    Or:           ./$APP/Contents/MacOS/Snappr"
