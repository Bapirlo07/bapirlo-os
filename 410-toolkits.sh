#!/usr/bin/env bash
# Bapirlo OS polish — step 2: every app toolkit gets the same ink + crimson look.
#   bash ~/bapirlo-os/410-toolkits.sh install    # YOU run this once (sudo): kvantum qt6ct qt6-wayland
#   bash ~/bapirlo-os/410-toolkits.sh            # backup + apply (no sudo)
#   bash ~/bapirlo-os/410-toolkits.sh restore    # undo
#
# - GTK3 (WhiteSur): dark neutral greys -> same lightness with the shell's ink undertone
#   (tools/tint-surfaces.py). Accent is already crimson (60-desktop-v2 recolour).
#   NOTE: re-running 60-desktop-v2's WhiteSur install would undo the tint — re-run this after it.
# - GTK4/libadwaita: ~/.config/gtk-4.0/gtk.css becomes WhiteSur + bapirlo-surfaces.css
# - Qt6 (MControlCenter, CachyOS tools): Kvantum theme "Bapirlo-Kuro" generated from the stock dark
#   theme with the same tint + crimson highlight; qt6ct sets style/icons/fonts; native Wayland
#   via qt6-wayland. QT_QPA_PLATFORMTHEME=qt6ct in environment.d -> needs logout.
# - Flatpak (none installed yet): user overrides so future apps read the same GTK3/4 theme + icons.
# - Electron/Chrome: nothing to do — Chrome, Electron 39/43 already run native Wayland and
#   follow the dark preference through the portal.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as yourself, WITHOUT sudo."; exit 1; }
cd "$(dirname "$0")"
LATEST=~/theme-backups/LATEST-TOOLKITS
G3=~/.themes/WhiteSur-Dark-red/gtk-3.0
G4=~/.config/gtk-4.0
KV=~/.config/Kvantum
QT=~/.config/qt6ct
ENVF=~/.config/environment.d/90-bapirlo-qt.conf
FPO=~/.local/share/flatpak/overrides/global
PKGS=(kvantum qt6ct qt6-wayland)

install_pkgs() {
  echo "== installing ${PKGS[*]} (pacman shows the list and asks first)"
  sudo pacman -S --needed "${PKGS[@]}"
  echo "done — now tell Claude, or run: bash ~/bapirlo-os/410-toolkits.sh"
}

apply() {
  for p in "${PKGS[@]}"; do pacman -Q "$p" &>/dev/null || { echo "!! $p missing — run: bash $0 install"; exit 1; }; done
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-toolkits
  mkdir -p "$BK/gtk-3.0" "$BK/gtk-4.0"
  cp -a "$G3"/*.css "$BK/gtk-3.0/"
  cp -a "$G4"/gtk.css "$BK/gtk-4.0/"            # the symlink itself
  [ -e "$KV" ] && cp -a "$KV" "$BK/Kvantum"
  [ -e "$QT" ] && cp -a "$QT" "$BK/qt6ct"
  [ -e "$ENVF" ] && cp -a "$ENVF" "$BK/"
  [ -e "$FPO" ] && cp -a "$FPO" "$BK/flatpak-global"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo "== 1/4 GTK3 + GTK4 surfaces"
  python3 tools/tint-surfaces.py
  rm -f "$G4/gtk.css"
  printf '%s\n' '/* Bapirlo OS: WhiteSur (crimson) + ink surfaces — 410-toolkits.sh */' \
    '@import url("gtk-Dark.css");' '@import url("bapirlo-surfaces.css");' > "$G4/gtk.css"

  echo "== 2/4 Qt: Kvantum Bapirlo-Kuro"
  local base=""
  for t in KvLibadwaitaDark KvGnomeDark KvArcDark; do [ -d /usr/share/Kvantum/$t ] && { base=$t; break; }; done
  [ -n "$base" ] || { echo "!! no stock dark Kvantum theme found"; exit 1; }
  python3 tools/tint-surfaces.py --kvantum /usr/share/Kvantum/$base "$KV/Bapirlo-Kuro" Bapirlo-Kuro
  printf '[General]\ntheme=Bapirlo-Kuro\n' > "$KV/kvantum.kvconfig"

  echo "== 3/4 qt6ct + environment"
  mkdir -p "$QT" "$(dirname "$ENVF")"
  local ui mono
  ui=$(gsettings get org.gnome.desktop.interface font-name | tr -d "'")      # e.g. Inter 10.5
  mono=$(gsettings get org.gnome.desktop.interface monospace-font-name | tr -d "'")
  cat > "$QT/qt6ct.conf" <<EOF
[Appearance]
custom_palette=false
icon_theme=$(gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")
standard_dialogs=xdgdesktopportal
style=kvantum

[Fonts]
fixed="${mono% *},${mono##* },-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
general="${ui% *},${ui##* },-1,5,400,0,0,0,0,0,0,0,0,0,0,1"

[Interface]
dialog_buttons_have_icons=0
menus_have_icons=true
underline_shortcut=1
wheel_scroll_lines=3
EOF
  printf '# Bapirlo OS — 410-toolkits.sh\nQT_QPA_PLATFORMTHEME=qt6ct\n' > "$ENVF"

  echo "== 4/4 Flatpak overrides (future apps)"
  flatpak override --user --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro \
    --filesystem=~/.themes:ro --filesystem=~/.local/share/icons:ro \
    --filesystem=xdg-config/Kvantum:ro --env=GTK_THEME=WhiteSur-Dark-red --env=QT_STYLE_OVERRIDE=kvantum
  flatpak override --user --show

  echo; echo "done. GTK apps: reopen them. Qt apps: log out/in once (environment). Undo: bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  cp -a "$BK/gtk-3.0/"*.css "$G3/"
  rm -f "$G4/gtk.css" "$G4/bapirlo-surfaces.css"; cp -a "$BK/gtk-4.0/gtk.css" "$G4/"
  rm -rf "$KV"; [ -e "$BK/Kvantum" ] && cp -a "$BK/Kvantum" "$KV"
  rm -rf "$QT"; [ -e "$BK/qt6ct" ] && cp -a "$BK/qt6ct" "$QT"
  rm -f "$ENVF"; [ -e "$BK/$(basename "$ENVF")" ] && cp -a "$BK/$(basename "$ENVF")" "$ENVF"
  rm -f "$FPO"; [ -e "$BK/flatpak-global" ] && cp -a "$BK/flatpak-global" "$FPO"
  echo "restored from $BK (packages stay: sudo pacman -Rns ${PKGS[*]} to remove; log out/in)"
}

case "${1:-}" in
  "") apply ;;
  install) install_pkgs ;;
  restore) restore ;;
  *) sed -n 2,5p "$0"; exit 1 ;;
esac
