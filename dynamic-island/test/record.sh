#!/usr/bin/env bash
# Record the island animating (volume → notification → screenshot) to ../../build/island/island.mp4/.gif
export T=${T:-/tmp/claude-1000/bapirlo-island-test}
HERE=$(dirname "$(readlink -f "$0")")
OUT=$HERE/../../build/island; mkdir -p "$OUT"; rm -rf "$T/rec"; mkdir -p "$T/rec"
W=$(cut -dx -f1 <<<"${MON:-1920x1200}")
# park the pointer away from the bar (hovering the pill keeps it open) and let it settle to rest
bash "$HERE/../../media-widget/test/drive.sh" eval "const Clutter=(await import('gi://Clutter')).default, GLib=(await import('gi://GLib')).default; globalThis._vp ??= Clutter.get_default_backend().get_default_seat().create_virtual_device(Clutter.InputDeviceType.POINTER_DEVICE); _vp.notify_absolute_motion(GLib.get_monotonic_time(), 200, 700); return 1" >/dev/null
sleep 3
bash "$HERE/../../media-widget/test/drive.sh" eval "
const Gio=(await import('gi://Gio')).default, GLib=(await import('gi://GLib')).default, Shell=(await import('gi://Shell')).default;
const sleep=ms=>new Promise(r=>GLib.timeout_add(0,ms,()=>{r();return false;}));
const X=Main.extensionManager.lookup('bapirlo-island@bapirlo-os').stateObj;
const times=[]; let i=0, rec=true;
const shoot=async()=>{ while(rec){ const s=new Shell.Screenshot(); const f=Gio.File.new_for_path('$T/rec/'+String(i++).padStart(4,'0')+'.png'); const o=f.replace(null,false,0,null);
  await new Promise(r=>s.screenshot_area($((W/2-360)),0,720,150,o,()=>r())); o.close(null); times.push(GLib.get_monotonic_time()); await sleep(1);} };
const p=shoot();
await sleep(600);
for (const v of [0.3,0.45,0.6,0.72]) { Main.osdWindowManager.showAll(new Gio.ThemedIcon({name:'audio-volume-high-symbolic'}), null, v, 1); await sleep(180); }
await sleep(2600);
Main.notify('Discord', 'kuro: you on tonight? queue opens at 9');
await sleep(5600);
X._shot(Gio.File.new_for_path('$T/fake-shot.png'));
await sleep(5600);
rec=false; await p;
const d=times.map((t,k)=>k?(t-times[k-1])/1e6:0); GLib.file_set_contents('$T/rec/times.json', JSON.stringify(d));
return times.length + ' frames, ' + ((times.at(-1)-times[0])/1e6).toFixed(1)+'s'"
cd "$T/rec" && python3 -c "
import json; d=json.load(open('times.json')); n=len(d)
with open('list.txt','w') as f:
  for k in range(n):
    f.write(f\"file '{k:04d}.png'\nduration {d[k+1] if k+1<n else 0.1:.4f}\n\")
  f.write(f\"file '{n-1:04d}.png'\n\")"
ffmpeg -y -loglevel error -f concat -safe 0 -i list.txt -vf "fps=30,format=yuv420p" -c:v libx264 -crf 18 "$OUT/island.mp4"
ffmpeg -y -loglevel error -i "$OUT/island.mp4" -vf "fps=25,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse" "$OUT/island.gif"
ls -la "$OUT"
