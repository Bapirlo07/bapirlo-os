#!/usr/bin/env bash
# Bapirlo OS — Hyprland as a SECOND login session. The parts that need your password.
# Run as YOURSELF (it asks for sudo itself).
#   bash ~/bapirlo-os/1500-hyprland-install.sh            # snapshot + packages + login entry
#   bash ~/bapirlo-os/1500-hyprland-install.sh restore    # remove the login entry + the packages it added
#
# 0. Timeshift snapshot "Before Hyprland" FIRST — nothing else runs unless it succeeds
# 1. packages: hyprland + portal, waybar, fuzzel, mako, hyprlock, hypridle, mpvpaper (live wallpaper),
#    hyprshot/grim/slurp, cliphist, swayosd, brightnessctl, hyprpolkitagent, blueman, qt5-wayland
# 2. login entry "Bapirlo Hyprland" (/usr/share/wayland-sessions/bapirlo-hyprland.desktop) →
#    ~/bapirlo-os/bin/bapirlo-hyprland-session (pins the Intel GPU)
# GNOME stays the default session; nothing in GNOME, LightDM's config, GRUB or boot is touched.
# Then run (no sudo):  bash ~/bapirlo-os/1510-hyprland.sh
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as yourself, WITHOUT sudo."; exit 1; }
LATEST=~/theme-backups/LATEST-HYPRLAND-INSTALL
SESSION=/usr/share/wayland-sessions/bapirlo-hyprland.desktop
PKGS=(hyprland xdg-desktop-portal-hyprland waybar fuzzel mako hyprlock hypridle mpvpaper
      hyprshot grim slurp cliphist swayosd brightnessctl hyprpolkitagent blueman qt5-wayland)

apply() {
  sudo -v
  echo "== 0/2 Timeshift snapshot \"Before Hyprland\" (incremental — a few minutes)"
  if ! sudo timeshift --list --scripted 2>/dev/null | grep -q "Before Hyprland"; then
    sudo timeshift --create --scripted --comments "Before Hyprland" --tags O
    sudo timeshift --list --scripted | grep -q "Before Hyprland" || { echo "!! snapshot missing — stopping, nothing changed."; exit 1; }
  fi
  sudo timeshift --list --scripted | grep "Before Hyprland"

  if [ -s "$LATEST" ] && [ -d "$(cat "$LATEST")" ]; then
    echo "re-run: keeping the first backup -> $(cat "$LATEST")"
  else
    local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-hyprland-install
    mkdir -p "$BK"
    pacman -Qq > "$BK/packages-before.txt"
    echo "$BK" > "$LATEST"; echo "backup -> $BK"
  fi

  echo; echo "== 1/2 packages"
  sudo pacman -S --needed "${PKGS[@]}"

  echo; echo "== 2/2 login entry \"Bapirlo Hyprland\""
  sudo tee "$SESSION" >/dev/null <<EOF
[Desktop Entry]
Name=Bapirlo Hyprland
Comment=Tiling Wayland session, Bapirlo Kuro theme
Exec=$HOME/bapirlo-os/bin/bapirlo-hyprland-session
Type=Application
DesktopNames=Hyprland
EOF
  cat "$SESSION"
  grep -q "^user-session=gnome" /etc/lightdm/lightdm.conf && echo "   default session is still GNOME"

  echo; echo "Done. Now run (no sudo):  bash ~/bapirlo-os/1510-hyprland.sh"
}

restore() {
  local BK; BK=$(cat "$LATEST" 2>/dev/null || true)
  [ -d "$BK" ] || { echo "no backup at $LATEST"; exit 1; }
  sudo -v
  sudo rm -f "$SESSION"
  # only remove what this script added (anything you already had stays)
  mapfile -t added < <(comm -13 <(sort "$BK/packages-before.txt") <(pacman -Qq | sort))
  if [ "${#added[@]}" -gt 0 ]; then
    echo "removing: ${added[*]}"
    sudo pacman -Rns "${added[@]}"
  fi
  echo "Hyprland login entry and packages removed."
}

case "${1:-apply}" in
  apply) apply ;;
  restore) restore ;;
  *) echo "usage: $0 [restore]"; exit 1 ;;
esac
