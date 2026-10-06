#!/usr/bin/env bash
# Bapirlo OS — "click a running app = focus it" everywhere (NO sudo). Complements 80-dock-behaviour.sh.
#   bash ~/bapirlo-os/85-app-focus.sh            # backup + apply
#   bash ~/bapirlo-os/85-app-focus.sh restore    # undo
#
# - ArcMenu (menu + its search, which is what the Super key opens): activate-on-launch was OFF, which makes every
#   click on a running app open a NEW window. On → focus/raise; middle-click / Ctrl+click still open a new window.
# - GNOME overview grid + search: use GNOME's AppIcon, already focus-or-new-window-on-middle/Ctrl once
#   launch-new-instance is disabled (done by 80-dock-behaviour.sh).
# - App fixes (window → .desktop matching; when GNOME can't match, it thinks the app isn't running and launches it):
#   Google Chrome: windows always resolve to the HIDDEN com.google.Chrome.desktop (StartupWMClass=google-chrome),
#   while menus show google-chrome.desktop → every launch = new Chrome window. User-level overrides swap which one
#   is visible. Package files in /usr/share are untouched; default-browser (already com.google.Chrome) unchanged.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
APPS=~/.local/share/applications
LATEST=~/theme-backups/LATEST-APP-FOCUS
OVR="com.google.Chrome.desktop google-chrome.desktop"

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-app-focus
  mkdir -p "$BK"
  dconf dump /org/gnome/shell/extensions/arcmenu/ > "$BK/arcmenu.ini"
  for f in $OVR; do [ -e "$APPS/$f" ] && cp -a "$APPS/$f" "$BK/$f" || echo "$f" >> "$BK/absent.txt"; done
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  gsettings set org.gnome.shell.extensions.arcmenu activate-on-launch true
  echo "arcmenu: activate-on-launch true (menu + search focus running apps)"

  mkdir -p "$APPS"
  # visible entry = the one Chrome's windows actually match
  grep -v '^NoDisplay=true' /usr/share/applications/com.google.Chrome.desktop \
    | grep -v '^# This is the same as google-chrome.desktop\|^# duplicate menu entries\|^# used by XDG desktop portal\|^# The old desktop file is kept' \
    > "$APPS/com.google.Chrome.desktop"
  # legacy entry hidden from menus/search (still valid for links/mime)
  { cat /usr/share/applications/google-chrome.desktop; } | awk '
    /^\[Desktop Entry\]/ {print; print "NoDisplay=true"; next} /^NoDisplay=/ {next} {print}' \
    > "$APPS/google-chrome.desktop"
  update-desktop-database "$APPS" 2>/dev/null || true
  desktop-file-validate "$APPS/com.google.Chrome.desktop" "$APPS/google-chrome.desktop" 2>&1 | grep -iv 'hint\|deprecated' || true
  echo "chrome: menus/dock now use com.google.Chrome.desktop = the ID Chrome's windows report"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  dconf load /org/gnome/shell/extensions/arcmenu/ < "$BK/arcmenu.ini"
  gsettings reset org.gnome.shell.extensions.arcmenu activate-on-launch
  grep -q activate-on-launch "$BK/arcmenu.ini" && dconf load /org/gnome/shell/extensions/arcmenu/ < "$BK/arcmenu.ini"
  for f in $OVR; do
    rm -f "$APPS/$f"; [ -e "$BK/$f" ] && cp -a "$BK/$f" "$APPS/$f"
  done
  update-desktop-database "$APPS" 2>/dev/null || true
  echo "restored"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
