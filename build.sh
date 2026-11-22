#!/bin/bash
# DisplayToggle.app 번들을 만든다. 사용법: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="DisplayToggle.app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/DisplayToggle"

ICON_DIR="$(mktemp -d)"
trap 'rm -rf "$ICON_DIR"' EXIT
ICONSET="$ICON_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ICON_DIR/AppIcon.icns"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DisplayToggle"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp "$ICON_DIR/AppIcon.icns" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
$(for d in Resources/*.lproj; do echo "        <string>$(basename "$d" .lproj)</string>"; done)
    </array>
    <key>CFBundleName</key><string>DisplayToggle</string>
    <key>CFBundleDisplayName</key><string>DisplayToggle</string>
    <key>CFBundleIconFile</key><string>AppIcon.icns</string>
    <key>CFBundleIdentifier</key><string>com.displaytoggle.app</string>
    <key>CFBundleExecutable</key><string>DisplayToggle</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "만든 파일: $APP"
