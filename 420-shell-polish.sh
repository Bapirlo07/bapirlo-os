#!/usr/bin/env bash
# Bapirlo OS polish — step 3: notifications, quick settings, calendar (NO sudo, no logout).
#   bash ~/bapirlo-os/420-shell-polish.sh            # backup + apply (preview: build/polish/notif-qs-preview.png)
#   bash ~/bapirlo-os/420-shell-polish.sh restore    # undo
#
# - Notification cards are opaque (GNOME 50 stacks a group's cards; see-through cards overlapped)
# - Banner: crimson glow from the left, 3px edge, ember app name
# - Quick settings: toggle + arrow joined into one pill, arrow half darker crimson when on
# - Calendar: small flat month arrows, styled Clear button
# - ArcMenu search box radius 25 -> 12 (same as the overview search)
# The staged theme build/polish/shell becomes the theme source (build/round2 copy is updated too,
# so 210/340 re-runs keep it). The shell reloads its theme live.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
LATEST=~/theme-backups/LATEST-SHELL-POLISH
THEME=~/.themes/Bapirlo-Kuro
SRC=$HERE/build/polish/shell/Bapirlo-Kuro
R2=$HERE/build/round2/shell/Bapirlo-Kuro/gnome-shell/gnome-shell.css
AM=org.gnome.shell.extensions.arcmenu

reload_theme() {
  local ut=org.gnome.shell.extensions.user-theme
  gsettings set $ut name ''; sleep 1; gsettings set $ut name 'Bapirlo-Kuro'
}

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-shell-polish
  mkdir -p "$BK"
  cp -a "$THEME" "$BK/theme"
  cp -a "$R2" "$BK/round2-gnome-shell.css"
  gsettings get $AM search-entry-border-radius > "$BK/arcmenu-search-radius.txt"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  cp "$SRC/gnome-shell/gnome-shell.css" "$R2"
  rm -rf "$THEME"; cp -r "$SRC" "$THEME"
  sed -i "s|@HOME@|$HOME|g" "$THEME"/gnome-shell/gnome-shell.css
  gsettings set $AM search-entry-border-radius '(true, 12)'
  reload_theme
  echo "done (live). Undo: bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  rm -rf "$THEME"; cp -a "$BK/theme" "$THEME"
  cp -a "$BK/round2-gnome-shell.css" "$R2"
  gsettings set $AM search-entry-border-radius "$(cat "$BK/arcmenu-search-radius.txt")"
  reload_theme
  echo "restored from $BK"
}

case "${1:-}" in
  "") apply ;;
  restore) restore ;;
  *) sed -n 2,4p "$0"; exit 1 ;;
esac
