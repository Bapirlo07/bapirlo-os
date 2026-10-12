#!/usr/bin/env bash
# Blur my Shell's panel blur draws a square box that ignores the floating bar's margins,
# leaving a dark strip under the bar. Turn panel blur off (bar keeps its own translucent fill).
#   bash 350-panel-blur-off.sh          apply (backs up first)
#   bash 350-panel-blur-off.sh restore  put the old value back
set -euo pipefail
KEY=/org/gnome/shell/extensions/blur-my-shell/panel/blur
BK=~/theme-backups
if [ "${1:-}" = restore ]; then
  d=$(cat "$BK/LATEST-PANEL-BLUR-OFF")
  old=$(cat "$d/panel-blur.value")
  if [ -n "$old" ]; then dconf write $KEY "$old"; else dconf reset $KEY; fi
  echo "restored panel blur = ${old:-default}"; exit 0
fi
d=$BK/$(date +%Y%m%d-%H%M%S)-panel-blur-off
mkdir -p "$d"
dconf read $KEY > "$d/panel-blur.value" || true
echo "$d" > "$BK/LATEST-PANEL-BLUR-OFF"
dconf write $KEY false
echo "panel blur off (backup $d). Undo: bash 350-panel-blur-off.sh restore"
