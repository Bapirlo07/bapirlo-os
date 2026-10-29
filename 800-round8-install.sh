#!/usr/bin/env bash
# Bapirlo OS round 8 — the parts that need your password. Run as YOURSELF (it asks for sudo itself).
#   bash ~/bapirlo-os/800-round8-install.sh            # snapshot + backup + install
#   bash ~/bapirlo-os/800-round8-install.sh restore    # undo everything below (snapshot stays)
#
# 0. Timeshift snapshot "Before round 8" FIRST — nothing else runs unless it succeeds
# 1. official repo: zoxide (`z <part of a folder name>` in fish)
# 2. AUR, via paru as you — shown and asked first: vesktop-bin (Discord client with Vencord themes;
#    the official upstream build by Vencord's author). Your normal Discord stays installed.
# 3. Bapirlo-Cursors system-wide (/usr/share/icons) so the login screen can use it
# 4. login screen cursor: /etc/lightdm/bapirlo-displays.sh (regenerated from tools/build-lightdm-v2.py)
#    sets Xcursor.theme for the greeter's X server — only that one added block changes
# Then run (no sudo):  bash ~/bapirlo-os/820-round8.sh
# Never touches Limine, GRUB, partitions, fstab or EFI.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as yourself, WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
LATEST=~/theme-backups/LATEST-ROUND8-INSTALL
PKGS=(zoxide)
AUR=vesktop-bin
CURSORS=/usr/share/icons/Bapirlo-Cursors
DSS=/etc/lightdm/bapirlo-displays.sh

show_aur() {
  local p=$1
  echo; echo "──── $p"
  echo "   Vesktop: Discord with Vencord built in (themes, plugins), native Wayland screen share."
  echo "   Official release tarball from github.com/Vencord/Vesktop, repacked; maintainer = Vencord's author."
  paru -Si --aur "$p" 2>/dev/null | grep -E '^(Version|Maintainer|Votes|Last Modified|URL)' | sed 's/^/   /'
  read -rp "   Show its PKGBUILD first? [Y/n] " a
  if [[ ! $a =~ ^[Nn] ]]; then
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
  echo "== 0/4 Timeshift snapshot \"Before round 8\" (incremental — a few minutes)"
  if sudo timeshift --list --scripted 2>/dev/null | grep -q "Before round 8"; then
    echo "already there:"
  else
    sudo timeshift --create --scripted --comments "Before round 8" --tags O
    sudo timeshift --list --scripted | grep -q "Before round 8" || { echo "!! snapshot missing — stopping, nothing changed."; exit 1; }
  fi
  sudo timeshift --list --scripted | grep "Before round 8"

  # a re-run keeps the FIRST backup (its package list is from before anything was installed)
  if [ -s "$LATEST" ] && [ -f "$(cat "$LATEST")/packages-before.txt" ]; then
    echo "re-run: keeping the first backup -> $(cat "$LATEST")"
  else
    local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round8-install
    mkdir -p "$BK"
    pacman -Q > "$BK/packages-before.txt"
    cp -a "$DSS" "$BK/bapirlo-displays.sh"
    [ -d "$CURSORS" ] && touch "$BK/cursors-preexisting"
    echo "$BK" > "$LATEST"; echo "backup -> $BK"
  fi

  echo; echo "== 1/4 official package: ${PKGS[*]}"
  sudo pacman -S --needed "${PKGS[@]}"

  echo; echo "== 2/4 AUR: $AUR (paru, as you)"
  if pacman -Q "$AUR" >/dev/null 2>&1; then
    echo "   $AUR already installed"
  else
    show_aur "$AUR"
    read -rp "   Install $AUR? [y/N] " a
    if [[ $a =~ ^[Yy] ]]; then
      paru -S --needed --removemake "$AUR" || echo "   !! $AUR failed — carrying on, Claude will check"
      rm -rf ~/.cache/paru/clone/"$AUR"
    fi
  fi

  echo; echo "== 3/4 Bapirlo-Cursors -> $CURSORS"
  python3 "$HERE/tools/build-cursors.py" "$HERE/build/round8/Bapirlo-Cursors"
  sudo rm -rf "$CURSORS"
  sudo cp -r "$HERE/build/round8/Bapirlo-Cursors" "$CURSORS"
  sudo chown -R root:root "$CURSORS"; sudo chmod -R u=rwX,go=rX "$CURSORS"

  echo; echo "== 4/4 login screen cursor"
  python3 "$HERE/tools/build-lightdm-v2.py" >/dev/null
  sh -n "$HERE/build/lightdm-v2/bapirlo-displays.sh"
  diff -u "$DSS" "$HERE/build/lightdm-v2/bapirlo-displays.sh" | sed 's/^/   /' || true
  sudo install -m755 "$HERE/build/lightdm-v2/bapirlo-displays.sh" "$DSS"

  echo
  echo "Done. Now (no sudo):  bash $HERE/820-round8.sh"
  echo "Undo this part:       bash $HERE/800-round8-install.sh restore"
}

restore() {
  local BK; BK=$(cat "$LATEST" 2>/dev/null) || { echo "nothing to restore ($LATEST missing)"; exit 1; }
  sudo -v
  sudo install -m755 "$BK/bapirlo-displays.sh" "$DSS" && echo ":: login screen script restored"
  [ -e "$BK/cursors-preexisting" ] || { sudo rm -rf "$CURSORS" && echo ":: $CURSORS removed"; }
  local rm=()
  for p in "${PKGS[@]}" "$AUR"; do
    pacman -Q "$p" >/dev/null 2>&1 && ! grep -q "^$p " "$BK/packages-before.txt" && rm+=("$p")
  done
  [ ${#rm[@]} -eq 0 ] || sudo pacman -Rns "${rm[@]}"
  echo "Restored from $BK (the \"Before round 8\" snapshot is kept)."
}

case "${1:-}" in
  restore) restore ;;
  "") apply ;;
  *) sed -n '2,13p' "$0"; exit 64 ;;
esac
