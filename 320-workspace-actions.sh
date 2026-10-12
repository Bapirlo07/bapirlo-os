#!/usr/bin/env bash
# Bapirlo OS — add / remove workspaces on demand (NO sudo).
#   bash ~/bapirlo-os/320-workspace-actions.sh            # backup + apply
#   bash ~/bapirlo-os/320-workspace-actions.sh restore    # undo
#
# Lives in the Bapirlo Bar extension (bar/bapirlo-bar@bapirlo-os/workspaces.js):
# - right-click a workspace dot → "Remove workspace" / "Add workspace"
# - Super+Shift+W (or Ctrl+Super+F4)  remove the CURRENT workspace
# - Super+Shift+N (or Ctrl+Super+D)   add a workspace right after the current one and go there
# - windows on a removed workspace move to the previous one (the next one if it was the first)
# - the dot flashes ember and shrinks away; a new dot grows in; an on-screen note confirms it
# Turns GNOME's dynamic workspaces ON (empty workspaces close by themselves, one spare stays at
# the end). Replaces the old Ctrl+Super+D / Ctrl+Super+F4 custom keys from 90-workspaces.sh,
# which only changed the workspace count and do nothing with dynamic workspaces.
# Space Bar (space-bar@luchrioh) supports GNOME 50 too, but would replace the themed dots.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
. "$HERE/lib/ext.sh"
LATEST=~/theme-backups/LATEST-WS-ACTIONS
UUID=bapirlo-bar@bapirlo-os
MK=org.gnome.settings-daemon.plugins.media-keys
KB=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
OLD_KEYS=(bapirlo-ws-add bapirlo-ws-remove)
KEYS=("org.gnome.mutter dynamic-workspaces"
      "org.gnome.desktop.wm.preferences num-workspaces"
      "$MK custom-keybindings")

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-ws-actions
  mkdir -p "$BK"
  dconf dump / > "$BK/dconf-full.ini"
  backup_keys "$BK" "${KEYS[@]}"
  backup_dconf "$BK" /org/gnome/shell/extensions/bapirlo-bar/
  for k in "${OLD_KEYS[@]}"; do dconf dump "$KB/$k/" > "$BK/key-$k.ini"; done
  [ -d "$EXT_DIR/$UUID" ] && cp -a "$EXT_DIR/$UUID" "$BK/ext-before"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo "== Bapirlo Bar with workspace menu + shortcuts"
  glib-compile-schemas --strict "$HERE/bar/$UUID/schemas"
  rm -rf "${EXT_DIR:?}/$UUID"; cp -rL "$HERE/bar/$UUID" "$EXT_DIR/$UUID"   # -L: mpris/art are shared with the media card

  echo "== old Ctrl+Super+D / Ctrl+Super+F4 custom keys → now handled by the bar (no double action)"
  python3 - "${OLD_KEYS[@]}" <<'PY'
import ast, subprocess, sys
k = "org.gnome.settings-daemon.plugins.media-keys"
cur = subprocess.run(["gsettings", "get", k, "custom-keybindings"], capture_output=True, text=True).stdout.strip()
cur = [] if cur.startswith("@as") else ast.literal_eval(cur)
drop = {f"/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/{i}/" for i in sys.argv[1:]}
subprocess.run(["gsettings", "set", k, "custom-keybindings", str([p for p in cur if p not in drop])], check=True)
PY
  for k in "${OLD_KEYS[@]}"; do dconf reset -f "$KB/$k/"; done

  echo "== dynamic workspaces on"
  gsettings set org.gnome.mutter dynamic-workspaces true

  echo
  echo "done. Dynamic workspaces are live now; log out and back in once to load the new menu + keys."
  echo "  right-click a workspace dot  → Remove workspace / Add workspace"
  echo "  Super+Shift+W  (Ctrl+Super+F4)  remove current workspace (windows → previous one)"
  echo "  Super+Shift+N  (Ctrl+Super+D)   add a workspace after the current one"
  echo "Undo: bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  rm -rf "${EXT_DIR:?}/$UUID"
  [ -d "$BK/ext-before" ] && cp -a "$BK/ext-before" "$EXT_DIR/$UUID"
  restore_dconf "$BK" /org/gnome/shell/extensions/bapirlo-bar/
  for k in "${OLD_KEYS[@]}"; do
    dconf reset -f "$KB/$k/"
    [ -s "$BK/key-$k.ini" ] && dconf load "$KB/$k/" < "$BK/key-$k.ini"
  done
  restore_keys "$BK"
  echo "restored (log out/in to load the previous bar code)"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
