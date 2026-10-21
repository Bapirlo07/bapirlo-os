#!/usr/bin/env bash
# Bapirlo OS — every update deletes the old leftovers. Run in a terminal:
#   sudo bash ~/bapirlo-os/950-update-cleanup-install.sh            # install
#   sudo bash ~/bapirlo-os/950-update-cleanup-install.sh restore    # undo
#
#  1. update snapshots: keep ONLY the newest "Before update" snapshot (was 3) — each update deletes
#     the previous one. Your own named snapshots and the weekly ones are never touched.
#  2. pacman hook zz-bapirlo-pkgcache.hook: after every install/upgrade/remove, the package cache keeps
#     only the installed version (paccache -rk1) and nothing of removed packages (-ruk0).
#  3. cleans the cache down to that right now.
# (bin/bapirlo-update itself — deletes paru's AUR build files after each update — needs no install.)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo:  sudo bash $0 ${1:-}"; exit 1; }
U=${SUDO_USER:?run with sudo from your own account}
H=$(getent passwd "$U" | cut -d: -f6)
OS=$H/bapirlo-os
BK=$H/theme-backups
LATEST=$BK/LATEST-UPDATE-CLEANUP
PRESNAP=/usr/local/lib/bapirlo/bapirlo-presnap
HOOK=/etc/pacman.d/hooks/zz-bapirlo-pkgcache.hook
gb() { df -B1 --output=avail / | tail -1; }

case "${1:-install}" in
restore)
  d=$(cat "$LATEST" 2>/dev/null) || { echo "nothing to restore ($LATEST missing)"; exit 1; }
  [ -f "$d/bapirlo-presnap" ] && install -m755 "$d/bapirlo-presnap" "$PRESNAP" && echo ":: snapshot hook restored"
  rm -f "$HOOK" && echo ":: package-cache hook removed (deleted packages stay deleted)"
  exit 0 ;;
install) ;;
*) sed -n '2,11p' "$0"; exit 64 ;;
esac

d=$BK/$(date +%Y%m%d-%H%M%S)-update-cleanup; mkdir -p "$d"
cp -a "$PRESNAP" "$d/" 2>/dev/null || true
echo "$d" > "$LATEST"; chown -R "$U:$U" "$d" "$LATEST"; echo "backup -> $d"
before=$(gb)

echo "== 1/3 update snapshots: keep 1"
install -m755 "$OS/round3/root/bapirlo-presnap" "$PRESNAP"
grep -E '^KEEP=' "$PRESNAP"

echo "== 2/3 pacman hook: drop old package versions after every transaction"
install -Dm644 "$OS/update-cleanup/root/zz-bapirlo-pkgcache.hook" "$HOOK"
echo "   $HOOK"

echo "== 3/3 clean now"
paccache -rk1; paccache -ruk0
mapfile -t ours < <(timeshift --list --scripted 2>/dev/null |
  awk '$1 ~ /^[0-9]+$/ && $2 == ">" && index($0, "Before update") { print $3 }' | sort)
if [ "${#ours[@]}" -gt 1 ]; then
  for s in "${ours[@]:0:$((${#ours[@]} - 1))}"; do
    echo ":: removing old update snapshot $s"
    timeshift --delete --snapshot "$s" --scripted >/dev/null 2>&1 || true
  done
fi
echo
echo "Done. Freed $(( ($(gb) - before) / 1000000 )) MB now; every update cleans up after itself from here on."
