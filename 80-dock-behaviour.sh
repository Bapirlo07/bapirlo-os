#!/usr/bin/env bash
# Bapirlo OS — dock behaviour (NO sudo).
#   bash ~/bapirlo-os/80-dock-behaviour.sh            # backup + apply
#   bash ~/bapirlo-os/80-dock-behaviour.sh patch      # re-apply only the click patch (after a Dash2Dock update)
#   bash ~/bapirlo-os/80-dock-behaviour.sh restore    # undo
#
# 1. Intellihide: the dock hides when a window overlaps it (maximised or not), reveals when the pointer touches the
#    2px strip at the bottom edge under the dock, hides again ~120ms after the pointer leaves. No struts while
#    autohide is on → maximised windows reach the bottom edge. Top bar untouched.
# 2. Clicks on a running app: focus it, or minimise it if it is already focused. Middle-click / Ctrl+click = new
#    window. Fixes:
#    - disable launch-new-instance (that extension makes EVERY dock click open a new window)
#    - patch dash2dock-lite dock.js: forward the mouse button to GNOME's activate() (it was dropped, so middle-click
#      never counted as middle), and detect middle-click with BUTTON2 (it checked BUTTON3 = right button, so a
#      middle-click on a focused app minimised it instead of opening a new window).
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
EXT=~/.local/share/gnome-shell/extensions
D2D=$EXT/dash2dock-lite@icedman.github.com
LATEST=~/theme-backups/LATEST-DOCK-BEHAVIOUR
d2d() { gsettings --schemadir "$D2D/schemas" set org.gnome.shell.extensions.dash2dock-lite "$1" "$2"; }

patch_clicks() {
  python3 - "$D2D/dock.js" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read(); n = 0
old1 = '''          c._appwell.activate = () => {
            try {
              if (!c._menu) {
                this._maybeBounce(c);
              }
              this._maybeMinimizeOrMaximize(c._appwell.app);
              c._appwell._activate();'''
new1 = '''          c._appwell.activate = (...args) => { // bapirlo: forward mouse button
            try {
              if (!c._menu) {
                this._maybeBounce(c);
              }
              this._maybeMinimizeOrMaximize(c._appwell.app);
              c._appwell._activate(...args);'''
old2 = '''      let isMiddleButton = button3; // middle?'''
new2 = '''      let isMiddleButton = button2 || (event && event.get_button && event.get_button() == 2); // bapirlo: was button3 (right)'''
for o, nw in ((old1, new1), (old2, new2)):
    if nw in s: continue
    if o not in s: sys.exit(f"patch anchor not found in {p} — Dash2Dock changed, not patching:\n{o}")
    s = s.replace(o, nw); n += 1
open(p, 'w').write(s)
print(f"dock.js: {n} change(s) applied" if n else "dock.js: already patched")
EOF
}

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-dock-behaviour
  mkdir -p "$BK"
  dconf dump / > "$BK/dconf-full.ini"
  gnome-extensions list --enabled > "$BK/enabled-extensions.txt"
  cp -a "$D2D/dock.js" "$BK/dock.js"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  # --- 2. clicks
  gnome-extensions disable launch-new-instance@gnome-shell-extensions.gcampax.github.com || true
  patch_clicks

  # --- 1. intellihide
  d2d pressure-sense false        # reveal as soon as the pointer enters the 2px bottom strip (no dwell counting)
  d2d autohide-dodge true         # hide only when a window overlaps the dock (= intellihide)
  d2d autohide-speed 0.35         # slide ≈ 255ms — same 250ms motion as windows / overview
  d2d autohide-dash true          # last: re-registers the dock without struts → work area to the bottom edge
  echo
  echo "dock: intellihide on, bottom-edge reveal, ~255ms slide; launch-new-instance off."
  echo "The click patch is JavaScript: log out and back in once for it to load (Wayland can't reload extensions live)."
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  cp -a "$BK/dock.js" "$D2D/dock.js"
  dconf load / < "$BK/dconf-full.ini"
  grep -qx launch-new-instance@gnome-shell-extensions.gcampax.github.com "$BK/enabled-extensions.txt" \
    && gnome-extensions enable launch-new-instance@gnome-shell-extensions.gcampax.github.com
  echo "restored — log out/in to unload the click patch"
}

case "${1:-}" in
  "") apply ;; patch) patch_clicks ;; restore) restore ;;
  *) sed -n 2,5p "$0"; exit 1 ;;
esac
