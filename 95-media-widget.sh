#!/usr/bin/env bash
# Bapirlo OS — desktop media widget (GNOME Shell extension, NO sudo).
#   bash ~/bapirlo-os/95-media-widget.sh            # backup + install + enable
#   bash ~/bapirlo-os/95-media-widget.sh restore    # disable + uninstall + restore extension lists
#
# Quick off switch without uninstalling:  gnome-extensions disable bapirlo-media@bapirlo-os
# Source: ~/bapirlo-os/media-widget/bapirlo-media@bapirlo-os (re-run this script after editing it).
# Wayland loads newly installed extensions only at login → log out and back in once.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
UUID=bapirlo-media@bapirlo-os
SRC=~/bapirlo-os/media-widget/$UUID
DST=~/.local/share/gnome-shell/extensions/$UUID
LATEST=~/theme-backups/LATEST-MEDIA-WIDGET

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-media-widget
  mkdir -p "$BK"
  gsettings get org.gnome.shell enabled-extensions  > "$BK/enabled-extensions.txt"
  gsettings get org.gnome.shell disabled-extensions > "$BK/disabled-extensions.txt"
  [ -e "$DST" ] && cp -a "$DST" "$BK/previous-install"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  rm -rf "$DST"; mkdir -p "$(dirname "$DST")"
  cp -a "$SRC" "$DST"
  python3 - "$UUID" <<'PY'
import ast, subprocess, sys
uuid = sys.argv[1]
def get(k):
    v = subprocess.run(["gsettings", "get", "org.gnome.shell", k], capture_output=True, text=True).stdout.strip()
    return [] if v.startswith("@as") else ast.literal_eval(v)
en, dis = get("enabled-extensions"), get("disabled-extensions")
if uuid not in en: en.append(uuid)
dis = [d for d in dis if d != uuid]
subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(en)], check=True)
subprocess.run(["gsettings", "set", "org.gnome.shell", "disabled-extensions", str(dis)], check=True)
PY
  # already known to this session (re-install) → reload it now; otherwise it starts at next login
  if gnome-extensions info "$UUID" >/dev/null 2>&1; then
    gnome-extensions disable "$UUID" 2>/dev/null || true
    gnome-extensions enable "$UUID" 2>/dev/null || true
  fi
  echo "installed $DST"
  echo "log out and back in once to load it (Wayland). Off switch: gnome-extensions disable $UUID"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  gnome-extensions disable "$UUID" 2>/dev/null || true
  gsettings set org.gnome.shell enabled-extensions  "$(cat "$BK/enabled-extensions.txt")"
  gsettings set org.gnome.shell disabled-extensions "$(cat "$BK/disabled-extensions.txt")"
  rm -rf "$DST"
  [ -d "$BK/previous-install" ] && cp -a "$BK/previous-install" "$DST"
  rm -rf ~/.cache/bapirlo-media-widget ~/.local/state/bapirlo-media
  echo "restored (widget removed; takes full effect at next login if it was loaded)"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
