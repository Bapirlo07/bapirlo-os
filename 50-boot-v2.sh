#!/usr/bin/env bash
# Kuro OS — install the "Kuro" boot experience (run with sudo, AFTER approving the preview).
#   sudo bash ~/bapirlo-os/50-boot-v2.sh
#
#  0. full backup  -> ~/theme-backups/<timestamp>-boot-v2/   (incl. current initramfs images)
#  1. GRUB theme   -> /boot/grub/themes/bapirlo-kuro  (old 'bapirlo' theme kept)
#  2. GRUB config  -> native 2560x1600, 3 s timeout, quiet/flicker-free cmdline,
#                     "Windows" label + hide circular "CachyOS" firmware entry (via our own
#                     /etc/grub.d/31_bapirlo_bootnext wrapper; package files untouched)
#  3. grub-mkconfig to a TEMP file, verified (Linux + Windows + theme) before it replaces grub.cfg
#  4. Plymouth     -> theme 'bapirlo-kuro', DeviceScale=1, ShowDelay=0
#  5. Early KMS    -> i915 first in MODULES (internal panel is on the Intel GPU; NVIDIA follows)
#  6. mkinitcpio -P, verified (theme + i915 + font inside every image); auto-rollback on failure
#  7. LightDM      -> same artwork as the splash, palette CSS for the greeter
#
# Never touches partitions, fstab, the EFI partition, or grub-install.
# Restore everything from this run:   sudo bash ~/bapirlo-os/restore-boot-v2.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
U=${SUDO_USER:?run via sudo}; U_HOME=$(getent passwd "$U" | cut -d: -f6)
B="$U_HOME/bapirlo-os/build"
for f in "$B/grub-v2/bapirlo/theme.txt" "$B/plymouth-v2/bapirlo/bapirlo.script" "$B/lightdm-v2/login.png"; do
  [ -f "$f" ] || { echo "Missing build output: $f"; exit 1; }
done
CFG=/boot/grub/grub.cfg; NEW=/boot/grub/grub.cfg.kuro-new
GTHEME=/boot/grub/themes/bapirlo-kuro
PTHEME=/usr/share/plymouth/themes/bapirlo-kuro
WRAP=/etc/grub.d/31_bapirlo_bootnext

# ------------------------------------------------------------------ 0. backup
BK="$U_HOME/theme-backups/$(date +%Y%m%d-%H%M%S)-boot-v2"
echo "== 0. Backing up to $BK"
mkdir -p "$BK"
for p in /etc/default/grub /boot/grub/grub.cfg /etc/grub.d /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d \
         /etc/plymouth /etc/lightdm /var/lib/lightdm/.config/gtk-3.0 /etc/pacman.d/hooks \
         /boot/grub/themes /usr/share/plymouth/themes/bapirlo /usr/share/themes/WhiteSur-Dark-red; do
  if [ -e "$p" ]; then mkdir -p "$BK$(dirname "$p")"; cp -a "$p" "$BK$p"; echo "  saved $p"; else echo "  absent $p"; fi
done
mkdir -p "$BK/boot"; cp -a /boot/initramfs-*.img "$BK/boot/"; echo "  saved /boot/initramfs-*.img"
plymouth-set-default-theme > "$BK/plymouth-theme.txt"
grep -E '^\s*(menuentry|submenu)' "$CFG" | sed -E "s/^\s*(menuentry|submenu) '([^']*)'.*/\1: \2/" > "$BK/grub-entries-before.txt"
echo "$BK" > "$U_HOME/theme-backups/LATEST-BOOT-V2"
chown -R "$U": "$BK" "$U_HOME/theme-backups/LATEST-BOOT-V2"
echo "  entries before:"; sed 's/^/    /' "$BK/grub-entries-before.txt"

restore_grub_files() {
  cp -a "$BK/etc/default/grub" /etc/default/grub
  rm -f "$WRAP" "$NEW"
}

# ------------------------------------------------------------------ 1. GRUB theme
echo "== 1. GRUB theme -> $GTHEME"
rm -rf "$GTHEME"; cp -r "$B/grub-v2/bapirlo" "$GTHEME"; chown -R root:root "$GTHEME"

