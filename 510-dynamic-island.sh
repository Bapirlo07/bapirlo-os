#!/usr/bin/env bash
# Bapirlo OS — Dynamic Island in the centre of the top bar (NO sudo).
#   bash ~/bapirlo-os/510-dynamic-island.sh            # backup + install + enable (then log out / in once)
#   bash ~/bapirlo-os/510-dynamic-island.sh restore    # remove it, settings back as before
#
# bapirlo-island@bapirlo-os (source: dynamic-island/): the clock + weather sit in a dark capsule; it
# grows to show volume/brightness (replaces GNOME's OSD), notification banners (click = open,
# right/middle-click = dismiss, hover = keep open), the track when music starts/changes (play/pause,
# next), charger plugged/unplugged + low battery (20 %, 10 %) and screenshots (click = open).
# While the main screen is fullscreen (games, video) it steps aside: GNOME's normal OSD/banners.
# Do Not Disturb and per-app "banners off" are respected. No polling — signals only.
#
# Settings (live, no logout):
#   S="gsettings --schemadir ~/.local/share/gnome-shell/extensions/bapirlo-island@bapirlo-os/schemas"
#   $S set org.gnome.shell.extensions.bapirlo-island rest-pill false        # no capsule while idle
#   keys osd / notifications / media / charging / screenshots  (true|false) switch each part
# Off switch:  gnome-extensions disable bapirlo-island@bapirlo-os
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/ext.sh"
EXT=~/.local/share/gnome-shell/extensions
LATEST=~/theme-backups/LATEST-DYNAMIC-ISLAND
UUID=bapirlo-island@bapirlo-os

apply() {
  if [ -z "${BAPIRLO_INSTALLER:-}" ] && ! grep -qs '"Before round 5"' /timeshift/snapshots/*/info.json; then
    echo "No Timeshift snapshot \"Before round 5\" yet — run first:  bash $HERE/500-round5-greeter.sh snapshot"
    exit 1
  fi
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-dynamic-island
  mkdir -p "$BK"
  [ -d "$EXT/$UUID" ] && cp -a "$EXT/$UUID" "$BK/$UUID"
  dconf dump /org/gnome/shell/extensions/bapirlo-island/ > "$BK/bapirlo-island.dconf"
  gsettings get org.gnome.shell enabled-extensions > "$BK/enabled-extensions.txt"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  glib-compile-schemas "$HERE/dynamic-island/$UUID/schemas"
  rm -rf "${EXT:?}/$UUID"
  cp -rL "$HERE/dynamic-island/$UUID" "$EXT/$UUID"   # -L: mpris.js / art.js are links into media-widget
  ext_enable "$UUID"
  echo "installed + enabled. Log out and back in once (Wayland loads extension code at login)."
  echo "Off switch: gnome-extensions disable $UUID · undo: bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  gnome-extensions disable "$UUID" 2>/dev/null || true
  python3 - "$UUID" <<'PY'
import ast, subprocess, sys
v = subprocess.run(["gsettings", "get", "org.gnome.shell", "enabled-extensions"], capture_output=True, text=True).stdout.strip()
en = [] if v.startswith("@as") else ast.literal_eval(v)
subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str([e for e in en if e != sys.argv[1]])], check=True)
PY
  rm -rf "${EXT:?}/$UUID"
  [ -d "$BK/$UUID" ] && cp -a "$BK/$UUID" "$EXT/$UUID"
  dconf reset -f /org/gnome/shell/extensions/bapirlo-island/
  [ -s "$BK/bapirlo-island.dconf" ] && dconf load /org/gnome/shell/extensions/bapirlo-island/ < "$BK/bapirlo-island.dconf"
  echo "removed (backup $BK) — log out and back in once to clear it from the running shell."
}

case "${1:-}" in
  "") apply ;;
  restore) restore ;;
  *) sed -n 2,4p "$0"; exit 1 ;;
esac
