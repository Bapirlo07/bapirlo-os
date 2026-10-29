#!/usr/bin/env bash
# Bapirlo OS round 11 — wallpapers, everything that does NOT need your password (after 1100-round11-install.sh).
#   bash ~/bapirlo-os/1110-round11.sh              # backup + all steps
#   bash ~/bapirlo-os/1110-round11.sh STEP …       # only those steps (live app switch)
#   bash ~/bapirlo-os/1110-round11.sh restore      # undo all of it
#
#  live    4 original live wallpapers (tools/build-live-wallpapers.py: night, dawn, day, dusk — 16 s
#          seamless loops, 2560x1600 H.264, ~70 MB) into the Bapirlo originals
#  app     the Wallpapers app (Super+Alt+P; also in the app grid), Super+Alt+N = next wallpaper,
#          Files right-click → Scripts → "Set as wallpaper"
#  switch  the wallpaper manager takes over (bin/bapirlo-wallpaper; the 10-minute timer keeps running
#          it): mode Fixed on the wallpaper you have now, OS colours follow the wallpaper — so the
#          theme is re-made from it straight away (Theme Studio, with the usual fade)
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/ext.sh"
LATEST=~/theme-backups/LATEST-ROUND11
ALL_STEPS=(live app switch)

LIVE_DIR=~/.local/share/backgrounds/bapirlo/originals/live
APPS=~/.local/share/applications
DESKTOP=$APPS/os.bapirlo.Wallpapers.desktop
NAUT=~/.local/share/nautilus/scripts
NSCRIPT="$NAUT/Set as wallpaper"
KB=/org/gnome/settings-daemon/plugins/media-keys
KEYS=(bapirlo-wallpapers bapirlo-wallpaper-next)
CONF=~/.config/bapirlo/wallpaper.json
WSTATE=~/.local/state/bapirlo/wallpaper
DAYCYCLE=$HERE/bin/bapirlo-daycycle
DCONF_PATHS=(/org/gnome/desktop/background/ "$KB/")

backup() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round11
  mkdir -p "$BK"
  gsettings get org.gnome.shell enabled-extensions > "$BK/enabled-extensions.txt"
  backup_dconf "$BK" "${DCONF_PATHS[@]}"
  cp -a "$DAYCYCLE" "$BK/bapirlo-daycycle"
  cp -a ~/.local/state/bapirlo/studio/active.json "$BK/studio-active.json" 2>/dev/null || touch "$BK/no-studio-active"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"
}

