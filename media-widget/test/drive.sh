#!/usr/bin/env bash
# Helpers for the headless test shell:  drive.sh eval 'JS' | shot NAME | player NAME [args] | click X Y | drag X1 Y1 X2 Y2 | wait
T=${T:-/tmp/claude-1000/bapirlo-media-test}
set -a; . <(sed 's/^export //' "$T/env" | tr ' ' '\n'); set +a
HERE=$(cd "$(dirname "$0")" && pwd)
case "$1" in
  eval) gdbus call --session -d org.bapirlo.Test -o /org/bapirlo/Test -m org.bapirlo.Test.Eval "$2" | sed -e "s/^('//" -e "s/',)\$//" -e 's/\\n/\n/g' ;;
  shot) gdbus call --session -d org.bapirlo.Test -o /org/bapirlo/Test -m org.bapirlo.Test.Shot "$T/$2.png" >/dev/null && echo "$T/$2.png" ;;
  player) shift; nohup python3 "$HERE/fake-player.py" "$@" > "$T/player-$1.log" 2>&1 & echo $! ;;
  click) "$0" eval "const Clutter = (await import('gi://Clutter')).default, GLib = (await import('gi://GLib')).default; const seat = (Clutter.get_default_backend?.() ?? global.stage.context.get_backend()).get_default_seat(); globalThis._vp ??= seat.create_virtual_device(Clutter.InputDeviceType.POINTER_DEVICE); const t = GLib.get_monotonic_time(); _vp.notify_absolute_motion(t, $2, $3); _vp.notify_button(t + 1000, Clutter.BUTTON_PRIMARY, Clutter.ButtonState.PRESSED); _vp.notify_button(t + 60000, Clutter.BUTTON_PRIMARY, Clutter.ButtonState.RELEASED); return 1" ;;
  drag) "$0" eval "const Clutter = (await import('gi://Clutter')).default, GLib = (await import('gi://GLib')).default; const seat = (Clutter.get_default_backend?.() ?? global.stage.context.get_backend()).get_default_seat(); globalThis._vp ??= seat.create_virtual_device(Clutter.InputDeviceType.POINTER_DEVICE); const sleep = ms => new Promise(r => GLib.timeout_add(0, ms, () => r())); const t = () => GLib.get_monotonic_time(); _vp.notify_absolute_motion(t(), $2, $3); await sleep(30); _vp.notify_button(t(), Clutter.BUTTON_PRIMARY, Clutter.ButtonState.PRESSED); for (let i = 1; i <= 20; i++) { await sleep(16); _vp.notify_absolute_motion(t(), $2 + ($4 - $2) * i / 20, $3 + ($5 - $3) * i / 20); } await sleep(30); _vp.notify_button(t(), Clutter.BUTTON_PRIMARY, Clutter.ButtonState.RELEASED); await sleep(400); return 1" ;;
  wait) for i in $(seq 60); do gdbus call --session -d org.bapirlo.Test -o /org/bapirlo/Test -m org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1 && exit 0; sleep 0.5; done; exit 1 ;;
esac
