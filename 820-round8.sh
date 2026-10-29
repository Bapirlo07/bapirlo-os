#!/usr/bin/env bash
# Bapirlo OS round 8 — everything that does NOT need your password (run after 800-round8-install.sh).
#   bash ~/bapirlo-os/820-round8.sh             # backup + apply (then log out / in once)
#   bash ~/bapirlo-os/820-round8.sh restore     # undo all of it
#
#  1. OSD pop-ups (volume/brightness in fullscreen, Caps Lock, displays): Island-style ink pill, crimson
#     bar, Bangers label — appended to the Bapirlo-Kuro shell theme (+ its build copies), live reload
#  2. Folder icons: crimson manga folders (tools/build-folders.py) in the Bapirlo icon theme
#  3. Cursor: Bapirlo-Cursors for your session (the login screen got it from 800-round8-install.sh)
#  4. Bapirlo Panels: manga-panel window open/close + SFX burst — replaces Burn My Windows (switched off)
#  5. Bapirlo Keys: Super+/ cheat sheet of every shortcut
#  6. fish: zoxide (z / zi) + fzf (Ctrl+R history, Ctrl+T files, Alt+C folders) in Kuro colours
#  7. Vesktop: Bapirlo Kuro theme, enabled (only if Vesktop is installed)
#  8. Health: free-space watch every 30 min (one notification a day below 15 GB). The Welcome app's
#     HEALTH card and the Doctor's battery/SSD checks need no install.
# 4 + 5 load at your next log in (GNOME only picks up new extensions at login).
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/ext.sh"
R8=$HERE/round8
LATEST=~/theme-backups/LATEST-ROUND8
THEME=~/.themes/Bapirlo-Kuro/gnome-shell/gnome-shell.css
THEME_COPIES=("$HERE/build/round2/shell/Bapirlo-Kuro/gnome-shell/gnome-shell.css"
              "$HERE/build/polish/shell/Bapirlo-Kuro/gnome-shell/gnome-shell.css")
ICONS=~/.local/share/icons/Bapirlo
CURSORS=~/.local/share/icons/Bapirlo-Cursors
FISH=~/.config/fish/conf.d/bapirlo-nav.fish
UNITS=~/.config/systemd/user
VESK=~/.config/vesktop
NEW_EXTS=(bapirlo-panels@bapirlo-os bapirlo-keys@bapirlo-os)
BMW=burn-my-windows@schneegans.github.com
DCONF_PATHS=(/org/gnome/shell/extensions/bapirlo-panels/ /org/gnome/shell/extensions/bapirlo-keys/)
MARK_START='/* >>> bapirlo round 8: OSD'
MARK_END='/* <<< bapirlo round 8: OSD */'

strip_osd() {   # remove our block from a stylesheet (idempotent)
  [ -f "$1" ] || return 0
  python3 - "$1" "$MARK_START" "$MARK_END" <<'PY'
import sys
p, a, b = sys.argv[1:]
s = open(p).read()
i = s.find(a)
if i >= 0:
    j = s.find(b, i)
    s = s[:i].rstrip("\n") + "\n" + s[j + len(b):].lstrip("\n") if j >= 0 else s[:i]
    open(p, "w").write(s)
PY
}

reload_shell_theme() {   # user-theme re-reads the stylesheet when its name changes
  local ut=org.gnome.shell.extensions.user-theme name
  name=$(gsettings get $ut name | tr -d "'")
  gsettings set $ut name ''; sleep 1; gsettings set $ut name "${name:-Bapirlo-Kuro}"
}

ext_disable() {
  python3 - "$@" <<'PY'
import ast, subprocess, sys
def get(k):
    v = subprocess.run(["gsettings", "get", "org.gnome.shell", k], capture_output=True, text=True).stdout.strip()
    return [] if v.startswith("@as") else ast.literal_eval(v)
en, dis = get("enabled-extensions"), get("disabled-extensions")
en = [e for e in en if e not in sys.argv[1:]]
dis += [u for u in sys.argv[1:] if u not in dis]
subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(en)], check=True)
subprocess.run(["gsettings", "set", "org.gnome.shell", "disabled-extensions", str(dis)], check=True)
PY
}

