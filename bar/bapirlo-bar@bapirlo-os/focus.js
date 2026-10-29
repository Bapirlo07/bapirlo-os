// Bapirlo Bar — focus timer. Sits next to the clock (inside the Dynamic Island's resting capsule)
// and is only visible while a session runs:  FOCUS 24:13  (crimson) → BREAK 4:59  (jade).
//   Super+Alt+F (or `bapirlo-focus`) = start / stop · click = pause / resume · right-click = stop
// A focus block switches notification banners off (only if they were on, and back on after);
// at its end an OSD + the "complete" sound say so — OSDs show over fullscreen apps and through DND,
// banners would not. The break starts by itself; the next focus block never does.
// State lives in the bar's GSettings keys (focus-phase/-end/-left/-total/-started), so it survives a
// shell restart; bin/bapirlo-focus drives it through focus-request. This file is the only writer of the log
// ~/.local/state/bapirlo/focus.tsv (start ISO time · minutes · done|stopped) the Welcome app reads.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Pango from 'gi://Pango';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {Group, attachTooltip} from './util.js';

export const FOCUS_LOG = GLib.build_filenamev([GLib.get_user_state_dir(), 'bapirlo', 'focus.tsv']);
const LATE_S = 60;   // ended this long ago (shell was off / suspended) → finish quietly, no break

const now = () => Math.floor(GLib.get_real_time() / 1e6);

