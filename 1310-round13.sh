#!/usr/bin/env bash
# Bapirlo OS round 13 (NO sudo):
#   · wallpaper shuffle ON: a new wallpaper + theme every SHUFFLE_HOURS (default 3), each bringing back
#     its own bar look / widgets (round 12)          change: bapirlo-wallpaper mode fixed|shuffle N
#   · notifications (Dynamic Island + GNOME banners) wear the bar look — manga = comic bubble
#   · accent pulse: active workspace + focused window border breathe 3x after a switch
#     (off: gsettings … bapirlo-bar accent-pulse false)
#   · login + unlock sounds generated in the wallpaper's mood (sounds/mood/bapirlo-sound-mood)
#   · "Send Wallpaper to Phone" (bin/bapirlo-phone-wallpaper, GSConnect)
#   bash ~/bapirlo-os/1310-round13.sh            install
#   bash ~/bapirlo-os/1310-round13.sh restore    put it all back
# Needs a log out/in once (bar extension code). Backup: ~/theme-backups/LATEST-ROUND13
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
LATEST=~/theme-backups/LATEST-ROUND13
EXT_DIR=~/.local/share/gnome-shell/extensions
BAR=bapirlo-bar@bapirlo-os
SND=~/.local/share/sounds/bapirlo/stereo
HOURS=${SHUFFLE_HOURS:-3}

backup() {
  if [ -e "$LATEST" ]; then echo "backup kept: $(readlink -f "$LATEST")"; return; fi
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round13
  mkdir -p "$BK/sounds"
  cp -a "$EXT_DIR/$BAR" "$BK/"
  cp -a "$SND"/. "$BK/sounds/"
  cp -a ~/.config/bapirlo/wallpaper.json "$BK/" 2>/dev/null || true
  [ -f ~/theme-backups/bapirlo-lockd.pre-round12 ] && cp -a ~/theme-backups/bapirlo-lockd.pre-round12 "$BK/bapirlo-lockd"
  ln -sfn "$BK" "$LATEST"; echo "backup -> $BK"
}

install() {
  rm -rf "${EXT_DIR:?}/$BAR"; cp -rL "$HERE/bar/$BAR" "$EXT_DIR/"
  glib-compile-schemas "$EXT_DIR/$BAR/schemas"
  "$HERE/sounds/mood/bapirlo-sound-mood"
  systemctl --user restart bapirlo-lockd.service
  sed "s|@HOME@|$HOME|g" "$HERE/apps/os.bapirlo.PhoneWallpaper.desktop" > ~/.local/share/applications/os.bapirlo.PhoneWallpaper.desktop
  ln -sfn "$HERE/bin/bapirlo-phone-wallpaper" ~/.local/bin/bapirlo-phone-wallpaper 2>/dev/null || true
  "$HERE/bin/bapirlo-wallpaper" mode shuffle "$HOURS"
  echo "round 13: installed. Log out/in once for the bar (notification looks + accent pulse)."
}

restore() {
  local BK; BK=$(readlink -f "$LATEST")
  [ -d "$BK" ] || { echo "no backup at $LATEST"; exit 1; }
  rm -rf "${EXT_DIR:?}/$BAR"; cp -a "$BK/$BAR" "$EXT_DIR/"
  rm -f "$SND/desktop-screen-unlock.oga"; cp -a "$BK/sounds"/. "$SND/"
  [ -f "$BK/bapirlo-lockd" ] && cp -a "$BK/bapirlo-lockd" "$HERE/bin/bapirlo-lockd" && systemctl --user restart bapirlo-lockd.service
  if [ -f "$BK/wallpaper.json" ]; then
    "$HERE/bin/bapirlo-wallpaper" mode "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["mode"])' "$BK/wallpaper.json")"
  fi
  rm -f ~/.local/share/applications/os.bapirlo.PhoneWallpaper.desktop
  echo "restored from $BK (Theme Studio still calls bapirlo-sound-mood; run it with 'off' for the old login sound)"
}

case "${1:-}" in
  "") backup; install ;;
  restore) restore ;;
  *) sed -n 2,13p "$0"; exit 1 ;;
esac
