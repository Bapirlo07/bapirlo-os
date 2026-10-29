#!/usr/bin/env bash
# Kuro OS — pop-out picture-in-picture for ANY window (NO sudo):
#   Super+Alt+I (or window menu → "Picture in Picture") floats a live mini copy of the window in a
#   corner, above everything, on every workspace. Drag / scroll / Ctrl+scroll / double-click / ✕.
#   Lives in the Kuro Desk extension (desk/…/popout.js).
#   bash ~/bapirlo-os/1320-popout-pip.sh            install
#   bash ~/bapirlo-os/1320-popout-pip.sh restore    put the previous Desk extension back
# Needs a log out/in once (shell extension code). Backup: ~/theme-backups/LATEST-POPOUT
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
LATEST=~/theme-backups/LATEST-POPOUT
EXT_DIR=~/.local/share/gnome-shell/extensions
DESK=bapirlo-desk@bapirlo-os

backup() {
  if [ -e "$LATEST" ]; then echo "backup kept: $(readlink -f "$LATEST")"; return; fi
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-popout
  mkdir -p "$BK"
  cp -a "$EXT_DIR/$DESK" "$BK/"
  ln -sfn "$BK" "$LATEST"; echo "backup -> $BK"
}

install() {
  rm -rf "${EXT_DIR:?}/$DESK"; cp -rL "$HERE/desk/$DESK" "$EXT_DIR/"
  glib-compile-schemas "$EXT_DIR/$DESK/schemas"
  echo "pop-out PiP: installed. Log out/in once, then Super+Alt+I on any window."
}

restore() {
  local BK; BK=$(readlink -f "$LATEST")
  [ -d "$BK" ] || { echo "no backup at $LATEST"; exit 1; }
  rm -rf "${EXT_DIR:?}/$DESK"; cp -a "$BK/$DESK" "$EXT_DIR/"
  echo "restored from $BK (log out/in to unload it)"
}

case "${1:-}" in
  "") backup; install ;;
  restore) restore ;;
  *) sed -n 2,9p "$0"; exit 1 ;;
esac
