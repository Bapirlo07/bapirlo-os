#!/usr/bin/env bash
# Bapirlo OS — Mac-style features (NO sudo).
#   bash ~/bapirlo-os/105-mac-features.sh            # backup + install + configure + enable
#   bash ~/bapirlo-os/105-mac-features.sh restore    # everything back as it was
#
# - Spotlight-style search: ArcMenu's standalone runner, centred, on Super+Space
#   (Search Light was skipped: its GNOME 50 build crashes the shell on outside click, fix #170 unmerged).
#   Super+Space was "switch keyboard layout"; you only have the GB layout, so that binding is dropped.
# - Rounded Window Corners Reborn: 16px = the Bapirlo surface radius. Maximised / fullscreen windows
#   (games!) are left square and unshadowed, so nothing extra is drawn over them.
# - Desktop Cube: 3D cube when switching workspaces (also follows 3-finger swipes).
# - Touchpad gestures need nothing: GNOME 50 has 3-finger left/right = workspaces, 3-finger up = overview.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
. "$(dirname "$(readlink -f "$0")")/lib/ext.sh"
EXTS=(rounded-window-corners@fxgn desktop-cube@schneegans.github.com)
PATHS=(/org/gnome/shell/extensions/rounded-window-corners-reborn/ /org/gnome/shell/extensions/desktop-cube/)
KEYS=("org.gnome.desktop.wm.keybindings switch-input-source" "org.gnome.desktop.wm.keybindings switch-input-source-backward"
      "org.gnome.shell.extensions.arcmenu runner-hotkey" "org.gnome.shell.extensions.arcmenu runner-position" "org.gnome.shell.extensions.arcmenu runner-searchbar-location" "org.gnome.shell.extensions.arcmenu runner-search-display-style" "org.gnome.shell.extensions.arcmenu runner-menu-width" "org.gnome.shell.extensions.arcmenu runner-menu-height" "org.gnome.shell.extensions.arcmenu runner-menu-height-static" "org.gnome.shell.extensions.arcmenu runner-font-size" "org.gnome.shell.extensions.arcmenu runner-show-settings-button" "org.gnome.shell.extensions.arcmenu runner-hotkey-open-primary-monitor")
LATEST=~/theme-backups/LATEST-MAC-FEATURES

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-mac-features
  mkdir -p "$BK"
  backup_dconf "$BK" "${PATHS[@]}"
  backup_keys "$BK" "${KEYS[@]}"
  touch "$BK/preexisting.txt"
  for u in "${EXTS[@]}"; do [ -d "$EXT_DIR/$u" ] && echo "$u" >> "$BK/preexisting.txt"; done
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo "installing (GNOME $SHELL_MAJOR):"
  for u in "${EXTS[@]}"; do ext_install "$u"; done

  # ---- Spotlight: ArcMenu runner (already installed + themed), Super+Space, centred
  local A=org.gnome.shell.extensions.arcmenu
  gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['XF86Keyboard']"
  gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward "['<Shift>XF86Keyboard']"
  gsettings set $A runner-hotkey "['<Super>space']"
  gsettings set $A runner-position Centered
  gsettings set $A runner-searchbar-location Top
  gsettings set $A runner-search-display-style List
  gsettings set $A runner-menu-width 640
  gsettings set $A runner-menu-height 440
  gsettings set $A runner-menu-height-static false
  gsettings set $A runner-font-size 0
  gsettings set $A runner-show-settings-button false
  gsettings set $A runner-hotkey-open-primary-monitor false   # opens on the monitor you're using

  # ---- Rounded Window Corners Reborn
  local R=org.gnome.shell.extensions.rounded-window-corners-reborn U=rounded-window-corners@fxgn
  eset $U $R global-rounded-corner-settings "{'padding': <{'left': <uint32 1>, 'right': <uint32 1>, 'top': <uint32 1>, 'bottom': <uint32 1>}>, 'keepRoundedCorners': <{'maximized': <false>, 'fullscreen': <false>}>, 'borderRadius': <uint32 16>, 'smoothing': <0>, 'borderColor': <[0.882, 0.114, 0.18, 0.28]>, 'enabled': <true>}"
  eset $U $R border-width 0
  eset $U $R skip-libadwaita-app true       # GNOME apps already draw their own rounded corners
  eset $U $R keep-shadow-for-maximized-fullscreen false
  eset $U $R focused-shadow "{'horizontalOffset': 0, 'verticalOffset': 6, 'blurOffset': 28, 'spreadRadius': 2, 'opacity': 55}"
  eset $U $R unfocused-shadow "{'horizontalOffset': 0, 'verticalOffset': 3, 'blurOffset': 14, 'spreadRadius': -1, 'opacity': 45}"

  # ---- Desktop Cube: on for switching + overview; no accidental spins from the top bar or screen edges
  local Q=org.gnome.shell.extensions.desktop-cube U=desktop-cube@schneegans.github.com
  eset $U $Q enable-panel-dragging false     # top-bar drags stay "un-maximise window"
  eset $U $Q enable-desktop-edge-switch false
  eset $U $Q enable-overview-edge-switch false
  eset $U $Q enable-desktop-dragging true    # drag empty desktop to spin it
  eset $U $Q enable-overview-dragging true
  eset $U $Q do-explode true
  eset $U $Q window-parallax 0.5

  ext_enable "${EXTS[@]}"
  echo; echo "done. Log out and back in once to load them. Undo: bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  ext_unenable "${EXTS[@]}"
  for u in "${EXTS[@]}"; do grep -qx "$u" "$BK/preexisting.txt" || rm -rf "${EXT_DIR:?}/$u"; done
  restore_dconf "$BK" "${PATHS[@]}"
  restore_keys "$BK"
  echo "restored (log out/in to fully unload)"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
