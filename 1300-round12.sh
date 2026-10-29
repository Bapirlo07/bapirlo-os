#!/usr/bin/env bash
# Kuro OS round 12 (NO sudo): more of the desktop follows the wallpaper.
#   · Firefox: Kuro userChrome.css / userContent.css (+ user.js pref) — Theme Studio recolours them
#   · Vesktop: Studio now recolours the theme you actually have enabled (bapirlo-kuro.theme.css)
#   · VS Code: "Bapirlo Kuro" selected as the colour theme
#   · cava: colours follow the wallpaper (running cava refreshes live) + a "Visualizer" launcher
#   · each Theme Studio preset remembers its bar look, desk cards and their layout
#   bash ~/bapirlo-os/1300-round12.sh            install + recolour everything to the current preset
#   bash ~/bapirlo-os/1300-round12.sh restore    put it all back
# Needs a log out/in once for the desk widgets code; Firefox needs a restart.
# Backup: ~/theme-backups/LATEST-ROUND12
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
LATEST=~/theme-backups/LATEST-ROUND12
EXT_DIR=~/.local/share/gnome-shell/extensions
DESK=bapirlo-desk@bapirlo-os
VSC=~/.config/Code/User/settings.json
FF=$(cd "$HERE/studio" && python3 -c 'import studio; print(studio.FIREFOX or "")')

backup() {
  if [ -e "$LATEST" ]; then echo "backup kept: $(readlink -f "$LATEST")"; return; fi
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round12
  mkdir -p "$BK"
  cp -a "$EXT_DIR/$DESK" "$BK/"
  [ -f "$VSC" ] && cp -a "$VSC" "$BK/vscode-settings.json"
  if [ -n "$FF" ]; then
    echo "$FF" > "$BK/firefox-profile"
    [ -d "$FF/chrome" ] && cp -a "$FF/chrome" "$BK/firefox-chrome"
    [ -f "$FF/user.js" ] && cp -a "$FF/user.js" "$BK/firefox-user.js"
  fi
  ln -sfn "$BK" "$LATEST"; echo "backup -> $BK"
}

install() {
  # desk widgets: re-read the layout when Theme Studio switches preset
  rm -rf "${EXT_DIR:?}/$DESK"; cp -rL "$HERE/desk/$DESK" "$EXT_DIR/"
  glib-compile-schemas "$EXT_DIR/$DESK/schemas"

  if [ -n "$FF" ]; then
    mkdir -p "$FF/chrome"
    cp "$HERE/apps/firefox/userChrome.css" "$HERE/apps/firefox/userContent.css" "$FF/chrome/"
    touch "$FF/user.js"
    grep -v -F -f <(grep -o 'user_pref("[^"]*"' "$HERE/apps/firefox/user.js") "$FF/user.js" > "$FF/user.js.new" || true
    cat "$HERE/apps/firefox/user.js" >> "$FF/user.js.new"; mv "$FF/user.js.new" "$FF/user.js"
    echo "firefox: theme in $FF/chrome (restart Firefox)"
  fi

  if command -v code >/dev/null; then
    mkdir -p "$(dirname "$VSC")"
    python3 - "$VSC" <<'PY'
import json, sys, re
p = sys.argv[1]
try:
    d = json.loads(re.sub(r"(?m)^\s*//.*$", "", open(p).read()) or "{}")
except (OSError, ValueError):
    d = {}
d["workbench.colorTheme"] = "Bapirlo Kuro"
open(p, "w").write(json.dumps(d, indent=4) + "\n")
PY
    echo "vscode: Bapirlo Kuro selected"
  fi

  if command -v cava >/dev/null; then
    [ -f ~/.config/cava/config ] || { mkdir -p ~/.config/cava; cp "$HERE/apps/cava/config" ~/.config/cava/config; }
    cp "$HERE/apps/cava/os.bapirlo.Visualizer.desktop" ~/.local/share/applications/
  fi

  # recolour the newly tracked files to the active preset now, and seed its look memory
  (cd "$HERE/studio" && python3 - <<'PY'
import json, studio as S, engine as E
a = S.active()
if a:
    a["written"] = {**a.get("written", {}), **S.inplace_apply(E.Transform(a["palette"]), a.get("written", {}))}
    S.write_atomic(S.ACTIVE, json.dumps(a, indent=1))
    S.sh("pkill", "-USR2", "-x", "cava")
    print("studio: recoloured to", a["name"])
S.look_save((a or {}).get("preset", "original"))
PY
  )
  echo "round 12: installed. Log out/in once (desk widgets); restart Firefox."
}

restore() {
  local BK; BK=$(readlink -f "$LATEST")
  [ -d "$BK" ] || { echo "no backup at $LATEST"; exit 1; }
  rm -rf "${EXT_DIR:?}/$DESK"; cp -a "$BK/$DESK" "$EXT_DIR/"
  if [ -f "$BK/vscode-settings.json" ]; then cp -a "$BK/vscode-settings.json" "$VSC"; else rm -f "$VSC"; fi
  if [ -f "$BK/firefox-profile" ]; then
    local P; P=$(cat "$BK/firefox-profile")
    rm -rf "$P/chrome"; [ -d "$BK/firefox-chrome" ] && cp -a "$BK/firefox-chrome" "$P/chrome"
    if [ -f "$BK/firefox-user.js" ]; then cp -a "$BK/firefox-user.js" "$P/user.js"; else rm -f "$P/user.js"; fi
  fi
  rm -f ~/.local/share/applications/os.bapirlo.Visualizer.desktop
  echo "restored from $BK (Studio still lists the new files; it skips ones that are gone)"
}

case "${1:-}" in
  "") backup; install ;;
  restore) restore ;;
  *) sed -n 2,10p "$0"; exit 1 ;;
esac
