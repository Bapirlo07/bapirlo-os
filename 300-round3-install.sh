#!/usr/bin/env bash
# Bapirlo OS round 3 — the parts that need your password. Run as YOURSELF (it asks for sudo itself).
#   bash ~/bapirlo-os/300-round3-install.sh            # snapshot + backup + install
#   bash ~/bapirlo-os/300-round3-install.sh restore    # undo everything below (snapshot stays)
#
# 0. Timeshift snapshot "Before round 3" FIRST — nothing else runs unless it succeeds
# 1. pacman (official repos, no AUR needed this round): satty (screenshot annotation),
#    bitwarden (password manager), wl-clipboard (copy colours / screenshots from scripts)
# 2. firewall (ufw): deny incoming / allow outgoing, plus — from HOME networks only
#    (192.168.0.0/16, 10.0.0.0/8, iPhone hotspot 172.20.10.0/28; eduroam/public Wi-Fi stay closed):
#      GSConnect/KDE Connect 1714-1764 · Steam LAN (Remote Play, LAN game transfer, discovery)
#      · mDNS (finding printers / shares) · Samba (Windows-style file sharing)
#    Your existing rules are kept.
# 3. Timeshift snapshot before every system update: pacman hook → /usr/local/lib/bapirlo/bapirlo-presnap
#    (once per update run, keeps the newest 3 automatic ones, never blocks an update)
# 4. Monthly cleanup: bapirlo-cleanup.timer (cache: keep 2 versions · orphans · logs > 1 month),
#    notifies you with what it cleaned. Preview any time: sudo /usr/local/lib/bapirlo/bapirlo-cleanup --dry-run
# 5. Plymouth: reboot now says "BE RIGHT BACK" (shutdown keeps "SEE YOU SOON"); initramfs rebuilt.
# Never touches partitions, fstab, EFI or the bootloader config.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as yourself, WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
R=$HERE/round3/root
LATEST=~/theme-backups/LATEST-ROUND3-INSTALL
PKGS=(satty bitwarden wl-clipboard)
NETS=(192.168.0.0/16 10.0.0.0/8 172.20.10.0/28)
PTHEME=/usr/share/plymouth/themes/bapirlo-kuro
FILES=(/usr/local/lib/bapirlo/bapirlo-presnap /etc/pacman.d/hooks/00-bapirlo-timeshift.hook
       /usr/local/lib/bapirlo/bapirlo-cleanup /etc/systemd/system/bapirlo-cleanup.service
       /etc/systemd/system/bapirlo-cleanup.timer /etc/bapirlo/cleanup-keep)

# rule spec: "proto port comment"
RULES=("tcp 1714:1764 bapirlo-kdeconnect" "udp 1714:1764 bapirlo-kdeconnect"
       "udp 27031:27036 bapirlo-steam-lan" "tcp 27036:27037 bapirlo-steam-lan"
       "udp 5353 bapirlo-mdns"
       "udp 137:138 bapirlo-samba" "tcp 139 bapirlo-samba" "tcp 445 bapirlo-samba")

