#!/usr/bin/env bash
# Bapirlo OS round 2 — "make it feel alive" (NO sudo; needs matugen from 200-round2-install.sh).
#   bash ~/bapirlo-os/220-alive.sh            # backup + install + configure + enable
#   bash ~/bapirlo-os/220-alive.sh restore    # everything back as it was
#   1. Wallpaper accents (matugen): the 2nd accent of bar / dock / terminal / MangoHud follows the
#      wallpaper; black base + crimson main accent never change.  Service: bapirlo-autotheme
#   2. Coverflow Alt-Tab (Alt+Tab windows, Super+Tab apps), 3D, crimson tint, 250 ms
#   3. ddterm drop-down terminal on Super+Enter (Kuro colours, no bar icon)
#   4. Desktop Icons NG (GTK4 build): ~/Desktop files + Home/Trash/drives on the desktop
# Extensions verified for this GNOME version before install. Log out/in once to load them.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
. "$HERE/lib/ext.sh"
EXTS=(CoverflowAltTab@palatis.blogspot.com ddterm@amezin.github.com gtk4-ding@smedius.gitlab.com)
PATHS=(/org/gnome/shell/extensions/coverflowalttab/ /com/github/amezin/ddterm/
       /org/gnome/shell/extensions/gtk4-ding/ /org/gnome/shell/extensions/dash2dock-lite/)
ALAC=~/.config/alacritty/alacritty.toml
UNITS=~/.config/systemd/user
LATEST=~/theme-backups/LATEST-ALIVE

# Kuro terminal palette (same as Alacritty) — 5/6/13/14 are then driven by the wallpaper
PALETTE="['#1C1418', '#E11D2E', '#3FC69A', '#F2B45A', '#7C9CFF', '#F08AA4', '#6FC7C2', '#CAB5BF', '#857079', '#FF4655', '#6EE0B4', '#FFD08A', '#A3B8FF', '#FFB3C6', '#9EE6E1', '#FFFFFF']"

