#!/usr/bin/env bash
# Bapirlo OS final round — the parts that need your password. Run in a terminal:
#   sudo bash ~/bapirlo-os/900-final-install.sh             # 1-6 below, then run 900-final.sh (no sudo)
#   sudo bash ~/bapirlo-os/900-final-install.sh snapshot    # the "Bapirlo OS final" snapshot (at the very end)
#   sudo bash ~/bapirlo-os/900-final-install.sh restore     # undo 2-4 (Spicetify stays installed: pacman -R it)
#
#  1. Timeshift snapshot "Before final" (incremental, 1-3 min)
#  2. update snapshots: keep the newest 3 "Before update" snapshots (was 1); still skipped below 15 GB free
#  3. Restart to Windows: /usr/local/lib/bapirlo/bapirlo-bootnext-windows + a one-shot unit + polkit rule so
#     your session may start ONLY that unit. It sets EFI BootNext (one boot) to the GENUINE Windows Boot
#     Manager and refuses if that entry is really GRUB/Limine. Boot order, EFI partition, GRUB and Limine
#     are never changed. Prints what it found.
#  4. read-only checks printed for Claude: Bluetooth keys Windows vs Linux (bapirlo-bt-sync dry run)
#  5. Spicetify from the AUR (shows the PKGBUILD, asks first; paru runs as you)
# Never touches: partitions, /etc/fstab, the EFI partition, Limine or GRUB configuration.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo:  sudo bash $0 ${1:-}"; exit 1; }
U=${SUDO_USER:?run with sudo from your own account}
H=$(getent passwd "$U" | cut -d: -f6)
OS=$H/bapirlo-os
BK=$H/theme-backups
LATEST=$BK/LATEST-FINAL-ROOT
LIB=/usr/local/lib/bapirlo
PRESNAP=$LIB/bapirlo-presnap
UNIT=/etc/systemd/system/bapirlo-bootnext-windows.service
RULE=/etc/polkit-1/rules.d/51-bapirlo-windows.rules
as_user() { sudo -u "$U" -H "$@"; }
has_snap() { grep -qs "\"$1\"" /timeshift/snapshots/*/info.json; }
snap() {  # $1 = comment
  if has_snap "$1"; then echo ":: snapshot \"$1\" already exists — not taking another"; return 0; fi
  echo ":: Timeshift snapshot \"$1\" (incremental)…"
  timeshift --create --scripted --tags O --comments "$1"
}

case "${1:-install}" in
snapshot)
  snap "Bapirlo OS final"
  timeshift --list --scripted | tail -8
  exit 0 ;;
restore)
  d=$(cat "$LATEST" 2>/dev/null) || { echo "nothing to restore ($LATEST missing)"; exit 1; }
  [ -f "$d/bapirlo-presnap" ] && install -m755 "$d/bapirlo-presnap" "$PRESNAP" && echo ":: snapshot hook back to KEEP=1"
  rm -f "$UNIT" "$RULE" "$LIB/bapirlo-bootnext-windows"
  systemctl daemon-reload
  echo ":: Restart to Windows removed. Spicetify (if installed): sudo pacman -R spicetify-bin  (or spicetify-cli)"
  exit 0 ;;
install) ;;
*) sed -n '2,17p' "$0"; exit 64 ;;
esac

echo "== 1/5 snapshot"
if [ -n "${BAPIRLO_INSTALLER:-}" ]; then echo "install.sh took \"Before Bapirlo OS\" — no extra snapshot"
else snap "Before final"; fi
d=$BK/$(date +%Y%m%d-%H%M%S)-final-root; mkdir -p "$d"
cp -a "$PRESNAP" "$d/" 2>/dev/null || true
[ -d /etc/polkit-1/rules.d ] && cp -a /etc/polkit-1/rules.d "$d/polkit-rules.d"
efibootmgr -v > "$d/efibootmgr-before.txt" 2>&1 || true
echo "$d" > "$LATEST"; chown -R "$U:$U" "$d" "$LATEST"; echo "backup -> $d"

echo "== 2/5 update snapshots: keep 3"
install -m755 "$OS/round3/root/bapirlo-presnap" "$PRESNAP"
grep -E '^(KEEP|MIN_FREE_GB)=' "$PRESNAP"

echo "== 3/5 Restart to Windows"
install -Dm755 "$OS/final/root/bapirlo-bootnext-windows" "$LIB/bapirlo-bootnext-windows"
install -Dm644 "$OS/final/root/bapirlo-bootnext-windows.service" "$UNIT"
sed "s/@USER@/$U/g" "$OS/final/root/51-bapirlo-windows.rules.in" | install -Dm644 /dev/stdin "$RULE"
systemctl daemon-reload
echo "--- what the firmware has (read-only):"
"$LIB/bapirlo-bootnext-windows" check || echo "!! Restart to Windows will refuse to run — tell Claude what is printed above"

echo "== 4/5 read-only checks"
echo "--- Bluetooth keys, Windows vs Linux (dry run, nothing changed):"
if command -v bapirlo-bt-sync >/dev/null; then
  bapirlo-bt-sync 2>&1 | sed 's/^/    /' | head -40 || true
else echo "    bapirlo-bt-sync not installed"; fi

echo "== 5/5 Spicetify (Spotify theme) from the AUR"
if command -v spicetify >/dev/null; then
  echo "already installed: $(spicetify -v 2>/dev/null)"
else
  cat <<'EOF'
Two AUR packages, both checked (PKGBUILDs printed below, nothing else in them):
  1) spicetify-bin  — Spicetify's OFFICIAL prebuilt release from github.com/spicetify/cli,
                      sha256-pinned. ~15 MB, no build tools. Maintainer: JoveYu (2 votes).
  2) spicetify-cli  — built from source by the Spicetify author's own PKGBUILD (khanhas, 95 votes);
                      needs go + pnpm (~300 MB, removed again after the build).
EOF
  for p in spicetify-bin spicetify-cli; do
    echo; echo "----- PKGBUILD: $p"
    curl -fsS --max-time 20 "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=$p" | sed 's/^/    /' || echo "    (could not download)"
  done
  echo
  read -rp "Install which? [1 = spicetify-bin (recommended) / 2 = spicetify-cli / n = skip]: " ans
  case "$ans" in
    1) as_user paru -S --needed spicetify-bin ;;
    2) as_user paru -S --needed --removemake spicetify-cli ;;
    *) echo "skipped — the Spotify theme step in 900-final.sh will skip too" ;;
  esac
  rm -rf "$H"/.cache/paru/clone/spicetify-*                 # drop the AUR build folder again
fi

echo
echo "Done. Now, WITHOUT sudo:   bash ~/bapirlo-os/900-final.sh"
