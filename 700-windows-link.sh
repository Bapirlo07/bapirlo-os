#!/usr/bin/env bash
# Windows link — the Windows partition (found automatically) in Files + dual-boot helpers.
#   sudo bash ~/bapirlo-os/700-windows-link.sh           snapshot → backup → install
#   sudo bash ~/bapirlo-os/700-windows-link.sh restore   remove everything this installed
# Installs: udev hint (name "Windows" + icon, no-password mount, hide 2 recovery partitions),
# /etc/udisks2/mount_options.conf (ntfs3, READ-ONLY default), icons, hivex (read Windows registry),
# /usr/local/bin/bapirlo-windows + bapirlo-bt-sync.
# Never touches: /etc/fstab, partitions, the EFI partition, Limine/GRUB, the "Restart to Windows" entry.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
U=${SUDO_USER:?run with sudo from your own account}; H=$(getent passwd "$U" | cut -d: -f6)
BK=$H/theme-backups; SRC=$H/bapirlo-os/windows
SNAP="Before Windows link"
FILES=(/etc/udev/rules.d/90-bapirlo-windows.rules /etc/udisks2/mount_options.conf
       /usr/share/icons/hicolor/scalable/devices/bapirlo-windows-drive.svg
       /usr/share/icons/hicolor/scalable/devices/bapirlo-windows-drive-symbolic.svg
       /usr/local/bin/bapirlo-windows /usr/local/bin/bapirlo-bt-sync)
# The Windows C: drive = the largest NTFS "Microsoft basic data" partition; recovery partitions are
# hidden. Found with lsblk every run (nothing about this laptop is hard-coded). GPT type GUIDs:
BASIC=ebd0a0a2-b9e5-4433-87c0-68b6b72699c7 RECOVERY=de94bba4-06d1-4d40-a16a-bfd50179d6ac
WIN_DEV=$(lsblk -rpbno NAME,SIZE,FSTYPE,PARTTYPE | awk -v t=$BASIC '$3 == "ntfs" && tolower($4) == t { print $2, $1 }' | sort -rn | awk 'NR == 1 { print $2 }')
[ -n "$WIN_DEV" ] || { echo "!! no Windows (NTFS basic data) partition found — nothing to do"; exit 1; }
WIN_UUID=$(lsblk -no UUID "$WIN_DEV")
mapfile -t REC_DEVS < <(lsblk -rpno NAME,FSTYPE,PARTTYPE | awk -v t=$RECOVERY '$2 == "ntfs" && tolower($3) == t { print $1 }')
PARTS=("$WIN_DEV" "${REC_DEVS[@]}")
echo ":: Windows partition: $WIN_DEV (UUID $WIN_UUID) · recovery: ${REC_DEVS[*]:-none}"
# put the detected UUIDs into a file from windows/ while installing it
fill() {  # fill SRC DEST MODE
  local rec="" r
  for r in "${REC_DEVS[@]}"; do
    rec+="SUBSYSTEM==\"block\", ENV{ID_FS_UUID}==\"$(lsblk -no UUID "$r")\", ENV{UDISKS_IGNORE}=\"1\""$'\n'
  done
  python3 -c 'import sys; s = open(sys.argv[1]).read().replace("@WIN_UUID@", sys.argv[2]).replace("@RECOVERY_RULES@\n", sys.argv[3]); sys.stdout.write(s)' \
    "$1" "$WIN_UUID" "$rec" | install -Dm"$3" /dev/stdin "$2"
}

reload() {
  udevadm control --reload
  udevadm trigger --action=change "${PARTS[@]}"; udevadm settle
  gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
  systemctl restart udisks2
}

if [ "${1:-}" = restore ]; then
  d=$(cat "$BK/LATEST-WINDOWS-LINK")
  findmnt -S "UUID=$WIN_UUID" >/dev/null && umount "$WIN_DEV" && echo ":: unmounted Windows"
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
[ -z "$(findmnt -nro TARGET -S "UUID=$WIN_UUID")" ] || { echo "!! unmount Windows first (bapirlo-windows off)"; exit 1; }
if [ -n "${BAPIRLO_INSTALLER:-}" ]; then
  echo ":: install.sh took \"Before Kuro OS\" — no extra snapshot"
elif timeshift --list --scripted 2>/dev/null | grep -q "$SNAP"; then
  echo ":: snapshot \"$SNAP\" already there"
else
  echo ":: Timeshift snapshot \"$SNAP\" (incremental — a few minutes)"
  nice -n 10 timeshift --create --scripted --comments "$SNAP" --tags O
  timeshift --list --scripted | grep -q "$SNAP" || { echo "!! snapshot missing — stopping, nothing changed."; exit 1; }
fi
[ -n "${BAPIRLO_INSTALLER:-}" ] || timeshift --list --scripted | grep "$SNAP"

# ---- 1. backup whatever is already there (fstab copied for reference only — it is NOT edited)
d=$BK/$(date +%Y%m%d-%H%M%S)-windows-link; mkdir -p "$d/root"
for f in "${FILES[@]}" /etc/fstab; do [ -e "$f" ] && install -D -m600 "$f" "$d/root$f" || true; done
echo "$d" > "$BK/LATEST-WINDOWS-LINK"; chown -R $U:$U "$d" "$BK/LATEST-WINDOWS-LINK"
echo ":: backup $d"

# ---- 2. hivex (read-only Windows registry reader, ~1 MB)
pacman -S --needed hivex

# ---- 3. install
fill "$SRC/90-bapirlo-windows.rules" /etc/udev/rules.d/90-bapirlo-windows.rules 644
fill "$SRC/mount_options.conf"       /etc/udisks2/mount_options.conf 644
install -Dm644 "$SRC/bapirlo-windows-drive.svg" /usr/share/icons/hicolor/scalable/devices/bapirlo-windows-drive.svg
install -Dm644 "$SRC/bapirlo-windows-drive-symbolic.svg" /usr/share/icons/hicolor/scalable/devices/bapirlo-windows-drive-symbolic.svg
fill "$SRC/bapirlo-windows" /usr/local/bin/bapirlo-windows 755
fill "$SRC/bapirlo-bt-sync" /usr/local/bin/bapirlo-bt-sync 755
reload

echo ":: Windows partition hints:"; udevadm info "$WIN_DEV" | grep -E 'UDISKS_|ID_FS_TYPE'
echo ":: done. Undo: sudo bash $0 restore"
