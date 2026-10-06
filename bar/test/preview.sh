#!/usr/bin/env bash
# Throwaway headless GNOME Shell showing the round-2 top bar (staged theme + bapirlo-bar + the
# real top-bar extensions with a copy of their settings). Never touches the real session.
#   bash preview.sh        then drive with ../../media-widget/test/drive.sh (T=/tmp/claude-1000/bapirlo-bar-test)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OS=$HERE/../..
T=${T:-/tmp/claude-1000/bapirlo-bar-test}
rm -rf "$T"; mkdir -p "$T"/{config,data/gnome-shell/extensions,data/themes,cache,state}
ln -s "$HERE/../bapirlo-bar@bapirlo-os" "$T/data/gnome-shell/extensions/"
ln -s "$OS/media-widget/test/testhelper@bapirlo-os" "$T/data/gnome-shell/extensions/"
for e in Vitals@CoreCoding.com simple-weather@romanlefler.com clipboard-indicator@tudmotu.com caffeine@patapon.info; do
  ln -s ~/.local/share/gnome-shell/extensions/$e "$T/data/gnome-shell/extensions/"
done
cp -r "${THEME_SRC:-$OS/build/round2/shell/Bapirlo-Kuro}" "$T/data/themes/Bapirlo-Preview"
sed -i "s|@HOME@|$HOME|g" "$T/data/themes/Bapirlo-Preview/gnome-shell/gnome-shell.css"
ln -s ~/.local/share/fonts "$T/data/fonts"
[ -d ~/.local/share/icons ] && ln -s ~/.local/share/icons "$T/data/icons"
dconf dump /org/gnome/shell/extensions/ > "$T/ext.dconf"
dconf dump /org/gnome/desktop/interface/ > "$T/iface.dconf"
REAL_BG=$(gsettings get org.gnome.desktop.background picture-uri-dark)
EXTS='["user-theme@gnome-shell-extensions.gcampax.github.com", "arcmenu@arcmenu.com", "appindicatorsupport@rgcjonas.gmail.com", "Vitals@CoreCoding.com", "simple-weather@romanlefler.com", "clipboard-indicator@tudmotu.com", "caffeine@patapon.info", "bapirlo-bar@bapirlo-os", "testhelper@bapirlo-os"]'
export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_CACHE_HOME=$T/cache XDG_STATE_HOME=$T/state
export PULSE_SERVER=unix:/nonexistent GSETTINGS_BACKEND=dconf
exec dbus-run-session -- bash -c '
  set -e
  dconf load /org/gnome/shell/extensions/ < '"$T"'/ext.dconf
  dconf load /org/gnome/desktop/interface/ < '"$T"'/iface.dconf
  # planned round-2 Vitals trim: CPU % + CPU temp only
  dconf load /org/gnome/shell/extensions/vitals/ < '"$HERE"'/vitals-round2.dconf
  g() { gsettings set "$@"; }
  g org.gnome.shell enabled-extensions '"'$EXTS'"'
  g org.gnome.shell disable-user-extensions false
  g org.gnome.shell welcome-dialog-last-shown-version "999"
  g org.gnome.shell.extensions.user-theme name "Bapirlo-Preview"
  g org.gnome.desktop.interface enable-hot-corners false
  g org.gnome.desktop.interface show-battery-percentage true
  g org.gnome.mutter dynamic-workspaces false
  g org.gnome.desktop.wm.preferences num-workspaces 4
  g org.gnome.desktop.background picture-uri '"$REAL_BG"'
  g org.gnome.desktop.background picture-uri-dark '"$REAL_BG"'
  echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" > '"$T"'/env
  echo "export XDG_CONFIG_HOME='"$T"'/config XDG_DATA_HOME='"$T"'/data XDG_CACHE_HOME='"$T"'/cache WAYLAND_DISPLAY=bapirlo-bar-test" >> '"$T"'/env
  exec gnome-shell --headless --wayland --no-x11 --wayland-display bapirlo-bar-test \
       --virtual-monitor 1920x1200 --force-animations 2>&1 | tee '"$T"'/shell.log
'
