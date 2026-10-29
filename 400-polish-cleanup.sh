#!/usr/bin/env bash
# Kuro OS polish — step 1: remove the leftovers the audit found. Run as YOURSELF (it asks for sudo itself).
#   bash ~/bapirlo-os/400-polish-cleanup.sh            # snapshot + backup + remove
#   bash ~/bapirlo-os/400-polish-cleanup.sh restore    # reinstall everything below (snapshot stays)
#
# 0. Timeshift snapshot "Before polish" FIRST — nothing else runs unless it succeeds
# 1. Openbox desktop leftovers: openbox obconf-qt tint2 rofi jgmenu picom lxappearance arandr
#    (+ the "Openbox" login entry and the old Onyx/Clearlooks/… themes, which belong to openbox)
# 2. Tray/notification clashes: pasystray (crashes at every login), dunst (second notification daemon)
# 3. Duplicate apps: thunar + 3 plugins, xfce4-terminal, xed, ptyxis  (evince stays — sushi needs it)
# 4. Unused dock: gnome-shell-extension-dash-to-dock + the disabled Compiz windows effect (user extension)
# pacman -Rns also removes 13 libraries only these used (vte4, libxfce4ui, xfconf, exo, …).
# Your own config folders (~/.config/tint2, xfce4, xed) are copied to the backup and left in place.
# Never touches partitions, fstab, EFI or the bootloader.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as yourself, WITHOUT sudo."; exit 1; }
LATEST=~/theme-backups/LATEST-POLISH-CLEANUP
PKGS=(openbox obconf-qt tint2 rofi jgmenu picom lxappearance arandr
      pasystray dunst
      thunar thunar-archive-plugin thunar-media-tags-plugin thunar-volman xfce4-terminal xed ptyxis
      gnome-shell-extension-dash-to-dock)
COMPIZ=compiz-windows-effect@hermes83.github.com
EXT_DIR=~/.local/share/gnome-shell/extensions

apply() {
  sudo -v
  echo "== 0/3 Timeshift snapshot \"Before polish\" (incremental — a few minutes)"
  if sudo timeshift --list --scripted 2>/dev/null | grep -q "Before polish"; then
    echo "already there:"
  else
    sudo timeshift --create --scripted --comments "Before polish" --tags O
    sudo timeshift --list --scripted | grep -q "Before polish" || { echo "!! snapshot missing — stopping, nothing changed."; exit 1; }
  fi
  sudo timeshift --list --scripted | grep "Before polish"

  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-polish-cleanup
  mkdir -p "$BK/etc" "$BK/config"
  pacman -Q > "$BK/packages-before.txt"
  local present=()
  for p in "${PKGS[@]}"; do pacman -Q "$p" &>/dev/null && present+=("$p"); done
  printf '%s\n' "${present[@]}" > "$BK/removed-explicit.txt"
  # /etc files pacman tracks as config for these packages (-n would delete them)
  pacman -Qii "${present[@]}" 2>/dev/null | awk '/^Backup Files/{f=1; sub(/^Backup Files *: */,"")} /^$/{f=0} f && $1 ~ /^\// {print $1}' \
    | while read -r f; do [ -e "$f" ] && sudo cp -a --parents "$f" "$BK/etc/"; done
  for d in tint2 xfce4 xed Thunar rofi dunst picom openbox jgmenu; do
    [ -e ~/.config/$d ] && cp -a ~/.config/$d "$BK/config/"
  done
  [ -d "$EXT_DIR/$COMPIZ" ] && cp -a "$EXT_DIR/$COMPIZ" "$BK/"
  sudo chown -R "$USER:" "$BK"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo; echo "== 1/3 removing packages (pacman shows the full list and asks before doing anything)"
  if [ ${#present[@]} -gt 0 ]; then
    sudo pacman -Rns "${present[@]}"
    pacman -Q > "$BK/packages-after.txt"
    comm -23 <(sort "$BK/packages-before.txt") <(sort "$BK/packages-after.txt") | awk '{print $1}' > "$BK/removed-all.txt"
  else
    echo "nothing left to remove"
  fi

  echo; echo "== 2/3 Compiz windows effect (disabled user extension)"
  if [ -d "$EXT_DIR/$COMPIZ" ]; then gnome-extensions uninstall "$COMPIZ" 2>/dev/null || rm -rf "${EXT_DIR:?}/$COMPIZ"; echo "removed"; else echo "already gone"; fi

  echo; echo "== 3/3 check"
  for p in "${PKGS[@]}"; do pacman -Q "$p" &>/dev/null && echo "   still installed: $p"; done
  ls /usr/share/xsessions 2>/dev/null; ls /usr/share/wayland-sessions
  echo "done. Undo: bash ~/bapirlo-os/400-polish-cleanup.sh restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  sudo -v
  if [ -s "$BK/removed-all.txt" ]; then
    sudo pacman -S --needed $(cat "$BK/removed-explicit.txt")
    # libraries come back as dependencies; mark the originals explicit again
    sudo pacman -D --asexplicit $(cat "$BK/removed-explicit.txt") >/dev/null
  fi
  [ -d "$BK/etc" ] && sudo cp -a "$BK/etc/." /
  [ -d "$BK/$COMPIZ" ] && cp -a "$BK/$COMPIZ" "$EXT_DIR/"
  echo "restored from $BK (log out/in for the extension)"
}

case "${1:-}" in
  "") apply ;;
  restore) restore ;;
  *) sed -n 2,4p "$0"; exit 1 ;;
esac
