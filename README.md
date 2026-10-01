# DeskBuddy

A floating desktop buddy for macOS. A little character sits on top of your screen;
click it and your to-do list unfolds. Visible across every Space and even over
full-screen apps.

Website: **[deskbuddy.snghnl.com](https://deskbuddy.snghnl.com)**

## Install

```sh
curl -fsSL https://deskbuddy.snghnl.com/install.sh | sh
```

Or download [`DeskBuddy.dmg`](https://github.com/snghnl/deskbuddy/releases/latest/download/DeskBuddy.dmg)
and drag the app to Applications.

Requires macOS 14 (Sonoma) or later. Universal binary (Apple Silicon + Intel).

### Why two ways

DeskBuddy is not notarized — that needs a paid Apple Developer account. macOS
quarantines anything a browser downloaded, so opening the `.dmg` build the first
time takes a detour: launch it, dismiss the warning, then **System Settings →
Privacy & Security → Open Anyway**. Control-clicking the app no longer works;
Apple removed that bypass in macOS 15.

`curl` does not set the quarantine flag, so the one-liner installs the very same
build with no warning at all. It is a short, readable script — [give it a
look](docs/install.sh) before piping it into a shell.

Already installed the hard way? `xattr -dr com.apple.quarantine /Applications/DeskBuddy.app`

### Updating

DeskBuddy asks GitHub for the latest release once a day, and the buddy speaks up
when it finds one. **Settings → Updates** shows the installed version and installs
the update in place: it downloads the release zip, matches it against the release's
`checksums.txt`, swaps the app and relaunches.

Every build carries a different ad-hoc signature, so macOS treats an updated
DeskBuddy as a new app and drops its calendar permission along the way. Reconnect
it in **Settings → Integrations** afterwards — the app says so when it happens.

## Build & Run

```sh
./make-app.sh              # builds build/DeskBuddy.app (native arch)
./make-app.sh --universal  # arm64 + x86_64 (what CI ships)
open build/DeskBuddy.app

./make-dmg.sh --build      # universal build, then build/DeskBuddy.dmg
```

`make-dmg.sh` lays the disk image window out with
[dmgbuild](https://pypi.org/project/dmgbuild/) (`pip install dmgbuild`), which
writes the Finder `.DS_Store` directly instead of scripting Finder — the only way
that also works on a headless CI runner. Without it you still get a plain,
usable image.

During development you can also just `swift run`. No Xcode project — plain Swift Package Manager.

## Features

- **One character, or your own image**: the built-in buddy is drawn as a shape rather
  than an image, so it stays sharp at any size and inverts with your system appearance —
  white with a dark outline in light mode, black with a light outline in dark mode. It
  blinks, and a badge shows the number of open to-dos. You can also add any image as your
  own character and name it in Settings
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
  All strings live in `Sources/DeskBuddyCore/Resources/Localizations/*.yml` — translation
  fixes and new languages are welcome as PRs
- **Always on top**: `NSPanel` at `.floating` level, visible on all Spaces and over
  full-screen apps
- **Non-activating**: clicking the buddy never steals focus from the app you are using
- Add (Enter), check off, hover-to-delete, drag to reorder
- Tooltips show when each item was added; a detail page holds the title, memo, and timestamps
- Character position and list size persist across restarts
- Menu bar icon (no Dock icon); each feature keeps its data in
  `~/Library/Application Support/DeskBuddy/plugins/<feature>/` — to-dos in `plugins/todo/todos.json`.
  0.18 moved them there from the folder above and kept the originals in its `backups/` folder

## Agent Integration (CLI / URL scheme)

External scripts and agents (Claude Code, background workers, cron jobs) can talk to
DeskBuddy:

```sh
bin/deskbuddy notify "Build finished!"            # speech bubble (stays until clicked, or per Settings)
bin/deskbuddy notify "heads up" --autohide 8      # auto-dismiss after 8s
bin/deskbuddy add "Review the PR" --memo "not urgent"
bin/deskbuddy list                                # open to-dos
bin/deskbuddy list --json                         # full data as JSON (for agents)
bin/deskbuddy done a42620c8                       # complete by id prefix or title part
bin/deskbuddy toggle                              # open/close the list
bin/deskbuddy timer 25 "Write the report"         # start a 25-minute timer
bin/deskbuddy run todo.list                       # run any command by name, print its answer
```

While DeskBuddy runs, the CLI talks to it over a socket
(`~/Library/Application Support/DeskBuddy/deskbuddy.sock`, readable only by you), so
errors come back with a message and a non-zero exit. When the app is not running,
notify/add/done/toggle go through the `deskbuddy://` URL scheme, which launches it, and
list reads `plugins/todo/todos.json` directly (or the older `todos.json`, for apps before 0.18). timer and run need the socket, so they launch the app
first. To put the CLI on PATH:
`ln -s "$(pwd)/bin/deskbuddy" /usr/local/bin/deskbuddy`

Commands, for `deskbuddy run <command> name=value ...` or `deskbuddy://<command>?name=value`:

| Command | Arguments |
|---|---|
| `buddy.say` | `message`, `autohide` (seconds, optional) |
| `list.toggle` | — |
| `todo.add` | `title`, `memo` (optional) |
| `todo.complete` | `id` (full UUID) |
| `todo.toggle` / `todo.remove` | `id` (full UUID) — quietly, like the row's buttons |
| `todo.show` | `id` (full UUID) — opens the list on that to-do's detail |
| `todo.list` | — (answers with every to-do, as in todos.json) |
| `pomodoro.start` | `minutes`, `label` (optional), `todo` (UUID to link, optional) |

The short URL forms the CLI has always used keep working:

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

The app is a small host plus built-in plugins, each its own SwiftPM target. A plugin depends on
DeskBuddyCore and on other features' API modules, never on another plugin.

- `Sources/DeskBuddyCore/` — what plugins build on: the plugin lifecycle (`Plugins/`), services, slots
  on the shared UI (`Slots/`), commands and the CLI socket (`Commands/`), events (`Events/`), the
  `Buddy` protocol, and YAML-backed localization (`L.s("key")` / `L.f("key", args...)`) with its
  tables in `Resources/Localizations/` (`ko.yml`, `en.yml`)
- `Sources/TodoAPI/` — what the to-do feature offers others: `TodoService`, `TodoDeleted`, the to-do row slot
- `Sources/TodoPlugin/` — to-dos: model and JSON persistence, To Do/Done tabs, detail page, history settings
- `Sources/PomodoroPlugin/` — timers: the Timer tab, timer icons on to-do rows, the done bubble
- `Sources/CalendarPlugin/` — the Calendar tab (completion heatmap + EventKit events), calendar settings, event alerts
- `Sources/DeskBuddy/` — the host: registers the plugins, draws the character, list panel, speech
  bubble and settings window, and handles click/drag/throw, wandering, the hotkey, menus, the URL
  scheme and updates
- `bin/deskbuddy` — CLI for agent integration
- `plugin/` — Claude Code plugin (skill, hook, bundled CLI)
- `tools/make-assets.swift` — renders the website art and link-preview card from the same shape the app draws
- `tools/dmg-settings.py` — disk image window layout, used by `make-dmg.sh`
- `docs/` — the website (GitHub Pages) and `install.sh`

## License

[MIT](LICENSE)