function mmss(s) {
    s = Math.max(0, s);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

export const FocusTimer = GObject.registerClass(
class BapirloFocusTimer extends Group {
    _init(settings) {
        super._init('Bapirlo focus timer', 'bapirlo-focus');
        this._settings = settings;
        this._btn = new St.Button({
            style_class: 'bapirlo-focus-btn', can_focus: true, track_hover: true,
            button_mask: St.ButtonMask.PRIMARY | St.ButtonMask.SECONDARY,
            child: new St.BoxLayout({style_class: 'bapirlo-focus-box', y_align: Clutter.ActorAlign.CENTER}),
        });
        this._icon = new St.Icon({icon_name: 'timer-symbolic', style_class: 'bapirlo-focus-icon',
            y_align: Clutter.ActorAlign.CENTER});
        this._phaseLabel = new St.Label({style_class: 'bapirlo-focus-phase', y_align: Clutter.ActorAlign.CENTER});
        this._time = new St.Label({style_class: 'bapirlo-focus-time', y_align: Clutter.ActorAlign.CENTER});
        for (const l of [this._phaseLabel, this._time])
            l.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;   // see power.js
        this._btn.child.add_child(this._icon);
        this._btn.child.add_child(this._phaseLabel);
        this._btn.child.add_child(this._time);
        this.box.add_child(this._btn);
        attachTooltip(this._btn, () => this._tooltip());
        this._btn.connect('clicked', (_b, button) => {
            if (button === Clutter.BUTTON_SECONDARY)
                this.stop();
            else
                this.pauseResume();
        });
        this.visible = false;

        this._banners = new Gio.Settings({schema_id: 'org.gnome.desktop.notifications'});
        // state changes go through their own settings object, kept in delay-apply mode (delay() can't be
        // undone), so apply() commits all keys of one change at once and nobody reads a half-done state
        this._writer = new Gio.Settings({settings_schema: settings.settings_schema});
        this._writer.delay();
        this._last = null;
        this._finished = '';   // phase:end already finished — _sync can run several times for one change
        this._settings.connectObject(
            'changed::focus-phase', () => this._sync(),
            'changed::focus-end', () => this._sync(),
            'changed::focus-left', () => this._sync(),
            'changed::focus-request', () => this._request(),
            this);
        this._settings.get_string('focus-request');   // GSettings only emits changed:: for keys read once
        this._sync();
    }

    // ---------------------------------------------------------------- state
    _state() {
        const s = this._settings;
        return {
            phase: s.get_string('focus-phase'),         // '' | 'focus' | 'break'
            end: s.get_int64('focus-end'),              // unix s; 0 while paused
            left: s.get_int('focus-left'),              // s left while paused, else 0
            total: s.get_int('focus-total'),            // s the phase lasts
            started: s.get_int64('focus-started'),      // unix s the focus block began
        };
    }

    _remaining(st) {
        return st.left > 0 ? st.left : st.end - now();
    }

    _set(phase, seconds) {
        const s = this._writer;
        s.set_string('focus-phase', phase);
        s.set_int('focus-total', seconds);
        s.set_int('focus-left', 0);
        s.set_int64('focus-end', phase ? now() + seconds : 0);
        if (phase === 'focus')
            s.set_int64('focus-started', now());
        s.apply();
    }

    toggle() {
        if (this._state().phase)
            this.stop();
        else
            this._set('focus', this._settings.get_int('focus-minutes') * 60);
    }

    pauseResume() {
        const st = this._state();
        if (!st.phase)
            return;
        const s = this._writer;
        if (st.left > 0) {
            s.set_int64('focus-end', now() + st.left);
            s.set_int('focus-left', 0);
        } else {
            s.set_int('focus-left', Math.max(1, st.end - now()));
            s.set_int64('focus-end', 0);
        }
        s.apply();
    }

    stop() {
        const st = this._state();
        if (st.phase === 'focus') {
            const done = st.total - this._remaining(st);
            if (done >= 60)
                this._log(st.started, Math.round(done / 60), 'stopped');
        }
        this._set('', 0);
    }

    // bin/bapirlo-focus writes ONE key ("start 25 @<nonce>", "stop @…", "toggle @…", "pause @…") and the
    // shell applies it in a single delayed write — several separate gsettings calls could be seen half-done
    _request() {
        const [verb, arg] = this._settings.get_string('focus-request').split(' ');
        const st = this._state();
        if (verb === 'start' && !st.phase) {
            const min = Number.parseInt(arg, 10);
            this._set('focus', (min > 0 && min <= 600 ? min : this._settings.get_int('focus-minutes')) * 60);
        } else if (verb === 'stop' && st.phase) {
            this.stop();
        } else if (verb === 'toggle') {
            this.toggle();
        } else if (verb === 'pause') {
            this.pauseResume();
        }
    }

    _sync() {
        const st = this._state();
        this._last = st;
        this._syncBanners(st.phase === 'focus');

        if (!st.phase) {
            this._stopTick();
            this.visible = false;
            return;
        }
        if (st.left <= 0 && st.end - now() <= 0) {
            this._finish(st);
            return;
        }
        this.visible = true;
        this._btn.remove_style_class_name(st.phase === 'focus' ? 'break' : 'focus');
        this._btn.add_style_class_name(st.phase);
        (st.left > 0 ? this._btn.add_style_class_name : this._btn.remove_style_class_name).call(this._btn, 'paused');
        this._icon.icon_name = st.left > 0 ? 'media-playback-pause-symbolic' : 'timer-symbolic';
        this._phaseLabel.text = st.phase === 'focus' ? 'FOCUS' : 'BREAK';
        this._update();
        if (st.left > 0)
            this._stopTick();
        else
            this._startTick();
    }

    _finish(st) {
        const key = `${st.phase}:${st.end}`;
        if (this._finished === key)
            return;
        this._finished = key;
        const late = now() - st.end > LATE_S;
        if (st.phase === 'focus' && st.total > 0) {
            this._log(st.started, Math.round(st.total / 60), 'done');
            const brk = this._settings.get_int('break-minutes');
            if (late || brk <= 0) {
                this._set('', 0);
            } else {
                this._set('break', brk * 60);
                this._announce(`Focus done · ${brk} min break`);
            }
        } else {
            this._set('', 0);
            if (st.phase === 'break' && !late)
                this._announce('Break over');
        }
    }

    _announce(title) {
        Main.osdWindowManager.showAll(Gio.ThemedIcon.new('timer-symbolic'), title, null, null);
        try {
            global.display.get_sound_player().play_from_theme('complete', title, null);
        } catch {}
    }

    // banners off for the focus block — only if they were on, and only ever undone by us
    _syncBanners(want) {
        const owned = this._settings.get_boolean('focus-owns-dnd');
        if (want && !owned && this._banners.get_boolean('show-banners')) {
            this._banners.set_boolean('show-banners', false);
            this._settings.set_boolean('focus-owns-dnd', true);
        } else if (!want && owned) {
            this._banners.set_boolean('show-banners', true);
            this._settings.set_boolean('focus-owns-dnd', false);
        }
    }

    // ---------------------------------------------------------------- display
    _update() {
        const st = this._last;
        if (!st?.phase)
            return;
        const r = this._remaining(st);
        this._time.text = mmss(r);
        if (st.left <= 0 && r <= 0)
            this._sync();
    }

    _startTick() {
        if (this._tick)
            return;
        // one text change a second; nothing animates, so idle repaint cost stays at one label
        this._tick = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1, () => {
            this._update();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _stopTick() {
        if (this._tick)
            GLib.source_remove(this._tick);
        this._tick = 0;
    }

    _tooltip() {
        const st = this._last;
        if (!st?.phase)
            return '';
        const what = st.phase === 'focus' ? 'Focus block' : 'Break';
        if (st.left > 0)
            return `${what} paused · ${mmss(st.left)} left — click to resume, right-click to stop`;
        const end = GLib.DateTime.new_from_unix_local(st.end).format('%H:%M');
        return `${what} ends at ${end} — click to pause, right-click (or Super+Alt+F) to stop`;
    }

    _log(started, minutes, status) {
        try {
            const when = GLib.DateTime.new_from_unix_local(started || now() - minutes * 60).format('%Y-%m-%dT%H:%M:%S');
            const file = Gio.File.new_for_path(FOCUS_LOG);
            GLib.mkdir_with_parents(GLib.path_get_dirname(FOCUS_LOG), 0o755);
            const out = file.append_to(Gio.FileCreateFlags.NONE, null);
            out.write_all(new TextEncoder().encode(`${when}\t${minutes}\t${status}\n`), null);
            out.close(null);
        } catch (e) {
            logError(e, 'bapirlo-bar: focus log');
        }
    }

    destroy() {
        this._stopTick();
        this._settings.disconnectObject(this);
        this._writer = null;
        // the session keeps running (state is in GSettings); a disabled bar must not hold banners off
        if (this._settings.get_boolean('focus-owns-dnd')) {
            this._banners.set_boolean('show-banners', true);
            this._settings.set_boolean('focus-owns-dnd', false);
        }
        this._settings = null;
        super.destroy();
    }
});
