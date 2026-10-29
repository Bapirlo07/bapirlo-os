#!/usr/bin/env bash
# Kuro OS — open KDE Connect ports (1714-1764 tcp+udp) in ufw for HOME networks only. NEEDS sudo.
#   sudo bash ~/bapirlo-os/111-gsconnect-firewall.sh            # backup + add rules
#   sudo bash ~/bapirlo-os/111-gsconnect-firewall.sh restore    # remove exactly these rules
# Allowed from: 192.168.0.0/16 (home routers), 10.0.0.0/8 (Android hotspots, some routers),
# 172.20.10.0/28 (iPhone hotspot). eduroam (172.25.x.x) and every other network stay closed.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
U=${SUDO_USER:?run via sudo from your user}; H=$(getent passwd "$U" | cut -d: -f6)
LATEST=$H/theme-backups/LATEST-GSCONNECT-FW
NETS=(192.168.0.0/16 10.0.0.0/8 172.20.10.0/28)
COMMENT=bapirlo-kdeconnect

apply() {
  local BK=$H/theme-backups/$(date +%Y%m%d-%H%M%S)-gsconnect-fw
  mkdir -p "$BK"
  ufw status numbered > "$BK/ufw-status-before.txt"
  cp -a /etc/ufw/user.rules /etc/ufw/user6.rules "$BK/"
  chown -R "$U:" "$BK"; echo "$BK" > "$LATEST"; chown "$U:" "$LATEST"
  echo "backup -> $BK"
  for n in "${NETS[@]}"; do
    for p in tcp udp; do ufw allow proto $p from "$n" to any port 1714:1764 comment $COMMENT; done
  done
  ufw status | grep -E "1714|Status"
}

restore() {
  echo "removing $COMMENT rules (backup of the old rule files: $(cat "$LATEST"))"
  for n in "${NETS[@]}"; do
    for p in tcp udp; do ufw delete allow proto $p from "$n" to any port 1714:1764 2>/dev/null || true; done
  done
  ufw status | grep -E "1714|Status" || echo "no KDE Connect rules left"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
