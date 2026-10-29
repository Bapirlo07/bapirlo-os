#!/usr/bin/env bash
# Kuro OS — give Waydroid (Android) internet, and install the "Android" launcher.
# Run once:  sudo bash ~/bapirlo-os/910-waydroid-net.sh
# Why: UFW blocks Waydroid's bridge (waydroid0) — Android's DHCP/DNS requests to the host are
# dropped as incoming traffic, and its outgoing traffic hits DEFAULT_FORWARD_POLICY="DROP".
# The rules below open ONLY the waydroid0 bridge; the rest of the firewall is unchanged.
# Undo:  sudo bash ~/bapirlo-os/910-waydroid-net.sh restore
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
BIN="$(cd "$(dirname "$0")" && pwd)/bin"

if [ "${1:-}" = restore ]; then
  ufw delete allow in on waydroid0 || true
  ufw delete route allow in on waydroid0 || true
  ufw delete route allow out on waydroid0 || true
  rm -f /usr/local/bin/bapirlo-android
  systemctl restart waydroid-container
  exit 0
fi

echo "==> Opening the firewall for the Waydroid bridge"
ufw allow in on waydroid0 comment 'Waydroid DHCP/DNS'
ufw route allow in on waydroid0 comment 'Waydroid to internet'
ufw route allow out on waydroid0 comment 'Waydroid replies'
ufw reload

echo "==> Make sure packet forwarding stays on"
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/90-waydroid.conf
sysctl -q --system

echo "==> Installing the bapirlo-android command"
install -m755 "$BIN/bapirlo-android" /usr/local/bin/bapirlo-android

echo "==> Restarting Waydroid so Android picks up an address"
systemctl enable waydroid-container
systemctl restart waydroid-container

echo
echo "Done. Open \"Android\" from the app menu, or run:  bapirlo-android"
