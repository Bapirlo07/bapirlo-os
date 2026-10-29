#!/usr/bin/env bash
# Kuro OS round 10 — the parts that need your password. Run as YOURSELF (it asks for sudo itself).
#   bash ~/bapirlo-os/1000-round10-install.sh            # snapshot + backup + changes
#   bash ~/bapirlo-os/1000-round10-install.sh restore    # undo (snapshot stays; deleted caches stay deleted)
#
# 0. Timeshift snapshot "Before round 10" FIRST — nothing else runs unless it succeeds
# 1. remove the Discord app (pacman shows it and asks) — Vesktop is your Discord now
# 2. package cache: delete every cached package now (~3 GB) and from now on after each update
#    (pacman hook zz-bapirlo-pkgcache.hook: -rk1 → -rk0). Anything can be downloaded again.
# 3. Waydroid: delete the downloaded image zips in /var/lib/waydroid/cache_http (~0.7 GB; the
#    installed Android images are not touched — an upgrade downloads fresh ones)
# 4. system logs: trim to 100 MB now and cap them there (journald drop-in)
# Then run (no sudo):  bash ~/bapirlo-os/1010-round10.sh
# Never touches Limine, GRUB, partitions, fstab or EFI.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as yourself, WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
LATEST=~/theme-backups/LATEST-ROUND10-INSTALL
HOOK=/etc/pacman.d/hooks/zz-bapirlo-pkgcache.hook
JOURNALD=/etc/systemd/journald.conf.d/50-bapirlo.conf
WAYDROID_CACHE=/var/lib/waydroid/cache_http
gb() { df -B1 --output=avail / | tail -1; }

apply() {
  sudo -v
  echo "== 0/4 Timeshift snapshot \"Before round 10\" (incremental — a few minutes)"
  if sudo timeshift --list --scripted 2>/dev/null | grep -q "Before round 10"; then
    echo "already there:"
  else
    sudo timeshift --create --scripted --comments "Before round 10" --tags O
    sudo timeshift --list --scripted | grep -q "Before round 10" || { echo "!! snapshot missing — stopping, nothing changed."; exit 1; }
  fi
  sudo timeshift --list --scripted | grep "Before round 10"

  # a re-run keeps the FIRST backup (its package list is from before anything was removed)
  if [ -s "$LATEST" ] && [ -f "$(cat "$LATEST")/packages-before.txt" ]; then
    echo "re-run: keeping the first backup -> $(cat "$LATEST")"
  else
    local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round10-install
    mkdir -p "$BK"
    pacman -Q > "$BK/packages-before.txt"
    cp -a "$HOOK" "$BK/" 2>/dev/null || touch "$BK/no-hook-before"
    [ -f "$JOURNALD" ] && cp -a "$JOURNALD" "$BK/" || touch "$BK/no-journald-before"
    echo "$BK" > "$LATEST"; echo "backup -> $BK"
  fi
  local before; before=$(gb)

  echo; echo "== 1/4 remove Discord (Vesktop stays)"
  if pacman -Q discord >/dev/null 2>&1; then
    pgrep -f '/discord/app-' >/dev/null && { echo "   Discord is running — quitting it"; pkill -f '/discord/app-' || true; sleep 2; }
    sudo pacman -Rns discord
  else echo "   not installed"; fi

  echo; echo "== 2/4 package cache: keep nothing"
  diff -u "$HOOK" "$HERE/update-cleanup/root/zz-bapirlo-pkgcache.hook" | sed 's/^/   /' || true
  sudo install -Dm644 "$HERE/update-cleanup/root/zz-bapirlo-pkgcache.hook" "$HOOK"
  sudo paccache -rk0 | tail -1

  echo; echo "== 3/4 Waydroid download cache"
  if [ -d "$WAYDROID_CACHE" ]; then
    echo "   $(sudo du -sh "$WAYDROID_CACHE" | cut -f1) in $WAYDROID_CACHE"
    sudo find "$WAYDROID_CACHE" -mindepth 1 -delete
  else echo "   none"; fi

  echo; echo "== 4/4 system logs: 100 MB cap"
  sudo install -Dm644 /dev/stdin "$JOURNALD" <<'EOF'
# Kuro OS round 10 — keep at most 100 MB of system logs (was ~200 MB). Remove this file to undo.
[Journal]
SystemMaxUse=100M
EOF
  sudo systemctl restart systemd-journald
  sudo journalctl --vacuum-size=100M 2>&1 | tail -1

  echo
  echo "Done. Freed $(( ($(gb) - before) / 1000000 )) MB here."
  echo "Now (no sudo):  bash $HERE/1010-round10.sh"
  echo "Undo this part: bash $HERE/1000-round10-install.sh restore"
}

restore() {
  local BK; BK=$(cat "$LATEST" 2>/dev/null) || { echo "nothing to restore ($LATEST missing)"; exit 1; }
  sudo -v
  if [ -f "$BK/zz-bapirlo-pkgcache.hook" ]; then
    sudo install -m644 "$BK/zz-bapirlo-pkgcache.hook" "$HOOK" && echo ":: pacman hook restored"
  elif [ -e "$BK/no-hook-before" ]; then
    sudo rm -f "$HOOK" && echo ":: pacman hook removed"
  fi
  if [ -f "$BK/50-bapirlo.conf" ]; then
    sudo install -m644 "$BK/50-bapirlo.conf" "$JOURNALD"
  else
    sudo rm -f "$JOURNALD"
  fi
  sudo systemctl restart systemd-journald && echo ":: log cap restored"
  if grep -q '^discord ' "$BK/packages-before.txt" && ! pacman -Q discord >/dev/null 2>&1; then
    sudo pacman -S --needed discord
  fi
  echo "Restored from $BK (the \"Before round 10\" snapshot is kept; deleted caches stay deleted)."
}

case "${1:-}" in
  restore) restore ;;
  "") apply ;;
  *) sed -n '2,14p' "$0"; exit 64 ;;
esac
