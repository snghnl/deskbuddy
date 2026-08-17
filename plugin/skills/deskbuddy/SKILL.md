---
name: deskbuddy
description: >
  Send speech-bubble notifications to the user and manage their to-dos through
  DeskBuddy (a floating character on the macOS screen). Use when: (1) a
  long-running task (build, tests, migration, deploy, lengthy analysis) finishes
  and the user should be notified (2) the user says "notify me", "remind me", or
  mentions "deskbuddy" (3) adding, listing, or completing the user's to-dos
  ("add a to-do", "what's on my list", "mark this done"). macOS only.
---

# DeskBuddy Integration

DeskBuddy is a character that floats on top of the screen at all times. Through
its CLI you can show speech-bubble notifications and manage to-dos; the user
sees the bubble immediately no matter which app they are using.

## Locating the CLI

1. `command -v deskbuddy` — use it if it is on PATH
2. Otherwise use `scripts/deskbuddy` inside the plugin this skill was installed
   from (`../../scripts/deskbuddy` relative to this SKILL.md)
3. If neither exists, the DeskBuddy app is not installed — point the user to
   https://github.com/snghnl/deskbuddy

## Commands

```sh
deskbuddy notify "message"               # Speech bubble (stays until the user clicks it)
deskbuddy notify "message" --autohide 8   # Auto-dismiss after 8s (for light-weight notices)
deskbuddy add "title"                     # Add a to-do
deskbuddy add "title" --memo "note"       # Add with a memo
deskbuddy list                            # Open to-dos (id prefix + title)
deskbuddy list --json                     # Full data as JSON (for parsing)
deskbuddy done <id prefix|title part>     # Mark as done
deskbuddy toggle                          # Open/close the to-do list panel
```

Sending a command launches the app automatically if it is not running
(except `list`, which reads the data file directly and works either way).

## Usage guidelines

- **Report finished work**: when a long task (several minutes or more) that the
  user may have stepped away from completes, `notify` with the key result.
  e.g. `deskbuddy notify "✅ Migration done — 37 files, tests passing"`
- **Failures and decisions**: if something failed or needs the user's judgment,
  send without autohide (the bubble stays until clicked, so it won't be missed).
  e.g. `deskbuddy notify "⚠️ Deploy failed — check the logs"`
- **Light progress updates**: use `--autohide 8` to keep interruptions low.
- **Keep messages short and specific**: a one-line summary plus the next action.
  Never paste long logs into a bubble.
- **To-do flow**: `list` to check → do the work → `done <id>` → `notify` to
  report. `done` also matches on partial titles but fails when ambiguous, so
  prefer the id prefix.
- **Don't spam**: do not notify on every turn. Short interactive work where the
  user is watching the terminal needs no bubbles.
