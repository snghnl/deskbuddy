#!/bin/zsh
# Notification hook — surfaces a DeskBuddy speech bubble when Claude Code is
# waiting for approval or input. The hook event JSON arrives on stdin
# (fields: message, cwd, ...).
# Always exits 0 so a missing DeskBuddy app never disrupts the session.

input=$(cat)

text=$(printf '%s' "$input" | python3 -c '
import json, sys, os
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
msg = (d.get("message") or "Claude Code is waiting for your input").replace("\n", " ")
cwd = os.path.basename(d.get("cwd") or "")
print(f"[{cwd}] {msg}" if cwd else msg)
' 2>/dev/null)

[[ -z "$text" ]] && text="Claude Code is waiting for your input"

# Prefer the CLI bundled with the plugin, fall back to deskbuddy on PATH
cli="$(dirname "$0")/deskbuddy"
if [[ -x "$cli" ]]; then
  "$cli" notify "🔔 $text" || true
elif command -v deskbuddy >/dev/null 2>&1; then
  deskbuddy notify "🔔 $text" || true
fi

exit 0
