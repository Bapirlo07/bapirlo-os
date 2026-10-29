#!/usr/bin/env bash
# Bapirlo OS round 14 — the parts that need your password. Run as YOURSELF (it asks for sudo itself).
#   bash ~/bapirlo-os/1400-round14-install.sh            # snapshot + backup + changes
#   bash ~/bapirlo-os/1400-round14-install.sh restore    # undo (snapshot stays; packages stay installed)
#
# 0. Timeshift snapshot "Before round 14" FIRST — nothing else runs unless it succeeds
# 1. packages: easyeffects + lsp-plugins-lv2 (speaker / headphone sound presets)
# 2. charge limit switch: /usr/local/lib/bapirlo/bapirlo-charge (accepts only 80 | 100 | status) +
#    polkit action os.bapirlo.charge-limit (no password for the person at the laptop) +
#    bapirlo-perfd now re-applies your choice (/var/lib/bapirlo/charge-limit) after boot / resume
# Then run (no sudo):  bash ~/bapirlo-os/1410-round14.sh
# Never touches Limine, GRUB, partitions, fstab or EFI.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as yourself, WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
LATEST=~/theme-backups/LATEST-ROUND14-INSTALL
LIB=/usr/local/lib/bapirlo
POLICY=/usr/share/polkit-1/actions/os.bapirlo.charge.policy

apply() {
  sudo -v
  echo "== 0/2 Timeshift snapshot \"Before round 14\" (incremental — a few minutes)"
  if ! sudo timeshift --list --scripted 2>/dev/null | grep -q "Before round 14"; then
    sudo timeshift --create --scripted --comments "Before round 14" --tags O
    sudo timeshift --list --scripted | grep -q "Before round 14" || { echo "!! snapshot missing — stopping, nothing changed."; exit 1; }
  fi
  sudo timeshift --list --scripted | grep "Before round 14"

  if [ -s "$LATEST" ] && [ -d "$(cat "$LATEST")" ]; then
    echo "re-run: keeping the first backup -> $(cat "$LATEST")"
  else
    local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round14-install
    mkdir -p "$BK"
    pacman -Q > "$BK/packages-before.txt"
    cp -a "$LIB/bapirlo-perfd" "$BK/"
    echo "$BK" > "$LATEST"; echo "backup -> $BK"
  fi

  echo; echo "== 1/2 EasyEffects + LSP plugins"
  sudo pacman -S --needed easyeffects lsp-plugins-lv2

  echo; echo "== 2/2 charge limit switch"
  sudo install -Dm755 "$HERE/round14/root/bapirlo-charge" "$LIB/bapirlo-charge"
  sudo install -Dm644 "$HERE/round14/root/os.bapirlo.charge.policy" "$POLICY"
  diff -u "$LIB/bapirlo-perfd" "$HERE/round2/root/bapirlo-perfd" | sed 's/^/   /' || true
  sudo install -Dm755 "$HERE/round2/root/bapirlo-perfd" "$LIB/bapirlo-perfd"
  [ -f /var/lib/bapirlo/charge-limit ] || { sudo mkdir -p /var/lib/bapirlo; echo 80 | sudo tee /var/lib/bapirlo/charge-limit >/dev/null; }
  sudo systemctl restart bapirlo-perfd.service
  sleep 1
  systemctl is-active bapirlo-perfd.service
  echo "   limit now: $(pkexec "$LIB/bapirlo-charge" status) %  (pkexec ran without a password = polkit OK)"

  echo; echo "Done. Now run (no sudo):  bash ~/bapirlo-os/1410-round14.sh"
}

restore() {
  local BK; BK=$(cat "$LATEST" 2>/dev/null || true)
  [ -d "$BK" ] || { echo "no backup at $LATEST"; exit 1; }
  sudo -v
  sudo install -Dm755 "$BK/bapirlo-perfd" "$LIB/bapirlo-perfd"
  sudo rm -f "$LIB/bapirlo-charge" "$POLICY" /var/lib/bapirlo/charge-limit
  sudo systemctl restart bapirlo-perfd.service
  echo "restored from $BK (charge limit back to perfd.conf; EasyEffects stays installed —"
  echo "  remove it with: sudo pacman -Rns easyeffects lsp-plugins-lv2)"
}

case "${1:-}" in
  "") apply ;;
  restore) restore ;;
  *) sed -n 2,13p "$0"; exit 1 ;;
esac
