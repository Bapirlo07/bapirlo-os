#!/usr/bin/env bash
# Throwaway headless GNOME Shell with only bapirlo-live + testhelper (never touches the real session).
#   T=/tmp/claude-1000/bapirlo-live-$RANDOM bash live/test/preview.sh   then drive with media-widget/test/drive.sh
# Use a NEW T each run: the old run's gvfs / document-portal FUSE mounts block rm -rf.
set -euo pipefail
OS=$HOME/bapirlo-os
T=${T:-/tmp/claude-1000/bapirlo-live-test}
rm -rf "$T"; mkdir -p "$T"/{config,data/gnome-shell/extensions,cache,state,run}; chmod 700 "$T/run"
ln -s "$OS/live/bapirlo-live@bapirlo-os" "$T/data/gnome-shell/extensions/"
ln -s "$OS/media-widget/test/testhelper@bapirlo-os" "$T/data/gnome-shell/extensions/"
BG=${BG:-file://$OS/build/art/hero-2560x1600.png}
export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_CACHE_HOME=$T/cache XDG_STATE_HOME=$T/state XDG_RUNTIME_DIR=$T/run
export PULSE_SERVER=unix:/nonexistent GSETTINGS_BACKEND=dconf
exec dbus-run-session -- bash -c '
  g() { gsettings set "$@"; }
  g org.gnome.shell enabled-extensions "[\"bapirlo-live@bapirlo-os\", \"testhelper@bapirlo-os\"]"
  g org.gnome.shell disable-user-extensions false
  g org.gnome.shell welcome-dialog-last-shown-version "999"
  g org.gnome.desktop.background picture-uri "'"$BG"'"
  g org.gnome.desktop.background picture-uri-dark "'"$BG"'"
  echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" > '"$T"'/env
  echo "export XDG_CONFIG_HOME='"$T"'/config XDG_DATA_HOME='"$T"'/data XDG_CACHE_HOME='"$T"'/cache XDG_RUNTIME_DIR='"$T"'/run WAYLAND_DISPLAY=bapirlo-live-test" >> '"$T"'/env
  exec gnome-shell --headless --wayland --no-x11 --wayland-display bapirlo-live-test \
       --virtual-monitor ${MON:-2560x1600} 2>&1 | tee '"$T"'/shell.log
'