# ------------------------------------------------------------------ 2. /etc/default/grub
echo "== 2. /etc/default/grub"
setkey() {  # setkey KEY VALUE — replace (even if commented) or append
  if grep -qE "^#?\s*$1=" /etc/default/grub; then sed -i -E "s|^#?\s*$1=.*|$1=\"$2\"|" /etc/default/grub
  else echo "$1=\"$2\"" >> /etc/default/grub; fi
}
setkey GRUB_THEME "$GTHEME/theme.txt"
setkey GRUB_GFXMODE "2560x1600x32,2560x1600,1920x1200,auto"
setkey GRUB_GFXPAYLOAD_LINUX "keep"
setkey GRUB_TIMEOUT "3"
setkey GRUB_TIMEOUT_STYLE "menu"
setkey GRUB_DISABLE_BOOTNEXT "true"          # stock 31_efi_bootnext silenced; our wrapper runs it
# kernel cmdline: keep whatever is there, add the quiet/flicker-free set if missing
cur=$(sed -nE 's/^GRUB_CMDLINE_LINUX_DEFAULT="([^"]*)".*/\1/p' /etc/default/grub)
for a in quiet splash loglevel=3 rd.udev.log_level=3 systemd.show_status=auto rd.systemd.show_status=auto \
         vt.global_cursor_default=0; do
  case " $cur " in *" ${a%%=*}="*|*" $a "*) ;; *) cur="$cur $a" ;; esac
done
setkey GRUB_CMDLINE_LINUX_DEFAULT "$(echo $cur)"
grep -nE '^GRUB_(THEME|GFXMODE|GFXPAYLOAD_LINUX|TIMEOUT|TIMEOUT_STYLE|DISABLE_BOOTNEXT|CMDLINE_LINUX_DEFAULT)=' /etc/default/grub | sed 's/^/  /'

cat > "$WRAP" <<'EOF'
#!/bin/sh
# Kuro OS: EFI BootNext entries, relabelled. The stock 31_efi_bootnext is silenced with
# GRUB_DISABLE_BOOTNEXT=true in /etc/default/grub; here we run it with the switch off and
#   * show "Windows Boot Manager (EFI BootNext)" as "Windows"
#   * drop "CachyOS (EFI BootNext)" — that firmware entry is THIS grub (\EFI\CachyOS\grubx64.efi)
#     and would only reboot back into this menu.
# To undo: delete this file and the GRUB_DISABLE_BOOTNEXT line, then grub-mkconfig.
GRUB_DISABLE_BOOTNEXT=false /etc/grub.d/31_efi_bootnext | awk '
  /^if \[ "\$grub_platform" = "efi" \]; then$/ { buf = $0 "\n"; inblk = 1; next }
  inblk { buf = buf $0 "\n"
          if ($0 ~ /^fi$/) {
            inblk = 0
            if (buf ~ /menuentry .CachyOS \(EFI BootNext\)/) next
            gsub(/menuentry .Windows Boot Manager \(EFI BootNext\)./, "menuentry '\''Windows'\''", buf)
            printf "%s", buf
          }
          next }
  { print }'
EOF
chmod 755 "$WRAP"

# ------------------------------------------------------------------ 3. grub.cfg (temp + verify)
echo "== 3. grub-mkconfig -> $NEW"
if ! grub-mkconfig -o "$NEW"; then echo "!! grub-mkconfig failed — reverting"; restore_grub_files; exit 1; fi
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
ck "timeout 3"                        "set timeout=3"
if grep -q "CachyOS (EFI BootNext)" "$NEW"; then echo "  FAIL circular CachyOS entry still present"; fail=1; else echo "  OK   circular CachyOS entry hidden"; fi
if [ "$fail" -ne 0 ]; then echo "!! Verification failed — reverting; $CFG NOT changed"; restore_grub_files; exit 1; fi
mv "$NEW" "$CFG"
echo "  installed. Entries now:"
grep -E '^\s*(menuentry|submenu)' "$CFG" | sed -E "s/^\s*(menuentry|submenu) '([^']*)'.*/    \1: \2/"

# ------------------------------------------------------------------ 4. Plymouth
echo "== 4. Plymouth theme -> $PTHEME"
rm -rf "$PTHEME"; cp -r "$B/plymouth-v2/bapirlo" "$PTHEME"
mv "$PTHEME/bapirlo.plymouth" "$PTHEME/bapirlo-kuro.plymouth"
sed -i "s|/usr/share/plymouth/themes/bapirlo$|$PTHEME|; s|/usr/share/plymouth/themes/bapirlo/|$PTHEME/|" "$PTHEME/bapirlo-kuro.plymouth"
chown -R root:root "$PTHEME"; chmod -R a+rX "$PTHEME"
plymouth-set-default-theme bapirlo-kuro
conf=/etc/plymouth/plymouthd.conf
grep -q '^\[Daemon\]' "$conf" 2>/dev/null || echo "[Daemon]" >> "$conf"
for kv in "ShowDelay=0" "DeviceScale=1"; do
  k=${kv%%=*}
  if grep -qE "^$k=" "$conf"; then sed -i "s|^$k=.*|$kv|" "$conf"; else sed -i "/^\[Daemon\]/a $kv" "$conf"; fi
done
sed 's/^/  /' "$conf"

