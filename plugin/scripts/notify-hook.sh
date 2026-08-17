#!/bin/zsh
# Notification 훅 — Claude Code 가 승인/입력을 기다릴 때 DeskBuddy 말풍선으로 알린다.
# stdin 으로 훅 이벤트 JSON 이 들어온다 (message, cwd 등).
# DeskBuddy 앱이 없어도 훅이 세션을 방해하지 않도록 항상 0 으로 끝낸다.

input=$(cat)

text=$(printf '%s' "$input" | python3 -c '
import json, sys, os
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
msg = (d.get("message") or "Claude Code가 입력을 기다려요").replace("\n", " ")
cwd = os.path.basename(d.get("cwd") or "")
print(f"[{cwd}] {msg}" if cwd else msg)
' 2>/dev/null)

[[ -z "$text" ]] && text="Claude Code가 입력을 기다려요"

# 플러그인에 동봉된 CLI 우선, 없으면 PATH 의 deskbuddy
cli="$(dirname "$0")/deskbuddy"
if [[ -x "$cli" ]]; then
  "$cli" notify "🔔 $text" || true
elif command -v deskbuddy >/dev/null 2>&1; then
  deskbuddy notify "🔔 $text" || true
fi

exit 0
