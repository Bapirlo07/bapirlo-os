#!/usr/bin/env bash
# Kuro OS round 10 — everything that does NOT need your password (run after 1000-round10-install.sh).
#   bash ~/bapirlo-os/1010-round10.sh              # backup + all steps (then log out / in once)
#   bash ~/bapirlo-os/1010-round10.sh STEP …       # only those steps (exts vesktop grid wallpapers space caps gtk)
#   bash ~/bapirlo-os/1010-round10.sh restore      # undo all of it
#
#  exts       Smart Auto Move + Wiggly off (stay installed)
#  vesktop    discord:// links open Vesktop; the old Discord app's 0.7 GB of data goes
#  grid       app grid, folders, search and workspace thumbnails in Kuro ink + crimson (Blur My Shell
#             stops repainting them grey); folders: Focus Timer → Kuro, new Android folder,
#             Onedriver → Internet. Island notifications fit their text, first action filled crimson
#  wallpapers 8 original manga wallpapers (tools/build-wallpapers.py) in four time slots —
#             dawn · day · dusk · night — plus your own pictures in ~/Pictures/wallpapers/bapirlo/<slot>
#  space      Chrome + Spotify caches (only while they are closed), Go build cache
#  caps       Chrome cache ≤ 300 MB, Spotify ≤ 500 MB, Spotify's web cache + Go cache trimmed by age
#  gtk        primary buttons (Save, Connect, "=") crimson instead of WhiteSur blue, GTK 4 + GTK 3
# The island loads its new code at your next log in; everything else is live.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/ext.sh"
R10=$HERE/round10
LATEST=~/theme-backups/LATEST-ROUND10
ALL_STEPS=(exts vesktop grid wallpapers space caps gtk)

TRIM_EXTS=(SmartAutoMoveNG@lauinger-clan.de wiggly@mojarch)
ISLAND=bapirlo-island@bapirlo-os
THEME=~/.themes/Bapirlo-Kuro/gnome-shell/gnome-shell.css
THEME_SRC=$HERE/build/round2/shell/Bapirlo-Kuro/gnome-shell/gnome-shell.css
MARK_START='/* >>> bapirlo round 10'
MARK_END='/* <<< bapirlo round 10 */'
ORIGINALS=~/.local/share/backgrounds/bapirlo/originals
SLOTS=~/Pictures/wallpapers/bapirlo
CHROME_FLAGS=~/.config/chrome-flags.conf
SPOTIFY_PREFS=~/.config/spotify/prefs
TMPFILES=~/.config/user-tmpfiles.d/bapirlo-caches.conf
GTK4=~/.config/gtk-4.0
GTK3=~/.config/gtk-3.0
IMPORT='@import url("bapirlo-accent.css");'
BMS=/org/gnome/shell/extensions/blur-my-shell
DCONF_PATHS=(/org/gnome/desktop/app-folders/)
FILES=("$CHROME_FLAGS" "$SPOTIFY_PREFS" "$TMPFILES" "$GTK4/gtk.css" "$GTK3/gtk.css" ~/.config/mimeapps.list)

strip_block() {   # remove our block from a stylesheet (idempotent)
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

running() { pgrep -x "$1" >/dev/null || pgrep -f "$2" >/dev/null; }
mb() { du -sm "$@" 2>/dev/null | awk '{s+=$1} END {print s+0}'; }

backup() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round10
  mkdir -p "$BK/files"
  gsettings get org.gnome.shell enabled-extensions > "$BK/enabled-extensions.txt"
  gsettings get org.gnome.shell disabled-extensions > "$BK/disabled-extensions.txt"
  gsettings get org.gnome.shell favorite-apps > "$BK/favorite-apps.txt"
  for k in overview/style-components appfolder/style-dialogs; do
    echo "$k $(dconf read $BMS/$k)" >> "$BK/bms.txt"
  done
  backup_dconf "$BK" "${DCONF_PATHS[@]}"
  cp -a "$THEME" "$BK/live.css"
  cp -a "$THEME_SRC" "$BK/src.css"
  cp -a "$EXT_DIR/$ISLAND" "$BK/island"
  git -C "$HERE" show 88580a8:bin/bapirlo-daycycle > "$BK/bapirlo-daycycle"   # the 2-slot version (last commit before round 10)
  for f in "${FILES[@]}"; do
    if [ -e "$f" ]; then mkdir -p "$BK/files$(dirname "$f")"; cp -a "$f" "$BK/files$f"; else echo "$f" >> "$BK/new-files.txt"; fi
  done
  echo "$BK" > "$LATEST"; echo "backup -> $BK"
}