apply() {
  command -v matugen >/dev/null || { echo "matugen missing — run 200-round2-install.sh first"; exit 1; }
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-alive
  mkdir -p "$BK"
  backup_dconf "$BK" "${PATHS[@]}"
  cp -a "$ALAC" "$BK/alacritty.toml"
  for u in "${EXTS[@]}"; do [ -d "$EXT_DIR/$u" ] && echo "$u" >> "$BK/preexisting.txt"; done; touch "$BK/preexisting.txt"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo "installing (GNOME $SHELL_MAJOR):"
  for u in "${EXTS[@]}"; do ext_install "$u"; done

  # ---- 1. wallpaper accents
  # Alacritty: imports load BEFORE the main file, so the wallpaper-driven keys move out of it
  python3 - "$ALAC" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
imp = 'import = ["~/.local/state/bapirlo/accent/alacritty.toml"]   # wallpaper accents (bapirlo-autotheme)'
if "bapirlo/accent/alacritty.toml" not in s:
    s = s.replace("[general]\n", "[general]\n" + imp + "\n", 1)
s = re.sub(r'^(magenta|cyan) = "#[0-9A-Fa-f]{6}"\n', "", s, flags=re.M)
s = re.sub(r'\[colors\.hints\.start\]\n(?:[a-z_]+ = "[^"]*"\n)+\n?', "", s)
open(p, "w").write(s)
PY
  "$HERE/bin/bapirlo-autotheme" reset >/dev/null      # stock accents first, so every file exists
  mkdir -p "$UNITS"
  install -m644 "$HERE/round2/systemd/bapirlo-autotheme.service" "$UNITS/"
  systemctl --user daemon-reload
  systemctl --user enable --now bapirlo-autotheme.service

  # ---- 2. Coverflow Alt-Tab
  local C=org.gnome.shell.extensions.coverflowalttab U=CoverflowAltTab@palatis.blogspot.com
  eset $U $C switcher-style "'Coverflow'"
  eset $U $C animation-time 0.25
  eset $U $C easing-function "'ease-out-cubic'"
  eset $U $C hide-panel true
  eset $U $C dim-factor 0.55
  eset $U $C desaturate-factor 0.25
  eset $U $C use-tint true
  eset $U $C tint-use-theme-color false
  eset $U $C tint-color "(0.882, 0.114, 0.180)"       # crimson
  eset $U $C tint-blend 0.12
  eset $U $C highlight-use-theme-color false
  eset $U $C highlight-color "(1.0, 0.275, 0.333)"    # ember
  eset $U $C icon-style "'Overlay'"
  eset $U $C overlay-icon-size 96.0
  eset $U $C overlay-icon-opacity 0.9
  eset $U $C position "'Bottom'"
  eset $U $C current-workspace-only "'current'"
  eset $U $C use-glitch-effect false
  eset $U $C randomize-animation-times false
  eset $U $C bind-to-switch-windows true             # Alt+Tab
  eset $U $C bind-to-switch-applications true        # Super+Tab

  # ---- 3. ddterm
  local D=org.gnome.shell.extensions.ddterm U=ddterm@amezin.github.com
  eset $U $D ddterm-toggle-hotkey "['<Super>Return']"
  eset $U $D panel-icon-type "'none'"
  eset $U $D theme-variant "'dark'"
  eset $U $D window-position "'top'"
  eset $U $D window-size 0.45
  eset $U $D window-monitor "'current'"
  eset $U $D hide-when-focus-lost true
  eset $U $D show-animation-duration 0.18
  eset $U $D hide-animation-duration 0.15
  eset $U $D tab-policy "'automatic'"
  eset $U $D use-system-font false
  eset $U $D custom-font "'JetBrainsMono Nerd Font 10.5'"
  eset $U $D use-theme-colors false
  eset $U $D foreground-color "'#F2E9EC'"
  eset $U $D background-color "'#0E0A0D'"
  eset $U $D palette "$PALETTE"
  eset $U $D transparent-background true
  eset $U $D background-opacity 0.94
  eset $U $D cursor-colors-set true
  eset $U $D cursor-background-color "'#FF4655'"
  eset $U $D cursor-foreground-color "'#0E0A0D'"
  eset $U $D highlight-colors-set true
  eset $U $D highlight-background-color "'#7A1420'"
  eset $U $D highlight-foreground-color "'#FFFFFF'"

  # ---- 4. Desktop Icons NG
  local G=org.gnome.shell.extensions.gtk4-ding U=gtk4-ding@smedius.gitlab.com
  eset $U $G icon-size "'standard'"
  eset $U $G show-home true
  eset $U $G show-trash true
  eset $U $G show-volumes true
  eset $U $G show-network-volumes false
  eset $U $G start-corner "'top-left'"
  eset $U $G free-position-icons true      # place icons anywhere, like Windows
  eset $U $G show-second-monitor false
  eset $U $G show-desktop-widgets false
  mkdir -p "$(xdg-user-dir DESKTOP)"

  "$HERE/bin/bapirlo-autotheme" apply                  # now with the real wallpaper colours
  ext_enable "${EXTS[@]}"
  echo; echo "done. Log out and back in once to load them. Undo: bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  ext_unenable "${EXTS[@]}"
  for u in "${EXTS[@]}"; do grep -qx "$u" "$BK/preexisting.txt" || rm -rf "${EXT_DIR:?}/$u"; done
  systemctl --user disable --now bapirlo-autotheme.service 2>/dev/null || true
  rm -f "$UNITS/bapirlo-autotheme.service"; systemctl --user daemon-reload
  cp -a "$BK/alacritty.toml" "$ALAC"
  rm -f ~/.local/state/bapirlo/accent/shell.css     # bar falls back to the stock Kuro accents
  restore_dconf "$BK" "${PATHS[@]}"
  echo "restored (log out/in to fully unload)"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
