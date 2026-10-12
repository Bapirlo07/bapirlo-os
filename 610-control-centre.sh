#!/usr/bin/env bash
# Bapirlo OS — round 6 · Mac-style Control Centre (NO sudo).
#   bash ~/bapirlo-os/610-control-centre.sh            # backup + install + enable (then log out / in once)
#   bash ~/bapirlo-os/610-control-centre.sh restore    # remove it, settings back as before
#
# bapirlo-control-centre@bapirlo-os (source: control-centre/): clicking the status icons on the right of
# the bar (or Super+S) drops down a tile grid — Wi-Fi, Bluetooth, power mode, Do Not Disturb,
# Night Light, Caffeine, screen recording, dark style, volume + brightness, battery, storage,
# now playing. Long-press or right-click a tile to expand it inside the panel (networks, devices,
# outputs, power modes…). Pencil button = edit: drag to reorder, − to remove, + to add.
# GNOME's original menu is untouched: "Classic" button or Super+Alt+S.
# Tiles mirror GNOME's own quick-settings backends; nothing polls, nothing runs while closed.
#
# Off switch:  gnome-extensions disable bapirlo-control-centre@bapirlo-os   (GNOME's menu is back at once)
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/ext.sh"
EXT=~/.local/share/gnome-shell/extensions
LATEST=~/theme-backups/LATEST-CONTROL-CENTRE
UUID=bapirlo-control-centre@bapirlo-os
DCONF=/org/gnome/shell/extensions/bapirlo-control-centre/

apply() {
  if [ -z "${BAPIRLO_INSTALLER:-}" ] && ! grep -qs '"Before round 6"' /timeshift/snapshots/*/info.json; then
    echo "No Timeshift snapshot \"Before round 6\" yet — run first:  sudo bash $HERE/600-round6-storage.sh"
    exit 1
  fi
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-control-centre
  mkdir -p "$BK"
  [ -d "$EXT/$UUID" ] && cp -a "$EXT/$UUID" "$BK/$UUID"
  dconf dump $DCONF > "$BK/control-centre.dconf"
  gsettings get org.gnome.shell enabled-extensions > "$BK/enabled-extensions.txt"
  gsettings get org.gnome.shell.keybindings toggle-quick-settings > "$BK/toggle-quick-settings.txt"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  chmod +x "$HERE/bin/bapirlo-record" "$HERE/bin/bapirlo-cleanup-now"
  mkdir -p ~/Videos/Recordings
  glib-compile-schemas "$HERE/control-centre/$UUID/schemas"
  rm -rf "${EXT:?}/$UUID"
  cp -rL "$HERE/control-centre/$UUID" "$EXT/$UUID"
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
  dconf reset -f $DCONF
  [ -s "$BK/control-centre.dconf" ] && dconf load $DCONF < "$BK/control-centre.dconf"
  echo "removed (backup $BK) — GNOME's quick settings are back. Log out / in once to unload the code."
}

case "${1:-apply}" in
  apply) apply ;;
  restore) restore ;;
  *) sed -n 2,15p "$0"; exit 1 ;;
esac
