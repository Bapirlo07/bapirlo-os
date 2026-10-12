#!/usr/bin/env bash
# Restart the island test shell (JS modules are cached per process, so code changes need a restart).
#   bash restart.sh      then drive with ../../media-widget/test/drive.sh (T=/tmp/claude-1000/bapirlo-island-test)
export T=${T:-/tmp/claude-1000/bapirlo-island-test}
HERE=$(dirname "$(readlink -f "$0")")
for p in $(pgrep -f '^gnome-shell --headless') $(pgrep -f '^python3 .*fake-player'); do kill "$p"; done
sleep 2
(MON=${MON:-1920x1200} bash "$HERE/preview.sh" > /dev/null 2>&1 &)
for i in $(seq 40); do [ -f "$T/env" ] && break; sleep 0.5; done
bash "$HERE/../../media-widget/test/drive.sh" wait && sleep 4
# GNOME shows a "Screen Lock disabled" banner at start-up here; clear it so the island gets the tray
bash "$HERE/../../media-widget/test/drive.sh" eval "Main.messageTray._notification?.destroy(); return 1" >/dev/null
