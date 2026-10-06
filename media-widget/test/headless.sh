#!/usr/bin/env bash
# Throwaway headless GNOME Shell with the widget, isolated from the real session
# (own D-Bus, dconf, XDG dirs; audio server unreachable so no real volume is touched).
#   bash headless.sh            # foreground; writes $T/env for drivers
#   EXTRA_MON=1280x1024 bash headless.sh   # + a second monitor
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
T=${T:-/tmp/claude-1000/bapirlo-media-test}
rm -rf "$T"; mkdir -p "$T"/{config,data/gnome-shell/extensions,cache,state}
ln -s "$HERE/../bapirlo-media@bapirlo-os" "$T/data/gnome-shell/extensions/"
ln -s "$HERE/testhelper@bapirlo-os" "$T/data/gnome-shell/extensions/"
ln -s ~/.local/share/fonts "$T/data/fonts"
[ -d ~/.local/share/icons ] && ln -s ~/.local/share/icons "$T/data/icons"
[ -d ~/.local/share/backgrounds ] && ln -s ~/.local/share/backgrounds "$T/data/backgrounds"
REAL_ICON=$(gsettings get org.gnome.desktop.interface icon-theme)
REAL_BG=$(gsettings get org.gnome.desktop.background picture-uri-dark)
export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_CACHE_HOME=$T/cache XDG_STATE_HOME=$T/state
export PULSE_SERVER=unix:/nonexistent GSETTINGS_BACKEND=dconf
exec dbus-run-session -- bash -c '
  set -e
  g() { gsettings set "$@"; }
  g org.gnome.shell enabled-extensions "[\"user-theme@gnome-shell-extensions.gcampax.github.com\", \"bapirlo-media@bapirlo-os\", \"testhelper@bapirlo-os\"]"
  g org.gnome.shell disable-user-extensions false
  g org.gnome.shell welcome-dialog-last-shown-version "999"
  g org.gnome.shell.extensions.user-theme name "Bapirlo-Kuro" || true
  g org.gnome.desktop.interface color-scheme prefer-dark
  g org.gnome.desktop.interface enable-hot-corners false   # virtual pointer starts at 0,0
  g org.gnome.desktop.interface icon-theme '"$REAL_ICON"'
  g org.gnome.desktop.background picture-uri '"$REAL_BG"'
  g org.gnome.desktop.background picture-uri-dark '"$REAL_BG"'
  g org.gnome.desktop.background picture-options zoom
  echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" > '"$T"'/env
  echo "export XDG_CONFIG_HOME='"$T"'/config XDG_DATA_HOME='"$T"'/data XDG_CACHE_HOME='"$T"'/cache WAYLAND_DISPLAY=bapirlo-test" >> '"$T"'/env
  exec gnome-shell --headless --wayland --no-x11 --wayland-display bapirlo-test \
       --virtual-monitor 1920x1200 '"${EXTRA_MON:+--virtual-monitor $EXTRA_MON}"' --force-animations 2>&1 | tee '"$T"'/shell.log
'
