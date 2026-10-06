#!/usr/bin/env bash
# Bapirlo OS round 2 — the parts that need your password. Run as YOURSELF (it asks for sudo itself).
#   bash ~/bapirlo-os/200-round2-install.sh            # backup + packages + MSI + hostname
#   bash ~/bapirlo-os/200-round2-install.sh restore    # undo (asks pacman to remove what it added)
#
# 1. pacman (official repos): dkms matugen mangohud lib32-mangohud gpu-screen-recorder
#                              evolution-data-server gvfs-goa rclone
# 2. paru (AUR, as you — review each PKGBUILD when paru shows it):
#      msi-ec-dkms-git        upstream msi-ec driver; it knows your EC firmware 15P3EMS1.103
#      visual-studio-code-bin official Microsoft VS Code
# 3. msi-ec loaded → bapirlo-perfd (root service): charge limit 80 %, AC → Turbo, battery → Eco,
#    profile ↔ MSI shift/fan mode. MControlCenter (already installed) works once msi-ec is loaded.
# 4. hostname bapirlo-os (pretty name "Bapirlo OS"), /etc/hosts updated to match.
# Never touches partitions, fstab, EFI or the bootloader.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as yourself, WITHOUT sudo (paru must not run as root)."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
R=$HERE/round2/root
LATEST=~/theme-backups/LATEST-ROUND2-INSTALL
PKGS=(dkms matugen mangohud lib32-mangohud gpu-screen-recorder evolution-data-server gvfs-goa rclone)
AUR=(msi-ec-dkms-git visual-studio-code-bin)
IS_MSI=0; grep -q "Micro-Star" /sys/class/dmi/id/sys_vendor 2>/dev/null && IS_MSI=1
[ $IS_MSI = 1 ] || AUR=(visual-studio-code-bin)     # the MSI EC driver only makes sense on MSI laptops
NEW_HOST=bapirlo-os
FILES=(/usr/local/lib/bapirlo/bapirlo-perfd /etc/bapirlo/perfd.conf /etc/systemd/system/bapirlo-perfd.service)

apply() {
  sudo -v
  # install.sh takes its own "Before Bapirlo OS" snapshot and sets BAPIRLO_INSTALLER=1
  if [ -z "${BAPIRLO_INSTALLER:-}" ] && ! sudo timeshift --list 2>/dev/null | grep -q "Before round 2"; then
    echo "No Timeshift snapshot \"Before round 2\" yet. Take it first:"
    echo "  sudo timeshift --create --comments \"Before round 2\" --tags O"
    exit 1
  fi
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round2-install
  mkdir -p "$BK"
  pacman -Q > "$BK/packages-before.txt"
  cp -a /etc/hostname /etc/hosts "$BK/"
  [ -f /etc/machine-info ] && cp -a /etc/machine-info "$BK/"
  for f in "${FILES[@]}"; do [ -e "$f" ] && echo "$f" >> "$BK/preexisting.txt"; done; touch "$BK/preexisting.txt"
  cat /sys/class/power_supply/BAT1/charge_control_end_threshold > "$BK/charge-limit.txt" 2>/dev/null || echo 100 > "$BK/charge-limit.txt"
  powerprofilesctl get > "$BK/profile.txt" 2>/dev/null || true
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo; echo "== 1/4 official packages"
  sudo pacman -S --needed "${PKGS[@]}"

  echo; echo "== 2/4 AUR packages (paru shows each PKGBUILD — read, then confirm)"
  paru -S --needed "${AUR[@]}"

  echo; echo "== 3/4 MSI: msi-ec driver + power glue"
  if [ $IS_MSI = 1 ]; then
    sudo modprobe -r msi_ec 2>/dev/null || true
    sudo modprobe msi_ec
    modinfo -n msi_ec
  fi
  if [ $IS_MSI = 0 ]; then
    echo "not an MSI laptop — skipping msi-ec (perfd still switches power profiles on AC/battery)"
  elif [ -r /sys/devices/platform/msi-ec/fw_version ]; then
    echo "msi-ec OK — EC firmware $(cat /sys/devices/platform/msi-ec/fw_version)"
    echo "shift modes: $(cat /sys/devices/platform/msi-ec/available_shift_modes | tr '\n' ' ')"
    echo "fan modes:   $(cat /sys/devices/platform/msi-ec/available_fan_modes | tr '\n' ' ')"
  else
    echo "!! msi-ec did not attach — check: sudo dmesg | grep msi_ec   (continuing; perfd will just skip the EC)"
  fi
  sudo install -Dm755 "$R/bapirlo-perfd" /usr/local/lib/bapirlo/bapirlo-perfd
  [ -e /etc/bapirlo/perfd.conf ] || sudo install -Dm644 "$R/perfd.conf" /etc/bapirlo/perfd.conf
  sudo install -Dm644 "$R/bapirlo-perfd.service" /etc/systemd/system/bapirlo-perfd.service
  sudo systemctl daemon-reload
  sudo systemctl enable --now bapirlo-perfd
  sleep 3
  echo "charge limit now: $(cat /sys/class/power_supply/BAT1/charge_control_end_threshold 2>/dev/null || echo n/a) %   profile: $(powerprofilesctl get)"

  echo; echo "== 4/4 hostname → $NEW_HOST"
  local OLD; OLD=$(cat /etc/hostname)
  sudo hostnamectl set-hostname "$NEW_HOST"
  sudo hostnamectl set-hostname --pretty "Bapirlo OS"
  sudo sed -i -E "s/^(127\.0\.1\.1[[:space:]]+)${OLD}\$/\1${NEW_HOST}/" /etc/hosts
  grep -q "^127\.0\.1\.1[[:space:]]\+${NEW_HOST}\$" /etc/hosts || echo "127.0.1.1  $NEW_HOST" | sudo tee -a /etc/hosts >/dev/null
  hostnamectl | sed -n 1,3p

  echo; echo "All done. Tell Claude — it will apply the desktop side next."
  echo "Reboot once when convenient (new hostname everywhere + msi-ec from boot)."
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "undoing round-2 install step (backup $BK)"
  sudo systemctl disable --now bapirlo-perfd 2>/dev/null || true
  for f in "${FILES[@]}"; do grep -qx "$f" "$BK/preexisting.txt" || sudo rm -f "$f"; done
  sudo systemctl daemon-reload
  [ -e /sys/class/power_supply/BAT1/charge_control_end_threshold ] && \
    cat "$BK/charge-limit.txt" | sudo tee /sys/class/power_supply/BAT1/charge_control_end_threshold >/dev/null || true
  [ -s "$BK/profile.txt" ] && powerprofilesctl set "$(cat "$BK/profile.txt")" || true
  sudo install -m644 "$BK/hostname" /etc/hostname
  sudo install -m644 "$BK/hosts" /etc/hosts
  sudo hostnamectl set-hostname "$(cat "$BK/hostname")"
  if [ -f "$BK/machine-info" ]; then sudo install -m644 "$BK/machine-info" /etc/machine-info; else sudo hostnamectl set-hostname --pretty ""; fi
  local rm=()
  for p in "${PKGS[@]}" "${AUR[@]}"; do
    grep -q "^$p " "$BK/packages-before.txt" || { pacman -Q "$p" >/dev/null 2>&1 && rm+=("$p"); }
  done
  [ ${#rm[@]} -gt 0 ] && sudo pacman -Rns "${rm[@]}"
  sudo modprobe -r msi_ec 2>/dev/null || true
  echo "done (reboot to be back on the stock kernel msi-ec state)"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
