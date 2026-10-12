#!/usr/bin/env bash
# Bapirlo OS round 7 — the parts that need your password. Run as YOURSELF (it asks for sudo itself).
#   bash ~/bapirlo-os/800-round7-install.sh            # snapshot + backup + install
#   bash ~/bapirlo-os/800-round7-install.sh restore    # undo everything below (snapshot stays)
#
# 0. Timeshift snapshot "Before round 7" FIRST — nothing else runs unless it succeeds
# 1. official repo: gocryptfs (the encrypted Vault) · playerctl (Play/Pause from the iPhone)
#    · kernel-modules-hook (after a kernel update the running kernel keeps its drivers until you
#      reboot — without it, USB sticks stop working until a reboot, as on 12 Oct)
# 2. AUR, via paru as you — each one is shown and asked separately:
#      uxplay (AirPlay mirroring) · localsend-bin (file sharing) · rustdesk-bin (remote access)
#      · librepods (AirPods battery + noise control) · icloudpd-bin (optional iCloud Photos download)
# 3. firewall: NOTHING is opened permanently. /usr/local/lib/bapirlo/bapirlo-port opens AirPlay /
#    LocalSend ports for home networks only while they are switched on (runtime ufw rules that
#    vanish on reboot); bapirlo-port@.service + a polkit rule let your desktop session switch
#    ONLY bapirlo-port@airplay, bapirlo-port@localsend and rustdesk.service without a password.
# 4. RustDesk: strong permanent password (generated, saved in your GNOME keyring), permanent
#    password only, no click-to-accept, no direct-IP port, no LAN discovery, auto-disconnect when
#    idle 30 min. The service stays OFF and is never enabled at boot — the Control Centre switches it.
# 5. Timeshift also skips the encrypted Vault store and per-user Flatpaks (Live Captions).
# Never touches Limine, GRUB, partitions, fstab or EFI.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as yourself, WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
R=$HERE/round7/root
LATEST=~/theme-backups/LATEST-ROUND7-INSTALL
PKGS=(gocryptfs playerctl kernel-modules-hook)
AUR=(uxplay localsend-bin rustdesk-bin librepods)
AUR_OPT=icloudpd-bin
FILES=(/usr/local/lib/bapirlo/bapirlo-port /etc/systemd/system/bapirlo-port@.service
       /etc/polkit-1/rules.d/50-bapirlo-toggles.rules)
TS=/etc/timeshift/timeshift.json
TS_EXCLUDES=("$HOME/.local/share/bapirlo/vault/**" "$HOME/.local/share/flatpak/**")

declare -A WHY=(
  [uxplay]="AirPlay receiver: iPhone → Screen Mirroring → \"Bapirlo OS\". Builds from FDH2/UxPlay source (cmake, ~1 min)."
  [localsend-bin]="LocalSend: AirDrop-style file sharing with the free LocalSend iPhone app. Official release .deb repacked."
  [rustdesk-bin]="RustDesk: remote desktop from the RustDesk iPhone app / another PC. Official release package repacked."
  [librepods]="LibrePods: AirPods battery (left/right/case) + noise control. Builds the tag signed by its author (Qt6, ~2 min)."
  [icloudpd-bin]="icloudpd: downloads your iCloud Photos to ~/Pictures/iCloud. Official single-file release binary."
)

show_aur() {   # summary from the AUR, then the PKGBUILD on request
  local p=$1
  echo; echo "──── $p"
  echo "   ${WHY[$p]}"
  paru -Si --aur "$p" 2>/dev/null | grep -E '^(Version|Maintainer|Votes|Last Modified|URL)' | sed 's/^/   /'
  read -rp "   Show its PKGBUILD first? [Y/n] " a
  if [[ ! $a =~ ^[Nn] ]]; then
    # git, not the AUR web page (its bot protection drops requests); a failed preview never stops the script
    local d; d=$(mktemp -d)
    if git clone -q --depth 1 "https://aur.archlinux.org/$p.git" "$d/$p" 2>/dev/null ||
       { sleep 3; git clone -q --depth 1 "https://aur.archlinux.org/$p.git" "$d/$p" 2>/dev/null; }; then
      less -R "$d/$p/PKGBUILD" || true
    else
      echo "   !! couldn't fetch the PKGBUILD right now (AUR busy) — answer N below and run this script again later"
    fi
    rm -rf "$d"
  fi
}