apply() {
  if ! grep -qs '"Before round 8"' /timeshift/snapshots/*/info.json; then
    echo "No Timeshift snapshot \"Before round 8\" yet — run first:  bash $HERE/800-round8-install.sh"; exit 1
  fi
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round8
  mkdir -p "$BK"/{units,css}
  cp -a "$THEME" "$BK/css/live.css"
  for i in "${!THEME_COPIES[@]}"; do [ -f "${THEME_COPIES[$i]}" ] && cp -a "${THEME_COPIES[$i]}" "$BK/css/copy$i.css"; done
  cp -a "$ICONS/scalable/places" "$BK/icons-places"
  gsettings get org.gnome.desktop.interface cursor-theme > "$BK/cursor-theme.txt"
  gsettings get org.gnome.shell enabled-extensions > "$BK/enabled-extensions.txt"
  gsettings get org.gnome.shell disabled-extensions > "$BK/disabled-extensions.txt"
  backup_dconf "$BK" "${DCONF_PATHS[@]}"
  [ -e "$FISH" ] && cp -a "$FISH" "$BK/"
  for u in bapirlo-diskwatch.service bapirlo-diskwatch.timer; do [ -e "$UNITS/$u" ] && cp -a "$UNITS/$u" "$BK/units/"; done
  [ -d "$VESK" ] && mkdir -p "$BK/vesktop" && cp -a "$VESK/settings.json" "$VESK/settings" "$BK/vesktop/" 2>/dev/null || true   # reference copy only
  [ -d "$CURSORS" ] && touch "$BK/cursors-preexisting"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo "== 1/8 OSD pop-ups"
  for f in "$THEME" "${THEME_COPIES[@]}"; do
    [ -f "$f" ] || continue
    strip_osd "$f"; printf '\n' >> "$f"; cat "$R8/shell/osd.css" >> "$f"
  done
  reload_shell_theme

  echo "== 2/8 folder icons"
  python3 "$HERE/tools/build-folders.py" "$ICONS/scalable/places"
  gtk-update-icon-cache -f -t "$ICONS" >/dev/null 2>&1 || true

  echo "== 3/8 cursor"
  if [ -d /usr/share/icons/Bapirlo-Cursors/cursors ]; then
    rm -rf "$CURSORS"     # the system copy (same build) serves the session too
  else
    python3 "$HERE/tools/build-cursors.py" "$CURSORS"
  fi
  gsettings set org.gnome.desktop.interface cursor-theme 'Bapirlo-Cursors'

  echo "== 4-5/8 Bapirlo Panels + Bapirlo Keys (Burn My Windows off)"
  for e in "${NEW_EXTS[@]}"; do
    glib-compile-schemas "$R8/$e/schemas"
    rm -rf "${EXT_DIR:?}/$e"; cp -rL "$R8/$e" "$EXT_DIR/"
  done
  ext_disable "$BMW"
  ext_enable "${NEW_EXTS[@]}"

  echo "== 6/8 fish: zoxide + fzf"
  install -Dm644 "$R8/fish/bapirlo-nav.fish" "$FISH"
  command -v zoxide >/dev/null || echo "   (zoxide not installed yet — 800-round8-install.sh installs it; z works after that)"

  echo "== 7/8 Vesktop theme"
  mkdir -p "$VESK/themes" "$VESK/settings"
  install -m644 "$R8/vesktop/bapirlo-kuro.theme.css" "$VESK/themes/"
  python3 - "$VESK" <<'PY'
import json, os, sys
d = sys.argv[1]
def merge(path, upd):
    try:
        cur = json.load(open(path))
    except (OSError, ValueError):
        cur = {}
    for k, v in upd.items():
        if isinstance(v, list):
            cur[k] = sorted(set(cur.get(k, [])) | set(v))
        else:
            cur[k] = v
    json.dump(cur, open(path, "w"), indent=4)
merge(os.path.join(d, "settings", "settings.json"), {"enabledThemes": ["bapirlo-kuro.theme.css"]})
merge(os.path.join(d, "settings.json"), {"splashTheming": True, "splashBackground": "#0E0A0D",
                                         "splashColor": "#F2E9EC"})
PY
  pacman -Q vesktop-bin >/dev/null 2>&1 || echo "   (Vesktop not installed — the theme is ready for when it is)"

  echo "== 8/8 free-space watch"
  install -Dm644 -t "$UNITS" "$R8/systemd/bapirlo-diskwatch.service" "$R8/systemd/bapirlo-diskwatch.timer"
  systemctl --user daemon-reload
  systemctl --user enable --now bapirlo-diskwatch.timer

  echo
  echo "Done (backup $BK). Log out and back in once for the window animation and Super+/."
  echo "Undo: bash $HERE/820-round8.sh restore"
}

restore() {
  local BK; BK=$(cat "$LATEST" 2>/dev/null) || { echo "nothing to restore ($LATEST missing)"; exit 1; }
  cp -a "$BK/css/live.css" "$THEME"
  for i in "${!THEME_COPIES[@]}"; do [ -f "$BK/css/copy$i.css" ] && cp -a "$BK/css/copy$i.css" "${THEME_COPIES[$i]}"; done
  reload_shell_theme
  rm -rf "$ICONS/scalable/places"; cp -a "$BK/icons-places" "$ICONS/scalable/places"
  gtk-update-icon-cache -f -t "$ICONS" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface cursor-theme "$(tr -d "'" < "$BK/cursor-theme.txt")"
  [ -e "$BK/cursors-preexisting" ] || rm -rf "$CURSORS"
  gsettings set org.gnome.shell enabled-extensions "$(cat "$BK/enabled-extensions.txt")"
  gsettings set org.gnome.shell disabled-extensions "$(cat "$BK/disabled-extensions.txt")"
  for e in "${NEW_EXTS[@]}"; do rm -rf "${EXT_DIR:?}/$e"; done
  restore_dconf "$BK" "${DCONF_PATHS[@]}"
  if [ -e "$BK/bapirlo-nav.fish" ]; then cp -a "$BK/bapirlo-nav.fish" "$FISH"; else rm -f "$FISH"; fi
  systemctl --user disable --now bapirlo-diskwatch.timer 2>/dev/null || true
  rm -f "$UNITS/bapirlo-diskwatch.service" "$UNITS/bapirlo-diskwatch.timer"
  cp -a "$BK/units/." "$UNITS/" 2>/dev/null || true
  systemctl --user daemon-reload
  # Vesktop: take out only our theme — copying old settings back would log you out of Discord
  rm -f "$VESK/themes/bapirlo-kuro.theme.css"
  python3 - "$VESK/settings/settings.json" <<'PY'
import json, sys
try:
    cur = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    sys.exit(0)
cur["enabledThemes"] = [t for t in cur.get("enabledThemes", []) if t != "bapirlo-kuro.theme.css"]
json.dump(cur, open(sys.argv[1], "w"), indent=4)
PY
  echo "Restored from $BK. Log out and back in to unload the two extensions."
}

case "${1:-}" in
  restore) restore ;;
  "") apply ;;
  *) sed -n '2,17p' "$0"; exit 64 ;;
esac
