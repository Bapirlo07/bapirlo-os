#!/usr/bin/env bash
# Bapirlo OS — GSConnect (KDE Connect for GNOME), NO sudo.
#   bash ~/bapirlo-os/110-gsconnect.sh            # backup + install + enable
#   bash ~/bapirlo-os/110-gsconnect.sh restore    # disable + remove + settings back
# The firewall part is separate (needs sudo):  sudo bash ~/bapirlo-os/111-gsconnect-firewall.sh
# Pairing: KDE Connect app on the phone, same home Wi-Fi / phone hotspot (eduroam blocks device-to-device).
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
. "$(dirname "$(readlink -f "$0")")/lib/ext.sh"
EXTS=(gsconnect@andyholmes.github.io)
PATHS=(/org/gnome/shell/extensions/gsconnect/)
LATEST=~/theme-backups/LATEST-GSCONNECT

apply() {
  command -v openssl >/dev/null || { echo "openssl missing (GSConnect needs it)"; exit 1; }
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-gsconnect
  mkdir -p "$BK"
  backup_dconf "$BK" "${PATHS[@]}"
  touch "$BK/preexisting.txt"
  for u in "${EXTS[@]}"; do [ -d "$EXT_DIR/$u" ] && echo "$u" >> "$BK/preexisting.txt"; done
  [ -d ~/.config/gsconnect ] && cp -a ~/.config/gsconnect "$BK/config-gsconnect"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo "installing (GNOME $SHELL_MAJOR):"
  for u in "${EXTS[@]}"; do ext_install "$u"; done
  local G=org.gnome.Shell.Extensions.GSConnect U=gsconnect@andyholmes.github.io
  eset $U $G show-indicators false          # one entry in Quick Settings, no extra top-bar icons
  eset $U $G discoverable true
  eset $U $G keep-alive-when-locked true    # notifications/battery keep syncing while locked
  ext_enable "${EXTS[@]}"
  echo; echo "done. Log out and back in once to load it. Undo: bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  ext_unenable "${EXTS[@]}"
  for u in "${EXTS[@]}"; do grep -qx "$u" "$BK/preexisting.txt" || rm -rf "${EXT_DIR:?}/$u"; done
  restore_dconf "$BK" "${PATHS[@]}"
  rm -rf ~/.config/gsconnect
  [ -d "$BK/config-gsconnect" ] && cp -a "$BK/config-gsconnect" ~/.config/gsconnect
  echo "restored (log out/in to fully unload)"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