apply() {
  sudo -v
  echo "== 0/5 Timeshift snapshot \"Before round 3\" (incremental — a few minutes)"
  if [ -n "${BAPIRLO_INSTALLER:-}" ]; then
    echo "install.sh already took a \"Before Bapirlo OS\" snapshot"
  elif sudo timeshift --list --scripted 2>/dev/null | grep -q "Before round 3"; then
    echo "already there:"; sudo timeshift --list --scripted | grep "Before round 3"
  else
    sudo timeshift --create --scripted --comments "Before round 3" --tags O
    sudo timeshift --list --scripted | grep -q "Before round 3" || { echo "!! snapshot missing — stopping, nothing changed."; exit 1; }
  fi
  [ -n "${BAPIRLO_INSTALLER:-}" ] || sudo timeshift --list --scripted | grep "Before round 3"

  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round3-install
  mkdir -p "$BK"
  pacman -Q > "$BK/packages-before.txt"
  sudo cp -a /etc/ufw "$BK/etc-ufw"
  sudo ufw status verbose > "$BK/ufw-status-before.txt" || true
  systemctl is-enabled ufw > "$BK/ufw-enabled.txt" 2>&1 || true
  [ -d "$PTHEME" ] && sudo cp -a "$PTHEME" "$BK/plymouth-theme"
  for f in "${FILES[@]}"; do [ -e "$f" ] && echo "$f" >> "$BK/preexisting.txt"; done; touch "$BK/preexisting.txt"
  sudo chown -R "$USER:" "$BK"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo; echo "== 1/5 official packages: ${PKGS[*]}"
  for p in "${PKGS[@]}"; do pacman -Si "$p" | awk -F': ' -v p="$p" '/^$/{exit} /^Repository/{r=$2} /^Version/{v=$2} /^Description/{d=$2} /^Installed Size/{s=$2} END{printf "   %-13s %-14s %-18s %s · %s\n", p, v, r, s, d}' || true; done
  sudo pacman -S --needed "${PKGS[@]}"

  echo; echo "== 2/5 firewall"
  echo "current rules:"; sudo ufw status numbered | sed 's/^/   /'
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw default deny routed
  sudo ufw logging low
  for n in "${NETS[@]}"; do
    for r in "${RULES[@]}"; do
      set -- $r
      sudo ufw allow proto "$1" from "$n" to any port "$2" comment "$3" >/dev/null
    done
  done
  sudo systemctl enable --now ufw >/dev/null
  sudo ufw --force enable >/dev/null
  sudo ufw status verbose | sed 's/^/   /'

  echo; echo "== 3/5 snapshot before every update"
  sudo install -Dm755 "$R/bapirlo-presnap" /usr/local/lib/bapirlo/bapirlo-presnap
  sudo install -Dm644 "$R/00-bapirlo-timeshift.hook" /etc/pacman.d/hooks/00-bapirlo-timeshift.hook
  echo "   hook installed: /etc/pacman.d/hooks/00-bapirlo-timeshift.hook"

  echo; echo "== 4/5 monthly cleanup"
  sudo install -Dm755 "$R/bapirlo-cleanup" /usr/local/lib/bapirlo/bapirlo-cleanup
  sudo install -Dm644 "$R/bapirlo-cleanup.service" /etc/systemd/system/bapirlo-cleanup.service
  sudo install -Dm644 "$R/bapirlo-cleanup.timer" /etc/systemd/system/bapirlo-cleanup.timer
  [ -e /etc/bapirlo/cleanup-keep ] || sudo install -Dm644 "$R/cleanup-keep" /etc/bapirlo/cleanup-keep
  sudo systemctl daemon-reload
  sudo systemctl enable --now bapirlo-cleanup.timer
  echo "   what the first run WOULD clean (dry run):"
  sudo /usr/local/lib/bapirlo/bapirlo-cleanup --dry-run | sed 's/^/   /'
  systemctl list-timers bapirlo-cleanup.timer --no-pager | head -2 | sed 's/^/   /'

  echo; echo "== 5/5 Plymouth reboot caption"
  if [ ! -d "$PTHEME" ]; then echo "   Bapirlo Plymouth theme not installed (boot phase skipped) — nothing to do"
  else
  sudo install -m644 "$HERE/build/plymouth-v2/bapirlo/bye-reboot.png" "$PTHEME/bye-reboot.png"
  sudo install -m644 "$HERE/build/plymouth-v2/bapirlo/bapirlo.script" "$PTHEME/bapirlo.script"
  sudo mkinitcpio -P
  for img in /boot/initramfs-linux-cachyos*.img; do
    case "$img" in *fallback*) continue ;; esac
    if lsinitcpio "$img" | grep -q "bapirlo-kuro/bye-reboot.png"; then echo "   $img: theme OK"
    else echo "   !! $img does not contain the new theme files"; fi
  done
  fi

  echo; echo "All done. Tell Claude — it will now apply the rest (310-round3.sh)."
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "undoing round 3 install (backup $BK)"
  sudo systemctl disable --now bapirlo-cleanup.timer 2>/dev/null || true
  for f in "${FILES[@]}"; do grep -qx "$f" "$BK/preexisting.txt" || sudo rm -f "$f"; done
  sudo systemctl daemon-reload
  echo "-- firewall back to the saved state"
  sudo rm -rf /etc/ufw && sudo cp -a "$BK/etc-ufw" /etc/ufw && sudo chown -R root:root /etc/ufw
  if grep -q enabled "$BK/ufw-enabled.txt"; then sudo ufw reload; else sudo ufw disable; sudo systemctl disable ufw; fi
  if [ -d "$BK/plymouth-theme" ]; then
    echo "-- Plymouth theme"
    sudo rm -rf "$PTHEME" && sudo cp -a "$BK/plymouth-theme" "$PTHEME" && sudo chown -R root:root "$PTHEME"
    sudo mkinitcpio -P
  fi
  local rm=()
  for p in "${PKGS[@]}"; do
    grep -q "^$p " "$BK/packages-before.txt" || { pacman -Q "$p" >/dev/null 2>&1 && rm+=("$p"); }
  done
  [ ${#rm[@]} -gt 0 ] && sudo pacman -Rns "${rm[@]}"
  echo "done. The \"Before round 3\" snapshot is still there: sudo timeshift --list"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
