#!/usr/bin/env bash
# Bapirlo OS — top bar v3 (NO sudo). Mac-style layout in capsules, neutral hover, red only for states.
#   bash ~/bapirlo-os/360-topbar-v3.sh                 # all steps below, in order
#   bash ~/bapirlo-os/360-topbar-v3.sh theme|bar|settings|tray   # one step
#   bash ~/bapirlo-os/360-topbar-v3.sh restore         # undo everything (back to the pre-v3 backup)
#
#   theme     shell theme: 6px floating gap, bar 74% ink, neutral hover/press tints   (live)
#   bar       bapirlo-bar v3 (capsule layout, app name, tooltips, red states, fullscreen reveal)
#             installed + re-enabled (it was in disabled-extensions)
#   settings  Vitals every 3 s with fixed widths
#   tray      CachyOS "arch-update --tray" no longer autostarts (the Arch Update extension stays)
# Backup: ~/theme-backups/LATEST-TOPBAR-V3 (taken before the first step, never overwritten)
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
LATEST=~/theme-backups/LATEST-TOPBAR-V3
THEME=~/.themes/Bapirlo-Kuro
SRC=$HERE/build/polish/shell/Bapirlo-Kuro
R2=$HERE/build/round2/shell/Bapirlo-Kuro/gnome-shell/gnome-shell.css
UUID=bapirlo-bar@bapirlo-os
EXT_DIR=~/.local/share/gnome-shell/extensions
VITALS=/org/gnome/shell/extensions/vitals/
TRAY=~/.config/autostart/arch-update-tray.desktop
. "$HERE/lib/ext.sh"

reload_theme() {
  local ut=org.gnome.shell.extensions.user-theme
  gsettings set $ut name ''; sleep 1; gsettings set $ut name 'Bapirlo-Kuro'
}

backup() {
  if [ -e "$LATEST" ]; then echo "backup kept: $(readlink -f "$LATEST")"; return; fi
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-topbar-v3-pre
  mkdir -p "$BK/dconf" "$BK/extensions"
  cp -a "$THEME" "$BK/theme-Bapirlo-Kuro"
  cp -a "$R2" "$BK/round2-src-gnome-shell.css"
  cp -a "$EXT_DIR/$UUID" "$BK/extensions/"
  dconf dump $VITALS > "$BK/dconf/vitals.dconf"
  gsettings get org.gnome.shell enabled-extensions > "$BK/enabled-extensions.txt"
  gsettings get org.gnome.shell disabled-extensions > "$BK/disabled-extensions.txt"
  ln -sfn "$BK" "$LATEST"; echo "backup -> $BK"
}

step_theme() {
  # the pre-v3 theme source is in the backup; build/polish is the source of truth (see 420)
  cp "$SRC/gnome-shell/gnome-shell.css" "$R2"
  rm -rf "$THEME"; cp -r "$SRC" "$THEME"
  sed -i "s|@HOME@|$HOME|g" "$THEME"/gnome-shell/gnome-shell.css
  reload_theme
  echo "theme: applied (live)"
}

step_bar() {
  rm -rf "${EXT_DIR:?}/$UUID"
  cp -rL "$HERE/bar/$UUID" "$EXT_DIR/"
  glib-compile-schemas "$EXT_DIR/$UUID/schemas"
  ext_enable "$UUID"
  echo "bar: installed + enabled (if the shell had already loaded the old code this session, log out/in)"
}

step_settings() {
  dconf write ${VITALS}update-time 3
  dconf write ${VITALS}fixed-widths true
  echo "settings: Vitals every 3 s, fixed widths"
}

step_tray() {
  mkdir -p "$(dirname "$TRAY")"
  printf '[Desktop Entry]\nType=Application\nName=Cachy-Update Systray Applet\nExec=/bin/true\nHidden=true\nX-Bapirlo=topbar-v3\n' > "$TRAY"
  # stop the running one (match the exact process name, never this script's own command line)
  for p in $(pgrep -x arch-update-tra 2>/dev/null) $(pgrep -x arch-update-tray 2>/dev/null); do kill "$p" 2>/dev/null || true; done
  echo "tray: CachyOS update tray stopped + no autostart (Arch Update extension still shows updates)"
}

restore() {
  local BK; BK=$(readlink -f "$LATEST")
  [ -d "$BK" ] || { echo "no backup at $LATEST"; exit 1; }
  rm -rf "$THEME"; cp -a "$BK/theme-Bapirlo-Kuro" "$THEME"
  cp -a "$BK/round2-src-gnome-shell.css" "$R2"
  cp -a "$BK/round2-src-gnome-shell.css" "$SRC/gnome-shell/gnome-shell.css"   # both keep @HOME@
  rm -rf "${EXT_DIR:?}/$UUID"; cp -a "$BK/extensions/$UUID" "$EXT_DIR/"
  dconf reset -f $VITALS; dconf load $VITALS < "$BK/dconf/vitals.dconf"
  gsettings set org.gnome.shell enabled-extensions "$(cat "$BK/enabled-extensions.txt")"
  gsettings set org.gnome.shell disabled-extensions "$(cat "$BK/disabled-extensions.txt")"
  if grep -q 'X-Bapirlo=topbar-v3' "$TRAY" 2>/dev/null; then rm -f "$TRAY"; (setsid -f sh -c 'arch-update --tray' >/dev/null 2>&1 || true); fi
  reload_theme
  echo "restored from $BK (log out/in to unload the v3 bar code)"
}

case "${1:-}" in
  "") backup; step_theme; step_bar; step_settings; step_tray ;;
  theme|bar|settings|tray) backup; "step_$1" ;;
  restore) restore ;;
  *) sed -n 2,5p "$0"; exit 1 ;;
esac
