#!/usr/bin/env bash
# Kuro OS — restore everything from a backup.
#   User settings only:   bash ~/bapirlo-os/restore.sh user   [backup-dir]
#   System (boot/login):  sudo bash ~/bapirlo-os/restore.sh system [backup-dir]
# Default backup-dir = the first backup taken (~/theme-backups/LATEST).
set -euo pipefail
MODE=${1:?usage: restore.sh user|system [backup-dir]}
U=${SUDO_USER:-$USER}; U_HOME=$(getent passwd "$U" | cut -d: -f6)
B=${2:-"$U_HOME/theme-backups/$(cat "$U_HOME/theme-backups/LATEST")"}
[ -d "$B" ] || { echo "no backup at $B"; exit 1; }
echo "Restoring $MODE from $B"

if [ "$MODE" = user ]; then
  [ "$(id -u)" -ne 0 ] || { echo "run 'user' mode WITHOUT sudo"; exit 1; }
  # Disable everything Kuro enabled, then restore dconf exactly
  for e in $(gnome-extensions list --enabled); do
    grep -qx "$e" "$B/user/extensions-enabled.txt" || gnome-extensions disable "$e" || true
  done
  dconf reset -f /
  dconf load / < "$B/user/dconf-full.ini"
  # Restore/remove user theme dirs (absent in backup = didn't exist before)
  for d in .config/gtk-3.0 .config/gtk-4.0 .config/fastfetch .themes .icons \
           .local/share/icons .local/share/themes .local/share/gnome-shell/extensions \
           .config/burn-my-windows .local/share/backgrounds/bapirlo; do
    rm -rf "$U_HOME/$d"
    [ -e "$B/user/$d" ] && cp -a "$B/user/$d" "$U_HOME/$d"
  done
  rm -f "$U_HOME/.local/bin/gnome-theme-switcher" \
        "$U_HOME/.local/share/applications/org.gnome.GTK4ThemeSwitcher.desktop"
  systemctl --user disable --now bapirlo-wallpaper.path 2>/dev/null || true
  rm -f "$U_HOME/.config/systemd/user/bapirlo-wallpaper."{path,service}
  echo "User settings restored. Log out and back in."

elif [ "$MODE" = system ]; then
  [ "$(id -u)" -eq 0 ] || { echo "run 'system' mode WITH sudo"; exit 1; }
  S="$B/system"
  cp -a "$S/etc/default/grub" /etc/default/grub
  [ -d "$S/etc/grub.d" ] && cp -a "$S/etc/grub.d/." /etc/grub.d/
  rm -rf /etc/lightdm && cp -a "$S/etc/lightdm" /etc/lightdm
  [ -e "$S/etc/plymouth/plymouthd.conf" ] && cp -a "$S/etc/plymouth/plymouthd.conf" /etc/plymouth/plymouthd.conf
  cp -a "$S/etc/mkinitcpio.conf" /etc/mkinitcpio.conf
  plymouth-set-default-theme "$(cat "$S/plymouth-theme.txt")"
  rm -rf /boot/grub/themes/bapirlo /usr/share/plymouth/themes/bapirlo
  rm -f /etc/pacman.d/hooks/95-bapirlo-grub-name.hook
  # system-wide copies made by 30-lightdm.sh (only paths it recorded as its own)
  if [ -f "$S/installed-system-paths.txt" ]; then
    while IFS= read -r p; do
      case "$p" in /usr/share/themes/*|/usr/share/icons/*|/usr/share/backgrounds/bapirlo) rm -rf "$p"; echo "removed $p";; esac
    done < "$S/installed-system-paths.txt"
  fi
  echo "Rebuilding initramfs..."; mkinitcpio -P
  echo "Regenerating GRUB..."; grub-mkconfig -o /boot/grub/grub.cfg
  echo; echo "Entries now:"; grep -E '^\s*(menuentry|submenu)' /boot/grub/grub.cfg | cut -c1-120
  echo "Entries before theming:"; cat "$S/grub-entries-before.txt"
fi
