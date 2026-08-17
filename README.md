# DeskBuddy

A floating desktop buddy for macOS. A little character sits on top of your screen;
click it and your to-do list unfolds. Visible across every Space and even over
full-screen apps.

## Build & Run

```sh
./make-app.sh          # builds build/DeskBuddy.app
open build/DeskBuddy.app
```

During development you can also just `swift run`. No Xcode project — plain Swift Package Manager.

## Features

- **3 built-in characters + custom images**: pick the slime, ghost, or cat — or add any
  image as your own character (name it and rename it in Settings). Built-in characters
  blink and change expressions; a badge shows the number of open to-dos
- **Click → list toggle**: click the character to open the to-do panel next to it;
  drag the character to move (the list follows)
- **Throwing**: grab and flick the character — it flies with momentum, bounces off the
  screen edges, and lands. Catch it mid-air with a click (can be disabled in Settings)
- **Wandering**: optionally lets the character stroll around the screen, picking random
  spots, walking there, and resting. Pauses while the list is open, while being held,
  or while a menu is up
- **Global shortcut**: register a hotkey in Settings to open the list and start typing
  from any app (Carbon hotkey — no Accessibility permission needed)
- **To Do / Done / Calendar tabs**: completed items move to the Done tab, grouped by day
  (Today/Yesterday/…) with completion times. ⌘1/⌘2/⌘3 switch tabs while the list is up
- **Calendar tab**: a monthly grid with a completion heatmap (busier days shaded darker)
  plus dots on days that have calendar events. Tap a date to see that day's events and
  completed items together
- **Calendar integration (EventKit)**: reads events from any account connected to macOS
  Calendar (Google included) — no OAuth. Today's events get "Now" / "in N min" badges.
  Managed from the Integrations section in Settings
- **Event alerts (speech bubble)**: 5/10/15/30 minutes (configurable) before an event
  starts, the character raises a speech bubble. It stays until clicked, follows the
  character around, and repositions above/below/left/right based on screen space
- **Language setting**: follow the system language or force Korean/English from Settings.
  All strings live in `Sources/DeskBuddy/Resources/Localizations/*.yml` — translation
  fixes and new languages are welcome as PRs
- **Always on top**: `NSPanel` at `.floating` level, visible on all Spaces and over
  full-screen apps
- **Non-activating**: clicking the buddy never steals focus from the app you are using
- Add (Enter), check off, hover-to-delete, drag to reorder
- Tooltips show when each item was added; a detail page holds the title, memo, and timestamps
- Character position and list size persist across restarts
- Menu bar icon (no Dock icon); data lives in `~/Library/Application Support/DeskBuddy/todos.json`

## Agent Integration (CLI / URL scheme)

External scripts and agents (Claude Code, background workers, cron jobs) can talk to
DeskBuddy:

```sh
bin/deskbuddy notify "Build finished!"            # speech bubble (stays until clicked)
bin/deskbuddy notify "heads up" --autohide 8      # auto-dismiss after 8s
bin/deskbuddy add "Review the PR" --memo "not urgent"
bin/deskbuddy list                                # open to-dos
bin/deskbuddy list --json                         # full data as JSON (for agents)
bin/deskbuddy done a42620c8                       # complete by id prefix or title part
bin/deskbuddy toggle                              # open/close the list
```

Writes (notify/add/done/toggle) go through the `deskbuddy://` URL scheme, so the app
launches automatically if it is not running. Reads (list) go straight to todos.json and
work either way. To put the CLI on PATH:
`ln -s "$(pwd)/bin/deskbuddy" /usr/local/bin/deskbuddy`

- `deskbuddy://notify?message=...&autohide=8`
- `deskbuddy://add?title=...&memo=...`
- `deskbuddy://done?id=<uuid>`
- `deskbuddy://toggle`

## Claude Code Plugin

This repository doubles as a Claude Code plugin marketplace. Installing the plugin
teaches agents to use DeskBuddy on their own (skill + waiting-for-input alert hook +
bundled CLI).

```
/plugin marketplace add snghnl/deskbuddy
/plugin install deskbuddy@deskbuddy
```

What's included:
- **Skill** (`plugin/skills/deskbuddy/`): guidelines for agents — report long-running
  work via bubbles, add/list/complete to-dos, don't spam
- **Notification hook** (`plugin/hooks/`): when Claude Code waits for permission or
  input, a bubble appears automatically (`🔔 [project] message`). Silently does nothing
  if the app isn't installed
- **Bundled CLI** (`plugin/scripts/deskbuddy`): works without any PATH setup

If you edit `bin/deskbuddy`, copy it to `plugin/scripts/deskbuddy` to keep them in sync.

## Launch at Login

System Settings → General → Login Items → add `build/DeskBuddy.app`.

## Project Layout

- `Sources/DeskBuddy/App.swift` — entry point, character/list panels (NSPanel subclasses), click/drag/throw handling, menus, settings window, URL scheme
- `Sources/DeskBuddy/CharacterView.swift` — the three built-in characters (Shape drawing + animation), custom image rendering
- `Sources/DeskBuddy/CustomCharacters.swift` — custom character images, display names, image cache
- `Sources/DeskBuddy/WanderController.swift` — wandering (pick target → walk → rest loop)
- `Sources/DeskBuddy/ThrowController.swift` — throw physics (gravity, restitution, friction)
- `Sources/DeskBuddy/HotKeyCenter.swift` — Carbon global hotkey
- `Sources/DeskBuddy/Bubble.swift` — speech bubble panel + event alert watcher
- `Sources/DeskBuddy/CalendarService.swift` — EventKit integration (access, queries, change tracking)
- `Sources/DeskBuddy/CalendarView.swift` — calendar tab (heatmap grid + events/completions)
- `Sources/DeskBuddy/SettingsView.swift` — settings (language, characters, toggles, hotkey recorder)
- `Sources/DeskBuddy/TodoListView.swift` — list (To Do/Done/Calendar tabs) + detail page
- `Sources/DeskBuddy/TodoStore.swift` — model + JSON persistence
- `Sources/DeskBuddy/Localization.swift` — YAML-backed localization (`L.s("key")` / `L.f("key", args...)`)
- `Sources/DeskBuddy/Resources/Localizations/` — translation tables (`ko.yml`, `en.yml`)
- `bin/deskbuddy` — CLI for agent integration
- `plugin/` — Claude Code plugin (skill, hook, bundled CLI)
