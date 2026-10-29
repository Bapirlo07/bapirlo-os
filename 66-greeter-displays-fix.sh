#!/usr/bin/env bash
# Kuro OS — fix for the login-screen display script installed by 65-multimonitor.sh (needs sudo).
#   sudo bash ~/bapirlo-os/66-greeter-displays-fix.sh            # backup + install fixed script
#   sudo bash ~/bapirlo-os/66-greeter-displays-fix.sh restore    # put the previous script back
#
# /var/log/bapirlo-displays.log showed "Can't open display" on every boot: the script got no
# DISPLAY, so the HDMI monitor was never linked/laid out at the greeter. The new version falls back
# to :0 + /run/lightdm/root/:0 and waits for the X server. Only /etc/lightdm/bapirlo-displays.sh
# changes; lightdm.conf, Plymouth and initramfs are untouched (full undo is still 65-multimonitor.sh restore).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
U_HOME=$(getent passwd "${SUDO_USER:?run with sudo from your user}" | cut -d: -f6)
DSS=/etc/lightdm/bapirlo-displays.sh
NEW="$U_HOME/bapirlo-os/build/lightdm-v2/bapirlo-displays.sh"
PTR="$U_HOME/theme-backups/LATEST-GREETER-DISPLAYS"

if [ "${1:-}" = restore ]; then
  BK=$(cat "$PTR"); cp -a "$BK/bapirlo-displays.sh" "$DSS"; echo "restored $DSS from $BK"; exit 0
fi

[ -f "$NEW" ] || { echo "Missing $NEW — run: python3 ~/bapirlo-os/tools/build-lightdm-v2.py"; exit 1; }
sh -n "$NEW" || { echo "New script has a syntax error — not installing."; exit 1; }
BK="$U_HOME/theme-backups/$(date +%Y%m%d-%H%M%S)-greeter-displays"
mkdir -p "$BK"; cp -a "$DSS" "$BK/"; chown -R "${SUDO_USER:?run with sudo from your user}:" "$BK"
echo "$BK" > "$PTR"; chown "${SUDO_USER:?run with sudo from your user}:" "$PTR"
install -m 755 -o root -g root "$NEW" "$DSS"
grep -q "^display-setup-script=$DSS" /etc/lightdm/lightdm.conf && echo "lightdm.conf points at $DSS: OK"
echo "installed. backup -> $BK"
echo "Check after next boot:  cat /var/log/bapirlo-displays.log   (should list both screens, no 'Can't open display')"
echo "Undo: sudo bash ~/bapirlo-os/66-greeter-displays-fix.sh restore"
