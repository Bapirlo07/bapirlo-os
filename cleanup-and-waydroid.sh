#!/usr/bin/env bash
# Frees disk space (old Timeshift snapshots, pacman cache) and installs Waydroid with GApps.
set -euo pipefail

echo "==> Deleting old Timeshift snapshots (keeping the newest 2)"
mapfile -t snaps < <(ls -1 /timeshift/snapshots | sort)
keep=2
for ((i = 0; i < ${#snaps[@]} - keep; i++)); do
    echo "   - ${snaps[i]}"
    timeshift --delete --snapshot "${snaps[i]}" --scripted
done

echo "==> Cleaning pacman cache (keep 1 version, drop uninstalled)"
paccache -rk1
paccache -ruk0

echo "==> Installing Waydroid"
pacman -S --needed --noconfirm waydroid

echo "==> Downloading Android image with GApps"
waydroid init -s GAPPS -f

systemctl enable --now waydroid-container

echo
df -h /
echo
echo "Done. Start Android with:  waydroid show-full-ui"
