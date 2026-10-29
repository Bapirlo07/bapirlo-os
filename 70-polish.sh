#!/usr/bin/env bash
# Kuro OS — v3 "polish" pass on top of v2 Kuro (NO sudo). Same palette/wallpaper/layout, refined.
#   bash ~/bapirlo-os/70-polish.sh backup        # always first (done automatically by 'all')
#   bash ~/bapirlo-os/70-polish.sh extensions | animations | blur | shell | dock | arcmenu | fonts | terminal | fastfetch
#   bash ~/bapirlo-os/70-polish.sh all
# Undo everything:   bash ~/bapirlo-os/70-polish.sh restore
#
# Design tokens (shared by every step):
#   radius   surface 16 · bar 14 · item 10 · chip 8        (bar 14 = item 10 + 4px inset → concentric)
#   surface  rgba(22,16,21,0.94) + 1px rgba(225,29,46,0.28) hairline + 0 8px 24px rgba(0,0,0,0.45)
#   hover    rgba(225,29,46,0.20)   active #E11D2E / white text   accent-as-text #FF4655 (5.9:1)
#   motion   180ms hover/press · 250ms open/close/minimise (matches mutter's own 250ms overview/workspace)
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
B=~/bapirlo-os/build/polish-v3
LATEST=~/theme-backups/LATEST-POLISH-V3
EXT=~/.local/share/gnome-shell/extensions
bms() { gsettings --schemadir "$EXT/blur-my-shell@aunetx/schemas" set org.gnome.shell.extensions.blur-my-shell.$1 "$2" "$3"; }
d2d() { gsettings --schemadir "$EXT/dash2dock-lite@icedman.github.com/schemas" set org.gnome.shell.extensions.dash2dock-lite "$1" "$2"; }
lamp() { gsettings --schemadir "$EXT/compiz-alike-magic-lamp-effect@hermes83.github.com/schemas" set org.gnome.shell.extensions.com.github.hermes83.compiz-alike-magic-lamp-effect "$1" "$2"; }
tile() { gsettings --schemadir "$EXT/tiling-assistant@leleat-on-github/schemas" set org.gnome.shell.extensions.tiling-assistant "$1" "$2"; }
arc() { gsettings set org.gnome.shell.extensions.arcmenu "$1" "$2"; }

BACKUP_PATHS=".themes/Bapirlo-Kuro .config/fastfetch .config/alacritty .config/burn-my-windows .local/share/org.gnome.Ptyxis"

step_backup() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-polish-v3
  mkdir -p "$BK"
  dconf dump / > "$BK/dconf-full.ini"
  gnome-extensions list --enabled > "$BK/enabled-extensions.txt"
  for d in $BACKUP_PATHS; do
    if [ -e ~/"$d" ]; then mkdir -p "$BK/$(dirname "$d")"; cp -a ~/"$d" "$BK/$d"; else echo "$d" >> "$BK/absent.txt"; fi
  done
  echo "$BK" > "$LATEST"; echo "backup -> $BK"
}

step_extensions() {
  # ArcMenu already is the start menu; these two add duplicate "Applications"/"Places" buttons to the bar
  gnome-extensions disable apps-menu@gnome-shell-extensions.gcampax.github.com || true
  gnome-extensions disable places-menu@gnome-shell-extensions.gcampax.github.com || true
  # bottom taskbar underneath dash2dock — two docks
  gnome-extensions disable window-list@gnome-shell-extensions.gcampax.github.com || true
  # wobbly windows: redraws a deformed mesh every frame while dragging — GPU cost, and "overdone"
  gnome-extensions disable compiz-windows-effect@hermes83.github.com || true
  echo "extensions: removed duplicate menus, second taskbar and wobbly windows"
}

step_animations() {
  # one motion language: 250ms open/close/minimise, same as mutter's overview & workspace switch
  mkdir -p ~/.config/burn-my-windows/profiles
  cp "$B/burn-my-windows/"*.conf ~/.config/burn-my-windows/profiles/
  lamp duration 300.0          # lamp needs a touch longer than a fade to read as a lamp; was 450
  lamp x-tiles 8.0; lamp y-tiles 8.0   # coarser mesh — same look at this speed, fewer vertices
  tile enable-tile-animations true; tile enable-untile-animations true
  d2d lamp-app-animation false  # minimise is owned by Magic Lamp only
  # reload burn-my-windows so it re-reads the profiles
  gnome-extensions disable burn-my-windows@schneegans.github.com; sleep 0.5
  gnome-extensions enable burn-my-windows@schneegans.github.com
  echo "animations: 250ms glide open/close (broken-glass removed), 300ms lamp minimise, no wobble"
}

step_blur() {
  # per-window blur behind every app = the most expensive thing on the desktop; also made apps see-through
  bms applications blur false
  # one blur strength everywhere (sigma 30 / brightness 0.55), all static = blurred once, not per frame
  bms panel sigma 30;    bms panel brightness 0.55;    bms panel static-blur true
  bms panel corner-radius 16
  bms dash-to-dock sigma 30; bms dash-to-dock brightness 0.55; bms dash-to-dock static-blur true
  bms appfolder sigma 30; bms appfolder brightness 0.55
  bms overview blur true
  bms panel unblur-in-overview true   # bar melts into the overview's own blur instead of double-blurring
  echo "blur: app-window blur off (GPU), one sigma/brightness everywhere, all static"
}

