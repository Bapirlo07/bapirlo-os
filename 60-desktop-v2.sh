#!/usr/bin/env bash
# Kuro OS — desktop "Kuro" (NO sudo). Each step can be run alone so you can watch it:
#   bash ~/bapirlo-os/60-desktop-v2.sh backup      # always first (done automatically by 'all')
#   bash ~/bapirlo-os/60-desktop-v2.sh topbar | blur | gtk | dock | arcmenu | terminal | fastfetch | wallpaper
#   bash ~/bapirlo-os/60-desktop-v2.sh all
# Undo everything:   bash ~/bapirlo-os/60-desktop-v2.sh restore
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
B=~/bapirlo-os/build/desktop-v2
LATEST=~/theme-backups/LATEST-DESKTOP-V2
EXT=~/.local/share/gnome-shell/extensions
bms() { gsettings --schemadir "$EXT/blur-my-shell@aunetx/schemas" set org.gnome.shell.extensions.blur-my-shell.$1 "$2" "$3"; }
d2d() { gsettings --schemadir "$EXT/dash2dock-lite@icedman.github.com/schemas" set org.gnome.shell.extensions.dash2dock-lite "$1" "$2"; }
arc() { gsettings set org.gnome.shell.extensions.arcmenu "$1" "$2"; }

step_backup() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-desktop-v2
  mkdir -p "$BK"
  dconf dump / > "$BK/dconf-full.ini"
  for d in .themes .config/gtk-4.0 .config/gtk-3.0 .config/fastfetch .local/share/org.gnome.Ptyxis .local/share/backgrounds/bapirlo; do
    [ -e ~/"$d" ] && { mkdir -p "$BK/$(dirname "$d")"; cp -a ~/"$d" "$BK/$d"; }
  done
  systemctl --user is-enabled bapirlo-wallpaper.path > "$BK/wallpaper-watcher.txt" 2>/dev/null || true
  echo "$BK" > "$LATEST"; echo "backup -> $BK"
}

step_topbar() {
  rm -rf ~/.themes/Bapirlo-Kuro; cp -r "$B/shell/Bapirlo-Kuro" ~/.themes/Bapirlo-Kuro
  sed -i "s|@HOME@|$HOME|g" ~/.themes/Bapirlo-Kuro/gnome-shell/gnome-shell.css
  gsettings set org.gnome.shell.extensions.user-theme name 'Bapirlo-Kuro'
  gsettings set org.gnome.desktop.interface clock-show-weekday true
  gsettings set org.gnome.desktop.interface clock-show-date true
  gsettings set org.gnome.desktop.interface clock-show-seconds false
  echo "top bar: floating ink-glass bar, crimson hover/press, workspace pill, clock capsule"
}

step_blur() {
  bms panel blur true
  bms panel customize true
  bms panel sigma 28
  bms panel brightness 0.55
  bms panel corner-radius 14
  bms panel noise-amount 0.18
  bms panel noise-lightness 0.0
  bms panel static-blur true
  bms panel override-background false        # keep our ink tint + crimson hairline from the CSS
  echo "blur: panel blur rounded to match the bar, film grain like the artwork"
}

step_gtk() {
  python3 ~/bapirlo-os/tools/recolor-whitesur.py
  gsettings set org.gnome.desktop.interface accent-color 'red'   # libadwaita apps
  # re-apply so GTK + shell pick up the recoloured CSS
  gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'; sleep 0.3
  gsettings set org.gnome.desktop.interface gtk-theme 'WhiteSur-Dark-red'
  gsettings set org.gnome.shell.extensions.user-theme name 'Default'; sleep 0.3
  gsettings set org.gnome.shell.extensions.user-theme name 'Bapirlo-Kuro'
  echo "gtk: WhiteSur salmon (#ED5F5D) -> Kuro crimson (#E11D2E) in GTK3/4 + shell; libadwaita accent red"
}

step_dock() {
  d2d background-color '(0.055, 0.039, 0.051, 0.55)'
  d2d border-color '(0.882, 0.114, 0.180, 0.45)'
  d2d border-thickness 1
  d2d running-indicator-color '(0.882, 0.114, 0.180, 1.0)'
  d2d drawing-accent-color '(0.882, 0.114, 0.180, 1.0)'
  d2d drawing-secondary-color '(0.941, 0.541, 0.643, 1.0)'
  d2d drawing-dark-color '(0.137, 0.102, 0.122, 1.0)'
  d2d notification-badge-color '(1.0, 0.275, 0.333, 1.0)'
  d2d label-background-color '(0.086, 0.063, 0.082, 0.92)'
  d2d label-foreground-color '(0.949, 0.914, 0.925, 1.0)'
  d2d label-border-color '(0.882, 0.114, 0.180, 0.5)'
  d2d label-border-thickness 1
  d2d label-border-radius 2.0
  d2d separator-color '(0.322, 0.231, 0.267, 1.0)'
  d2d separator-thickness 1
  echo "dock: ink glass, crimson hairline + running dots, sakura secondary, dark labels"
}