step_exts() {
  echo "== exts: Smart Auto Move + Wiggly off"
  ext_disable "${TRIM_EXTS[@]}"
  for e in "${TRIM_EXTS[@]}"; do gnome-extensions disable "$e" 2>/dev/null || true; done
}

step_vesktop() {
  echo "== vesktop: your Discord"
  xdg-mime default vesktop.desktop x-scheme-handler/discord
  local fav; fav=$(gsettings get org.gnome.shell favorite-apps)
  [[ $fav == *"'discord.desktop'"* ]] && gsettings set org.gnome.shell favorite-apps "${fav//\'discord.desktop\'/\'vesktop.desktop\'}"
  if pacman -Q discord >/dev/null 2>&1; then
    echo "   Discord app still installed — its data stays (run 1000-round10-install.sh, then: bash $0 vesktop)"
  elif [ -d ~/.config/discord ]; then
    echo "   old Discord data: $(mb ~/.config/discord) MB → deleted"
    rm -rf ~/.config/discord
  fi
}

step_grid() {
  echo "== grid: app grid, folders, search, workspaces + island notifications"
  for css in "$THEME" "$THEME_SRC"; do
    strip_block "$css"
    printf '\n' >> "$css"
    if [ "$css" = "$THEME" ]; then sed "s|@HOME@|$HOME|g" "$R10/shell/overview.css" >> "$css"; else cat "$R10/shell/overview.css" >> "$css"; fi
  done
  # Blur My Shell's "follow system" style paints the grid / folders / search grey over the theme
  dconf write $BMS/overview/style-components 0
  dconf write $BMS/appfolder/style-dialogs 0
  python3 - <<'PY'
from gi.repository import Gio
base = "/org/gnome/desktop/app-folders/folders/"
def folder(fid):
    return Gio.Settings.new_with_path("org.gnome.desktop.app-folders.folder", f"{base}{fid}/")
def move(app, to):
    root = Gio.Settings.new("org.gnome.desktop.app-folders")
    for fid in root.get_strv("folder-children"):
        f = folder(fid)
        apps = f.get_strv("apps")
        if app in apps and fid != to:
            f.set_strv("apps", [a for a in apps if a != app])
    f = folder(to)
    if app not in f.get_strv("apps"):
        f.set_strv("apps", f.get_strv("apps") + [app])
root = Gio.Settings.new("org.gnome.desktop.app-folders")
if "android" not in root.get_strv("folder-children"):
    root.set_strv("folder-children", root.get_strv("folder-children") + ["android"])
    folder("android").set_string("name", "Android")
move("os.bapirlo.Focus.desktop", "bapirlo")
move("onedriver-launcher.desktop", "internet")
for app in ("bapirlo-android.desktop", "Waydroid.desktop"):
    move(app, "android")
# Waydroid's own app shortcuts (waydroid.<package>.desktop) live in the Android folder too
android = folder("android")
android.set_strv("categories", ["X-WayDroid-App"])
Gio.Settings.sync()
PY
  rm -rf "${EXT_DIR:?}/$ISLAND"; cp -rL "$HERE/dynamic-island/$ISLAND" "$EXT_DIR/"
  reload_shell_theme
}

step_wallpapers() {
  echo "== wallpapers: originals + four time slots"
  python3 "$HERE/tools/build-wallpapers.py" "$ORIGINALS" | sed 's/^/   /'
  mkdir -p "$SLOTS"/{dawn,day,dusk,night}
  "$HERE/bin/bapirlo-daycycle" --status | sed 's/^/   /'
  "$HERE/bin/bapirlo-daycycle"
}