step_shell() {
  rm -rf ~/.themes/Bapirlo-Kuro; cp -r "$B/shell/Bapirlo-Kuro" ~/.themes/Bapirlo-Kuro
  sed -i "s|@HOME@|$HOME|g" ~/.themes/Bapirlo-Kuro/gnome-shell/gnome-shell.css
  gsettings set org.gnome.shell.extensions.user-theme name 'Default'; sleep 0.3
  gsettings set org.gnome.shell.extensions.user-theme name 'Bapirlo-Kuro'
  echo "shell: unified radius/shadow/border on bar, popups, quick settings, notifications, OSD, Alt+Tab, dialogs"
}

step_dock() {
  d2d icon-size 0.27                 # preset 44px (was 32px)
  d2d animation-magnify 0.3          # peak ≈ 1.45x (was 1.75x)
  d2d animation-spread 0.5
  d2d animation-rise 0.15
  d2d animation-bounce-height 0.3    # bounce ≈ 28% of icon height (was 43%)
  d2d running-indicator-style 1      # 'dots': one dot per open window, mac-style
  d2d running-indicator-size 0
  d2d border-radius 2.0              # index 2 → 16px, same as every other surface (was 20)
  d2d icon-spacing 0.4
  d2d dock-padding 0.4
  d2d edge-distance 0.4              # floats 8px above the screen edge, like the bar floats 8px below the top
  d2d background-color '(0.086, 0.063, 0.082, 0.62)'
  d2d border-color '(0.882, 0.114, 0.180, 0.28)'
  d2d customize-label true
  d2d label-border-radius 3.0        # index 3 → 10px = item radius
  d2d label-border-color '(0.882, 0.114, 0.180, 0.28)'
  d2d label-background-color '(0.086, 0.063, 0.082, 0.94)'
  d2d autohide-speed 0.4
  echo "dock: 44px icons, gentler magnify/bounce, dot indicators, 16px radius, floating 8px"
}

step_arcmenu() {
  arc menu-background-color "'rgba(22,16,21,0.94)'"
  arc menu-border-color "'rgba(225,29,46,0.28)'"
  arc menu-border-radius 16
  arc menu-item-hover-bg-color "'rgba(225,29,46,0.20)'"
  arc menu-separator-color "'rgba(242,233,236,0.08)'"
  arc menu-button-fg-color "(true, 'rgb(255,70,85)')"      # ember: logo readable on any wallpaper
  arc menu-button-hover-bg-color "(true, 'rgba(225,29,46,0.20)')"
  arc menu-button-active-bg-color "(true, 'rgb(225,29,46)')"
  arc menu-button-border-radius '(true, 10)'
  arc menu-button-icon-size 22
  echo "arcmenu: same surface/hover/radius tokens as every popup"
}

step_fonts() {
  # UI: Inter (variable, so Medium/SemiBold are real weights). Display/branding: Bangers (GRUB, Plymouth, fastfetch header).
  gsettings set org.gnome.desktop.interface font-name 'Inter 10.5'
  gsettings set org.gnome.desktop.interface document-font-name 'Inter 11'
  gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Inter SemiBold 10.5'
  gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 10.5'
  # 220-dpi panel: subpixel AA is invisible at this density, grayscale+slight stays (crisp, no colour fringes)
  echo "fonts: Inter 10.5 UI / SemiBold titles / JetBrainsMono 10.5 — Bangers stays for branding only"
}

step_terminal() {
  cp "$B/ptyxis/bapirlo-kuro.palette" ~/.local/share/org.gnome.Ptyxis/palettes/
  mkdir -p ~/.config/alacritty
  cp "$B/alacritty/alacritty.toml" ~/.config/alacritty/alacritty.toml
  echo "terminal: Kuro palette in Ptyxis AND Alacritty, bright-black 1.9:1 -> 4.3:1 (fish autosuggestions/comments)"
}

step_fastfetch() {
  cp "$B/fastfetch/config.jsonc" ~/.config/fastfetch/config.jsonc
  echo "fastfetch: aligned keys, ember keys (readable), grouped sections"
}

step_restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  for d in $BACKUP_PATHS; do
    rm -rf ~/"$d"; [ -e "$BK/$d" ] && cp -a "$BK/$d" ~/"$d"
  done
  dconf load / < "$BK/dconf-full.ini"
  while read -r e; do gnome-extensions enable "$e" 2>/dev/null || true; done < "$BK/enabled-extensions.txt"
  gsettings set org.gnome.shell.extensions.user-theme name 'Default'; sleep 0.3
  gsettings set org.gnome.shell.extensions.user-theme name 'Bapirlo-Kuro'
  echo "polish v3 restored to v2 Kuro (log out/in if anything looks stale)"
}

case "${1:-}" in
  backup) step_backup ;; extensions) step_extensions ;; animations) step_animations ;; blur) step_blur ;;
  shell) step_shell ;; dock) step_dock ;; arcmenu) step_arcmenu ;; fonts) step_fonts ;;
  terminal) step_terminal ;; fastfetch) step_fastfetch ;; restore) step_restore ;;
  all) step_backup; step_extensions; step_animations; step_blur; step_shell; step_dock; step_arcmenu; step_fonts; step_terminal; step_fastfetch ;;
  *) sed -n 2,6p "$0"; exit 1 ;;
esac
