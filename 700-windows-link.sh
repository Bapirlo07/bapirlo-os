#!/usr/bin/env bash
# Windows link — the Windows partition (nvme0n1p3) in Files + dual-boot helpers.
#   sudo bash ~/bapirlo-os/700-windows-link.sh           snapshot → backup → install
#   sudo bash ~/bapirlo-os/700-windows-link.sh restore   remove everything this installed
# Installs: udev hint (name "Windows" + icon, no-password mount, hide 2 recovery partitions),
# /etc/udisks2/mount_options.conf (ntfs3, READ-ONLY default), icons, hivex (read Windows registry),
# /usr/local/bin/bapirlo-windows + bapirlo-bt-sync.
# Never touches: /etc/fstab, partitions, the EFI partition, Limine/GRUB, the "Restart to Windows" entry.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
U=${SUDO_USER:?run with sudo from your own account}; H=$(getent passwd "$U" | cut -d: -f6); BK=$H/theme-backups; SRC=$H/bapirlo-os/windows
SNAP="Before Windows link"
FILES=(/etc/udev/rules.d/90-bapirlo-windows.rules /etc/udisks2/mount_options.conf
       /usr/share/icons/hicolor/scalable/devices/bapirlo-windows-drive.svg
       /usr/share/icons/hicolor/scalable/devices/bapirlo-windows-drive-symbolic.svg
       /usr/local/bin/bapirlo-windows /usr/local/bin/bapirlo-bt-sync)
PARTS=(/dev/nvme0n1p3 /dev/nvme0n1p4 /dev/nvme0n1p5)

reload() {
  udevadm control --reload
  udevadm trigger --action=change "${PARTS[@]}"; udevadm settle
  gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
  systemctl restart udisks2
}

if [ "${1:-}" = restore ]; then
  d=$(cat "$BK/LATEST-WINDOWS-LINK")
  findmnt -S UUID=B4A053F6A053BE14 >/dev/null && umount /dev/nvme0n1p3 && echo ":: unmounted Windows"
  for f in "${FILES[@]}"; do
    if [ -e "$d/root$f" ]; then cp -a "$d/root$f" "$f"; echo ":: restored $f"
    else rm -f "$f"; echo ":: removed  $f"; fi
  done
  reload
  echo ":: done (hivex package left installed: 'sudo pacman -Rns hivex' to remove it)"
  echo ":: full rollback instead: sudo timeshift --restore  → pick \"$SNAP\""
  exit 0
fi

# ---- 0. snapshot FIRST — nothing else runs unless it exists
[ -z "$(findmnt -nro TARGET -S UUID=B4A053F6A053BE14)" ] || { echo "!! unmount Windows first (bapirlo-windows off)"; exit 1; }
if timeshift --list --scripted 2>/dev/null | grep -q "$SNAP"; then
  echo ":: snapshot \"$SNAP\" already there"
else
  echo ":: Timeshift snapshot \"$SNAP\" (incremental — a few minutes)"
  nice -n 10 timeshift --create --scripted --comments "$SNAP" --tags O
  timeshift --list --scripted | grep -q "$SNAP" || { echo "!! snapshot missing — stopping, nothing changed."; exit 1; }
fi
timeshift --list --scripted | grep "$SNAP"

# ---- 1. backup whatever is already there (fstab copied for reference only — it is NOT edited)
d=$BK/$(date +%Y%m%d-%H%M%S)-windows-link; mkdir -p "$d/root"
for f in "${FILES[@]}" /etc/fstab; do [ -e "$f" ] && install -D -m600 "$f" "$d/root$f" || true; done
echo "$d" > "$BK/LATEST-WINDOWS-LINK"; chown -R $U:$U "$d" "$BK/LATEST-WINDOWS-LINK"
echo ":: backup $d"

# ---- 2. hivex (read-only Windows registry reader, ~1 MB)
pacman -S --needed hivex

# ---- 3. install
install -Dm644 "$SRC/90-bapirlo-windows.rules" /etc/udev/rules.d/90-bapirlo-windows.rules
install -Dm644 "$SRC/mount_options.conf"       /etc/udisks2/mount_options.conf
install -Dm644 "$SRC/bapirlo-windows-drive.svg" /usr/share/icons/hicolor/scalable/devices/bapirlo-windows-drive.svg
install -Dm644 "$SRC/bapirlo-windows-drive-symbolic.svg" /usr/share/icons/hicolor/scalable/devices/bapirlo-windows-drive-symbolic.svg
install -Dm755 "$SRC/bapirlo-windows" /usr/local/bin/bapirlo-windows
install -Dm755 "$SRC/bapirlo-bt-sync" /usr/local/bin/bapirlo-bt-sync
reload

echo ":: Windows partition hints:"; udevadm info /dev/nvme0n1p3 | grep -E 'UDISKS_|ID_FS_TYPE'
echo ":: done. Undo: sudo bash $0 restore"
