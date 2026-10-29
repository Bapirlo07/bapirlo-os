#!/usr/bin/env bash
# Kuro OS — sharper wallpaper + live wallpaper (NO sudo).
#   bash ~/bapirlo-os/940-live-wallpaper.sh            # apply both steps
#   bash ~/bapirlo-os/940-live-wallpaper.sh hd|live    # one step
#   bash ~/bapirlo-os/940-live-wallpaper.sh restore    # undo
#
#   hd    re-upscale the Kuro art: Real-ESRGAN x4 anime with TTA on the NVIDIA card (~10 s),
#         unsharp, pixel-fine grain (tools/make-hero.py), then rebuild the day / night grades
#         (tools/make-daynight.py) and install them — same file names, the shell reloads them (live)
#   live  bapirlo-live@bapirlo-os: GPU shader on the wallpaper — embers, sakura petals, crimson
#         glow, optional parallax; 30 fps, stops whenever the wallpaper can't be seen, on battery
#         and in power-saver; Super+Alt+W pauses                                       (logout)
# Settings: gsettings --schemadir ~/.local/share/gnome-shell/extensions/bapirlo-live@bapirlo-os/schemas \
#             list-recursively org.gnome.shell.extensions.bapirlo-live
# Backup: ~/theme-backups/LATEST-LIVE-WALLPAPER
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/ext.sh"
LATEST=~/theme-backups/LATEST-LIVE-WALLPAPER
BG=~/.local/share/backgrounds/bapirlo
UUID=bapirlo-live@bapirlo-os
EXT=$EXT_DIR/$UUID

backup() {
  [ -e "$LATEST" ] && return
  BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-live-wallpaper
  mkdir -p "$BK"
  cp -a "$BG" "$BK/backgrounds"
  cp -a "$HERE/build/art" "$BK/build-art"
  ln -sfn "$BK" "$LATEST"
  echo "backup: $BK"
}

step_hd() {
  python3 -I "$HERE/tools/make-hero.py"
  cp "$HERE/build/art/hero-2560x1600.png" "$BG/kuro-2560x1600.png"
  cp "$HERE/build/art/blur-2560x1600.png" "$BG/kuro-blur-2560x1600.png"
  python3 -I "$HERE/tools/make-daynight.py"          # reads the hero just installed
  cp "$HERE"/build/art/kuro-{day,night}-2560x1600.jpg "$BG/"
  echo "hd: sharper wallpaper installed (day + night)"
}

step_live() {
  rm -rf "$EXT"
  cp -a "$HERE/live/$UUID" "$EXT"
  glib-compile-schemas "$EXT/schemas"
  ext_enable "$UUID"
  echo "live: $UUID installed + enabled — log out and back in to start it"
}

case "${1:-apply}" in
apply) backup; step_hd; step_live ;;
hd) backup; step_hd ;;
live) backup; step_live ;;
restore)
  [ -e "$LATEST" ] || { echo "no backup at $LATEST"; exit 1; }
  BK=$(readlink -f "$LATEST")
  gnome-extensions disable "$UUID" 2>/dev/null || true
  rm -rf "$EXT"
  dconf reset -f /org/gnome/shell/extensions/bapirlo-live/
  cp -a "$BK"/backgrounds/kuro-*-2560x1600.* "$BK/backgrounds/kuro-2560x1600.png" "$BG/"
  rm -rf "$HERE/build/art" && cp -a "$BK/build-art" "$HERE/build/art"
  echo "restored from $BK (tools/make-hero.py changes stay in git — revert there if wanted)"
  ;;
*) echo "usage: $0 [apply|hd|live|restore]"; exit 1 ;;
esac
