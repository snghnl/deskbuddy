#!/bin/zsh
# DeskBuddy.app 번들 생성 스크립트
set -e
cd "$(dirname "$0")"

swift build -c release

APP=build/DeskBuddy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/DeskBuddy "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DeskBuddy</string>
    <key>CFBundleIdentifier</key>
    <string>com.russell.deskbuddy</string>
    <key>CFBundleName</key>
    <string>DeskBuddy</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "✅ $APP 생성 완료"