step_arcmenu() {
  arc override-menu-theme true
  arc menu-background-color "'rgba(22,16,21,0.96)'"
  arc menu-foreground-color "'rgb(242,233,236)'"
  arc menu-border-color "'rgba(225,29,46,0.35)'"
  arc menu-border-width 1
  arc menu-border-radius 18
  arc menu-separator-color "'rgba(82,59,68,0.8)'"
  arc menu-item-hover-bg-color "'rgba(225,29,46,0.25)'"
  arc menu-item-hover-fg-color "'rgb(255,255,255)'"
  arc menu-item-active-bg-color "'rgb(225,29,46)'"
  arc menu-item-active-fg-color "'rgb(255,255,255)'"
  arc menu-button-fg-color "(true, 'rgb(225,29,46)')"
  arc menu-button-hover-bg-color "(true, 'rgba(225,29,46,0.22)')"
  arc menu-button-hover-fg-color "(true, 'rgb(255,255,255)')"
  arc menu-button-active-bg-color "(true, 'rgba(225,29,46,0.6)')"
  arc menu-button-active-fg-color "(true, 'rgb(255,255,255)')"
  arc menu-button-border-radius '(true, 10)'
  echo "arcmenu: ink menu, crimson hover/active, crimson logo button"
}

step_terminal() {
  mkdir -p ~/.local/share/org.gnome.Ptyxis/palettes
  cp "$B/ptyxis/bapirlo-kuro.palette" ~/.local/share/org.gnome.Ptyxis/palettes/
  local P; P=$(gsettings get org.gnome.Ptyxis default-profile-uuid | tr -d "'")
  local PATH_="/org/gnome/Ptyxis/Profiles/$P/"
  gsettings set "org.gnome.Ptyxis.Profile:$PATH_" palette 'bapirlo-kuro'
  gsettings set "org.gnome.Ptyxis.Profile:$PATH_" opacity 0.93 2>/dev/null || true
  gsettings set org.gnome.Ptyxis use-system-font false 2>/dev/null || true
  gsettings set org.gnome.Ptyxis font-name 'JetBrainsMono Nerd Font 11' 2>/dev/null || true
  echo "terminal: Ptyxis 'Bapirlo Kuro' palette, 93% opacity, JetBrainsMono Nerd Font"
}

step_fastfetch() {
  cp "$B/fastfetch/config.jsonc" "$B/fastfetch/bapirlo-logo.ans" ~/.config/fastfetch/
  echo "fastfetch: Kuro logo + crimson/sakura keys"
}

step_wallpaper() {
  local D=~/.local/share/backgrounds/bapirlo; mkdir -p "$D"
  cp ~/bapirlo-os/build/art/hero-2560x1600.png "$D/kuro-2560x1600.png"
  cp ~/bapirlo-os/build/art/blur-2560x1600.png "$D/kuro-blur-2560x1600.png"
  # the folder watcher would replace this with a slideshow of the raw 736px images — pause it
  systemctl --user disable --now bapirlo-wallpaper.path 2>/dev/null || true
  gsettings set org.gnome.desktop.background picture-uri "file://$D/kuro-2560x1600.png"
  gsettings set org.gnome.desktop.background picture-uri-dark "file://$D/kuro-2560x1600.png"
  gsettings set org.gnome.desktop.background picture-options 'zoom'
  gsettings set org.gnome.desktop.background primary-color '#0E0A0D'
  gsettings set org.gnome.desktop.screensaver picture-uri "file://$D/kuro-blur-2560x1600.png"
  gsettings set org.gnome.desktop.screensaver picture-options 'zoom'
  echo "wallpaper: upscaled + graded Kuro art; lock screen uses the blurred variant"
}

step_restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  for d in .themes .config/gtk-4.0 .config/gtk-3.0 .config/fastfetch .local/share/org.gnome.Ptyxis .local/share/backgrounds/bapirlo; do
    rm -rf ~/"$d"; [ -e "$BK/$d" ] && cp -a "$BK/$d" ~/"$d"
  done
  dconf load / < "$BK/dconf-full.ini"
  grep -qx enabled "$BK/wallpaper-watcher.txt" 2>/dev/null && systemctl --user enable --now bapirlo-wallpaper.path
  echo "desktop restored (log out/in if anything looks stale)"
}

case "${1:-}" in
  backup) step_backup ;; topbar) step_topbar ;; blur) step_blur ;; gtk) step_gtk ;; dock) step_dock ;;
  arcmenu) step_arcmenu ;; terminal) step_terminal ;; fastfetch) step_fastfetch ;; wallpaper) step_wallpaper ;;
  restore) step_restore ;;
  all) step_backup; step_wallpaper; step_topbar; step_blur; step_gtk; step_dock; step_arcmenu; step_terminal; step_fastfetch ;;
  *) sed -n 2,6p "$0"; exit 1 ;;
esac
