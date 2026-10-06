#!/usr/bin/env bash
# Bapirlo OS round 3 — desktop part (NO sudo; run AFTER 300-round3-install.sh).
#   bash ~/bapirlo-os/310-round3.sh            # backup + apply everything
#   bash ~/bapirlo-os/310-round3.sh restore    # everything back exactly as before
#   1. Welcome app (welcome-app/): dock icon, opens at the first login of the day
#   2. Super+A: floating Claude Code terminal (bapirlo-ai extension); GNOME's "show apps" loses Super+A
#   3. Arch Update in the top bar: count of repo + AUR updates (hidden when 0), click → bapirlo-update
#   4. Screen blanks + locks after 10 min idle (bapirlo-lockd does the locking through LightDM)
#   5. Wallpaper day/night by sunrise/sunset + Night Light sunset→sunrise (bapirlo-daycycle.timer);
#      accent colours follow through bapirlo-autotheme
#   6. Print = screenshot → Satty annotation · Shift+Print = GNOME's screenshot/recording UI ·
#      Ctrl+Print = instant full screenshot · Super+Shift+C = colour picker
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
. "$HERE/lib/ext.sh"
LATEST=~/theme-backups/LATEST-ROUND3
APPS=~/.local/share/applications
ICONS=~/.local/share/icons/Bapirlo
BGS=~/.local/share/backgrounds/bapirlo
UNITS=~/.config/systemd/user
WELCOME_DESK=$APPS/os.bapirlo.Welcome.desktop
AUTOSTART=~/.config/autostart/os.bapirlo.Welcome.desktop
SATTY=~/.config/satty/config.toml
SESSION=~/.config/bapirlo/session.json
AI=bapirlo-ai@bapirlo-os
AU=arch-update@RaphaelRochet
KB=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
FILES=("$WELCOME_DESK" "$AUTOSTART" "$ICONS/scalable/apps/bapirlo-welcome.svg" "$SATTY" "$SESSION"
       "$BGS/kuro-day-2560x1600.jpg" "$BGS/kuro-night-2560x1600.jpg"
       "$UNITS/bapirlo-daycycle.service" "$UNITS/bapirlo-daycycle.timer")
KEYS=("org.gnome.shell favorite-apps"
      "org.gnome.shell.keybindings toggle-application-view"
      "org.gnome.shell.keybindings show-screenshot-ui" "org.gnome.shell.keybindings screenshot"
      "org.gnome.settings-daemon.plugins.media-keys custom-keybindings"
      "org.gnome.desktop.session idle-delay"
      "org.gnome.desktop.screensaver lock-enabled" "org.gnome.desktop.screensaver lock-delay"
      "org.gnome.desktop.background picture-uri" "org.gnome.desktop.background picture-uri-dark"
      "org.gnome.settings-daemon.plugins.color night-light-enabled"
      "org.gnome.settings-daemon.plugins.color night-light-schedule-automatic"
      "org.gnome.settings-daemon.plugins.color night-light-schedule-from"
      "org.gnome.settings-daemon.plugins.color night-light-schedule-to")
PATHS=(/org/gnome/shell/extensions/arch-update/ /org/gnome/shell/extensions/bapirlo-ai/
       $KB/bapirlo-shot/ $KB/bapirlo-pick/)

add_keybinding() {  # add_keybinding ID NAME COMMAND BINDING
  local p=$KB/$1/
  gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$p name "$2"
  gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$p command "$3"
  gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$p binding "$4"
  python3 - "$p" <<'PY'
import ast, subprocess, sys
k = ["org.gnome.settings-daemon.plugins.media-keys", "custom-keybindings"]
v = subprocess.run(["gsettings", "get", *k], capture_output=True, text=True).stdout.strip()
cur = [] if v.startswith("@as") else ast.literal_eval(v)
if sys.argv[1] not in cur:
    cur.append(sys.argv[1])
subprocess.run(["gsettings", "set", *k, str(cur)], check=True)
PY
}

