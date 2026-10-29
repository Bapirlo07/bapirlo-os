#!/usr/bin/env bash
# Kuro OS — smooth Plymouth → LightDM hand-off (needs sudo).
#   sudo bash ~/bapirlo-os/75-boot-handoff.sh            # backup + apply
#   sudo bash ~/bapirlo-os/75-boot-handoff.sh restore    # undo
#
# Today: plymouth-quit.service kills the splash at ~6.6s, THEN LightDM starts (~6.8s) and Xorg comes up on a new
# VT → a black / console flash between the splash and the greeter.
# Fix (same pattern GDM ships): LightDM no longer waits for plymouth-quit; it starts while the splash is still up,
# notices Plymouth, starts Xorg on the same VT with "-background none" and tells Plymouth to quit --retain-splash
# once X is ready → the splash frame stays until the greeter paints over it.
# Safety net: if LightDM fails, plymouth-quit runs anyway; and Plymouth is force-quit 30s after LightDM starts.
#
# LightDM only takes over a splash whose VT >= minimum-vt (default 7, Plymouth is on VT1) → minimum-vt=1.
#
# Touches ONLY /etc/systemd/system/lightdm.service.d/ and /etc/lightdm/lightdm.conf.d/ — no GRUB, no initramfs,
# no partitions/fstab/EFI.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
U=${SUDO_USER:?run with sudo from your user}; H=$(getent passwd "$U" | cut -d: -f6)
D=/etc/systemd/system/lightdm.service.d
F=$D/10-bapirlo-plymouth.conf
C=/etc/lightdm/lightdm.conf.d/10-bapirlo-vt.conf
LATEST=$H/theme-backups/LATEST-BOOT-HANDOFF

restore() {
  local BK; BK=$(cat "$LATEST" 2>/dev/null || true)
  echo "restoring from ${BK:-<never applied — just removing Kuro files>}"
  rm -f "$F" "$C"
  rmdir /etc/lightdm/lightdm.conf.d 2>/dev/null || true
  [ -n "$BK" ] && [ -d "$BK/lightdm.service.d" ] && cp -a "$BK/lightdm.service.d/." "$D/"
  rmdir "$D" 2>/dev/null || true
  systemctl daemon-reload
  echo "restored — reboot to see the old hand-off"
}
[ "${1:-}" = restore ] && { restore; exit 0; }

BK=$H/theme-backups/$(date +%Y%m%d-%H%M%S)-boot-handoff
mkdir -p "$BK"
[ -d "$D" ] && cp -a "$D" "$BK/lightdm.service.d"
systemctl cat lightdm.service > "$BK/lightdm.service.before.txt"
chown -R "$U:$U" "$BK"; echo "$BK" > "$LATEST"; chown "$U:$U" "$LATEST"
echo "backup -> $BK"

mkdir -p "$D"
cat > "$F" <<'EOF'
# Kuro OS — keep the Plymouth splash up until the greeter is drawn (75-boot-handoff.sh)
[Unit]
Conflicts=plymouth-quit.service
After=plymouth-start.service
OnFailure=plymouth-quit.service

[Service]
ExecStartPost=-/usr/bin/sh -c 'sleep 30; /usr/bin/plymouth quit --retain-splash'
EOF
mkdir -p "$(dirname "$C")"
printf '%s\n' '# Kuro OS (75-boot-handoff.sh): let LightDM take over the Plymouth VT instead of switching to VT7' \
  '[LightDM]' 'minimum-vt=1' > "$C"
systemctl daemon-reload
echo "--- lightdm:"; sed 's/^/  /' "$C"
echo "--- effective unit:"
systemctl show lightdm.service -p Conflicts -p After -p OnFailure | sed 's/^/  /'
systemd-analyze verify lightdm.service 2>&1 | grep -v -i 'not found\|is marked' | sed 's/^/  verify: /' || true
echo
echo "GRUB, Plymouth theme and initramfs are untouched — no grub-mkconfig / mkinitcpio needed for this step."
echo "Reboot to see it. Undo:  sudo bash $H/bapirlo-os/75-boot-handoff.sh restore"
