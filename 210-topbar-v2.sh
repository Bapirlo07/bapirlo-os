#!/usr/bin/env bash
# Kuro OS round 2 — bigger top bar (NO sudo). The layout you approved in build/round2/topbar-preview.png.
#   bash ~/bapirlo-os/210-topbar-v2.sh            # backup + theme + bapirlo-bar + Vitals trim + battery %
#   bash ~/bapirlo-os/210-topbar-v2.sh restore    # previous theme, bapirlo-bar off/removed, settings back
# Bar 44px (was 38) · 12pt text · 22px icons · 13pt bold clock. Left: logo · workspace dots | quick launch
# | power chip. Right: mini player · REPLAY sticker · Vitals (CPU %, temp) · clipboard · system.
# Theme changes show immediately; the new extension loads after logout/login (Wayland).
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
. "$HERE/lib/ext.sh"
UUID=bapirlo-bar@bapirlo-os
THEME=~/.themes/Bapirlo-Kuro
PATHS=(/org/gnome/shell/extensions/vitals/)
KEYS=("org.gnome.desktop.interface show-battery-percentage")
LATEST=~/theme-backups/LATEST-TOPBAR-V2

reload_theme() {   # make user-theme re-read the CSS without a logout
  gsettings set org.gnome.shell.extensions.user-theme name 'Default'; sleep 0.5
  gsettings set org.gnome.shell.extensions.user-theme name 'Bapirlo-Kuro'
}

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-topbar-v2
  mkdir -p "$BK"
  cp -a "$THEME" "$BK/Bapirlo-Kuro"
  backup_dconf "$BK" "${PATHS[@]}"
  backup_keys "$BK" "${KEYS[@]}"
  [ -d "$EXT_DIR/$UUID" ] && cp -a "$EXT_DIR/$UUID" "$BK/ext-before"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  rm -rf "$THEME"; cp -r "$HERE/build/round2/shell/Bapirlo-Kuro" "$THEME"
  sed -i "s|@HOME@|$HOME|g" "$THEME"/gnome-shell/gnome-shell.css
  rm -rf "${EXT_DIR:?}/$UUID"; cp -rL "$HERE/bar/$UUID" "$EXT_DIR/$UUID"   # -L: mpris/art are shared with the media card

  local V=org.gnome.shell.extensions.vitals U=Vitals@CoreCoding.com
  eset $U $V hot-sensors "['_processor_usage_', '_temperature_processor_0_']"   # RAM/net made the bar overflow
  eset $U $V fixed-widths false
  gsettings set org.gnome.desktop.interface show-battery-percentage true

  ext_enable "$UUID"
  reload_theme
  echo; echo "done. Theme is live now; log out/in once to load the new bar pieces. Undo: bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  ext_unenable "$UUID"
  rm -rf "${EXT_DIR:?}/$UUID"
  [ -d "$BK/ext-before" ] && cp -a "$BK/ext-before" "$EXT_DIR/$UUID"
  rm -rf "$THEME"; cp -a "$BK/Bapirlo-Kuro" "$THEME"
  restore_dconf "$BK" "${PATHS[@]}"
  restore_keys "$BK"
  reload_theme
  echo "restored (log out/in to fully unload the extension)"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
