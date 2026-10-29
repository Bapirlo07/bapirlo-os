#!/usr/bin/env bash
# Kuro OS — workspace shortcuts (NO sudo).
#   bash ~/bapirlo-os/90-workspaces.sh            # backup + apply
#   bash ~/bapirlo-os/90-workspaces.sh restore    # undo
#
# Workspaces stay static (CachyOS override: dynamic-workspaces=false, 4 by default).
# - Ctrl+Super+D   add a workspace       (bin/bapirlo-workspace add, max 12)
# - Ctrl+Super+F4  remove the LAST one   (its windows move to the previous one, nothing is closed)
# - Ctrl+Super+Left/Right also switch workspace (on top of GNOME's Super+PgUp/PgDn, Ctrl+Alt+arrows)
# Super+D (show desktop) is untouched.
# SUPERSEDED by 320-workspace-actions.sh (2026-10-06): dynamic workspaces + the bar's right-click
# menu; Ctrl+Super+D / Ctrl+Super+F4 now live in the Kuro Bar extension (F4 removes the CURRENT one).
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
LATEST=~/theme-backups/LATEST-WORKSPACES
BIN=~/bapirlo-os/bin/bapirlo-workspace
MK=org.gnome.settings-daemon.plugins.media-keys
KB=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
WMK=/org/gnome/desktop/wm/keybindings

custom() { # id name binding command
  local p=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KB/$1/
  gsettings set "$p" name "$2"; gsettings set "$p" binding "$3"; gsettings set "$p" command "$4"
}

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-workspaces
  mkdir -p "$BK"
  dconf dump / > "$BK/dconf-full.ini"
  dconf read $WMK/switch-to-workspace-left  > "$BK/ws-left.txt"  || true
  dconf read $WMK/switch-to-workspace-right > "$BK/ws-right.txt" || true
  gsettings get $MK custom-keybindings > "$BK/custom-keybindings.txt"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  chmod +x "$BIN"
  custom bapirlo-ws-add    "Add workspace"         "<Control><Super>d"  "$BIN add"
  custom bapirlo-ws-remove "Remove last workspace" "<Control><Super>F4" "$BIN remove"
  python3 - <<'PY'
import ast, subprocess
k = "org.gnome.settings-daemon.plugins.media-keys"
cur = subprocess.run(["gsettings", "get", k, "custom-keybindings"], capture_output=True, text=True).stdout.strip()
cur = [] if cur.startswith("@as") else ast.literal_eval(cur)
for i in ("bapirlo-ws-add", "bapirlo-ws-remove"):
    p = f"/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/{i}/"
    if p not in cur: cur.append(p)
subprocess.run(["gsettings", "set", k, "custom-keybindings", str(cur)], check=True)
PY
  gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-left \
    "['<Super>Page_Up', '<Super>KP_Prior', '<Super><Alt>Left', '<Control><Alt>Left', '<Control><Super>Left']"
  gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-right \
    "['<Super>Page_Down', '<Super>KP_Next', '<Super><Alt>Right', '<Control><Alt>Right', '<Control><Super>Right']"
  echo "workspaces: Ctrl+Super+D add · Ctrl+Super+F4 remove last · Ctrl+Super+Left/Right switch"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  for i in bapirlo-ws-add bapirlo-ws-remove; do dconf reset -f "$KB/$i/"; done
  if [ -f "$BK/custom-keybindings.txt" ]; then
    gsettings set $MK custom-keybindings "$(cat "$BK/custom-keybindings.txt")"
  else  # backup made before this script existed: only the full dump; it had no custom keybindings
    gsettings reset $MK custom-keybindings
  fi
  for d in left right; do
    v=$(cat "$BK/ws-$d.txt" 2>/dev/null || true)
    if [ -n "$v" ]; then dconf write $WMK/switch-to-workspace-$d "$v"; else dconf reset $WMK/switch-to-workspace-$d; fi
  done
  echo "restored (workspace count left as is: $(gsettings get org.gnome.desktop.wm.preferences num-workspaces))"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
