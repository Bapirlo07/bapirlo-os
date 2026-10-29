#!/usr/bin/env bash
# Kuro OS — small GRUB tune-up on top of boot v2 (run with sudo).
#   sudo bash ~/bapirlo-os/55-grub-tune.sh            apply
#   sudo bash ~/bapirlo-os/55-grub-tune.sh restore    undo (from the backup this script made)
#
#  * GRUB background: 3.4 MB PNG -> 0.5 MB baseline JPEG (GRUB's PNG decoder is slow;
#    the loader stage was 11 s, 3 s of which is the menu timeout)
#  * drop i915.fastboot=1 from the kernel cmdline (kernel 6.18 ignores it: "unknown parameter";
#    fastboot is already the default)
#  * grub-mkconfig to a TEMP file, verified (Linux + Windows + theme + jpeg) before replacing grub.cfg
#
# Touches only /boot/grub/themes/bapirlo-kuro, /etc/default/grub and /boot/grub/grub.cfg.
# No initramfs change. Does not move ~/theme-backups/LATEST-BOOT-V2 (restore-boot-v2.sh still works).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
U=${SUDO_USER:?run via sudo}; U_HOME=$(getent passwd "$U" | cut -d: -f6)
SRC="$U_HOME/bapirlo-os/build/grub-v2/bapirlo"
CFG=/boot/grub/grub.cfg; NEW=/boot/grub/grub.cfg.tune-new
GTHEME=/boot/grub/themes/bapirlo-kuro
PTR="$U_HOME/theme-backups/LATEST-GRUB-TUNE"

entries() { grep -E '^\s*(menuentry|submenu)' "$1" | sed -E "s/^\s*(menuentry|submenu) '([^']*)'.*/    \1: \2/"; }

if [ "${1:-}" = restore ]; then
  BK=$(cat "$PTR"); [ -f "$BK/boot/grub/grub.cfg" ] || { echo "No tune backup at $BK"; exit 1; }
  echo "Restoring from $BK"
  cp -a "$BK/etc/default/grub" /etc/default/grub
  rm -rf "$GTHEME"; cp -a "$BK$GTHEME" "$GTHEME"
  cp -a "$BK/boot/grub/grub.cfg" "$CFG"
  echo "Restored. Entries:"; entries "$CFG"; exit 0
fi

[ -f "$SRC/background.jpg" ] && grep -q 'desktop-image: "background.jpg"' "$SRC/theme.txt" \
  || { echo "Build output missing — run: python3 ~/bapirlo-os/tools/build-grub-v2.py"; exit 1; }

# ------------------------------------------------------------------ 0. backup
BK="$U_HOME/theme-backups/$(date +%Y%m%d-%H%M%S)-grub-tune"
echo "== 0. Backing up to $BK"
for p in /etc/default/grub "$CFG" "$GTHEME"; do
  mkdir -p "$BK$(dirname "$p")"; cp -a "$p" "$BK$p"; echo "  saved $p"
done
echo "$BK" > "$PTR"; chown -R "$U": "$BK" "$PTR"
revert() { cp -a "$BK/etc/default/grub" /etc/default/grub; rm -rf "$GTHEME"; cp -a "$BK$GTHEME" "$GTHEME"; rm -f "$NEW"; }

# ------------------------------------------------------------------ 1. theme + cmdline
echo "== 1. Theme -> $GTHEME (JPEG background)"
rm -rf "$GTHEME"; cp -r "$SRC" "$GTHEME"; chown -R root:root "$GTHEME"
echo "== 2. Kernel cmdline: drop i915.fastboot=1"
sed -i -E '/^GRUB_CMDLINE_LINUX_DEFAULT=/{s/ ?i915\.fastboot=1//; s/=" /="/}' /etc/default/grub
grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | sed 's/^/  /'

# ------------------------------------------------------------------ 3. grub.cfg (temp + verify)
echo "== 3. grub-mkconfig -> $NEW"
if ! grub-mkconfig -o "$NEW"; then echo "!! grub-mkconfig failed — reverting"; revert; exit 1; fi
fail=0
ck() { if grep -qE "$2" "$NEW"; then echo "  OK   $1"; else echo "  FAIL $1"; fail=1; fi; }
grub-script-check "$NEW" && echo "  OK   syntax" || fail=1
ck "Linux entry 'Kuro OS'"         "menuentry 'Kuro OS'"
ck "kernel image"                     "linux\s+/(boot/)?vmlinuz-linux-cachyos"
ck "initramfs"                        "initrd\s+.*initramfs-linux-cachyos(-lts)?\.img"
ck "quiet splash on kernel line"      "vmlinuz-linux-cachyos.*quiet.*splash|vmlinuz-linux-cachyos.*splash.*quiet"
ck "Windows entry 'Windows'"          "menuentry 'Windows'"
ck "Windows uses firmware BootNext"   "bootnext 0000"
ck "Kuro theme loaded"                "set theme=.*bapirlo-kuro/theme.txt"
ck "jpeg module loaded"               "insmod jpeg"
ck "timeout 3"                        "set timeout=3"
if grep -q "i915.fastboot" "$NEW"; then echo "  FAIL i915.fastboot still on kernel line"; fail=1; else echo "  OK   i915.fastboot gone"; fi
if [ "$fail" -ne 0 ]; then echo "!! Verification failed — reverting; $CFG NOT changed"; revert; exit 1; fi
mv "$NEW" "$CFG"
echo "  installed. Entries now:"; entries "$CFG"
echo
echo "Done. Reboot to see it; compare with: systemd-analyze   (loader was 11.1 s)"
echo "Undo: sudo bash ~/bapirlo-os/55-grub-tune.sh restore"
