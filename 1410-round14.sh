#!/usr/bin/env bash
# Bapirlo OS round 14 (NO sudo — run 1400-round14-install.sh first):
#   · desk cards: Now playing (live visualizer) · To-do · Notes   (Super+Alt+D = add a to-do,
#     Super+Alt+E = edit; terminal: bapirlo-todo). Added to the cards of EVERY wallpaper's saved look.
#   · session restore: last session's apps come back on their workspaces after login
#     (bapirlo-session auto|ask|off|now)
#   · radial launcher: Super+Alt+O — 8 dock favourites around the pointer, in the bar's look
#   · Control Centre → Battery: health + Daily 80 % / Travel 100 %  (bapirlo-charge)
#   · EasyEffects: "Bapirlo Speakers / Headphones / Flat", switched by output
#     (bapirlo-sound-profile auto|speakers|headphones|flat)
#   bash ~/bapirlo-os/1410-round14.sh            install
#   bash ~/bapirlo-os/1410-round14.sh sound      only the EasyEffects part (after 1400 installed it)
#   bash ~/bapirlo-os/1410-round14.sh restore    put it all back
# Needs a log out/in once (Desk + Control Centre extension code). Backup: ~/theme-backups/LATEST-ROUND14
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
LATEST=~/theme-backups/LATEST-ROUND14
EXT_DIR=~/.local/share/gnome-shell/extensions
DESK=bapirlo-desk@bapirlo-os
CC=bapirlo-control-centre@bapirlo-os
PRESETS=~/.local/share/bapirlo/theme-studio/presets
STUDIO_DATA=~/.local/share/bapirlo/theme-studio
EE_DATA=~/.local/share/easyeffects
UNITS=~/.config/systemd/user
NEW_CARDS="nowplaying todo notes"
desk_gs() { gsettings --schemadir "$EXT_DIR/$DESK/schemas" "$@"; }

