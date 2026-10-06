#!/usr/bin/env bash
# Bapirlo OS — preview the new Plymouth splash WITHOUT rebooting and without changing
# the boot setup. Run from a text console, because your GNOME session owns the screen:
#
#   1. Ctrl+Alt+F3, log in
#   2. sudo bash ~/bapirlo-os/45-plymouth-preview.sh            # boot animation (12 s)
#      sudo bash ~/bapirlo-os/45-plymouth-preview.sh password   # + password prompt demo
#      sudo bash ~/bapirlo-os/45-plymouth-preview.sh shutdown   # shutdown look ("See you soon")
#      sudo bash ~/bapirlo-os/45-plymouth-preview.sh reboot     # reboot look ("Be right back")
#   3. Ctrl+Alt+F8 to get back to GNOME (your session runs on VT8)
#
# What it touches: copies the theme to /usr/share/plymouth/themes/bapirlo-kuro (inert —
# nothing uses it until 50-boot-v2.sh makes it the default). The current default theme,
# plymouthd.conf, GRUB and the initramfs are NOT changed.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
U_HOME=$(getent passwd "${SUDO_USER:?run via sudo}" | cut -d: -f6)
SRC="$U_HOME/bapirlo-os/build/plymouth-v2/bapirlo"
DST=/usr/share/plymouth/themes/bapirlo-kuro
WHAT=${1:-boot}
[ -f "$SRC/bapirlo.script" ] || { echo "Theme not built: $SRC"; exit 1; }

rm -rf "$DST"; cp -r "$SRC" "$DST"
mv "$DST/bapirlo.plymouth" "$DST/bapirlo-kuro.plymouth"
sed -i "s|/usr/share/plymouth/themes/bapirlo$|$DST|; s|/usr/share/plymouth/themes/bapirlo/|$DST/|" "$DST/bapirlo-kuro.plymouth"
chown -R root:root "$DST"; chmod -R a+rX "$DST"

case "$WHAT" in shutdown|reboot) MODE=$WHAT ;; *) MODE=boot ;; esac
cleanup() { plymouth quit 2>/dev/null || true; }
trap cleanup EXIT INT TERM

plymouthd --mode="$MODE" --tty="$(basename "$(tty)")" \
  --kernel-command-line="quiet splash plymouth.theme=bapirlo-kuro plymouth.ignore-serial-consoles"
plymouth show-splash
for i in $(seq 1 12); do
  plymouth update --status="preview-$i" || true
  sleep 1
done
if [ "$WHAT" = password ]; then
  plymouth display-message --text="Preview: type anything, then Enter"
  plymouth ask-for-password --prompt="Unlock to continue" --command="cat >/dev/null" || true
  plymouth hide-message --text="Preview: type anything, then Enter" || true
  sleep 2
fi
echo "Preview finished."
