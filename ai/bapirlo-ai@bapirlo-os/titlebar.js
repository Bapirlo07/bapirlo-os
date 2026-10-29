// Title strip for the assistant window. Its Alacritty runs without decorations, so this slim
// tab sits on the window's top edge: drag it to move the window, and it carries
//   pin   float above other windows or not (setting "keep-above", remembered)
//   –     hide (minimise) — the conversation keeps running, Super+A brings it back
//   ✕     close the window (ends the conversation)
// The strip lives in global.window_group right above the window's actor, so other windows
// cover it the same way they cover the window. Colours come from the Theme Studio palette.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';

export const STRIP_H = 30;

const PALETTE = GLib.build_filenamev([GLib.get_user_state_dir(), 'bapirlo', 'studio', 'active.json']);
const DEFAULTS = {night: '#161015', paper: '#F2E9EC', crimson: '#E11D2E', ember: '#FF4655'};

function readPalette() {
    const pal = {...DEFAULTS};
    try {
        const [, bytes] = GLib.file_get_contents(PALETTE);
        const got = JSON.parse(new TextDecoder().decode(bytes))?.palette ?? {};
        for (const k of Object.keys(pal)) {
            if (/^#[0-9a-fA-F]{6}$/.test(got[k] ?? ''))
                pal[k] = got[k];
        }
    } catch {}
    return pal;
}

function rgba(hex, a) {
    const [r, g, b] = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));
    return `rgba(${r}, ${g}, ${b}, ${a})`;
}

export class TitleStrip {
    constructor(win, settings) {
        this._win = win;
        this._settings = settings;
        this._drag = null;
        this._buttons = [];

        this.actor = new St.BoxLayout({style_class: 'bai-strip', reactive: true, track_hover: true});
        this._title = new St.Label({style_class: 'bai-title', text: win.get_title() || 'Claude',
            y_align: Clutter.ActorAlign.CENTER, x_expand: true});
        this._title.clutter_text.ellipsize = 3;     // Pango.EllipsizeMode.END
        this.actor.add_child(this._title);
        this._pin = this._button('view-pin-symbolic', () => this._togglePin());
        this._button('window-minimize-symbolic', () => this._win.minimize());
        this._button('window-close-symbolic', () => this._win.delete(global.get_current_time()));

        this._wactor = win.get_compositor_private();
        global.window_group.add_child(this.actor);

        this._paint();
        this._monitor = Gio.File.new_for_path(PALETTE).monitor_file(Gio.FileMonitorFlags.NONE, null);
        this._monitor.connect('changed', () => this._paint());

        this.actor.connect('button-press-event', (_a, ev) => this._press(ev));
        this.actor.connect('motion-event', (_a, ev) => this._motion(ev));
        this.actor.connect('button-release-event', () => this._release());

        win.connectObject(
            'position-changed', () => this._sync(),
            'size-changed', () => this._sync(),
            'notify::minimized', () => this._sync(),
            'notify::fullscreen', () => this._sync(),
            'notify::above', () => this._syncPin(),
            'notify::title', () => this._title.set_text(win.get_title() || 'Claude'), this);
        this._wactor?.connectObject('notify::visible', () => this._sync(), this);
        global.display.connectObject('restacked', () => this._restack(), this);
        this._restack();
        this._syncPin();
        this._sync();
    }

    _button(icon, cb) {
        const b = new St.Button({style_class: 'bai-button', can_focus: false,
            y_align: Clutter.ActorAlign.CENTER, child: new St.Icon({icon_name: icon, icon_size: 14})});
        b.connect('clicked', cb);
        this._buttons.push(b);
        this.actor.add_child(b);
        return b;
    }

    _paint() {
        const p = readPalette();
        this.actor.set_style(`background-color: ${rgba(p.night, 0.96)}; ` +
            `border-color: ${rgba(p.crimson, 0.45)}; color: ${p.paper};`);
        this._pinOn = `color: ${p.ember}; background-color: ${rgba(p.crimson, 0.22)};`;
        this._syncPin();
    }

    _togglePin() {
        const above = !this._win.is_above();
        this._settings.set_boolean('keep-above', above);
        if (above)
            this._win.make_above();
        else
            this._win.unmake_above();
    }

    _syncPin() {
        this._pin?.set_style(this._win.is_above() ? this._pinOn ?? null : null);
    }

    _restack() {
        if (this._wactor?.get_parent() === global.window_group)
            global.window_group.set_child_above_sibling(this.actor, this._wactor);
    }

    _sync() {
        const w = this._win;
        this.actor.visible = !!this._wactor?.visible && !w.minimized && !w.fullscreen;
        if (!this.actor.visible)
            return;
        const r = w.get_frame_rect();
        // no room above (pushed against the top bar) → lie over the window's first row instead
        const area = w.get_work_area_current_monitor();
        const y = r.y - STRIP_H >= area.y ? r.y - STRIP_H : r.y;
        this.actor.set_position(r.x, y);
        this.actor.set_size(r.width, STRIP_H);
    }

    // press on the strip (not a button) → stage grab; the window follows the pointer until release
    _press(ev) {
        // St.Button presses bubble up to here on GNOME 51 — grabbing would eat the button's release
        if (ev.get_button() !== Clutter.BUTTON_PRIMARY || this._drag ||
            this._buttons.some(b => b.contains(global.stage.get_event_actor(ev))))
            return Clutter.EVENT_PROPAGATE;
        const w = this._win;
        w.activate(global.get_current_time());
        if (w.is_maximized())
            w.unmaximize();
        const [sx, sy] = ev.get_coords();
        const r = w.get_frame_rect();
        this._drag = {dx: sx - r.x, dy: sy - r.y, grab: global.stage.grab(this.actor)};
        global.stage.set_cursor_type(Clutter.CursorType.GRABBING);
        return Clutter.EVENT_STOP;
    }

    _motion(ev) {
        if (!this._drag)
            return Clutter.EVENT_PROPAGATE;
        if (!(ev.get_state() & Clutter.ModifierType.BUTTON1_MASK)) {
            this._release();      // the release went somewhere else (grab broken)
            return Clutter.EVENT_STOP;
        }
        const [sx, sy] = ev.get_coords();
        const area = this._win.get_work_area_current_monitor();
        this._win.move_frame(true, Math.round(sx - this._drag.dx),
            Math.round(Math.max(sy - this._drag.dy, area.y + STRIP_H)));
        return Clutter.EVENT_STOP;
    }

    _release() {
        if (!this._drag)
            return Clutter.EVENT_PROPAGATE;
        this._drag.grab?.dismiss();
        this._drag = null;
        global.stage.set_cursor_type(Clutter.CursorType.DEFAULT);
        return Clutter.EVENT_STOP;
    }

    destroy() {
        this._release();
        this._monitor?.cancel();
        this._monitor = null;
        this._win.disconnectObject(this);
        this._wactor?.disconnectObject(this);
        global.display.disconnectObject(this);
        this.actor.destroy();
    }
}
