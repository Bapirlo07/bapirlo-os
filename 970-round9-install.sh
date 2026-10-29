#!/usr/bin/env bash
# Bapirlo OS round 9 — the parts that need your password. Run as YOURSELF (it asks for sudo itself).
#   bash ~/bapirlo-os/970-round9-install.sh            # snapshot + backup + install
#   bash ~/bapirlo-os/970-round9-install.sh restore    # undo everything below (snapshot stays)
#
# 0. Timeshift snapshot "Before round 9" FIRST — nothing else runs unless it succeeds
# 1. official repo: starship (the Kuro prompt in fish) + cava (terminal audio visualiser)
# 2. pacman hook zz-bapirlo-pkgcache.hook gains one job: after every update it also deletes the
#    download-* folders an interrupted update leaves in /var/cache/pacman/pkg (you have 21 now) —
#    and does it once right away
# Then run (no sudo):  bash ~/bapirlo-os/980-round9.sh
# Never touches Limine, GRUB, partitions, fstab or EFI.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as yourself, WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
LATEST=~/theme-backups/LATEST-ROUND9-INSTALL
PKGS=(starship cava)
HOOK=/etc/pacman.d/hooks/zz-bapirlo-pkgcache.hook
CACHE=/var/cache/pacman/pkg
gb() { df -B1 --output=avail / | tail -1; }

apply() {
  sudo -v
  echo "== 0/2 Timeshift snapshot \"Before round 9\" (incremental — a few minutes)"
  if sudo timeshift --list --scripted 2>/dev/null | grep -q "Before round 9"; then
    echo "already there:"
  else
    sudo timeshift --create --scripted --comments "Before round 9" --tags O
    sudo timeshift --list --scripted | grep -q "Before round 9" || { echo "!! snapshot missing — stopping, nothing changed."; exit 1; }
  fi
  sudo timeshift --list --scripted | grep "Before round 9"

  # a re-run keeps the FIRST backup (its package list is from before anything was installed)
  if [ -s "$LATEST" ] && [ -f "$(cat "$LATEST")/packages-before.txt" ]; then
    echo "re-run: keeping the first backup -> $(cat "$LATEST")"
  else
    local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round9-install
    mkdir -p "$BK"
    pacman -Q > "$BK/packages-before.txt"
    cp -a "$HOOK" "$BK/" 2>/dev/null || touch "$BK/no-hook-before"
    echo "$BK" > "$LATEST"; echo "backup -> $BK"
  fi
  local before; before=$(gb)

  echo; echo "== 1/2 official packages: ${PKGS[*]}"
  sudo pacman -S --needed "${PKGS[@]}"

  echo; echo "== 2/2 pacman hook: also clear half-finished downloads"
  diff -u "$HOOK" "$HERE/update-cleanup/root/zz-bapirlo-pkgcache.hook" | sed 's/^/   /' || true
  sudo install -Dm644 "$HERE/update-cleanup/root/zz-bapirlo-pkgcache.hook" "$HOOK"
  local n; n=$(sudo find "$CACHE" -mindepth 1 -maxdepth 1 -type d -name 'download-*' -mmin +60 | wc -l)
  sudo find "$CACHE" -mindepth 1 -maxdepth 1 -type d -name 'download-*' -mmin +60 -exec rm -rf {} +
  echo "   removed $n leftover download folder(s)"

  echo
  echo "Done. Freed $(( ($(gb) - before) / 1000000 )) MB here (packages added ~12 MB)."
  echo "Now (no sudo):  bash $HERE/980-round9.sh"
  echo "Undo this part: bash $HERE/970-round9-install.sh restore"
}

restore() {
  local BK; BK=$(cat "$LATEST" 2>/dev/null) || { echo "nothing to restore ($LATEST missing)"; exit 1; }
  sudo -v
  if [ -f "$BK/zz-bapirlo-pkgcache.hook" ]; then
    sudo install -m644 "$BK/zz-bapirlo-pkgcache.hook" "$HOOK" && echo ":: pacman hook restored"
  elif [ -e "$BK/no-hook-before" ]; then
    sudo rm -f "$HOOK" && echo ":: pacman hook removed"
  fi
  local rm=()
  for p in "${PKGS[@]}"; do
    pacman -Q "$p" >/dev/null 2>&1 && ! grep -q "^$p " "$BK/packages-before.txt" && rm+=("$p")
  done
  [ ${#rm[@]} -eq 0 ] || sudo pacman -Rns "${rm[@]}"
  echo "Restored from $BK (the \"Before round 9\" snapshot is kept; deleted downloads stay deleted)."
}

case "${1:-}" in
  restore) restore ;;
  "") apply ;;
  *) sed -n '2,11p' "$0"; exit 64 ;;
esac
