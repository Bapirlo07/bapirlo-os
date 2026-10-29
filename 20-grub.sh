#!/usr/bin/env bash
# Kuro OS — step 9: GRUB theme + rename "Arch Linux" -> "Kuro OS" (run with sudo).
# Safe-by-design:
#   * never touches partitions, fstab, the EFI partition, or grub-install
#   * generates the new grub.cfg to a TEMP file and only installs it if it still
#     contains the Kuro kernel entry AND Windows Boot Manager; otherwise rolls back.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
U_HOME=$(getent passwd "${SUDO_USER:?run via sudo}" | cut -d: -f6)
BK="$U_HOME/theme-backups/$(cat "$U_HOME/theme-backups/LATEST")/system"
SRC="$U_HOME/bapirlo-os/build/grub/bapirlo"
THEME_DIR=/boot/grub/themes/bapirlo
CFG=/boot/grub/grub.cfg
NEW=/boot/grub/grub.cfg.bapirlo-new

[ -f "$BK/etc/default/grub" ] && [ -f "$BK/etc/grub.d/10_linux" ] && [ -f "$BK/boot/grub/grub.cfg" ] \
  || { echo "Backup missing in $BK — run 00-backup-system.sh first."; exit 1; }
[ -f "$SRC/theme.txt" ] || { echo "Theme not built: $SRC"; exit 1; }

rollback() {
  echo "!! Rolling back /etc/default/grub and /etc/grub.d/10_linux from backup"
  cp -a "$BK/etc/default/grub" /etc/default/grub
  cp -a "$BK/etc/grub.d/10_linux" /etc/grub.d/10_linux
  rm -f "$NEW"
  echo "!! $CFG was NOT changed. Your boot menu is exactly as before."
}
trap 'rollback' ERR

# setkey KEY VALUE  — replace (even if commented) or append in /etc/default/grub
setkey() {
  if grep -qE "^#?\s*$1=" /etc/default/grub; then
    sed -i -E "s|^#?\s*$1=.*|$1=\"$2\"|" /etc/default/grub
  else
    echo "$1=\"$2\"" >> /etc/default/grub
  fi
}

echo "== 1. Installing theme to $THEME_DIR"
rm -rf "$THEME_DIR"
cp -r "$SRC" "$THEME_DIR"
chown -R root:root "$THEME_DIR"

echo "== 2. /etc/default/grub: name, theme, resolution"
setkey GRUB_DISTRIBUTOR "Kuro OS"
setkey GRUB_THEME "$THEME_DIR/theme.txt"
setkey GRUB_GFXMODE "1920x1200,1920x1080,auto"
grep -nE '^GRUB_(DISTRIBUTOR|THEME|GFXMODE|GFXPAYLOAD_LINUX|DISABLE_OS_PROBER)=' /etc/default/grub

echo "== 3. Entry title: drop the automatic ' Linux' suffix"
sed -i 's|OS="${GRUB_DISTRIBUTOR} Linux"|OS="${GRUB_DISTRIBUTOR}"|' /etc/grub.d/10_linux
grep -q 'OS="${GRUB_DISTRIBUTOR}"$' /etc/grub.d/10_linux

echo "== 4. Pacman hook: re-apply the rename after grub package upgrades"
mkdir -p /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/95-bapirlo-grub-name.hook <<'EOF'
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = grub

[Action]
Description = Kuro OS: keep GRUB entry name "Kuro OS"
When = PostTransaction
Exec = /usr/bin/sh -c 'sed -i "s|OS=\"\${GRUB_DISTRIBUTOR} Linux\"|OS=\"\${GRUB_DISTRIBUTOR}\"|" /etc/grub.d/10_linux && /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg'
EOF

echo "== 5. Generating NEW config into $NEW (current $CFG untouched)"
grub-mkconfig -o "$NEW"

echo "== 6. Verifying the new config"
fail=0
check() { if grep -qE "$2" "$NEW"; then echo "  OK   $1"; else echo "  FAIL $1"; fail=1; fi; }
grub-script-check "$NEW" && echo "  OK   syntax (grub-script-check)" || fail=1
check "entry named 'Kuro OS'"          "menuentry 'Kuro OS'"
check "Linux kernel vmlinuz-linux-cachyos" "linux\s+/(boot/)?vmlinuz-linux-cachyos"
check "initramfs"                          "initrd\s+.*initramfs-linux-cachyos\.img"
check "Windows Boot Manager"               "Windows Boot Manager"
check "theme loaded"                       "set theme=.*bapirlo/theme.txt"
if [ "$fail" -ne 0 ]; then false; fi   # triggers rollback

echo "== 7. Installing new config (old one kept as grub.cfg.pre-bapirlo)"
cp -a "$CFG" /boot/grub/grub.cfg.pre-bapirlo
mv "$NEW" "$CFG"
trap - ERR

echo
echo "Boot menu entries now:"
grep -E '^\s*(menuentry|submenu)' "$CFG" | sed -E "s/^\s*(menuentry|submenu) '([^']*)'.*/  \1: \2/"
echo
echo "GRUB done. Nothing was written to the EFI partition."
