#!/usr/bin/env bash
# Kuro OS round 11 (wallpapers) — the parts YOU run. Run as yourself (it asks for sudo for the snapshot).
#   bash ~/bapirlo-os/1100-round11-install.sh            # snapshot + live engine
#   bash ~/bapirlo-os/1100-round11-install.sh restore    # remove the live engine again (snapshot stays)
#
# 0. Timeshift snapshot "Before round 11" FIRST — nothing else runs unless it succeeds
# 1. live wallpaper engine: Hanabi (github.com/jeffshee/gnome-ext-hanabi), the last plain-JavaScript
#    version (commit 033dc86) vendored in wallpaper/vendor/, + "51" in its metadata and one Kuro
#    patch (pause while the overview is open). Installed for you only (~/.local/share), not enabled —
#    the wallpaper manager turns it on when you pick a video and off for a picture.
#    Settings: pause on battery / with a maximised or fullscreen window, muted, Intel video decoding
#    (keeps the NVIDIA card asleep), fill the screen, no top-bar menu.
# Then run (no sudo):  bash ~/bapirlo-os/1110-round11.sh
# Never touches Limine, GRUB, partitions, fstab or EFI.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as yourself, WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
UUID=hanabi-extension@jeffshee.github.io
SRC=$HERE/wallpaper/vendor/$UUID
DEST=${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID
SCHEMA=io.github.jeffshee.hanabi-extension
LATEST=~/theme-backups/LATEST-ROUND11-INSTALL

hset() { gsettings --schemadir "$DEST/schemas" set "$SCHEMA" "$1" "$2"; }

apply() {
  sudo -v
  echo "== 0/1 Timeshift snapshot \"Before round 11\" (incremental — a few minutes)"
  if sudo timeshift --list --scripted 2>/dev/null | grep -q "Before round 11"; then
    echo "already there:"
  else
    sudo timeshift --create --scripted --comments "Before round 11" --tags O
    sudo timeshift --list --scripted | grep -q "Before round 11" || { echo "!! snapshot missing — stopping, nothing changed."; exit 1; }
  fi
  sudo timeshift --list --scripted | grep "Before round 11"

  if ! [ -s "$LATEST" ]; then
    local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round11-install
    mkdir -p "$BK"
    [ -d "$DEST" ] && cp -a "$DEST" "$BK/hanabi" || touch "$BK/no-hanabi-before"
    gsettings get org.gnome.shell enabled-extensions > "$BK/enabled-extensions.txt"
    echo "$BK" > "$LATEST"; echo "backup -> $BK"
  else
    echo "re-run: keeping the first backup -> $(cat "$LATEST")"
  fi

  echo; echo "== 1/1 live wallpaper engine (Hanabi)"
  cat "$SRC/BAPIRLO-VENDOR.txt" | sed 's/^/   /'
  echo "   files: $(cd "$SRC" && find . -type f | wc -l), $(du -sh "$SRC" | cut -f1); it only starts its own video renderer (renderer/renderer.js)"
  read -r -p "   Install it for your user? [y/N] " ok
  [[ "$ok" =~ ^[Yy] ]] || { echo "   skipped — videos will show as a still frame until you run this again."; exit 0; }
  rm -rf "$DEST"
  mkdir -p "$(dirname "$DEST")"
  cp -a "$SRC" "$DEST"
  hset pause-on-battery 2                    # always on battery
  hset pause-on-maximize-or-fullscreen 1     # any monitor
  hset mute true
  hset enable-va true                        # Intel VA decoders above nvcodec → the dGPU stays asleep
  hset content-fit 2                         # cover
  hset show-panel-menu false
  hset change-wallpaper false                # the Kuro manager decides what plays
  echo "   installed -> $DEST"
  echo
  echo "Next:  bash $HERE/1110-round11.sh      (then log out and back in once so GNOME sees the new extension)"
}

restore() {
  local BK; BK=$(cat "$LATEST" 2>/dev/null) || { echo "nothing to restore ($LATEST missing)"; exit 1; }
  gsettings set org.gnome.shell enabled-extensions "$(cat "$BK/enabled-extensions.txt")"
  rm -rf "$DEST"
  [ -d "$BK/hanabi" ] && cp -a "$BK/hanabi" "$DEST"
  echo "Restored from $BK (the snapshot stays). Log out and back in to unload it."
}

case "${1:-}" in
  restore) restore ;;
  "") apply ;;
  *) sed -n '2,15p' "$0"; exit 64 ;;
esac
