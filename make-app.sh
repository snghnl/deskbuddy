#!/bin/zsh
# Builds the DeskBuddy.app bundle
set -e
cd "$(dirname "$0")"

swift build -c release

APP=build/DeskBuddy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/DeskBuddy "$APP/Contents/MacOS/"
# SPM resource bundle (localization tables) — Bundle.module finds it in Contents/Resources
cp -R .build/release/DeskBuddy_DeskBuddy.bundle "$APP/Contents/Resources/"

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
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.russell.deskbuddy</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>deskbuddy</string>
            </array>
        </dict>
    </array>
    <key>NSCalendarsUsageDescription</key>
    <string>DeskBuddy reads your calendar to show today's events.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>DeskBuddy reads your calendar to show today's events.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "✅ $APP created"
