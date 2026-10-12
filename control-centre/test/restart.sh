#!/usr/bin/env bash
# restart the Control Centre preview shell (JS is cached per process). Starts a fake MPRIS player.
T=${T:-/tmp/claude-1000/bapirlo-cc-test}
HERE=$(dirname "$(readlink -f "$0")")
D=$HERE/../../media-widget/test/drive.sh
for p in $(pgrep -f '^gnome-shell --headless') $(pgrep -f '^python3 .*fake-player'); do kill "$p"; done
sleep 2
(T=$T bash "$HERE/preview.sh" > /dev/null 2>&1 &)
sleep 1; T=$T bash "$D" wait && T=$T bash "$D" player spotify > /dev/null; sleep 4
