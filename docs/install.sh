#!/bin/sh
# DeskBuddy installer.
#
#   curl -fsSL https://snghnl.github.io/deskbuddy/install.sh | sh
#
# Downloads the latest release and puts DeskBuddy.app in /Applications.
#
# Why this exists: DeskBuddy is not notarized (that needs a paid Apple Developer
# account), so an app downloaded through a browser gets flagged by Gatekeeper and
# takes several clicks in System Settings to open. macOS only quarantines files
# that a browser downloaded — curl does not set that flag — so installing this way
# skips the warning entirely. The disk image on the website is the same build.
set -eu

REPO="snghnl/deskbuddy"
DMG_URL="https://github.com/$REPO/releases/latest/download/DeskBuddy.dmg"
APP="/Applications/DeskBuddy.app"

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- checks ---------------------------------------------------------------

[ "$(uname -s)" = "Darwin" ] || die "DeskBuddy is macOS only."

os_major=$(sw_vers -productVersion | cut -d. -f1)
[ "$os_major" -ge 14 ] 2>/dev/null || die "DeskBuddy needs macOS 14 (Sonoma) or later; found $(sw_vers -productVersion)."

command -v curl >/dev/null 2>&1 || die "curl is required."

# --- download -------------------------------------------------------------

tmp=$(mktemp -d)
mount=""
cleanup() {
  [ -n "$mount" ] && hdiutil detach "$mount" -quiet 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

say "→ Downloading DeskBuddy…"
curl -fsSL --retry 3 -o "$tmp/DeskBuddy.dmg" "$DMG_URL" \
  || die "download failed. Check https://github.com/$REPO/releases"

# A 404 page or a truncated transfer would not be a disk image
hdiutil imageinfo "$tmp/DeskBuddy.dmg" >/dev/null 2>&1 \
  || die "the downloaded file is not a disk image — try again, or download manually from https://github.com/$REPO/releases"

# --- install --------------------------------------------------------------

mount="$tmp/mnt"
mkdir -p "$mount"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$tmp/DeskBuddy.dmg" \
  || die "could not mount the disk image."
[ -d "$mount/DeskBuddy.app" ] || die "the disk image does not contain DeskBuddy.app."

was_running=no
if pgrep -x DeskBuddy >/dev/null 2>&1; then
  was_running=yes
  say "→ Quitting the running copy…"
  osascript -e 'tell application "DeskBuddy" to quit' 2>/dev/null || pkill -x DeskBuddy || true
  # Give it a moment to write out todos.json before the bundle is replaced
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x DeskBuddy >/dev/null 2>&1 || break
    sleep 0.3
  done
  pkill -x DeskBuddy 2>/dev/null || true
fi

say "→ Installing to /Applications…"
if [ -w /Applications ]; then
  rm -rf "$APP"
  cp -R "$mount/DeskBuddy.app" /Applications/
else
  say "  (/Applications needs administrator access)"
  sudo rm -rf "$APP"
  sudo cp -R "$mount/DeskBuddy.app" /Applications/
  sudo chown -R "$(id -u):$(id -g)" "$APP"
fi

# curl does not set the quarantine flag, but an earlier browser download might have
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "?")

# --- done -----------------------------------------------------------------

say ""
say "✅ DeskBuddy $version installed."
say ""
if [ "$was_running" = yes ]; then
  open -a "$APP"
  say "   Relaunched. Your to-dos and settings were left untouched."
else
  open -a "$APP"
  say "   Launched — look for the character on your screen."
  say "   It has no Dock icon; use the menu bar item to quit or open Settings."
fi
say ""
say "   Launch at login:  System Settings → General → Login Items → add DeskBuddy"
say "   CLI for agents:   https://github.com/$REPO#agent-integration-cli--url-scheme"
say ""
