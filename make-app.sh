#!/bin/zsh
# Builds the DeskBuddy.app bundle.
#
#   ./make-app.sh              fast native-arch build (development)
#   ./make-app.sh --universal  arm64 + x86_64 fat binary (release/distribution)
#
# VERSION can override the bundle version: VERSION=1.2.0 ./make-app.sh --universal
set -e
cd "$(dirname "$0")"

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.0.0)}"

if [[ "${1:-}" == "--universal" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  PRODUCTS=.build/apple/Products/Release
else
  swift build -c release
  PRODUCTS=.build/release
fi

APP=build/DeskBuddy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$PRODUCTS/DeskBuddy" "$APP/Contents/MacOS/"
# SPM resource bundle (localization tables) — Bundle.module finds it in Contents/Resources
cp -R "$PRODUCTS/DeskBuddy_DeskBuddy.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
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
    <string>$VERSION</string>
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
echo "✅ $APP created (v$VERSION)"
