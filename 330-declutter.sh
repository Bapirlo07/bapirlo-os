#!/usr/bin/env bash
# Bapirlo OS — tidy the app grid / ArcMenu and the home folder (NO sudo).
#   bash ~/bapirlo-os/330-declutter.sh            # backup + apply
#   bash ~/bapirlo-os/330-declutter.sh restore    # undo
#
# - HIDE: leftovers from other desktops (Openbox/Tint2/Xfce/Thunar/rofi…), test tools and
#   duplicates get NoDisplay=true via a copy in ~/.local/share/applications (tagged
#   X-Bapirlo-Declutter so restore only removes ours). Still installed, still open files,
#   still runnable from a terminal — just not listed in the grid, ArcMenu or search.
# - TOOLS folder: things needed now and then (Extensions, Tweaks, Disks, NVIDIA…) go into one
#   "Tools" folder in the app grid (replaces the old "System" folder).
# - HOME: ~/.hidden hides folders/files in Files (and every GTK file chooser). Ctrl+H shows them.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
LATEST=~/theme-backups/LATEST-DECLUTTER
APPS=~/.local/share/applications
SYS=/usr/share/applications
AF=org.gnome.desktop.app-folders
FP=/org/gnome/desktop/app-folders/folders

HIDE=(arandr avahi-discover bssh bvnc jgmenu lstopo micro vim obconf-qt tint2 tint2conf
      rofi rofi-theme-selector pasystray qv4l2 qvidcap thunar thunar-bulk-rename
      thunar-settings thunar-volman-settings xfce4-terminal org.x.editor org.gnome.Ptyxis
      org.gnome.Evince)
TOOLS=(org.gnome.Extensions com.mattjakeman.ExtensionManager org.gnome.tweaks
       org.gnome.GTK4ThemeSwitcher com.desktop.ding com.github.amezin.ddterm
       org.gnome.DiskUtility org.gnome.baobab nm-connection-editor nvidia-settings
       org.pulseaudio.pavucontrol net.nokyan.Resources btop org.gnome.PowerStats
       org.cachyos.KernelManager org.cachyos.scx-manager cachyos-hello cachyos-pi
       com.shellyorg.shelly arch-update timeshift-gtk mcontrolcenter
       org.freedesktop.MalcontentControl org.gnome.Meld cmake-gui org.gnome.SimpleScan)
HOME_HIDE=(Public Templates Modelfile theme-backups)

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-declutter
  mkdir -p "$BK"
  dconf dump /org/gnome/desktop/app-folders/ > "$BK/app-folders.ini"
  gsettings get org.gnome.shell app-picker-layout > "$BK/app-picker-layout.txt"
  [ -e ~/.hidden ] && cp -a ~/.hidden "$BK/dot-hidden"
  cp -a "$APPS" "$BK/applications"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo "== hide clutter apps"
  for a in "${HIDE[@]}"; do
    local src=$SYS/$a.desktop dst=$APPS/$a.desktop
    [ -e "$src" ] || continue
    [ -e "$dst" ] && ! grep -q '^X-Bapirlo-Declutter=' "$dst" && { echo "  skip $a (own override exists)"; continue; }
    # NoDisplay + tag go right under the first [Desktop Entry] header (not into [Desktop Action …])
    sed '0,/^\[Desktop Entry\]/{/^\[Desktop Entry\]/a NoDisplay=true\nX-Bapirlo-Declutter=true
}; /^NoDisplay=/{x;/seen/{x;d};s/.*/seen/;x}' "$src" > "$dst"
    echo "  hidden $a"
  done
  update-desktop-database "$APPS" 2>/dev/null || true

  echo "== Tools folder"
  local list=()
  for a in "${TOOLS[@]}"; do [ -e "$SYS/$a.desktop" ] || [ -e "$APPS/$a.desktop" ] && list+=("'$a.desktop'"); done
  dconf write "$FP/Tools/name" "'Tools'"
  dconf write "$FP/Tools/apps" "[$(IFS=,; echo "${list[*]}")]"
  dconf write "$FP/Tools/translate" false
  dconf reset -f "$FP/System/"
  gsettings set $AF folder-children "['Tools', 'Utilities', 'YaST', 'Pardus']"
  gsettings reset org.gnome.shell app-picker-layout   # re-sort the grid around the new folder

  echo "== hide home clutter (~/.hidden)"
  touch ~/.hidden
  for n in "${HOME_HIDE[@]}"; do grep -qxF "$n" ~/.hidden || echo "$n" >> ~/.hidden; done

  echo
  echo "done. Grid/ArcMenu update right away; reopen Files to see the home folder change."
  echo "Hidden folders: Ctrl+H in Files. Undo: bash ~/bapirlo-os/330-declutter.sh restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restore <- $BK"
  grep -l '^X-Bapirlo-Declutter=true' "$APPS"/*.desktop 2>/dev/null | xargs -r rm -v
  update-desktop-database "$APPS" 2>/dev/null || true
  dconf reset -f /org/gnome/desktop/app-folders/
  dconf load /org/gnome/desktop/app-folders/ < "$BK/app-folders.ini"
  gsettings set org.gnome.shell app-picker-layout "$(cat "$BK/app-picker-layout.txt")"
  if [ -e "$BK/dot-hidden" ]; then cp -a "$BK/dot-hidden" ~/.hidden; else rm -f ~/.hidden; fi
  echo "restored."
}

case "${1:-apply}" in
  apply) apply ;;
  restore) restore ;;
  *) echo "usage: $0 [apply|restore]"; exit 1 ;;
esac