step_space() {
  echo "== space: app caches"
  local before; before=$(df -B1M --output=avail / | tail -1)
  if running chrome /opt/google/chrome/chrome; then
    echo "   Chrome is running (it keeps a background process) — quit it fully, then: bash $0 space"
  else
    echo "   Chrome cache: $(mb ~/.cache/google-chrome) MB → deleted"; rm -rf ~/.cache/google-chrome/*
  fi
  if running spotify /spotify/spotify; then
    echo "   Spotify is running — quit it, then: bash $0 space"
  else
    echo "   Spotify cache: $(mb ~/.cache/spotify) MB → deleted"; rm -rf ~/.cache/spotify/*
  fi
  if command -v go >/dev/null; then go clean -cache; else rm -rf ~/.cache/go-build; fi
  echo "   freed $(( $(df -B1M --output=avail / | tail -1) - before )) MB"
}

step_caps() {
  echo "== caps: caches stay small"
  touch "$CHROME_FLAGS"
  grep -q -- '--disk-cache-size' "$CHROME_FLAGS" ||
    printf '# Kuro OS round 10 — HTTP cache at most 300 MB\n--disk-cache-size=314572800\n' >> "$CHROME_FLAGS"
  echo "   Chrome: 300 MB from its next start"
  if running spotify /spotify/spotify; then
    echo "   Spotify is running (it rewrites its settings on exit) — quit it, then: bash $0 caps"
  elif [ -f "$SPOTIFY_PREFS" ]; then
    sed -i '/^storage\.size=/d' "$SPOTIFY_PREFS"; echo 'storage.size=500' >> "$SPOTIFY_PREFS"
    echo "   Spotify: 500 MB"
  fi
  install -Dm644 /dev/stdin "$TMPFILES" <<'EOF'
# Kuro OS round 10 — caches with no size limit of their own: files unused this long are deleted
# (systemd-tmpfiles-clean.timer, once a day). Delete this file to stop.
e %C/spotify/Browser - - - 7d
e %C/spotify/Data - - - 14d
e %C/go-build - - - 30d
EOF
  systemctl --user enable --now systemd-tmpfiles-clean.timer >/dev/null 2>&1
  echo "   Spotify web cache 7 days, Go build cache 30 days (daily clean)"
}

step_gtk() {
  echo "== gtk: crimson primary buttons"
  for d in "$GTK4" "$GTK3"; do
    mkdir -p "$d"
    install -m644 "$R10/gtk/bapirlo-accent.css" "$d/bapirlo-accent.css"
    touch "$d/gtk.css"
    grep -qF "$IMPORT" "$d/gtk.css" || printf '%s\n' "$IMPORT" >> "$d/gtk.css"
  done
  echo "   apps pick it up when they next open"
}

apply() {
  if ! grep -qs '"Before round 10"' /timeshift/snapshots/*/info.json; then
    echo "No Timeshift snapshot \"Before round 10\" yet — run first:  bash $HERE/1000-round10-install.sh"; exit 1
  fi
  local steps=("$@")
  [ ${#steps[@]} -gt 0 ] || steps=("${ALL_STEPS[@]}")
  for s in "${steps[@]}"; do [[ " ${ALL_STEPS[*]} " == *" $s "* ]] || { echo "unknown step: $s"; exit 64; }; done
  # one backup per round: a single-step re-run keeps the first one
  if [ ${#steps[@]} -eq ${#ALL_STEPS[@]} ] || ! [ -s "$LATEST" ]; then backup; else echo "backup: keeping $(cat "$LATEST")"; fi
  for s in "${steps[@]}"; do "step_$s"; done
  echo
  echo "Done. Log out and back in once for the island. Undo: bash $HERE/1010-round10.sh restore"
}

restore() {
  local BK; BK=$(cat "$LATEST" 2>/dev/null) || { echo "nothing to restore ($LATEST missing)"; exit 1; }
  gsettings set org.gnome.shell enabled-extensions "$(cat "$BK/enabled-extensions.txt")"
  gsettings set org.gnome.shell disabled-extensions "$(cat "$BK/disabled-extensions.txt")"
  gsettings set org.gnome.shell favorite-apps "$(cat "$BK/favorite-apps.txt")"
  while read -r k v; do
    if [ -n "$v" ]; then dconf write "$BMS/$k" "$v"; else dconf reset "$BMS/$k"; fi
  done < "$BK/bms.txt"
  restore_dconf "$BK" "${DCONF_PATHS[@]}"
  cp -a "$BK/live.css" "$THEME"
  cp -a "$BK/src.css" "$THEME_SRC"
  rm -rf "${EXT_DIR:?}/$ISLAND"; cp -a "$BK/island" "$EXT_DIR/$ISLAND"
  cp -a "$BK/bapirlo-daycycle" "$HERE/bin/bapirlo-daycycle"
  (cd "$BK/files" && find . -type f) | while read -r f; do cp -a "$BK/files/$f" "/${f#./}"; done
  [ -f "$BK/new-files.txt" ] && while read -r f; do rm -f "$f"; done < "$BK/new-files.txt"
  rm -f "$GTK4/bapirlo-accent.css" "$GTK3/bapirlo-accent.css"
  rm -rf "$ORIGINALS"
  "$HERE/bin/bapirlo-daycycle"
  reload_shell_theme
  echo "Restored from $BK (deleted caches and Discord data stay deleted; your slot folders are kept)."
  echo "Log out and back in to load the previous island."
}

case "${1:-}" in
  restore) restore ;;
  ""|exts|vesktop|grid|wallpapers|space|caps|gtk) apply "$@" ;;
  *) sed -n '2,18p' "$0"; exit 64 ;;
esac
