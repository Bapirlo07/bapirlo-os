#!/usr/bin/env bash
# Fire every island event in the test shell and save a crop of each: $T/island-states.png
export T=${T:-/tmp/claude-1000/bapirlo-island-test}
HERE=$(dirname "$(readlink -f "$0")")
D="bash $HERE/../../media-widget/test/drive.sh"
W=$(cut -dx -f1 <<<"${MON:-1920x1200}")
crop() { magick "$T/$1.png" -crop 900x170+$(( W / 2 - 450 ))+0 +repage "$T/$1-c.png"; }
pre="const Gio=(await import('gi://Gio')).default; const GLib=(await import('gi://GLib')).default; const sleep=ms=>new Promise(r=>GLib.timeout_add(0,ms,()=>{r();return false;})); const X=Main.extensionManager.lookup('bapirlo-island@bapirlo-os').stateObj;"
settle="await sleep(${SETTLE:-700}); return 1"
step() {  # name js [gap-after]
  out=$($D eval "$pre $2 $settle"); [ "$out" = 1 ] || echo "!! $1: $out"
  $D shot "i-$1" >/dev/null; crop "i-$1"; sleep "${3:-6}"
}
$D eval "Main.overview.hide(); return 1" >/dev/null; sleep 1
$D shot i-rest >/dev/null; crop i-rest
step vol "Main.osdWindowManager.showAll(new Gio.ThemedIcon({name:'audio-volume-medium-symbolic'}), null, 0.4, 1.0); await sleep(250); Main.osdWindowManager.showAll(new Gio.ThemedIcon({name:'audio-volume-high-symbolic'}), null, 0.74, 1.0);" 3
step bright "Main.osdWindowManager.show(new Gio.ThemedIcon({name:'display-brightness-symbolic'}), null, {0:{level:0.55}});" 3
step notif "Main.notify('Discord', 'kuro: you on tonight? queue opens at 9, bring the good headset this time');" 7
pid=$($D player islandtest); sleep 3
step media "" 6
kill "$pid" 2>/dev/null
magick -size 1280x800 gradient:'#7A0F1A'-'#0E0A0D' "$T/fake-shot.png"
step shot "X._shot(Gio.File.new_for_path('$T/fake-shot.png'));" 6
step power "X._powerState=2; X._power={IsPresent:true, State:1, Percentage:64}; X._powerChanged();" 4
step low "X._powerState=2; X._lowShown=100; X._power={IsPresent:true, State:2, Percentage:19}; X._powerChanged();" 4
magick "$T"/i-{rest,vol,bright,notif,media,shot,power,low}-c.png -append "$T/island-states.png"
echo "$T/island-states.png"
grep -iE "bapirlo-island|island\.js|views\.js" "$T/shell.log" | grep -iv "DING" | tail -5