# ------------------------------------------------------------------ 5. early KMS order
echo "== 5. mkinitcpio MODULES: i915 first"
if grep -qE '^MODULES=\(([^)]*\s)?i915(\s[^)]*)?\)' /etc/mkinitcpio.conf; then
  echo "  i915 already listed"
else
  sed -i -E 's/^MODULES=\((.*)\)/MODULES=(i915 \1)/; s/^MODULES=\(i915 \)/MODULES=(i915)/' /etc/mkinitcpio.conf
fi
grep -E '^(MODULES|HOOKS)=' /etc/mkinitcpio.conf | sed 's/^/  /'

# ------------------------------------------------------------------ 6. initramfs
echo "== 6. mkinitcpio -P"
initramfs_rollback() {
  echo "!! Rolling back Plymouth theme + mkinitcpio.conf and restoring the saved initramfs images"
  cp -a "$BK/etc/mkinitcpio.conf" /etc/mkinitcpio.conf
  rm -rf /etc/plymouth; cp -a "$BK/etc/plymouth" /etc/plymouth
  plymouth-set-default-theme "$(cat "$BK/plymouth-theme.txt")"
  cp -a "$BK"/boot/initramfs-*.img /boot/
  echo "!! Boot images are exactly as before. GRUB theme stays installed (harmless)."
}
if ! mkinitcpio -P; then initramfs_rollback; exit 1; fi
ok=1
for img in /boot/initramfs-*.img; do
  list=$(lsinitcpio "$img")
  for need in "usr/share/plymouth/themes/bapirlo-kuro/bapirlo.script" "i915.ko" "usr/share/fonts/Plymouth.ttf"; do
    if grep -q "$need" <<<"$list"; then echo "  OK   $(basename "$img"): $need"; else echo "  FAIL $(basename "$img"): $need"; ok=0; fi
  done
done
if [ "$ok" -ne 1 ]; then initramfs_rollback; mkinitcpio -P >/dev/null 2>&1 || true; exit 1; fi
# early-load order inside the image: i915 must come before nvidia
echo "  early module order: $(bash -c 'source /etc/mkinitcpio.conf; for f in /etc/mkinitcpio.conf.d/*.conf; do [ -e "$f" ] && source "$f"; done; echo "${MODULES[*]}"')"

# ------------------------------------------------------------------ 7. LightDM
echo "== 7. LightDM greeter"
install -d -m 755 /usr/share/backgrounds/bapirlo
install -m 644 "$B/lightdm-v2/login.png" /usr/share/backgrounds/bapirlo/login-kuro.png
install -m 644 "$B/lightdm-v2/badge.png" /usr/share/backgrounds/bapirlo/badge-kuro.png
install -m 644 "$B/lightdm-v2/slick-greeter.conf" /etc/lightdm/slick-greeter.conf
LDH=$(getent passwd lightdm | cut -d: -f6)
install -d -o lightdm -g lightdm -m 755 "$LDH/.config" "$LDH/.config/gtk-3.0"
install -o lightdm -g lightdm -m 644 "$B/lightdm-v2/gtk.css" "$LDH/.config/gtk-3.0/gtk.css"
# greeter's system-wide GTK theme: refresh from the crimson-recoloured user copy (only if it is ours)
if grep -qxF /usr/share/themes/WhiteSur-Dark-red "$U_HOME/theme-backups/$(cat "$U_HOME/theme-backups/LATEST")/system/installed-system-paths.txt" 2>/dev/null; then
  rm -rf /usr/share/themes/WhiteSur-Dark-red; cp -a "$U_HOME/.themes/WhiteSur-Dark-red" /usr/share/themes/WhiteSur-Dark-red
  chown -R root:root /usr/share/themes/WhiteSur-Dark-red; chmod -R a+rX /usr/share/themes/WhiteSur-Dark-red
  echo "  OK   /usr/share/themes/WhiteSur-Dark-red refreshed (crimson)"
fi
sudo -u lightdm test -r /usr/share/backgrounds/bapirlo/login-kuro.png && echo "  OK   greeter can read its background"
grep -q '^greeter-session=lightdm-slick-greeter' /etc/lightdm/lightdm.conf && echo "  OK   lightdm still uses slick-greeter"

cat <<EOF

=====================================================================
 Kuro OS "Kuro" boot experience installed.  Backup: $BK

 If anything looks wrong after reboot, from the GRUB menu pick Kuro OS
 (or press E and remove 'splash' from the linux line for a text boot), then:

   sudo bash $U_HOME/bapirlo-os/restore-boot-v2.sh

 That puts back /etc/default/grub, /etc/grub.d, grub.cfg, plymouth, mkinitcpio.conf,
 lightdm and the exact initramfs images saved above.
=====================================================================
EOF
