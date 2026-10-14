#!/usr/bin/env bash
# Theme Studio integration test: a throwaway HOME with copies of the real themes and configs, and a
# headless GNOME Shell running in it. Nothing in your real session or home folder is changed.
#   bash fakehome.sh            (re)create + start;  then:  T=$F/run ../../media-widget/test/drive.sh …
#   env for commands inside:    . $F/env
set -u
F=${F:-/tmp/claude-1000/studio-home}
REAL=$HOME
for p in $(pgrep -x gnome-shell); do grep -qz "HOME=$F" /proc/$p/environ 2>/dev/null && kill $p; done
rm -rf "$F"; mkdir -p "$F"/{.themes,.config,.local/share/gnome-shell/extensions,.local/state,.cache,run,Pictures}
cp -a "$REAL/.themes/Bapirlo-Kuro" "$REAL/.themes/WhiteSur-Dark-red" "$F/.themes/"
sed -i "s|$REAL/.themes/WhiteSur|$F/.themes/WhiteSur|" "$F/.themes/Bapirlo-Kuro/gnome-shell/gnome-shell.css"
for c in gtk-4.0 gtk-3.0 Kvantum alacritty fastfetch spicetify bapirlo; do [ -e "$REAL/.config/$c" ] && cp -a "$REAL/.config/$c" "$F/.config/"; done
rm -rf "$F/.config/spicetify/Backup" "$F/.config/spicetify/Extracted" 2>/dev/null
for e in "$REAL"/.local/share/gnome-shell/extensions/*; do ln -s "$e" "$F/.local/share/gnome-shell/extensions/"; done
ln -sfn "$REAL/bapirlo-os/studio/bapirlo-studio@bapirlo-os" "$F/.local/share/gnome-shell/extensions/"
# test the repo versions of the extensions Theme Studio changed
for d in control-centre/bapirlo-control-centre@bapirlo-os media-widget/bapirlo-media@bapirlo-os; do
  ln -sfn "$REAL/bapirlo-os/$d" "$F/.local/share/gnome-shell/extensions/"
done
ln -s "$REAL/bapirlo-os/media-widget/test/testhelper@bapirlo-os" "$F/.local/share/gnome-shell/extensions/"
for d in fonts icons backgrounds sounds; do ln -s "$REAL/.local/share/$d" "$F/.local/share/$d"; done
ln -s "$REAL/bapirlo-os" "$F/bapirlo-os"
mkdir -p "$F/.local/state/bapirlo"; cp -a "$REAL/.local/state/bapirlo/accent" "$F/.local/state/bapirlo/" 2>/dev/null
dconf dump / > "$F/all.dconf"
EXTS=$(gsettings get org.gnome.shell enabled-extensions | sed "s/]$/, 'bapirlo-studio@bapirlo-os', 'testhelper@bapirlo-os']/")
cat > "$F/env" <<EOV
export HOME=$F XDG_CONFIG_HOME=$F/.config XDG_DATA_HOME=$F/.local/share XDG_STATE_HOME=$F/.local/state XDG_CACHE_HOME=$F/.cache
export GSETTINGS_BACKEND=dconf
# its own runtime dir: sharing /run/user/1000 lets the test session's portals unmount the real
# session's document portal (/run/user/1000/doc) — it exits with status 21
export XDG_RUNTIME_DIR=$F/xdg-run
EOV
mkdir -p -m 700 "$F/xdg-run"
(
  . "$F/env"
  exec dbus-run-session -- bash -c "
    dconf load / < $F/all.dconf
    gsettings set org.gnome.shell enabled-extensions \"$EXTS\"
    gsettings set org.gnome.shell welcome-dialog-last-shown-version 999
    echo DBUS_SESSION_BUS_ADDRESS=\$DBUS_SESSION_BUS_ADDRESS > $F/run/env
    echo \"export DBUS_SESSION_BUS_ADDRESS=\$DBUS_SESSION_BUS_ADDRESS\" >> $F/env
    exec gnome-shell --headless --wayland --no-x11 --wayland-display studio-test --virtual-monitor 1920x1200 > $F/shell.log 2>&1
  "
) &
