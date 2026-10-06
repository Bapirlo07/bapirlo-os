#!/usr/bin/env bash
# Bapirlo OS — keep apps open across log out / restart (NO sudo).
#   bash ~/bapirlo-os/125-session.sh            # backup + install + enable
#   bash ~/bapirlo-os/125-session.sh restore    # everything back as it was
#
# - bapirlo-session extension: saves open apps / terminal folders / Files folders, reopens them at login
#   (Another Window Session Manager was skipped: no GNOME 50 release + a multi-monitor crash-loop bug).
# - Smart Auto Move NG: puts each window back on its workspace / monitor / position / size.
# - fish hook: terminals reopen in their last folder.
# - Files (Nautilus): its folders are saved by the extension (Nautilus has no restore of its own).
# Chrome "Continue where you left off" is set by the sudo step (policy), VS Code is not installed.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
. "$HERE/lib/ext.sh"
SESSION_EXT=bapirlo-session@bapirlo-os
SAM=SmartAutoMoveNG@lauinger-clan.de
FISH_HOOK=~/.config/fish/conf.d/bapirlo-session.fish
CONF=~/.config/bapirlo/session.json
LATEST=~/theme-backups/LATEST-SESSION

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-session
  mkdir -p "$BK"
  backup_dconf "$BK" /org/gnome/shell/extensions/SmartAutoMoveNG/
  touch "$BK/preexisting.txt"
  for u in $SESSION_EXT $SAM; do [ -d "$EXT_DIR/$u" ] && { echo "$u" >> "$BK/preexisting.txt"; cp -a "$EXT_DIR/$u" "$BK/ext-$u"; }; done
  [ -f "$FISH_HOOK" ] && cp -a "$FISH_HOOK" "$BK/"
  [ -f "$CONF" ] && cp -a "$CONF" "$BK/"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo "installing (GNOME $SHELL_MAJOR):"
  ext_install $SAM
  local S=org.gnome.shell.extensions.SmartAutoMoveNG
  eset $SAM $S sync-mode RESTORE
  eset $SAM $S activate-workspace false     # don't fling you between workspaces while restoring
  eset $SAM $S notifications false
  eset $SAM $S quicksettings true           # Quick Settings toggle = "Freeze Saves"
  eset $SAM $S edit-saved-windows-position-x-max 4480
  eset $SAM $S edit-saved-windows-position-y-max 1600
  eset $SAM $S edit-saved-windows-width-max 2560
  eset $SAM $S edit-saved-windows-height-max 1600

  rm -rf "${EXT_DIR:?}/$SESSION_EXT"; cp -a "$HERE/session/$SESSION_EXT" "$EXT_DIR/"
  mkdir -p "$(dirname "$CONF")"
  [ -f "$CONF" ] || printf '{\n "restore": true,\n "exclude": []\n}\n' > "$CONF"
  mkdir -p "$(dirname "$FISH_HOOK")"; cp "$HERE/session/fish/bapirlo-session.fish" "$FISH_HOOK"

  ext_enable $SAM $SESSION_EXT
  echo; echo "done. Log out and back in once to load the extensions; from then on your apps come back."
  echo "Settings: $CONF   (\"restore\": false = don't reopen; \"exclude\": [\"app.desktop\"])"
  echo "Undo: bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  ext_unenable $SESSION_EXT $SAM
  for u in $SESSION_EXT $SAM; do
    rm -rf "${EXT_DIR:?}/$u"
    [ -d "$BK/ext-$u" ] && cp -a "$BK/ext-$u" "$EXT_DIR/$u"
  done
  rm -f "$FISH_HOOK"; [ -f "$BK/$(basename "$FISH_HOOK")" ] && cp -a "$BK/$(basename "$FISH_HOOK")" "$FISH_HOOK"
  rm -f "$CONF"; [ -f "$BK/$(basename "$CONF")" ] && cp -a "$BK/$(basename "$CONF")" "$CONF"
  restore_dconf "$BK" /org/gnome/shell/extensions/SmartAutoMoveNG/
  echo "restored (saved session data stays in ~/.local/state/bapirlo-session)"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
