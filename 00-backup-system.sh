#!/usr/bin/env bash
# Kuro OS — step 0b: back up system config files (run with sudo).
# Read-only on the originals: only copies INTO ~/theme-backups/<latest>/system.
set -euo pipefail
U_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
B="$U_HOME/theme-backups/$(cat "$U_HOME/theme-backups/LATEST")/system"
mkdir -p "$B"

for f in /etc/default/grub /boot/grub/grub.cfg /etc/mkinitcpio.conf \
         /etc/plymouth/plymouthd.conf /etc/lightdm /etc/mkinitcpio.conf.d \
         /etc/grub.d; do
  if [ -e "$f" ]; then
    mkdir -p "$B$(dirname "$f")"; cp -a "$f" "$B$f"; echo "backed up $f"
  else
    echo "absent: $f"
  fi
done

# Record state that the restore script needs
plymouth-set-default-theme > "$B/plymouth-theme.txt"
ls /boot/grub/themes > "$B/grub-themes-before.txt"
ls /usr/share/plymouth/themes > "$B/plymouth-themes-before.txt"
grep -E '^\s*(menuentry|submenu)' /boot/grub/grub.cfg | cut -c1-120 > "$B/grub-entries-before.txt" || true
chown -R "${SUDO_USER:-$USER}": "$B"
echo
echo "Boot entries before changes:"; cat "$B/grub-entries-before.txt"
echo "Done -> $B"
