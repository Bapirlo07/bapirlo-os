#!/usr/bin/env bash
# Kuro OS — app theming in the Kuro palette (NO sudo). Run after 130-install-step.sh.
#   bash ~/bapirlo-os/115-app-themes.sh            # backup + apply
#   bash ~/bapirlo-os/115-app-themes.sh restore    # configs back as they were
#
#  Starship prompt (fish) · cava colours · Vesktop/Vencord theme · Spicetify (Spotify) theme ·
#  Chrome theme folder (load once by hand) · VS Code theme (only if VS Code is installed)
# Sources: ~/bapirlo-os/apps/*  (palette: tools/palette.py)
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
APPS=$HERE/apps
FISH_CONF=~/.config/fish/config.fish
STARSHIP=~/.config/starship.toml
CAVA=~/.config/cava/config
VESK=~/.config/vesktop
SPICE=~/.config/spicetify
SPOTIFY_DIR=~/.local/share/spotify-launcher/install/usr/share/spotify
CHROME_THEME=~/.local/share/bapirlo/chrome-theme
LATEST=~/theme-backups/LATEST-APP-THEMES
MARK="# bapirlo: starship prompt"

running() { pgrep -x "$1" >/dev/null 2>&1; }

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-app-themes
  mkdir -p "$BK"
  for f in "$FISH_CONF" "$STARSHIP" "$CAVA" "$VESK/settings/settings.json" "$SPICE/config-xpui.ini"; do
    [ -f "$f" ] && { mkdir -p "$BK/files$(dirname "$f")"; cp -a "$f" "$BK/files$f"; }
  done
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  # ---- Starship (fish): replaces the Pure prompt; config.fish keeps everything else
  if command -v starship >/dev/null; then
    cp "$APPS/starship/starship.toml" "$STARSHIP"
    grep -qF "$MARK" "$FISH_CONF" || printf '\n%s\nif status is-interactive; and command -q starship\n    starship init fish | source\nend\n' "$MARK" >> "$FISH_CONF"
    echo "starship: ok (new terminals)"
  else echo "starship: not installed — skipped"; fi

  # ---- cava
  if command -v cava >/dev/null; then
    mkdir -p "$(dirname "$CAVA")"; cp "$APPS/cava/config" "$CAVA"; echo "cava: ok"
  else echo "cava: not installed — skipped"; fi

  # ---- Vesktop / Vencord
  if command -v vesktop >/dev/null; then
    running vesktop && { echo "vesktop: close Vesktop first (it overwrites its settings on exit) — skipped"; } || {
      mkdir -p "$VESK/themes" "$VESK/settings"
      cp "$APPS/vesktop/bapirlo.theme.css" "$VESK/themes/"
      python3 - "$VESK/settings/settings.json" <<'PY'
import json, os, sys
p = sys.argv[1]
s = json.load(open(p)) if os.path.exists(p) else {}
themes = s.get("enabledThemes", [])
if "bapirlo.theme.css" not in themes: themes.append("bapirlo.theme.css")
s["enabledThemes"] = themes
json.dump(s, open(p, "w"), indent=4)
PY
      echo "vesktop: theme installed + enabled"; }
  else echo "vesktop: not installed — skipped"; fi

  # ---- Spicetify (spotify-launcher install)
  if command -v spicetify >/dev/null && [ -d "$SPOTIFY_DIR" ]; then
    running spotify && { echo "spotify: close Spotify first — skipped"; } || {
      spicetify config >/dev/null 2>&1 || true                     # creates config-xpui.ini on first run
      mkdir -p "$SPICE/Themes"; rm -rf "$SPICE/Themes/Bapirlo"; cp -a "$APPS/spicetify/Bapirlo" "$SPICE/Themes/"
      spicetify config spotify_path "$SPOTIFY_DIR" prefs_path ~/.config/spotify/prefs \
        current_theme Bapirlo color_scheme Kuro inject_css 1 replace_colors 1 overwrite_assets 0
      spicetify backup apply || spicetify restore backup apply
      echo "spicetify: applied"; }
  else echo "spicetify: not installed (or Spotify never started) — skipped"; fi

  # ---- Chrome theme (Chrome only loads off-store themes by hand: once, see below)
  mkdir -p "$(dirname "$CHROME_THEME")"; rm -rf "$CHROME_THEME"; cp -a "$APPS/chrome-theme" "$CHROME_THEME"
  echo "chrome: theme folder ready at $CHROME_THEME"

  # ---- VS Code (skipped install; theme waits here)
  if [ -d ~/.vscode/extensions ] || [ -d ~/.vscode-oss/extensions ]; then
    for d in ~/.vscode/extensions ~/.vscode-oss/extensions; do
      [ -d "$d" ] && { rm -rf "$d/bapirlo.bapirlo-kuro-1.0.0"; cp -a "$APPS/vscode-theme" "$d/bapirlo.bapirlo-kuro-1.0.0"; }
    done
    echo "vscode: theme installed (Ctrl+K Ctrl+T → Bapirlo Kuro)"
  else echo "vscode: not installed — theme kept in $APPS/vscode-theme"; fi
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  # config.fish: drop our block, or put the old file back
  if [ -f "$BK/files$FISH_CONF" ]; then cp -a "$BK/files$FISH_CONF" "$FISH_CONF"; fi
  for f in "$STARSHIP" "$CAVA" "$VESK/settings/settings.json"; do
    if [ -f "$BK/files$f" ]; then cp -a "$BK/files$f" "$f"; else rm -f "$f"; fi
  done
  rm -f "$VESK/themes/bapirlo.theme.css"
  command -v spicetify >/dev/null && ! running spotify && spicetify restore 2>/dev/null || true
  rm -rf "$SPICE/Themes/Bapirlo" "$CHROME_THEME" ~/.vscode/extensions/bapirlo.bapirlo-kuro-1.0.0 ~/.vscode-oss/extensions/bapirlo.bapirlo-kuro-1.0.0
  echo "restored (Chrome: chrome://settings/appearance → Reset to default)"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
