#!/usr/bin/env bash
# Bapirlo OS — top-right power fix (NO sudo).
#   bash ~/bapirlo-os/370-power-fix.sh            # apply
#   bash ~/bapirlo-os/370-power-fix.sh restore    # undo
#
#   icons  battery-level-N-plugged-in icons in the Bapirlo theme: a plug, not WhiteSur's charging
#          bolt — with the 80 % charge limit the battery sits "plugged in, not charging"   (live)
#   bar    bapirlo-bar: GNOME's power-mode gauge leaves the system icons (the power chip on the
#          left already shows Eco / Balanced / Turbo)                                      (logout)
# Backup: ~/theme-backups/LATEST-POWER-FIX
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
LATEST=~/theme-backups/LATEST-POWER-FIX
ICONS=~/.local/share/icons/Bapirlo
UUID=bapirlo-bar@bapirlo-os
EXT=~/.local/share/gnome-shell/extensions/$UUID

refresh_icons() {
  gtk-update-icon-cache -q -f "$ICONS" || true
  # St caches icons per theme name — bounce the theme so the shell reloads them
  local cur; cur=$(gsettings get org.gnome.desktop.interface icon-theme)
  gsettings set org.gnome.desktop.interface icon-theme 'WhiteSur-red-dark'; sleep 1
  gsettings set org.gnome.desktop.interface icon-theme "$cur"
}

case "${1:-apply}" in
apply)
  if [ ! -e "$LATEST" ]; then
    BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-power-fix
    mkdir -p "$BK"
    cp -a "$ICONS/index.theme" "$BK/index.theme"
    cp -a "$EXT" "$BK/$UUID"
    ln -sfn "$BK" "$LATEST"
    echo "backup: $BK"
  fi
  python3 -I "$HERE/power/make-plugged-icons.py" "$ICONS/symbolic/status"
  if ! grep -q 'symbolic/status' "$ICONS/index.theme"; then
    sed -i 's|^Directories=.*|&,symbolic/status|' "$ICONS/index.theme"
    printf '\n[symbolic/status]\nSize=16\nMinSize=8\nMaxSize=512\nType=Scalable\nContext=Status\n' >> "$ICONS/index.theme"
  fi
  refresh_icons
  cp -a "$HERE/bar/$UUID/states.js" "$EXT/states.js"
  echo "done — battery icon is live; log out and back in for the gauge change."
  ;;
restore)
  [ -e "$LATEST" ] || { echo "no backup at $LATEST"; exit 1; }
  BK=$(readlink -f "$LATEST")
  rm -f "$ICONS"/symbolic/status/battery-level-*-plugged-in-symbolic.svg
  rmdir "$ICONS/symbolic/status" 2>/dev/null || true
  cp -a "$BK/index.theme" "$ICONS/index.theme"
  rm -rf "$EXT" && cp -a "$BK/$UUID" "$EXT"
  refresh_icons
  echo "restored from $BK — log out and back in for the bar."
  ;;
*) echo "usage: $0 [apply|restore]"; exit 1 ;;
esac
