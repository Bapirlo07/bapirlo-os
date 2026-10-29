#!/usr/bin/env bash
# Bapirlo OS — switchable top bar looks (NO sudo). bapirlo-bar gains looks.js:
#   classic (the bar as it was) · manga · glass · islands · flat — colours follow the wallpaper palette.
#   The bottom dock (Dash to Dock) follows the same look; classic gives it back its own colour settings.
#   Switch: the Bar Looks app · right-click an empty spot on the bar · Super+Alt+L cycles · bapirlo-bar-look <name|next>
#   bash ~/bapirlo-os/1200-bar-looks.sh            install the bar + start on the manga look (LOOK=… to pick)
#   bash ~/bapirlo-os/1200-bar-looks.sh restore    put the previous bar code + settings back
# Needs a log out/in once (the shell caches the bar's JS); after that switching is live.
# Backup: ~/theme-backups/LATEST-BAR-LOOKS
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
LATEST=~/theme-backups/LATEST-BAR-LOOKS
UUID=bapirlo-bar@bapirlo-os
EXT_DIR=~/.local/share/gnome-shell/extensions
DCONF=/org/gnome/shell/extensions/bapirlo-bar/
LOOK=${LOOK:-manga}

backup() {
  if [ -e "$LATEST" ]; then echo "backup kept: $(readlink -f "$LATEST")"; return; fi   # the pre-looks bar
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-bar-looks
  mkdir -p "$BK/extensions"
  cp -a "$EXT_DIR/$UUID" "$BK/extensions/"
  dconf dump $DCONF > "$BK/bapirlo-bar.dconf"
  ln -sfn "$BK" "$LATEST"; echo "backup -> $BK"
}

install() {
  rm -rf "${EXT_DIR:?}/$UUID"
  cp -rL "$HERE/bar/$UUID" "$EXT_DIR/"
  glib-compile-schemas "$EXT_DIR/$UUID/schemas"
  "$HERE/bin/bapirlo-bar-look" "$LOOK"
  # the Bar Looks app (also in the bar's right-click menu)
  sed "s|@HOME@|$HOME|g" "$HERE/bar-looks/os.bapirlo.BarLooks.desktop" > ~/.local/share/applications/os.bapirlo.BarLooks.desktop
  ln -sfn "$HERE/bar-looks/bapirlo-bar-looks" "$HERE/bin/bapirlo-bar-looks"
  echo "bar: installed. Log out and back in once, then switch any time (right-click the bar / Super+Alt+L)."
}

restore() {
  local BK; BK=$(readlink -f "$LATEST")
  [ -d "$BK" ] || { echo "no backup at $LATEST"; exit 1; }
  rm -rf "${EXT_DIR:?}/$UUID"; cp -a "$BK/extensions/$UUID" "$EXT_DIR/"
  dconf reset -f $DCONF; dconf load $DCONF < "$BK/bapirlo-bar.dconf"
  # dock: the colour keys saved when the looks first left classic
  local st=~/.local/state/bapirlo/bar
  if [ -f "$st/dock-classic.json" ] && [ "$(cat "$st/dock-look" 2>/dev/null)" != classic ]; then
    python3 -c 'import json,sys; [print(k, v) for k, v in json.load(open(sys.argv[1])).items()]' "$st/dock-classic.json" |
      while read -r k v; do dconf write "/org/gnome/shell/extensions/dash-to-dock/$k" "$v"; done
    echo "dock: colour settings put back"
  fi
  rm -f "$st/look.css" "$st/dock-look" "$st/dock-classic.json" ~/.local/share/applications/os.bapirlo.BarLooks.desktop
  echo "restored from $BK (log out/in to unload the looks code)"
}

case "${1:-}" in
  "") backup; install ;;
  restore) restore ;;
  *) sed -n 2,7p "$0"; exit 1 ;;
esac
