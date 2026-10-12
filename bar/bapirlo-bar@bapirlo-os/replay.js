// Bapirlo Bar — instant-replay dot. Only visible while the replay buffer
// (systemd --user bapirlo-replay.service) is running.
//   click = save the last 30 s (same as Super+Alt+G) · right-click = stop the buffer
// When a clip lands in ~/Videos/Replays an OSD says so (works over fullscreen games,
// where notification banners are muted by auto Do-Not-Disturb). No animation loops:
// the dot is static so it never forces the bar to repaint during a game.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Pango from 'gi://Pango';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {Group, attachTooltip, EASE} from './util.js';

const UNIT = 'bapirlo-replay.service';
const CMD = GLib.build_filenamev([GLib.get_home_dir(), 'bapirlo-os', 'bin', 'bapirlo-replay']);
export const REPLAY_DIR = GLib.build_filenamev([GLib.get_home_dir(), 'Videos', 'Replays']);

const SD = 'org.freedesktop.systemd1';
const UnitIface = `<node><interface name="org.freedesktop.systemd1.Unit">
  <property name="ActiveState" type="s" access="read"/>
</interface></node>`;
const UnitProxy = Gio.DBusProxy.makeProxyWrapper(UnitIface);

function run(...args) {
    try {
        Gio.Subprocess.new([CMD, ...args], Gio.SubprocessFlags.NONE);
    } catch (e) {
        logError(e, 'bapirlo-bar: bapirlo-replay failed');
    }
}

export const ReplayDot = GObject.registerClass(
class BapirloReplayDot extends Group {
    _init() {
        super._init('Bapirlo instant replay', 'bapirlo-replay');
        this._btn = new St.Button({
            style_class: 'bapirlo-replay-btn', can_focus: true, track_hover: true,
            button_mask: St.ButtonMask.PRIMARY | St.ButtonMask.SECONDARY,
            child: new St.BoxLayout({style_class: 'bapirlo-replay-box', y_align: Clutter.ActorAlign.CENTER}),
        });
        this._dot = new St.Widget({style_class: 'bapirlo-replay-dot', y_align: Clutter.ActorAlign.CENTER});
        this._btn.child.add_child(this._dot);
        const label = new St.Label({text: 'REPLAY', style_class: 'bapirlo-replay-label', y_align: Clutter.ActorAlign.CENTER});
        label.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;   // see power.js
        this._btn.child.add_child(label);
        this.box.add_child(this._btn);
        attachTooltip(this._btn, () => 'Instant replay is recording — click (or Super+Alt+G) to save the last 30 s, right-click to stop');
        this._btn.connect('clicked', (_b, button) => run(button === Clutter.BUTTON_SECONDARY ? 'stop' : 'save'));
        this.visible = false;

        this._cancellable = new Gio.Cancellable();
        this._watchUnit();
        this._watchDir();
    }

    _watchUnit() {
        const bus = Gio.DBus.session;
        // systemd only emits PropertiesChanged to subscribed clients
        bus.call(SD, '/org/freedesktop/systemd1', `${SD}.Manager`, 'Subscribe', null, null,
            Gio.DBusCallFlags.NONE, -1, this._cancellable, (c, r) => {
                try {
                    c.call_finish(r);
                } catch {}
            });
        bus.call(SD, '/org/freedesktop/systemd1', `${SD}.Manager`, 'LoadUnit',
            new GLib.Variant('(s)', [UNIT]), new GLib.VariantType('(o)'),
            Gio.DBusCallFlags.NONE, -1, this._cancellable, (c, r) => {
                try {
                    const [path] = c.call_finish(r).deepUnpack();
                    this._unit = new UnitProxy(bus, SD, path, (p, e) => {
                        if (e)
                            return;
                        this._unit.connectObject('g-properties-changed', () => this._sync(), this);
                        this._sync();
                    }, this._cancellable);
                } catch (e) {
                    if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                        logError(e, 'bapirlo-bar: replay unit');
                }
            });
    }

    _sync() {
        const s = this._unit?.ActiveState;
        this.visible = s === 'active' || s === 'activating';
    }

    _watchDir() {
        GLib.mkdir_with_parents(REPLAY_DIR, 0o755);
        this._monitor = Gio.File.new_for_path(REPLAY_DIR).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, null);
        this._monitor.connectObject('changed', (_m, file, _o, ev) => {
            // gsr writes the clip then closes it; CHANGES_DONE_HINT = finished
            if (ev === Gio.FileMonitorEvent.CHANGES_DONE_HINT && /\.(mp4|mkv|webm)$/i.test(file.get_basename()))
                this._saved();
        }, this);
    }

    _saved() {
        Main.osdWindowManager.showAll(Gio.ThemedIcon.new('media-record-symbolic'), 'Replay saved', null, null);
        this._dot.remove_all_transitions();
        this._dot.set_pivot_point(0.5, 0.5);
        this._dot.ease({
            scale_x: 1.8, scale_y: 1.8, duration: 160, mode: EASE,
            onComplete: () => this._dot.ease({scale_x: 1, scale_y: 1, duration: 260, mode: EASE}),
        });
    }

    destroy() {
        this._cancellable.cancel();
        this._monitor?.disconnectObject(this);
        this._monitor?.cancel();
        this._unit?.disconnectObject(this);
        super.destroy();
    }
});
