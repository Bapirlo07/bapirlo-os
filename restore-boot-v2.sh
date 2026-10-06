#!/usr/bin/env bash
# Bapirlo OS — undo 50-boot-v2.sh exactly, from the backup it made.
#   sudo bash ~/bapirlo-os/restore-boot-v2.sh [backup-dir]
# Default backup-dir: the one recorded in ~/theme-backups/LATEST-BOOT-V2
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
U_HOME=$(getent passwd "${SUDO_USER:?run via sudo}" | cut -d: -f6)
BK=${1:-$(cat "$U_HOME/theme-backups/LATEST-BOOT-V2")}
[ -f "$BK/etc/default/grub" ] && [ -f "$BK/boot/grub/grub.cfg" ] || { echo "Not a boot-v2 backup: $BK"; exit 1; }
echo "Restoring boot setup from $BK"

cp -a "$BK/etc/default/grub" /etc/default/grub
rm -f /etc/grub.d/31_bapirlo_bootnext
cp -a "$BK/etc/grub.d/." /etc/grub.d/
cp -a "$BK/etc/mkinitcpio.conf" /etc/mkinitcpio.conf
rm -rf /etc/plymouth && cp -a "$BK/etc/plymouth" /etc/plymouth
rm -rf /etc/lightdm && cp -a "$BK/etc/lightdm" /etc/lightdm
LDH=$(getent passwd lightdm | cut -d: -f6)
rm -f "$LDH/.config/gtk-3.0/gtk.css"
[ -e "$BK$LDH/.config/gtk-3.0" ] && cp -a "$BK$LDH/.config/gtk-3.0/." "$LDH/.config/gtk-3.0/"
[ -d "$BK/usr/share/themes/WhiteSur-Dark-red" ] && { rm -rf /usr/share/themes/WhiteSur-Dark-red; cp -a "$BK/usr/share/themes/WhiteSur-Dark-red" /usr/share/themes/WhiteSur-Dark-red; }
plymouth-set-default-theme "$(cat "$BK/plymouth-theme.txt")"
rm -rf /usr/share/plymouth/themes/bapirlo-kuro /boot/grub/themes/bapirlo-kuro
rm -f /usr/share/backgrounds/bapirlo/login-kuro.png /usr/share/backgrounds/bapirlo/badge-kuro.png

# boot images + menu: the exact files saved before the change
cp -a "$BK"/boot/initramfs-*.img /boot/
cp -a "$BK/boot/grub/grub.cfg" /boot/grub/grub.cfg
echo "Restored. Boot menu entries:"
grep -E '^\s*(menuentry|submenu)' /boot/grub/grub.cfg | sed -E "s/^\s*(menuentry|submenu) '([^']*)'.*/  \1: \2/"
echo "(If you changed kernels since the backup, also run: sudo mkinitcpio -P && sudo grub-mkconfig -o /boot/grub/grub.cfg)"
