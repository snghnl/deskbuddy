#!/bin/zsh
# Packages build/DeskBuddy.app into the disk image we ship.
#
#   ./make-dmg.sh              uses the existing build/DeskBuddy.app
#   ./make-dmg.sh --build      runs ./make-app.sh --universal first
#
# Output: build/DeskBuddy.dmg. The name carries no version so that
# github.com/snghnl/deskbuddy/releases/latest/download/DeskBuddy.dmg is a
# permanent link the website and install.sh can both point at.
#
# SIGN_IDENTITY is honoured the same way make-app.sh honours it, so that a
# notarized release signs the image with the same Developer ID as the app.
#
# Layout comes from tools/dmg-settings.py via dmgbuild, which writes the Finder
# .DS_Store directly instead of scripting Finder — the only approach that also
# works on a headless CI runner. Without dmgbuild we still emit a plain,
# unstyled image rather than failing the build.
set -e
cd "$(dirname "$0")"

APP=build/DeskBuddy.app
DMG=build/DeskBuddy.dmg
VOLNAME="DeskBuddy"

if [[ "${1:-}" == "--build" ]]; then
  ./make-app.sh --universal
fi

[[ -d "$APP" ]] || { echo "❌ $APP not found — run ./make-app.sh first" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
rm -f "$DMG"

# Resolve a dmgbuild invocation, in order of how little it disturbs the machine
if command -v dmgbuild >/dev/null 2>&1; then
  DMGBUILD=(dmgbuild)
elif python3 -c "import dmgbuild" >/dev/null 2>&1; then
  DMGBUILD=(python3 -m dmgbuild)
elif command -v uvx >/dev/null 2>&1; then
  DMGBUILD=(uvx --quiet --from dmgbuild dmgbuild)
else
  DMGBUILD=()
fi

if (( ${#DMGBUILD} )); then
  "${DMGBUILD[@]}" -s tools/dmg-settings.py -D "app=$APP" "$VOLNAME" "$DMG"
else
  echo "· dmgbuild not available — building an unstyled image (pip install dmgbuild for the nice one)"
  STAGE=$(mktemp -d)
  trap 'rm -rf "$STAGE"' EXIT
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ \
    -format UDZO -imagekey zlib-level=9 -ov -quiet "$DMG"
fi

# The image itself is signed too. Notarization rejects an ad-hoc signature, so
# this has to follow whatever identity make-app.sh used.
codesign --force --sign "${SIGN_IDENTITY:--}" "$DMG" 2>/dev/null || true

echo "✅ $DMG created (v$VERSION, $(du -h "$DMG" | cut -f1))"
