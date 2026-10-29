#!/usr/bin/env bash
# Kuro OS — fix: bapirlo-perfd never started at boot (ordering cycle with CachyOS's
# power-profiles-daemon, which runs After=multi-user.target). Moves it to graphical.target.
#   sudo bash ~/bapirlo-os/301-perfd-fix.sh            # backup + fix + start now
#   sudo bash ~/bapirlo-os/301-perfd-fix.sh restore    # old unit back
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
U=${SUDO_USER:?run with sudo from your user}; H=$(getent passwd "$U" | cut -d: -f6)
UNIT=/etc/systemd/system/bapirlo-perfd.service
LATEST=$H/theme-backups/LATEST-PERFD-FIX
case "${1:-}" in
  "")
    BK=$H/theme-backups/$(date +%Y%m%d-%H%M%S)-perfd-fix; mkdir -p "$BK"; cp -a "$UNIT" "$BK/"
    chown -R "$U:" "$BK"; echo "$BK" > "$LATEST"; chown "$U:" "$LATEST"; echo "backup -> $BK"
    systemctl disable bapirlo-perfd
    install -m644 "$H/bapirlo-os/round2/root/bapirlo-perfd.service" "$UNIT"
    systemctl daemon-reload
    systemctl enable --now bapirlo-perfd
    sleep 3
    systemctl --no-pager -n 6 status bapirlo-perfd | sed -n '1,3p;/bapirlo-perfd\[/p'
    echo "profile $(powerprofilesctl get) · EC $(cat /sys/devices/platform/msi-ec/shift_mode 2>/dev/null)/$(cat /sys/devices/platform/msi-ec/fan_mode 2>/dev/null) · charge limit $(cat /sys/class/power_supply/BAT1/charge_control_end_threshold)%"
    systemd-analyze verify graphical.target 2>&1 | grep -i 'cycle' || echo "no ordering cycle"
    ;;
  restore)
    BK=$(cat "$LATEST"); systemctl disable bapirlo-perfd
    install -m644 "$BK/bapirlo-perfd.service" "$UNIT"; systemctl daemon-reload; systemctl enable bapirlo-perfd
    echo "restored old unit" ;;
  *) sed -n 2,5p "$0"; exit 1 ;;
esac