backup() {
  if [ -e "$LATEST" ]; then echo "backup kept: $(readlink -f "$LATEST")"; return; fi
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round14
  mkdir -p "$BK/looks"
  cp -a "$EXT_DIR/$DESK" "$EXT_DIR/$CC" "$BK/"
  dconf dump /org/gnome/shell/extensions/bapirlo-desk/ > "$BK/desk.dconf"
  find "$STUDIO_DATA" -name 'look.json' -o -name 'original-look*.json' 2>/dev/null | while read -r f; do
    mkdir -p "$BK/looks/$(dirname "${f#"$STUDIO_DATA"/}")"; cp -a "$f" "$BK/looks/${f#"$STUDIO_DATA"/}"
  done
  [ -d "$EE_DATA" ] && cp -a "$EE_DATA" "$BK/easyeffects" || touch "$BK/no-easyeffects-before"
  ln -sfn "$BK" "$LATEST"; echo "backup -> $BK"
}

# add the new cards to a strv value like "['clock', 'weather']"
add_cards() {
  python3 -I -c '
import ast, sys
cur = ast.literal_eval(sys.argv[1].replace("@as ", ""))
for c in sys.argv[2].split():
    if c not in cur: cur.append(c)
print(repr(cur))' "$1" "$NEW_CARDS"
}

install_exts() {
  for e in $DESK $CC; do
    local src; src=$HERE/desk/$e; [ $e = $CC ] && src=$HERE/control-centre/$e
    rm -rf "${EXT_DIR:?}/$e"; cp -rL "$src" "$EXT_DIR/"
    glib-compile-schemas "$EXT_DIR/$e/schemas"
  done
  glib-compile-schemas "$HERE/desk/$DESK/schemas"   # the repo copy (test shell) too
  desk_gs set org.gnome.shell.extensions.bapirlo-desk widgets-cards \
    "$(add_cards "$(desk_gs get org.gnome.shell.extensions.bapirlo-desk widgets-cards)")"
  echo "   desk cards now: $(desk_gs get org.gnome.shell.extensions.bapirlo-desk widgets-cards)"
  # each wallpaper's saved look (round 12) brings its own card list back — give them the new cards too
  find "$STUDIO_DATA" -name 'look.json' -o -name 'original-look*.json' 2>/dev/null | while read -r f; do
    python3 -I - "$f" "$NEW_CARDS" <<'PY'
import ast, json, sys
path, new = sys.argv[1], sys.argv[2].split()
d = json.load(open(path))
k = d.get("keys", {})
if "bapirlo-desk/widgets-cards" in k:
    cur = ast.literal_eval(k["bapirlo-desk/widgets-cards"].replace("@as ", ""))
    cur += [c for c in new if c not in cur]
    k["bapirlo-desk/widgets-cards"] = repr(cur)
    json.dump(d, open(path, "w"), indent=1)
    print(f"   look: {path.split('/')[-2]}")
PY
  done
}

install_sound() {
  if ! command -v easyeffects >/dev/null; then
    echo "   EasyEffects not installed — run 1400-round14-install.sh first; skipping sound"; return
  fi
  python3 -I "$HERE/sounds/easyeffects/make-presets.py" "$EE_DATA" | sed 's/^/   /'
  local flag
  flag=$(easyeffects --help 2>&1 | grep -o -m1 -- '--service-mode\|--gapplication-service\|--hide-window' || true)
  [ -n "$flag" ] || { echo "   !! easyeffects --help shows no background flag:"; easyeffects --help 2>&1 | sed 's/^/      /'; return 1; }
  mkdir -p "$UNITS"
  cat > "$UNITS/bapirlo-easyeffects.service" <<EOF
[Unit]
Description=EasyEffects in the background (Bapirlo OS sound presets)
PartOf=graphical-session.target
After=graphical-session.target pipewire-pulse.service

[Service]
ExecStart=/usr/bin/easyeffects $flag
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF
  cat > "$UNITS/bapirlo-sound-profile.service" <<EOF
[Unit]
Description=Bapirlo OS — EasyEffects preset follows the audio output
PartOf=graphical-session.target
After=graphical-session.target bapirlo-easyeffects.service
Wants=bapirlo-easyeffects.service

[Service]
ExecStart=$HERE/bin/bapirlo-sound-profile watch
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF
  # EasyEffects' own autostart entry would start a second copy
  rm -f ~/.config/autostart/com.github.wwmm.easyeffects.desktop ~/.config/autostart/easyeffects-service.desktop
  systemctl --user daemon-reload
  systemctl --user enable --now bapirlo-easyeffects.service bapirlo-sound-profile.service
  sleep 6
  "$HERE/bin/bapirlo-sound-profile" status | sed 's/^/   /'
}

install() {
  echo "== desk + control centre"; install_exts
  echo "== sound presets"; install_sound
  echo
  echo "round 14: installed. Log out/in once for the new cards, session restore, Super+Alt+O and the Battery tile."
}

restore() {
  local BK; BK=$(readlink -f "$LATEST")
  [ -d "$BK" ] || { echo "no backup at $LATEST"; exit 1; }
  for e in $DESK $CC; do rm -rf "${EXT_DIR:?}/$e"; cp -a "$BK/$e" "$EXT_DIR/"; done
  dconf load /org/gnome/shell/extensions/bapirlo-desk/ < "$BK/desk.dconf"
  [ -d "$BK/looks" ] && cp -a "$BK/looks/." "$STUDIO_DATA/"
  systemctl --user disable --now bapirlo-sound-profile.service bapirlo-easyeffects.service 2>/dev/null || true
  rm -f "$UNITS/bapirlo-sound-profile.service" "$UNITS/bapirlo-easyeffects.service"
  systemctl --user daemon-reload
  if [ -d "$BK/easyeffects" ]; then rm -rf "$EE_DATA"; cp -a "$BK/easyeffects" "$EE_DATA"
  else rm -f "$EE_DATA/output/Bapirlo "*.json; fi
  echo "restored from $BK (log out/in to unload the new extension code; to-do / notes / session files stay in ~/.local/state/bapirlo)"
}

case "${1:-}" in
  "") backup; install ;;
  sound) install_sound ;;
  restore) restore ;;
  *) sed -n 2,15p "$0"; exit 1 ;;
esac
