#!/usr/bin/env bash
# Bapirlo OS — media player moves into the top bar (NO sudo).
#   bash ~/bapirlo-os/430-media-topbar.sh            # backup + install (then log out / in once)
#   bash ~/bapirlo-os/430-media-topbar.sh restore    # back to the previous desktop card + bar mini player
#
# bapirlo-media@bapirlo-os: top-bar button (cover + fading title, note icon when idle) with a dropdown
#   player — cover / video thumbnail, title, artist, drag-to-seek, times, prev/play/next, volume,
#   player switcher. Click / Super+Alt+M / Esc / click outside. Middle-click = play/pause,
#   scroll = switch player. The floating desktop card is OFF by default (setting desktop-widget).
# bapirlo-bar@bapirlo-os: its own mini player is removed; the media button takes its slot.
#
# Settings (all live, no logout):
#   S="gsettings --schemadir ~/.local/share/gnome-shell/extensions/bapirlo-media@bapirlo-os/schemas"
#   $S set org.gnome.shell.extensions.bapirlo-media desktop-widget true      # desktop card back on
#   $S set org.gnome.shell.extensions.bapirlo-media hide-when-idle true      # no note icon when idle
#   $S set org.gnome.shell.extensions.bapirlo-media tint-from-art false      # always crimson
#   $S set org.gnome.shell.extensions.bapirlo-media toggle-panel "['<Super><Alt>m']"
# Off switch:  gnome-extensions disable bapirlo-media@bapirlo-os
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
EXT=~/.local/share/gnome-shell/extensions
LATEST=~/theme-backups/LATEST-MEDIA-TOPBAR
MEDIA=bapirlo-media@bapirlo-os
BAR=bapirlo-bar@bapirlo-os

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-media-topbar
  mkdir -p "$BK"
  cp -a "$EXT/$MEDIA" "$BK/$MEDIA"
  cp -a "$EXT/$BAR" "$BK/$BAR"
  dconf dump /org/gnome/shell/extensions/bapirlo-media/ > "$BK/bapirlo-media.dconf"
  dconf dump /org/gnome/shell/extensions/bapirlo-bar/ > "$BK/bapirlo-bar.dconf"
  gsettings get org.gnome.shell enabled-extensions > "$BK/enabled-extensions.txt"
  [ -d ~/.local/state/bapirlo-media ] && cp -a ~/.local/state/bapirlo-media "$BK/state"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  glib-compile-schemas "$HERE/media-widget/$MEDIA/schemas"
  rm -rf "$EXT/$MEDIA" "$EXT/$BAR"
  cp -rL "$HERE/media-widget/$MEDIA" "$EXT/$MEDIA"
  cp -rL "$HERE/bar/$BAR" "$EXT/$BAR"
  rm -rf "$EXT/$MEDIA/test"
  echo "installed. Log out and back in once (Wayland loads extension code at login)."
  echo "Shortcut: Super+Alt+M · off switch: gnome-extensions disable $MEDIA · undo: bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  rm -rf "$EXT/$MEDIA" "$EXT/$BAR"
  cp -a "$BK/$MEDIA" "$EXT/$MEDIA"
  cp -a "$BK/$BAR" "$EXT/$BAR"
  dconf reset -f /org/gnome/shell/extensions/bapirlo-media/
  [ -s "$BK/bapirlo-media.dconf" ] && dconf load /org/gnome/shell/extensions/bapirlo-media/ < "$BK/bapirlo-media.dconf"
  echo "restored from $BK — log out and back in once."
}

case "${1:-}" in
  "") apply ;;
  restore) restore ;;
  *) sed -n 2,4p "$0"; exit 1 ;;
esac
