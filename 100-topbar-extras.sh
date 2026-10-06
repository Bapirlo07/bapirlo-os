#!/usr/bin/env bash
# Bapirlo OS — top bar extras (NO sudo): Vitals, SimpleWeather (your town, °C), Clipboard Indicator, Caffeine.
#   bash ~/bapirlo-os/100-topbar-extras.sh            # backup + install + configure + enable
#   bash ~/bapirlo-os/100-topbar-extras.sh restore    # disable + remove these four + settings back
# All four verified for the running GNOME version before install. Wayland: log out/in once to load them.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
. "$(dirname "$(readlink -f "$0")")/lib/ext.sh"
EXTS=(Vitals@CoreCoding.com simple-weather@romanlefler.com clipboard-indicator@tudmotu.com caffeine@patapon.info)
PATHS=(/org/gnome/shell/extensions/vitals/ /org/gnome/shell/extensions/simple-weather/
       /org/gnome/shell/extensions/clipboard-indicator/ /org/gnome/shell/extensions/caffeine/)
KEYS=("org.gnome.shell.keybindings toggle-message-tray")
LATEST=~/theme-backups/LATEST-TOPBAR-EXTRAS

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-topbar-extras
  mkdir -p "$BK"
  backup_dconf "$BK" "${PATHS[@]}"
  backup_keys "$BK" "${KEYS[@]}"
  for u in "${EXTS[@]}"; do [ -d "$EXT_DIR/$u" ] && echo "$u" >> "$BK/preexisting.txt"; done
  touch "$BK/preexisting.txt"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo "installing (GNOME $SHELL_MAJOR):"
  for u in "${EXTS[@]}"; do ext_install "$u"; done

  # ---- Vitals: CPU %, CPU temp, RAM, net down/up. No GPU (keeps the RTX 4060 asleep), no public-IP lookups.
  local V=org.gnome.shell.extensions.vitals U=Vitals@CoreCoding.com
  eset $U $V hot-sensors "['_processor_usage_', '_temperature_processor_0_', '_memory_usage_', '__network-rx_max__', '__network-tx_max__']"
  eset $U $V alphabetize false
  eset $U $V update-time 5
  eset $U $V position-in-panel 2
  eset $U $V fixed-widths true
  eset $U $V show-gpu false
  eset $U $V include-public-ip false
  for k in show-voltage show-fan show-storage show-system show-battery; do eset $U $V $k false; done
  eset $U $V monitor-cmd "'gnome-system-monitor'"

  # ---- SimpleWeather: your town (~/.config/bapirlo/location.json, never in the repo), °C (UK preset),
  #      Open-Meteo (no key), no IP geolocation
  local W=org.gnome.shell.extensions.simple-weather U=simple-weather@romanlefler.com
  local LOCF=~/.config/bapirlo/location.json
  if [ -f "$LOCF" ]; then
    eset $U $W locations "[$(python3 -c 'import json,sys; print(repr(json.dumps(json.load(open(sys.argv[1])), separators=(",", ":"))))' "$LOCF")]"
    eset $U $W main-location-index 0
  else
    echo "  no $LOCF — weather location left as is (example: {\"name\":\"London\",\"lat\":51.507,\"lon\":-0.128,\"cc\":\"GB\"})"
  fi
  eset $U $W my-loc-provider disable
  eset $U $W weather-provider open-meteo
  eset $U $W unit-preset uk
  eset $U $W temp-unit celsius
  eset $U $W panel-box center              # sits next to the clock pill, keeps the right side light
  eset $U $W panel-priority 1
  eset $U $W show-panel-icon true
  eset $U $W symbolic-icons-panel true     # monochrome like the other bar icons
  eset $U $W is-activated true             # skip the first-run wizard (it would auto-locate by IP)

  # ---- Clipboard Indicator: Super+V only (its default Ctrl+F8..F12 keys clash with games)
  local C=org.gnome.shell.extensions.clipboard-indicator U=clipboard-indicator@tudmotu.com
  eset $U $C toggle-menu "['<Super>v']"
  for k in clear-history prev-entry next-entry private-mode-binding; do eset $U $C $k "[]"; done
  eset $U $C history-size 30
  eset $U $C paste-on-select true          # pick an entry → it is pasted, like Windows Win+V
  eset $U $C move-item-first true
  eset $U $C notify-on-copy false
  eset $U $C display-mode 0                # icon only
  # Super+V belonged to the notification list; it keeps Super+M
  gsettings set org.gnome.shell.keybindings toggle-message-tray "['<Super>m']"

  # ---- Caffeine: icon only while active (toggle lives in Quick Settings), auto-on for fullscreen apps
  local K=org.gnome.shell.extensions.caffeine U=caffeine@patapon.info
  eset $U $K show-indicator only-active
  eset $U $K enable-fullscreen true
  eset $U $K show-notifications false
  eset $U $K show-timer true

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
