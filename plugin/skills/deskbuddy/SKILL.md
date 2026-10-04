---
name: deskbuddy
description: >
  Send speech-bubble notifications to the user, manage their to-dos, and start
  timers through DeskBuddy (a floating character on the macOS screen). Use when:
  (1) a long-running task (build, tests, migration, deploy, lengthy analysis)
  finishes and the user should be notified (2) the user says "notify me",
  "remind me", or mentions "deskbuddy" (3) adding, listing, or completing the
  user's to-dos ("add a to-do", "what's on my list", "mark this done") (4) the
  user asks for a timer, a pomodoro, or a focus session (5) you need the user's
  decision to go on while they are likely away from the terminal, or they asked
  to be asked through DeskBuddy. macOS only.
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
deskbuddy timer 25 "label"                # Start a countdown timer (label optional)
deskbuddy ask "question" [option ...]     # Ask in a panel next to the buddy, print the answer
deskbuddy ask "question" A B --timeout 540  # Give up after 540s (exit 1, panel closes)
```

Sending a command launches the app automatically if it is not running
(except `list`, which reads the data file directly when the app is off).
While the app runs, a failed command prints `deskbuddy: <reason>` to stderr and
exits non-zero — read it rather than assuming success. `timer` needs
DeskBuddy 0.16 or later, `ask` 0.17 or later.

## Usage guidelines

- **Report finished work**: when a long task (several minutes or more) that the
  user may have stepped away from completes, `notify` with the key result.
  e.g. `deskbuddy notify "✅ Migration done — 37 files, tests passing"`
- **Failures and decisions**: if something failed or needs the user's judgment,
  send without autohide (the bubble follows the user's dismiss setting — until
  clicked by default — so it won't be missed).
  e.g. `deskbuddy notify "⚠️ Deploy failed — check the logs"`
- **Light progress updates**: use `--autohide 8` to keep interruptions low.
- **Keep messages short and specific**: a one-line summary plus the next action.
  Never paste long logs into a bubble.
- **To-do flow**: `list` to check → do the work → `done <id>` → `notify` to
  report. `done` also matches on partial titles but fails when ambiguous, so
  prefer the id prefix.
- **Timers**: when the user asks for a focus session, a pomodoro, or "remind me
  in N minutes", start one with `timer`. DeskBuddy rings and shows a bubble when
  it runs out, so there is no need to wait and `notify` yourself.
- **Don't spam**: do not notify on every turn. Short interactive work where the
  user is watching the terminal needs no bubbles.

## Asking the user

`ask` puts a question in a panel next to the buddy, where the user sees it from
any app, and waits for the answer. With options it shows them as a choice (the
user may also type their own answer); without, a text field. It prints only the
answer.

- **When**: you need a decision to continue and the user is probably not
  watching the terminal — a long autonomous run, or they asked to be reached
  through DeskBuddy. While they are chatting with you, ask in the conversation.
- **How**: one short question, a handful of concrete options, the likely one
  first. e.g. `deskbuddy ask "Which database for the cache?" SQLite PostgreSQL`
- **Waiting**: it blocks until the user answers. Run it with the Bash tool's
  timeout at 600000 ms and pass `--timeout 540`, so `ask` gives up first and
  takes the question back off the screen.
- **No answer**: exit 1 means they closed the panel or time ran out (the reason
  is on stderr). Do not guess on anything hard to undo; stop and say what you
  need, or take the safe default and say which one you took.
