#!/usr/bin/env bash
# Bapirlo OS — 3D wallpaper + login intro (NO sudo):
#   · 3D wallpaper (bapirlo-live "depth"): an AI depth map of the wallpaper (Depth Anything V2 Small,
#     CPU, ~3 s, once per wallpaper) — near things move more than far ones as the pointer moves, also on
#     live videos; slow sway when the animation may run. Model + private venv in ~/.local/share/bapirlo
#     (bapirlo-wallpaper depth --setup); maps are made on every wallpaper change.
#     Tune: gsettings … bapirlo-live depth false | depth-strength 0.25–3 | depth-drift false
#   · login intro (bapirlo-desk "login-intro"): greeting, the wallpaper fades up from black, the top bar
#     slides down, the dock rises, the desk widgets cascade in. Replay:
#     gdbus call --session -d org.gnome.Shell -o /os/bapirlo/Desk -m os.bapirlo.Desk.Intro
#   bash ~/bapirlo-os/1600-depth-intro.sh            install
#   bash ~/bapirlo-os/1600-depth-intro.sh restore    put it back
# Needs a log out/in once (extension code). Backup: ~/theme-backups/LATEST-DEPTH-INTRO
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
LATEST=~/theme-backups/LATEST-DEPTH-INTRO
EXT_DIR=~/.local/share/gnome-shell/extensions
DESK=bapirlo-desk@bapirlo-os
LIVE=bapirlo-live@bapirlo-os

backup() {
  if [ -e "$LATEST" ]; then echo "backup kept: $(readlink -f "$LATEST")"; return; fi
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-depth-intro
  mkdir -p "$BK"
  cp -a "$EXT_DIR/$DESK" "$EXT_DIR/$LIVE" "$BK/"
  ln -sfn "$BK" "$LATEST"; echo "backup -> $BK"
}

install() {
  echo "== depth model (private venv + ~100 MB model, once)"
  "$HERE/bin/bapirlo-wallpaper" depth --setup
  echo "== extensions"
  for e in $DESK $LIVE; do
    local src=$HERE/desk/$e; [ $e = $LIVE ] && src=$HERE/live/$e
    rm -rf "${EXT_DIR:?}/$e"; cp -rL "$src" "$EXT_DIR/"
    glib-compile-schemas "$EXT_DIR/$e/schemas"
    glib-compile-schemas "$src/schemas"            # the repo copy (test shell) too
  done
  echo "== depth map for the current wallpaper"
  "$HERE/bin/bapirlo-wallpaper" depth || echo "   (no current wallpaper — made on the next change)"
  echo "installed. Log out/in once: the login intro plays, then move the pointer over the desktop."
}

restore() {
  local BK; BK=$(readlink -f "$LATEST") || { echo "no backup at $LATEST"; exit 1; }
  for e in $DESK $LIVE; do
    rm -rf "${EXT_DIR:?}/$e"; cp -a "$BK/$e" "$EXT_DIR/"
  done
  echo "restored from $BK (log out/in to unload the new code; the model stays in ~/.local/share/bapirlo — delete depth-venv + models to free ~180 MB)"
}

case "${1:-}" in
  "") backup; install ;;
  restore) restore ;;
  *) sed -n 2,14p "$0"; exit 1 ;;
esac
