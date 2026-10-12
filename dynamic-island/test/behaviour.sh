#!/usr/bin/env bash
# Behaviour checks in the test shell: click-to-activate, fullscreen fallback, disable/enable restore.
export T=${T:-/tmp/claude-1000/bapirlo-island-test}
HERE=$(dirname "$(readlink -f "$0")")
D() { bash "$HERE/../../media-widget/test/drive.sh" "$@"; }
pre="const Gio=(await import('gi://Gio')).default; const GLib=(await import('gi://GLib')).default; const MT=await import('resource:///org/gnome/shell/ui/messageTray.js'); const sleep=ms=>new Promise(r=>GLib.timeout_add(0,ms,()=>{r();return false;})); const EM=Main.extensionManager; const X=()=>EM.lookup('bapirlo-island@bapirlo-os').stateObj;"
echo "--- click notification → activated + closed"
xy=$(D eval "$pre globalThis._act=false; const src=new MT.Source({title:'Test', iconName:'dialog-information-symbolic'}); Main.messageTray.add(src); const n=new MT.Notification({source:src, title:'Click me', body:'body'}); n.connect('activated',()=>{_act=true}); src.addNotification(n); await sleep(700); const a=X()._island.actor; const [x,y]=a.get_transformed_position(); return Math.round(x+60)+' '+Math.round(y+30)" | tr -d '"')
D click $xy >/dev/null
D eval "$pre await sleep(900); return {activated: _act, state: X()._island._state}"
echo "--- media play button keeps it open"
pid=$(D player clicktest); sleep 4
xy=$(D eval "$pre const v=X()._island._current; if(!v||v.kind!=='media') return 'nomedia'; const b=v.view.get_children()[2]; const [x,y]=b.get_transformed_position(); return Math.round(x+b.width/2)+' '+Math.round(y+b.height/2)" | tr -d '"')
echo "play btn at $xy"; [ "$xy" != nomedia ] && D click $xy >/dev/null
D eval "$pre await sleep(500); return {state: X()._island._state, kind: X()._island._current?.kind}"
sleep 1; grep -c PlayPause "$T/player-clicktest.log"; kill "$pid"; sleep 5
echo "--- fullscreen → stock OSD, island idle"
D eval "$pre const m=Main.layoutManager.primaryMonitor; Object.defineProperty(m,'inFullscreen',{value:true,configurable:true,writable:true}); Main.osdWindowManager.showAll(new Gio.ThemedIcon({name:'audio-volume-high-symbolic'}), null, 0.5, 1); await sleep(400); const r={islandBusy: X()._island.busy, stockOsdVisible: Main.osdWindowManager._osdWindows[0].visible}; delete m.inFullscreen; m.inFullscreen=false; Main.osdWindowManager.hideAll(); return r"
sleep 2
echo "--- disable → everything restored"
D eval "$pre await EM.disableExtension('bapirlo-island@bapirlo-os'); await sleep(300); return {osdOwn: ['show','showAll','showOne'].filter(k=>Object.hasOwn(Main.osdWindowManager,k)), trayOwn: Object.hasOwn(Main.messageTray,'_showNotification'), restClass: Main.panel._centerBox.has_style_class_name('bapirlo-island-rest'), centreOpacity: Main.panel._centerBox.opacity}"
echo "--- stock OSD after disable"
D eval "$pre Main.osdWindowManager.showAll(new Gio.ThemedIcon({name:'audio-volume-high-symbolic'}), null, 0.5, 1); await sleep(300); const v=Main.osdWindowManager._osdWindows[0].visible; Main.osdWindowManager.hideAll(); return v"
echo "--- re-enable"
D eval "$pre await EM.enableExtension('bapirlo-island@bapirlo-os'); await sleep(300); Main.osdWindowManager.showAll(new Gio.ThemedIcon({name:'audio-volume-high-symbolic'}), null, 0.3, 1); await sleep(300); return {state: EM.lookup('bapirlo-island@bapirlo-os').state, busy: X()._island.busy}"
echo "--- island errors in log:"
grep -n "bapirlo-island@" "$T/shell.log" | tail -5
