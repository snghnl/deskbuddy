# dmgbuild settings for the DeskBuddy release image.
#
# dmgbuild writes the Finder layout straight into the volume's .DS_Store, so the
# window looks the same whether it is built on a desktop or on a headless CI
# runner. Invoked by ../make-dmg.sh — not meant to be run directly.
import os.path

app = defines.get("app", "build/DeskBuddy.app")  # noqa: F821 — dmgbuild injects `defines`
appname = os.path.basename(app)

# Image
format = "UDZO"
compression_level = 9
files = [app]
symlinks = {"Applications": "/Applications"}

# Window
background = "builtin-arrow"
window_rect = ((200, 160), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

# Icons — drag from left to right, the arrow between them comes from the background
icon_size = 112
text_size = 13
icon_locations = {
    appname: (165, 210),
    "Applications": (495, 210),
}

# Volume icon
if os.path.exists("assets/AppIcon.icns"):
    badge_icon = "assets/AppIcon.icns"