apply() {
  pacman -Q satty wl-clipboard >/dev/null || { echo "Run 300-round3-install.sh first (satty/wl-clipboard missing)."; exit 1; }
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round3
  mkdir -p "$BK/files"
  dconf dump / > "$BK/full-dconf.ini"                 # complete safety copy (restore uses the keys below)
  backup_dconf "$BK" "${PATHS[@]}"
  backup_keys "$BK" "${KEYS[@]}"
  for f in "${FILES[@]}"; do
    if [ -e "$f" ]; then mkdir -p "$BK/files$(dirname "$f")"; cp -a "$f" "$BK/files$f"; echo "$f" >> "$BK/preexisting.txt"; fi
  done
  touch "$BK/preexisting.txt"
  for u in "$AI" "$AU"; do [ -d "$EXT_DIR/$u" ] && echo "$u" >> "$BK/preexisting-ext.txt"; done; touch "$BK/preexisting-ext.txt"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo "== 1/6 Welcome app"
  install -Dm644 "$HERE/welcome-app/bapirlo-welcome.svg" "$ICONS/scalable/apps/bapirlo-welcome.svg"
  gtk-update-icon-cache -f -t "$ICONS" >/dev/null 2>&1 || true
  mkdir -p "$APPS" "$(dirname "$AUTOSTART")"
  cat > "$WELCOME_DESK" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Bapirlo Welcome
GenericName=Control centre
Comment=Time, weather, today's events, system status, quick launch and modes
Exec=$HERE/welcome-app/bapirlo-welcome
Icon=bapirlo-welcome
Terminal=false
Categories=Utility;System;
Keywords=welcome;dashboard;control;gaming;quiet;dnd;weather;calendar;bapirlo;
StartupWMClass=os.bapirlo.Welcome
DESKTOP
  cat > "$AUTOSTART" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Bapirlo Welcome (first login of the day)
Exec=$HERE/welcome-app/bapirlo-welcome --daily
Icon=bapirlo-welcome
NoDisplay=true
X-GNOME-Autostart-Delay=4
DESKTOP
  python3 - <<'PY'
import ast, subprocess
k = ["org.gnome.shell", "favorite-apps"]
fav = ast.literal_eval(subprocess.run(["gsettings", "get", *k], capture_output=True, text=True).stdout)
if "os.bapirlo.Welcome.desktop" not in fav:
    fav.insert(fav.index("org.gnome.Settings.desktop") if "org.gnome.Settings.desktop" in fav else len(fav),
               "os.bapirlo.Welcome.desktop")
subprocess.run(["gsettings", "set", *k, str(fav)], check=True)
PY
  # the session saver must not reopen the welcome window at login (the assistant window is unlisted → already skipped)
  if [ -f "$SESSION" ]; then
    python3 - "$SESSION" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for x in ("os.bapirlo.Welcome.desktop",):
    if x not in d.setdefault("exclude", []):
        d["exclude"].append(x)
json.dump(d, open(p, "w"), indent=1); open(p, "a").write("\n")
PY
  fi

  echo "== 2/6 Super+A assistant"
  rm -rf "${EXT_DIR:?}/$AI"; cp -r "$HERE/ai/$AI" "$EXT_DIR/$AI"
  gsettings set org.gnome.shell.keybindings toggle-application-view "[]"
  ext_enable "$AI"

  echo "== 3/6 update notifier"
  ext_install "$AU"
  eset "$AU" org.gnome.shell.extensions.arch-update check-cmd "/bin/sh -c \"/usr/bin/checkupdates; /usr/bin/paru -Qua 2>/dev/null | grep -v '\\[ignored\\]'\""
  eset "$AU" org.gnome.shell.extensions.arch-update update-cmd "alacritty --class bapirlo-update -T 'Bapirlo update' -e $HERE/bin/bapirlo-update"
  eset "$AU" org.gnome.shell.extensions.arch-update always-visible false
  eset "$AU" org.gnome.shell.extensions.arch-update show-count true
  eset "$AU" org.gnome.shell.extensions.arch-update notify false
  eset "$AU" org.gnome.shell.extensions.arch-update boot-wait 120
  eset "$AU" org.gnome.shell.extensions.arch-update check-interval 60
  ext_enable "$AU"

  echo "== 4/6 lock after 10 min idle"
  gsettings set org.gnome.desktop.session idle-delay "uint32 600"
  gsettings set org.gnome.desktop.screensaver lock-enabled true
  gsettings set org.gnome.desktop.screensaver lock-delay "uint32 0"
  systemctl --user is-active -q bapirlo-lockd.service && echo "   bapirlo-lockd running" || echo "   !! bapirlo-lockd is not running — idle lock needs it"

  echo "== 5/6 day/night wallpaper + Night Light"
  [ -f "$HERE/build/art/kuro-day-2560x1600.jpg" ] || python3 "$HERE/tools/make-daynight.py"
  install -Dm644 "$HERE/build/art/kuro-day-2560x1600.jpg" "$BGS/kuro-day-2560x1600.jpg"
  install -Dm644 "$HERE/build/art/kuro-night-2560x1600.jpg" "$BGS/kuro-night-2560x1600.jpg"
  mkdir -p ~/Pictures/wallpapers/bapirlo/day ~/Pictures/wallpapers/bapirlo/night
  install -Dm644 "$HERE/round3/systemd/bapirlo-daycycle.service" "$UNITS/bapirlo-daycycle.service"
  install -Dm644 "$HERE/round3/systemd/bapirlo-daycycle.timer" "$UNITS/bapirlo-daycycle.timer"
  gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
  systemctl --user daemon-reload
  systemctl --user enable --now bapirlo-daycycle.timer
  systemctl --user start bapirlo-daycycle.service
  "$HERE/bin/bapirlo-daycycle" --status | sed 's/^/   /'

  echo "== 6/6 screenshots + colour picker"
  install -Dm644 "$HERE/round3/satty/config.toml" "$SATTY"
  mkdir -p ~/Pictures/Screenshots
  gsettings set org.gnome.shell.keybindings show-screenshot-ui "['<Shift>Print']"
  gsettings set org.gnome.shell.keybindings screenshot "['<Primary>Print']"
  add_keybinding bapirlo-shot "Screenshot + annotate (Satty)" "$HERE/bin/bapirlo-capture shot" "Print"
  add_keybinding bapirlo-pick "Colour picker" "$HERE/bin/bapirlo-capture pick" "<Shift><Super>c"

  echo
  echo "done. Log out and back in to load the two new extensions (Super+A, update count)."
  echo "Undo: bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  systemctl --user disable --now bapirlo-daycycle.timer 2>/dev/null || true
  for u in "$AI" "$AU"; do
    ext_unenable "$u"
    grep -qx "$u" "$BK/preexisting-ext.txt" || rm -rf "${EXT_DIR:?}/$u"
  done
  for f in "${FILES[@]}"; do
    if grep -qx "$f" "$BK/preexisting.txt"; then cp -a "$BK/files$f" "$f"; else rm -f "$f"; fi
  done
  systemctl --user daemon-reload
  gtk-update-icon-cache -f -t "$ICONS" >/dev/null 2>&1 || true
  restore_dconf "$BK" "${PATHS[@]}"
  restore_keys "$BK"
  echo "restored (full dconf copy, if ever needed: $BK/full-dconf.ini). Log out/in to unload the extensions."
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
