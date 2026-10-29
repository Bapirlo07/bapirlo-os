#!/usr/bin/env bash
# Kuro OS — the parts that need your password. Run as YOURSELF (not with sudo); it asks for sudo itself.
#   bash ~/bapirlo-os/130-install-step.sh            # backup + install + firewall + Chrome restore
#   bash ~/bapirlo-os/130-install-step.sh restore    # undo (packages: asks pacman to remove them)
#
# 1. pacman (official repos):  starship (prompt), cava (visualiser)
# 2. paru (AUR, as you; paru asks for sudo only to install):
#      spicetify-cli 2.45.3  — builds from source, go + pnpm are removed again afterwards (--removemake)
#      vesktop-bin 1.6.7     — prebuilt Vesktop (Discord + Vencord)
#    paru shows each PKGBUILD for review before building — read it, then confirm.
# 3. ufw: KDE Connect ports for home networks only (111-gsconnect-firewall.sh)
# 4. Chrome: "Continue where you left off" as a *recommended* policy (default you can still change
#    in chrome://settings/onStartup) — /etc/opt/chrome/policies/recommended/bapirlo.json
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as yourself, WITHOUT sudo (paru must not run as root)."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
POLICY=/etc/opt/chrome/policies/recommended/bapirlo.json
LATEST=~/theme-backups/LATEST-INSTALL-STEP

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-install-step
  mkdir -p "$BK"
  pacman -Q > "$BK/packages-before.txt"
  [ -f "$POLICY" ] && cp -a "$POLICY" "$BK/"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo; echo "== 1/4 official packages"
  sudo pacman -S --needed starship cava

  echo; echo "== 2/4 AUR packages (paru, review the PKGBUILDs)"
  paru -S --needed --removemake spicetify-cli vesktop-bin

  echo; echo "== 3/4 firewall for KDE Connect (home networks only)"
  sudo bash "$HERE/111-gsconnect-firewall.sh"

  echo; echo "== 4/4 Chrome: continue where you left off"
  sudo install -Dm644 /dev/stdin "$POLICY" <<'EOF'
{
  "RestoreOnStartup": 1
}
EOF
  echo "wrote $POLICY"
  echo; echo "All done. Tell Claude — it will now apply the app themes (115-app-themes.sh)."
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "undoing install step (backup $BK)"
  sudo rm -f "$POLICY"
  [ -f "$BK/$(basename "$POLICY")" ] && sudo install -Dm644 "$BK/$(basename "$POLICY")" "$POLICY"
  sudo bash "$HERE/111-gsconnect-firewall.sh" restore
  local rm=()
  for p in starship cava spicetify-cli vesktop-bin; do
    grep -q "^$p " "$BK/packages-before.txt" || { pacman -Q "$p" >/dev/null 2>&1 && rm+=("$p"); }
  done
  [ ${#rm[@]} -gt 0 ] && sudo pacman -Rns "${rm[@]}"
  echo "done"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
