#!/usr/bin/env bash
# Bapirlo OS — top bar layout + menu contrast fix (NO sudo).
#   bash ~/bapirlo-os/340-topbar-layout.sh            # backup + apply
#   bash ~/bapirlo-os/340-topbar-layout.sh restore    # put everything back from the backup
#   bash ~/bapirlo-os/340-topbar-layout.sh settings   # only the dconf part (used by the test shell)
# What it does:
#   bar   numbered workspaces (1, 2, 3 …), clock + date centred with weather beside it, right side
#         ordered Vitals · media · clipboard · tray · system, fixed-width media title with a fade,
#         one UI font (Inter) everywhere except the logo — all in bapirlo-bar + the theme CSS
#   vitals  CPU % and temperature as one compact item (one CPU glyph, both values)
#   tray  AppIndicator icons desaturated and lifted so they match the symbolic icons
#   menus every menu/popup: paper-white text at all times (WCAG AA), subtle hover, 97 % opaque
#         surfaces; Blur my Shell popup blur OFF (it drew a square box behind the rounded menus)
# Theme CSS is live immediately; the bapirlo-bar code loads after logout/login (Wayland).
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
. "$HERE/lib/ext.sh"
UUID=bapirlo-bar@bapirlo-os
THEME=~/.themes/Bapirlo-Kuro
LATEST=~/theme-backups/LATEST-TOPBAR-LAYOUT
PATHS=(/org/gnome/shell/extensions/appindicator/ /org/gnome/shell/extensions/vitals/
       /org/gnome/shell/extensions/blur-my-shell/popup/)
KEYS=("org.gnome.shell.extensions.arcmenu menu-background-color")

reload_theme() {
  gsettings set org.gnome.shell.extensions.user-theme name 'Default'; sleep 0.5
  gsettings set org.gnome.shell.extensions.user-theme name 'Bapirlo-Kuro'
}

settings() {
  local AI=org.gnome.shell.extensions.appindicator
  # monochrome tray: full desaturation, a little brighter so grey glyphs read like the paper icons
  gsettings set $AI icon-saturation 1.0
  gsettings set $AI icon-brightness 0.25
  gsettings set $AI icon-contrast 0.15
  gsettings set $AI icon-opacity 255
  eset Vitals@CoreCoding.com org.gnome.shell.extensions.vitals hide-icons false
  local B=org.gnome.shell.extensions.blur-my-shell.popup
  eset blur-my-shell@aunetx $B blur false
  gsettings set org.gnome.shell.extensions.arcmenu menu-background-color 'rgba(22,16,21,0.97)'
}

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-topbar-layout
  mkdir -p "$BK"
  cp -a "$THEME" "$BK/Bapirlo-Kuro"
  [ -d "$EXT_DIR/$UUID" ] && cp -a "$EXT_DIR/$UUID" "$BK/ext-before"
  backup_dconf "$BK" "${PATHS[@]}"
  backup_keys "$BK" "${KEYS[@]}"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  rm -rf "$THEME"; cp -r "$HERE/build/round2/shell/Bapirlo-Kuro" "$THEME"
  sed -i "s|@HOME@|$HOME|g" "$THEME"/gnome-shell/gnome-shell.css
  rm -rf "${EXT_DIR:?}/$UUID"; cp -rL "$HERE/bar/$UUID" "$EXT_DIR/$UUID"
  glib-compile-schemas "$EXT_DIR/$UUID/schemas"
  settings
  reload_theme
  echo; echo "done. Menus/colours are live now; log out/in once for the new bar layout. Undo: bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  rm -rf "${EXT_DIR:?}/$UUID"
  [ -d "$BK/ext-before" ] && cp -a "$BK/ext-before" "$EXT_DIR/$UUID"
  rm -rf "$THEME"; cp -a "$BK/Bapirlo-Kuro" "$THEME"
  restore_dconf "$BK" "${PATHS[@]}"
  restore_keys "$BK"
  reload_theme
  echo "restored (log out/in to reload the old bar code)"
}

case "${1:-}" in "") apply ;; restore) restore ;; settings) settings ;; *) sed -n 2,5p "$0"; exit 1 ;; esac
