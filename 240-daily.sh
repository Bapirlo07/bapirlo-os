#!/usr/bin/env bash
# Kuro OS round 2 — daily use (NO sudo; Drive/calendar need packages from 200-round2-install.sh).
#   bash ~/bapirlo-os/240-daily.sh            # backup + install + configure + enable
#   bash ~/bapirlo-os/240-daily.sh restore    # everything back (Tiling Assistant reinstalled)
#   1. Emoji picker on Super+. (Emoji Copy): opens at the mouse, picking an emoji pastes it.
#   2. Tiling Shell (Windows 11 snap layouts: drag a window to the top edge, Super+arrows)
#      replaces Tiling Assistant (disabled + removed; a copy stays in the backup).
#   3. Google Drive: unit for rclone; you finish with  ~/bapirlo-os/bin/bapirlo-gdrive setup
#   Google Calendar in the clock: Settings → Online Accounts → Google (needs evolution-data-server).
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
. "$HERE/lib/ext.sh"
EXTS=(emoji-copy@felipeftn tilingshell@ferrarodomenico.com)
OLD=tiling-assistant@leleat-on-github
PATHS=(/org/gnome/shell/extensions/emoji-copy/ /org/gnome/shell/extensions/tilingshell/
       /org/gnome/shell/extensions/tiling-assistant/)
# only the keys the two tiling extensions take over (not the whole mutter tree)
KEYS=("org.freedesktop.ibus.panel.emoji hotkey"
      "org.gnome.mutter edge-tiling"
      "org.gnome.desktop.wm.keybindings maximize" "org.gnome.desktop.wm.keybindings unmaximize"
      "org.gnome.mutter.keybindings toggle-tiled-left" "org.gnome.mutter.keybindings toggle-tiled-right")
UNITS=~/.config/systemd/user
LATEST=~/theme-backups/LATEST-DAILY

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-daily
  mkdir -p "$BK"
  backup_dconf "$BK" "${PATHS[@]}"
  backup_keys "$BK" "${KEYS[@]}"
  for u in "${EXTS[@]}"; do [ -d "$EXT_DIR/$u" ] && echo "$u" >> "$BK/preexisting.txt"; done; touch "$BK/preexisting.txt"
  [ -d "$EXT_DIR/$OLD" ] && cp -a "$EXT_DIR/$OLD" "$BK/$OLD"
  gsettings get org.gnome.shell enabled-extensions | grep -q "'$OLD'" && touch "$BK/old-was-enabled"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  # Tiling Assistant out first — disabling it while the shell runs lets it hand back the
  # edge-tiling / maximize keys it took over
  if [ -d "$EXT_DIR/$OLD" ]; then
    gnome-extensions disable "$OLD" 2>/dev/null || true
    sleep 1
    ext_unenable "$OLD"
    rm -rf "${EXT_DIR:?}/$OLD"
    echo "Tiling Assistant disabled + removed (copy in $BK)"
  fi

  echo "installing (GNOME $SHELL_MAJOR):"
  for u in "${EXTS[@]}"; do ext_install "$u"; done

  # ---- Emoji Copy: Super+. like Windows; IBus' own Super+. emoji hotkey cleared so they never fight
  local E=org.gnome.shell.extensions.emoji-copy U=emoji-copy@felipeftn
  eset $U $E emoji-keybind "['<Super>period']"
  eset $U $E active-keybind true
  eset $U $E window-location "'cursor'"
  eset $U $E paste-on-select true
  eset $U $E keep-open false
  eset $U $E always-show false            # no permanent bar icon (keeps the bar's spacing)
  eset $U $E nbcols 9
  eset $U $E emojisize 28
  gsettings set org.freedesktop.ibus.panel.emoji hotkey "@as []" 2>/dev/null || true

  # ---- Tiling Shell
  local T=org.gnome.shell.extensions.tilingshell U=tilingshell@ferrarodomenico.com
  eset $U $T enable-snap-assist true      # drag to the top edge → layout picker (Windows 11 style)
  eset $U $T show-indicator false         # no bar icon; layouts are in the snap assistant + window menu
  eset $U $T override-alt-tab false       # Alt+Tab belongs to Coverflow
  eset $U $T inner-gaps 10
  eset $U $T outer-gaps 10                # = the bar's 10px inset
  eset $U $T enable-blur-snap-assistant false        # blur costs GPU every frame it shows
  eset $U $T enable-blur-selected-tilepreview false
  eset $U $T enable-window-border false
  eset $U $T snap-assistant-animation-time 180
  eset $U $T tile-preview-animation-time 120
  eset $U $T enable-move-keybindings true # Super+arrows move between tiles

  # ---- Google Drive (rclone) — unit only; sign-in is interactive
  mkdir -p "$UNITS"; install -m644 "$HERE/round2/systemd/bapirlo-gdrive.service" "$UNITS/"
  systemctl --user daemon-reload

  ext_enable "${EXTS[@]}"
  echo
  echo "done. Log out/in once to load them. Undo: bash $0 restore"
  echo "Next (yours): Settings → Online Accounts → Google (calendar), then: ~/bapirlo-os/bin/bapirlo-gdrive setup"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  ext_unenable "${EXTS[@]}"
  for u in "${EXTS[@]}"; do grep -qx "$u" "$BK/preexisting.txt" || rm -rf "${EXT_DIR:?}/$u"; done
  systemctl --user disable --now bapirlo-gdrive.service 2>/dev/null || true
  rm -f "$UNITS/bapirlo-gdrive.service"; systemctl --user daemon-reload
  restore_dconf "$BK" "${PATHS[@]}"
  restore_keys "$BK"
  if [ -d "$BK/$OLD" ]; then
    rm -rf "${EXT_DIR:?}/$OLD"; cp -a "$BK/$OLD" "$EXT_DIR/$OLD"
    [ -f "$BK/old-was-enabled" ] && ext_enable "$OLD"
  fi
  echo "restored (log out/in to fully reload)"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