step_live() {
  echo "== live wallpapers"
  local b=$HERE/build/live-wallpapers
  if ! ls "$b"/*-live.mp4 >/dev/null 2>&1; then
    echo "   rendering (≈4 min)…"; nice -n 10 python3 "$HERE/tools/build-live-wallpapers.py" "$b"
  fi
  mkdir -p "$LIVE_DIR"
  cp -a "$b"/*-live.mp4 "$LIVE_DIR/"
  ls -1 "$LIVE_DIR" | sed 's/^/   /'
}

add_key() {   # add_key NAME BINDING COMMAND LABEL
  local path=$KB/custom-keybindings/$1/
  dconf write "${path}name" "'$4'"
  dconf write "${path}binding" "'$2'"
  dconf write "${path}command" "'$3'"
  python3 - "$path" <<'PY'
import ast, subprocess, sys
k = "org.gnome.settings-daemon.plugins.media-keys"
v = subprocess.run(["gsettings", "get", k, "custom-keybindings"], capture_output=True, text=True).stdout.strip()
cur = [] if v.startswith("@as") else ast.literal_eval(v)
if sys.argv[1] not in cur:
    subprocess.run(["gsettings", "set", k, "custom-keybindings", str(cur + [sys.argv[1]])], check=True)
PY
}

step_app() {
  echo "== Wallpapers app + keys"
  mkdir -p "$APPS"
  cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Wallpapers
GenericName=Wallpapers and live wallpapers
Comment=Pick a wallpaper or a live one, and make Bapirlo OS themes from it (Wallpapers + Theme Studio)
Exec=$HERE/wallpaper/bapirlo-wallpapers %F
Icon=preferences-desktop-wallpaper
Terminal=false
Categories=Settings;DesktopSettings;GTK;
MimeType=image/jpeg;image/png;image/webp;video/mp4;video/webm;video/x-matroska;video/quicktime;image/gif;
Keywords=wallpaper;background;live;video;animated;theme;studio;colour;color;accent;palette;bapirlo;
StartupWMClass=os.bapirlo.Wallpapers
StartupNotify=true
EOF
  update-desktop-database -q "$APPS" 2>/dev/null || true
  add_key bapirlo-wallpapers '<Super><Alt>p' "$HERE/wallpaper/bapirlo-wallpapers" 'Wallpapers'
  add_key bapirlo-wallpaper-next '<Super><Alt>n' "$HERE/bin/bapirlo-wallpaper next" 'Next wallpaper'
  mkdir -p "$NAUT"
  cat > "$NSCRIPT" <<EOF
#!/bin/sh
# Files → right-click → Scripts → Set as wallpaper (Bapirlo OS): the first selected picture / video
f=\$(printf '%s\n' "\$NAUTILUS_SCRIPT_SELECTED_FILE_PATHS" | head -n1)
[ -n "\$f" ] && exec "$HERE/bin/bapirlo-wallpaper" set "\$f"
EOF
  chmod +x "$NSCRIPT"
  echo "   app: Super+Alt+P · next: Super+Alt+N · Files: right-click → Scripts → Set as wallpaper"
}

step_switch() {
  echo "== the wallpaper manager takes over"
  cp -a "$HERE/wallpaper/install/bapirlo-daycycle.new" "$DAYCYCLE"
  local uri cur
  uri=$(gsettings get org.gnome.desktop.background picture-uri | tr -d "'")
  cur=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(urllib.parse.urlparse(sys.argv[1]).path))' "$uri")
  [ -f "$cur" ] || cur=~/.local/share/backgrounds/bapirlo/originals/dusk-b.jpg
  echo "   now: $cur  (Fixed; colours follow it — re-theming, a few seconds)"
  "$HERE/bin/bapirlo-wallpaper" set "$cur"
  "$HERE/bin/bapirlo-wallpaper" status | sed 's/^/   /'
}

apply() {
  if ! grep -qs '"Before round 11"' /timeshift/snapshots/*/info.json; then
    echo "No Timeshift snapshot \"Before round 11\" yet — run first:  bash $HERE/1100-round11-install.sh"; exit 1
  fi
  local steps=("$@")
  [ ${#steps[@]} -gt 0 ] || steps=("${ALL_STEPS[@]}")
  for s in "${steps[@]}"; do [[ " ${ALL_STEPS[*]} " == *" $s "* ]] || { echo "unknown step: $s"; exit 64; }; done
  if [ ${#steps[@]} -eq ${#ALL_STEPS[@]} ] || ! [ -s "$LATEST" ]; then backup; else echo "backup: keeping $(cat "$LATEST")"; fi
  for s in "${steps[@]}"; do "step_$s"; done
  echo
  echo "Done. Open Wallpapers with Super+Alt+P. Undo: bash $HERE/1110-round11.sh restore"
}

restore() {
  local BK; BK=$(cat "$LATEST" 2>/dev/null) || { echo "nothing to restore ($LATEST missing)"; exit 1; }
  # theme first (while the manager can still tell its own presets apart), then the rest
  python3 - "$HERE" <<'PY' || true
import sys; sys.path.insert(0, sys.argv[1] + "/lib")
import bapirlo_wallpaper as W
W.theme_off()
PY
  cp -a "$BK/bapirlo-daycycle" "$DAYCYCLE"
  gsettings set org.gnome.shell enabled-extensions "$(cat "$BK/enabled-extensions.txt")"
  restore_dconf "$BK" "${DCONF_PATHS[@]}"
  rm -f "$DESKTOP" "$NSCRIPT" "$CONF"
  rm -rf "$WSTATE" "$LIVE_DIR"
  update-desktop-database -q "$APPS" 2>/dev/null || true
  "$DAYCYCLE"
  echo "Restored from $BK (your ~/Pictures/wallpapers/bapirlo files are kept; Theme Studio presets made from"
  echo "wallpapers stay in Theme Studio's list)."
}

case "${1:-}" in
  restore) restore ;;
  ""|live|app|switch) apply "$@" ;;
  *) sed -n '2,15p' "$0"; exit 64 ;;
esac
