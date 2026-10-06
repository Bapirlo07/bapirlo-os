#!/usr/bin/env bash
# Bapirlo OS — make boot + login fit every screen (laptop panel AND the HDMI monitor). Run with sudo.
#   sudo bash ~/bapirlo-os/65-multimonitor.sh            apply
#   sudo bash ~/bapirlo-os/65-multimonitor.sh restore    undo (from the backup this script made)
#
#  * Plymouth: new bapirlo.script — each screen gets its own copy of the scene laid out for
#    its own size (before: the 1920x1080 monitor showed a cut-out middle of the 2560x1600 scene).
#    The theme lives in the initramfs, so this rebuilds it (mkinitcpio -P) and verifies.
#  * LightDM: display-setup-script that switches on the NVIDIA-driven HDMI monitor at login
#    (it was left dark/frozen) and puts it right of the panel, like GNOME. Log:
#    /var/log/bapirlo-displays.log
#
# Touches only the Plymouth theme script, /etc/lightdm/lightdm.conf (+ one new script) and the
# initramfs images. GRUB, partitions, fstab and the ESP are not touched.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
U=${SUDO_USER:?run via sudo}; U_HOME=$(getent passwd "$U" | cut -d: -f6)
B="$U_HOME/bapirlo-os/build"
PSCRIPT=/usr/share/plymouth/themes/bapirlo-kuro/bapirlo.script
LCONF=/etc/lightdm/lightdm.conf
DSS=/etc/lightdm/bapirlo-displays.sh
PTR="$U_HOME/theme-backups/LATEST-MULTIMONITOR"

# mkinitcpio copies the installed theme at build time; confirm the script is in every image
check_initramfs() {
  local ok=1 img
  for img in /boot/initramfs-*.img; do
    if lsinitcpio "$img" | grep -qx "${PSCRIPT#/}"; then echo "  OK   $(basename "$img"): bapirlo.script inside"
    else echo "  FAIL $(basename "$img"): bapirlo.script missing"; ok=0; fi
  done
  [ "$ok" -eq 1 ]
}

if [ "${1:-}" = restore ]; then
  BK=$(cat "$PTR"); [ -f "$BK$PSCRIPT" ] || { echo "No multimonitor backup at $BK"; exit 1; }
  echo "Restoring from $BK"
  cp -a "$BK$PSCRIPT" "$PSCRIPT"
  cp -a "$BK$LCONF" "$LCONF"
  rm -f "$DSS"
  echo "== Rebuilding initramfs"; mkinitcpio -P
  check_initramfs || echo "!! initramfs check failed — run: sudo mkinitcpio -P"
  echo "Restored. Reboot to see it."; exit 0
fi

NEW_PS="$B/plymouth-v2/bapirlo/bapirlo.script"; NEW_DSS="$B/lightdm-v2/bapirlo-displays.sh"
grep -q "fun sync_displays" "$NEW_PS" && [ -f "$NEW_DSS" ] \
  || { echo "Build output missing — run: python3 ~/bapirlo-os/tools/build-plymouth-v2.py && python3 ~/bapirlo-os/tools/build-lightdm-v2.py"; exit 1; }
[ -f "$PSCRIPT" ] || { echo "Plymouth theme bapirlo-kuro not installed ($PSCRIPT)"; exit 1; }

# ------------------------------------------------------------------ 0. backup
BK="$U_HOME/theme-backups/$(date +%Y%m%d-%H%M%S)-multimonitor"
echo "== 0. Backing up to $BK"
for p in "$PSCRIPT" "$LCONF"; do mkdir -p "$BK$(dirname "$p")"; cp -a "$p" "$BK$p"; echo "  saved $p"; done
echo "$BK" > "$PTR"; chown -R "$U": "$BK" "$PTR"
revert() {
  echo "!! Reverting"; cp -a "$BK$PSCRIPT" "$PSCRIPT"; cp -a "$BK$LCONF" "$LCONF"; rm -f "$DSS"
  mkinitcpio -P >/dev/null 2>&1 || echo "!! mkinitcpio failed during revert — run: sudo mkinitcpio -P"
}

# ------------------------------------------------------------------ 1. LightDM
echo "== 1. LightDM: display-setup-script"
install -m 755 "$NEW_DSS" "$DSS"
# set display-setup-script inside the real [Seat:*] section (the one holding greeter-session=)
sed -i '/^display-setup-script=/d' "$LCONF"
sed -i "0,/^greeter-session=/s||display-setup-script=$DSS\n&|" "$LCONF"
grep -qx "display-setup-script=$DSS" "$LCONF" || { echo "!! could not edit $LCONF"; revert; exit 1; }
grep -nE '^\[|^(greeter-session|display-setup-script|user-session)=' "$LCONF" | sed 's/^/  /'

# ------------------------------------------------------------------ 2. Plymouth + initramfs
echo "== 2. Plymouth script -> $PSCRIPT"
install -m 644 "$NEW_PS" "$PSCRIPT"
echo "== 3. Rebuilding initramfs (mkinitcpio -P)"
if ! mkinitcpio -P; then revert; exit 1; fi
check_initramfs || { revert; exit 1; }

echo
echo "Done. Reboot to see it. After the reboot you can check the login-screen log:"
echo "  cat /var/log/bapirlo-displays.log"
echo "Undo: sudo bash ~/bapirlo-os/65-multimonitor.sh restore"
