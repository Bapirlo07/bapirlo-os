#!/usr/bin/env bash
# Kuro OS — step 10: Plymouth splash (run with sudo).
#   1. install theme + make it the default
#   2. add 'splash' to the kernel command line (GRUB regenerated to a temp file + verified)
#   3. rebuild initramfs and verify success + theme presence; roll back on failure
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
U_HOME=$(getent passwd "${SUDO_USER:?run via sudo}" | cut -d: -f6)
BK="$U_HOME/theme-backups/$(cat "$U_HOME/theme-backups/LATEST")/system"
SRC="$U_HOME/bapirlo-os/build/plymouth/bapirlo"
DST=/usr/share/plymouth/themes/bapirlo
OLD_THEME=$(cat "$BK/plymouth-theme.txt")
CFG=/boot/grub/grub.cfg; NEW=/boot/grub/grub.cfg.bapirlo-new
[ -f "$SRC/bapirlo.script" ] || { echo "Theme not built: $SRC"; exit 1; }

echo "== 1. Installing Plymouth theme"
rm -rf "$DST"; cp -r "$SRC" "$DST"; chown -R root:root "$DST"; chmod -R a+rX "$DST"
plymouth-set-default-theme bapirlo
echo "  default theme: $(plymouth-set-default-theme)"

echo "== 2. Kernel command line: add 'splash'"
if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=".*\bsplash\b' /etc/default/grub; then
  echo "  already has splash"
else
  cp -a /etc/default/grub /etc/default/grub.pre-splash
  sed -i -E 's/^(GRUB_CMDLINE_LINUX_DEFAULT=")([^"]*)"/\1\2 splash"/' /etc/default/grub
  grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub
  grub-mkconfig -o "$NEW"
  fail=0
  ck() { grep -qE "$2" "$NEW" && echo "  OK   $1" || { echo "  FAIL $1"; fail=1; }; }
  grub-script-check "$NEW" && echo "  OK   syntax" || fail=1
  ck "entry 'Kuro OS'"        "menuentry 'Kuro OS'"
  ck "kernel + splash"           "linux\s+/(boot/)?vmlinuz-linux-cachyos.* splash"
  ck "Windows Boot Manager"      "Windows Boot Manager"
  ck "theme"                     "set theme=.*bapirlo/theme.txt"
  if [ "$fail" -ne 0 ]; then
    echo "!! GRUB check failed — reverting cmdline; grub.cfg NOT changed"
    mv /etc/default/grub.pre-splash /etc/default/grub; rm -f "$NEW"
    plymouth-set-default-theme "$OLD_THEME"; exit 1
  fi
  cp -a "$CFG" /boot/grub/grub.cfg.pre-splash
  mv "$NEW" "$CFG"; rm -f /etc/default/grub.pre-splash
  echo "  grub.cfg updated (previous kept as grub.cfg.pre-splash)"
fi

echo "== 2b. Verifying the boot menu currently installed ($CFG)"
for pat in "menuentry 'Kuro OS'" "Windows Boot Manager" "vmlinuz-linux-cachyos .* splash" "bapirlo/theme.txt"; do
  grep -qE "$pat" "$CFG" && echo "  OK   $pat" || { echo "  FAIL $pat — stopping, nothing changed"; plymouth-set-default-theme "$OLD_THEME"; exit 1; }
done
grep -qE "vmlinuz-linux-cachyos-lts" "$CFG" && echo "  OK   LTS fallback kernel present" || echo "  info LTS kernel not in menu"

echo "== 3. Rebuilding initramfs (mkinitcpio -P)"
if ! mkinitcpio -P; then
  echo "!! mkinitcpio FAILED — switching back to '$OLD_THEME' and rebuilding"
  plymouth-set-default-theme "$OLD_THEME"
  mkinitcpio -P && echo "  Restored previous initramfs successfully."
  exit 1
fi

echo "== 4. Verifying images"
ok=1
for img in /boot/initramfs-*.img; do
  if lsinitcpio "$img" | grep -q 'usr/share/plymouth/themes/bapirlo/bapirlo.script'; then
    echo "  OK   $img contains the Kuro theme"
  else
    echo "  FAIL $img is missing the theme"; ok=0
  fi
done
[ "$ok" -eq 1 ] && echo "Plymouth done. Initramfs rebuilt successfully." || echo "!! Check output above."
