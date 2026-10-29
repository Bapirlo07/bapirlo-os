// Kuro Bar — accent pulse. Switch workspace or window and the active workspace pill plus a thin
// border around the focused window breathe in the wallpaper's crimson three times, then settle on
// a soft steady glow. Short on purpose: nothing animates while you just work (battery, games).
//   off: gsettings set org.gnome.shell.extensions.bapirlo-bar accent-pulse false
// The border (with an INSET glow: an outer St shadow fills the whole box) is a child of the window actor, so it moves, minimises and slides between
// workspaces with the window. Maximised / fullscreen / non-normal windows get none.
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Meta from 'gi://Meta';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {readPalette} from './looks.js';

const BREATHS = 3;
const BREATH_MS = 1200;
const FRAME_MS = 33;
const RADIUS = 12;     // rounded-window-corners' radius
const PALETTE = GLib.build_filenamev([GLib.get_user_state_dir(), 'bapirlo', 'studio', 'active.json']);

export class AccentPulse {
    constructor(settings, dots) {
        this._settings = settings;
        this._dots = dots;
        this._win = null;
        this._border = null;
        this._timer = 0;
        this._rgb = this._readRgb();

        this._palMonitor = Gio.File.new_for_path(PALETTE).monitor_file(Gio.FileMonitorFlags.WATCH_MOVES, null);
        this._palMonitor.connect('changed', () => {
            this._rgb = this._readRgb();
            this._paint(1);
        });
        settings.connectObject('changed::accent-pulse', () => this._sync(), this);
        global.display.connectObject('notify::focus-window', () => this._sync(), this);
        global.workspace_manager.connectObject('active-workspace-changed', () => this._start(), this);
        this._sync();
    }

    get _on() {
        return this._settings.get_boolean('accent-pulse');
    }

    _readRgb() {
        const h = readPalette().crimson;
        return [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16)).join(', ');
    }

    _wants(win) {
        if (!win || win.get_window_type() !== Meta.WindowType.NORMAL || win.is_fullscreen() || win.minimized)
            return false;
        const f = win.get_frame_rect();
        const wa = win.get_work_area_current_monitor();
        return f.width < wa.width || f.height < wa.height;      // maximised = fills the work area
    }

    // the focused window changed (or its state did): move the border, breathe again
    _sync() {
        const win = global.display.focus_window;
        if (win !== this._win) {
            this._win?.disconnectObject(this);
            this._win = win;
            win?.connectObject(
                'size-changed', () => this._place(),
                'notify::fullscreen', () => this._place(),
                'notify::minimized', () => this._place(),
                'unmanaging', () => this._drop(),
                this);
            this._drop();
        }
        this._place();
        this._start();
    }

    _drop() {
        this._border?.destroy();
        this._border = null;
    }

    _place() {
        const win = this._win;
        if (!this._on || !this._wants(win)) {
            this._drop();
            return;
        }
        const actor = win.get_compositor_private();
        if (!actor)
            return;
        if (!this._border || this._border.get_parent() !== actor) {
            this._drop();
            const border = new St.Widget({style_class: 'bapirlo-accent-border', reactive: false});
            // closing the window destroys its actor and our border with it
            border.connect('destroy', () => {
                if (this._border === border)
                    this._border = null;
            });
            actor.add_child(border);
            this._border = border;
        }
        const f = win.get_frame_rect();
        const b = win.get_buffer_rect();
        this._border.set_position(f.x - b.x, f.y - b.y);
        this._border.set_size(f.width, f.height);
        this._paint(1);
    }

    _start() {
        this._stop();
        if (!this._on) {
            this._clearDot();
            return;
        }
        const t0 = GLib.get_monotonic_time();
        this._timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, FRAME_MS, () => {
            const t = (GLib.get_monotonic_time() - t0) / 1000;
            if (t >= BREATHS * BREATH_MS) {
                this._timer = 0;
                this._paint(1);
                return GLib.SOURCE_REMOVE;
            }
            // 1 → 0 → 1 per breath, eased: a slow swell rather than a blink
            this._paint(0.5 + 0.5 * Math.cos(2 * Math.PI * t / BREATH_MS));
            return GLib.SOURCE_CONTINUE;
        });
    }

    _stop() {
        if (this._timer)
            GLib.source_remove(this._timer);
        this._timer = 0;
    }

    // k: 1 = the resting glow, 0 = the peak of a breath
    _paint(k) {
        const glow = 1 - k;
        const c = this._rgb;
        if (this._border)
            this._border.set_style(`border: 2px solid rgba(${c}, ${(0.55 + 0.45 * glow).toFixed(2)});` +
                ` border-radius: ${RADIUS}px;` +
                ` box-shadow: inset 0 0 ${Math.round(3 + 10 * glow)}px rgba(${c}, ${(0.15 + 0.40 * glow).toFixed(2)});`);
        this._clearDot();
        if (!this._on)
            return;
        const dot = this._dots._dots?.find(d => d.has_style_class_name('active'));
        if (dot) {
            dot.set_style(`box-shadow: 0 0 ${Math.round(3 + 9 * glow)}px rgba(${c}, ${(0.35 + 0.5 * glow).toFixed(2)});`);
            this._styledDot = dot;
        }
    }

    _clearDot() {
        // a workspace added / removed rebuilds the dots: only touch one that still exists
        if (this._styledDot && this._dots._dots?.includes(this._styledDot))
            this._styledDot.set_style(null);
        this._styledDot = null;
    }

    destroy() {
        this._stop();
        this._palMonitor.cancel();
        this._settings.disconnectObject(this);
        global.display.disconnectObject(this);
        global.workspace_manager.disconnectObject(this);
        this._win?.disconnectObject(this);
        this._win = null;
        this._drop();
        this._clearDot();
    }
}