apply() {
  command -v paru >/dev/null || { echo "paru not found"; exit 1; }
  sudo -v
  echo "== 0/5 Timeshift snapshot \"Before round 7\" (incremental — a few minutes)"
  if [ -n "${BAPIRLO_INSTALLER:-}" ]; then
    echo "install.sh took \"Before Bapirlo OS\" — no extra snapshot"
  elif sudo timeshift --list --scripted 2>/dev/null | grep -q "Before round 7"; then
    echo "already there:"
  else
    sudo timeshift --create --scripted --comments "Before round 7" --tags O
    sudo timeshift --list --scripted | grep -q "Before round 7" || { echo "!! snapshot missing — stopping, nothing changed."; exit 1; }
  fi
  [ -n "${BAPIRLO_INSTALLER:-}" ] || sudo timeshift --list --scripted | grep "Before round 7"

  # a re-run keeps the FIRST backup (its package list is from before anything was installed)
  if [ -s "$LATEST" ] && [ -f "$(cat "$LATEST")/packages-before.txt" ]; then
    echo "re-run: keeping the first backup -> $(cat "$LATEST")"
  else
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round7-install
  mkdir -p "$BK"
  pacman -Q > "$BK/packages-before.txt"
  sudo cp -a /etc/ufw "$BK/etc-ufw"
  sudo ufw status verbose > "$BK/ufw-status-before.txt" 2>&1 || true
  sudo cp -a "$TS" "$BK/timeshift.json"
  [ -d /etc/polkit-1/rules.d ] && sudo cp -a /etc/polkit-1/rules.d "$BK/polkit-rules.d"
  sudo test -d /root/.config/rustdesk && sudo cp -a /root/.config/rustdesk "$BK/root-rustdesk"
  for f in "${FILES[@]}"; do [ -e "$f" ] && echo "$f" >> "$BK/preexisting.txt"; done; touch "$BK/preexisting.txt"
  sudo chown -R "$USER:" "$BK"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"
  fi

  echo; echo "== 1/5 official package: ${PKGS[*]}"
  sudo pacman -S --needed "${PKGS[@]}"
  sudo systemctl enable linux-modules-cleanup.service   # tidies the kept old modules after reboots

  echo; echo "== 2/5 AUR packages (paru, as you) — one at a time"
  local want=()
  for p in "${AUR[@]}"; do
    pacman -Q "$p" >/dev/null 2>&1 && { echo "   $p already installed"; continue; }
    show_aur "$p"
    read -rp "   Install $p? [y/N] " a
    [[ $a =~ ^[Yy] ]] && want+=("$p")
  done
  echo; echo "   iCloud Photos download is optional (you can also just use iCloud.com from the Start menu)."
  if ! pacman -Q "$AUR_OPT" >/dev/null 2>&1; then
    read -rp "   Look at $AUR_OPT? [y/N] " a
    if [[ $a =~ ^[Yy] ]]; then
      show_aur "$AUR_OPT"
      read -rp "   Install $AUR_OPT? [y/N] " a
      [[ $a =~ ^[Yy] ]] && want+=("$AUR_OPT")
    fi
  fi
  for p in "${want[@]}"; do
    echo; echo "   -> paru -S $p"
    paru -S --needed --removemake "$p" || echo "   !! $p failed — carrying on, Claude will check"
  done
  # keep the disk low: paru's clone/build dirs for these
  for p in "${want[@]}"; do rm -rf ~/.cache/paru/clone/"$p"; done
  sudo systemctl is-active --quiet avahi-daemon || sudo systemctl enable --now avahi-daemon

  echo; echo "== 3/5 firewall helper (nothing opened now)"
  sudo install -Dm755 "$R/bapirlo-port" /usr/local/lib/bapirlo/bapirlo-port
  sudo install -Dm644 "$R/bapirlo-port@.service" /etc/systemd/system/bapirlo-port@.service
  sed "s/@USER@/$USER/g" "$R/50-bapirlo-toggles.rules.in" | sudo install -Dm644 /dev/stdin /etc/polkit-1/rules.d/50-bapirlo-toggles.rules
  sudo systemctl daemon-reload
  echo "   firewall now (unchanged — deny incoming, home-network KDE Connect/mDNS rules from round 3):"
  sudo ufw status | sed 's/^/   /'

  echo; echo "== 4/5 RustDesk security settings (service stays OFF)"
  if command -v rustdesk >/dev/null; then
    sudo systemctl disable rustdesk.service 2>/dev/null || true
    sudo systemctl start rustdesk.service; sleep 4
    local PW
    PW=$(python3 -c 'import secrets,string;a=string.ascii_letters+string.digits+"-_.";print("".join(secrets.choice(a) for _ in range(24)))')
    sudo rustdesk --password "$PW" >/dev/null
    for kv in "verification-method use-permanent-password" "approve-mode password" \
              "direct-server N" "enable-lan-discovery N" "allow-remote-config-modification N" \
              "allow-auto-disconnect Y" "auto-disconnect-timeout 30"; do
      set -- $kv; sudo rustdesk --option "$1" "$2" >/dev/null
      printf '   %-34s %s\n' "$1" "$(sudo rustdesk --option "$1")"
    done
    local ID; ID=$(sudo rustdesk --get-id 2>/dev/null | tail -1)
    printf '%s' "$PW" | secret-tool store --label="RustDesk permanent password (Bapirlo OS)" app bapirlo service rustdesk
    printf '%s' "$ID" > ~/.config/bapirlo/rustdesk-id 2>/dev/null || { mkdir -p ~/.config/bapirlo; printf '%s' "$ID" > ~/.config/bapirlo/rustdesk-id; }
    sudo systemctl stop rustdesk.service
    echo
    echo "   ┌─ RustDesk ──────────────────────────────────────────────"
    echo "   │ ID:        $ID"
    echo "   │ Password:  $PW"
    echo "   │ (saved in your keyring — show again: bapirlo-remote password)"
    echo "   │ Put it in Bitwarden too. Service is OFF until you switch it on."
    echo "   └─────────────────────────────────────────────────────────"
    echo "   enabled at boot: $(systemctl is-enabled rustdesk.service 2>&1) · running: $(systemctl is-active rustdesk.service 2>&1)"
  else
    echo "   rustdesk not installed — skipped"
  fi

  echo; echo "== 5/5 Timeshift excludes"
  sudo python3 - "$TS" "${TS_EXCLUDES[@]}" <<'PY'
import json, sys
path, new = sys.argv[1], sys.argv[2:]
c = json.load(open(path))
ex = c.setdefault("exclude", [])
# excludes must sit before the "+ ~/.**" include rule to win
pos = next((i for i, e in enumerate(ex) if e.startswith("+ ")), len(ex))
for e in new:
    if e not in ex:
        ex.insert(pos, e); pos += 1
json.dump(c, open(path, "w"), indent=2)
print("   now excluded:", *new, sep="\n     ")
PY

  echo; echo "All done. Tell Claude — it will now apply the rest (810-round7.sh)."
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "undoing round 7 install (backup $BK)"
  sudo systemctl stop 'bapirlo-port@*.service' rustdesk.service 2>/dev/null || true
  sudo systemctl disable linux-modules-cleanup.service 2>/dev/null || true
  for f in "${FILES[@]}"; do grep -qx "$f" "$BK/preexisting.txt" || sudo rm -f "$f"; done
  sudo systemctl daemon-reload
  sudo install -m644 "$BK/timeshift.json" "$TS"
  sudo rm -rf /etc/ufw && sudo cp -a "$BK/etc-ufw" /etc/ufw && sudo chown -R root:root /etc/ufw && sudo ufw reload
  if [ -d "$BK/root-rustdesk" ]; then sudo rm -rf /root/.config/rustdesk; sudo cp -a "$BK/root-rustdesk" /root/.config/rustdesk; sudo chown -R root:root /root/.config/rustdesk
  else sudo rm -rf /root/.config/rustdesk; fi
  secret-tool clear app bapirlo service rustdesk 2>/dev/null || true
  local rm=()
  for p in "${PKGS[@]}" "${AUR[@]}" "$AUR_OPT"; do
    grep -q "^$p " "$BK/packages-before.txt" || { pacman -Q "$p" >/dev/null 2>&1 && rm+=("$p"); }
  done
  [ ${#rm[@]} -gt 0 ] && sudo pacman -Rns "${rm[@]}"
  echo "done. The \"Before round 7\" snapshot is still there: sudo timeshift --list"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
