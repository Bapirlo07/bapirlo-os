#!/usr/bin/env bash
# restart the preview shell (JS modules are cached per process, so code changes need a restart)
T=${T:-/tmp/claude-1000/bapirlo-bar-test}
D=$(dirname "$(readlink -f "$0")")/../../media-widget/test/drive.sh
for p in $(pgrep -f '^gnome-shell --headless') $(pgrep -f '^python3 .*fake-player'); do kill "$p"; done
sleep 2
(bash "$(dirname "$(readlink -f "$0")")/preview.sh" > /dev/null 2>&1 &)
sleep 1; T=$T bash "$D" wait && T=$T bash "$D" player spotify > /dev/null; sleep 3
