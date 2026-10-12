#!/usr/bin/env bash
# Round 6 · step 1 — storage report + cleanup + Timeshift limits + "Before round 6" snapshot.
#   sudo bash ~/bapirlo-os/600-round6-storage.sh           report → clean → limits → snapshot
#   sudo bash ~/bapirlo-os/600-round6-storage.sh report    report only (changes nothing)
#   sudo bash ~/bapirlo-os/600-round6-storage.sh restore   put timeshift.json back (deleted caches stay deleted)
# Never touches the bootloader (Limine), partitions, fstab or EFI.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
U=${SUDO_USER:?run with sudo from your own account}; H=$(getent passwd "$U" | cut -d: -f6); BK=$H/theme-backups
TSCONF=/etc/timeshift/timeshift.json
SNAP="Before round 6"
MAX_SNAPS=3

report() {
  echo ":: disk"; df -h / | tail -1
  echo ":: biggest system dirs (root-only ones included)"
  du -xsh /timeshift /usr /opt /var /boot /usr/share/ollama "$H" 2>/dev/null | sort -rh
  echo ":: Timeshift snapshots"; timeshift --list 2>/dev/null | sed -n '/^Num/,$p'
  echo ":: pacman cache";  du -sh /var/cache/pacman/pkg
  echo ":: journal";       journalctl --disk-usage
  echo ":: orphans";       pacman -Qdtq || echo "(none)"
  echo ":: flatpak";       du -sh /var/lib/flatpak "$H/.local/share/flatpak" 2>/dev/null
  echo ":: paru build files"; du -sh "$H/.cache/paru" 2>/dev/null || echo "(none)"
}

if [ "${1:-}" = restore ]; then
  d=$(cat "$BK/LATEST-ROUND6-STORAGE"); cp -a "$d/timeshift.json" "$TSCONF"
  echo ":: restored $TSCONF from $d"; exit 0
fi
report
[ "${1:-}" = report ] && exit 0

read -rp ":: clean caches, set Timeshift limits and take the snapshot? [y/N] " a
[ "$a" = y ] || [ "$a" = Y ] || { echo "stopped, nothing changed"; exit 0; }

# ---- backup
d=$BK/$(date +%Y%m%d-%H%M%S)-round6-storage; mkdir -p "$d"
cp -a "$TSCONF" "$d/"; echo "$d" > "$BK/LATEST-ROUND6-STORAGE"
chown -R $U:$U "$d" "$BK/LATEST-ROUND6-STORAGE"
before=$(df -B1 --output=avail / | tail -1)

# ---- caches only
echo ":: pacman cache (keep last 2, none for removed pkgs)"; paccache -rk2; paccache -ruk0
orph=$(pacman -Qdtq || true)
if [ -n "$orph" ]; then echo ":: orphans: $orph"; pacman -Rns $orph; fi   # pacman asks before removing
echo ":: paru build files"; rm -rf "$H/.cache/paru/clone"
echo ":: journal ≤ 200M";  journalctl --vacuum-size=200M
echo ":: thumbnails";      rm -rf "$H/.cache/thumbnails/"*

# ---- Timeshift: weekly 2, explicit excludes for Downloads, Videos, ~/.cache
python3 -I - "$TSCONF" "$H" <<'PY'
import json, sys
p, h = sys.argv[1], sys.argv[2]; c = json.load(open(p))
c["count_weekly"] = "2"
for k in ("schedule_daily", "schedule_hourly", "schedule_boot", "schedule_monthly"): c[k] = "false"
ex = c.setdefault("exclude", [])
want = [f"{h}/Downloads/**", f"{h}/Videos/**", f"{h}/.cache/**"]
# excludes must sit before the "+ ~/.**" include rule to win
pos = next((i for i, e in enumerate(ex) if e.startswith("+ ")), len(ex))
for w in reversed(want):
    if w not in ex: ex.insert(pos, w)
json.dump(c, open(p, "w"), indent=2)
PY
echo ":: Timeshift: weekly 2, excludes Downloads/Videos/.cache"

# ---- keep at most MAX_SNAPS incl. the new one: drop the oldest first
mapfile -t snaps < <(ls -1 /timeshift/snapshots | sort)
while [ "${#snaps[@]}" -ge "$MAX_SNAPS" ]; do
  echo ":: deleting oldest snapshot ${snaps[0]}"
  timeshift --delete --snapshot "${snaps[0]}" --scripted
  snaps=("${snaps[@]:1}")
done
echo ":: creating snapshot \"$SNAP\""
nice -n 10 timeshift --create --scripted --comments "$SNAP" --tags O

after=$(df -B1 --output=avail / | tail -1)
printf ':: free space: %s → %s\n' "$(numfmt --to=iec "$before")" "$(numfmt --to=iec "$after")"
timeshift --list | sed -n '/^Num/,$p'
echo ":: undo config: sudo bash $0 restore"
