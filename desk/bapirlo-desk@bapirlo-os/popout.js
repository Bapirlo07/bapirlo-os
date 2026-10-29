// Bapirlo Desk — pop ANY window out into a live picture-in-picture.
// Super+Alt+I (or "Picture in Picture" in the window menu: Alt+Space / right-click the title bar)
// floats a small live copy of the focused window in a screen corner, above every window
// (fullscreen ones too) and on every workspace, so a video, a call, a build log or a game keeps
// playing while you work elsewhere. It is a Clutter clone of the window, not the window itself:
// the app is not resized or moved and you can minimise it or leave its workspace.
//   drag            move it; it snaps to the nearest corner of that screen
//   scroll          bigger / smaller        Ctrl+scroll   more / less see-through
//   double-click    go to the window        middle-click / ✕ / Super+Alt+I again   close
// Hidden in the overview and under the lock screen. Up to four at once; the last size, corner and
// opacity are remembered in ~/.local/state/bapirlo/pip.json ("popout"), next to pip.js's state.
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Mtk from 'gi://Mtk';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {WindowMenu} from 'resource:///org/gnome/shell/ui/windowMenu.js';

import {STATE_DIR, EASE, readJson, writeJson} from './util.js';
import {readPalette} from './widgets.js';

const STATE = GLib.build_filenamev([STATE_DIR, 'pip.json']);
const MAX = 4;
const MARGIN = 24;
const MIN_W = 200;
const CORNERS = ['br', 'bl', 'tr', 'tl'];
const DOUBLE_CLICK_US = 400 * 1000;

function hexA(hex, a) {
    const [r, g, b] = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));
    return `rgba(${r}, ${g}, ${b}, ${a})`;
}

export class PopOut {
    constructor() {
        this._pips = new Map();   // window → pip
        const st = readJson(STATE, {})?.popout ?? {};
        this._last = {width: st.width ?? 420, corner: CORNERS.includes(st.corner) ? st.corner : 'br', opacity: st.opacity ?? 255};

        Main.overview.connectObject(
            'showing', () => this._sync(),
            'hidden', () => this._sync(),
            this);
        Main.layoutManager.connectObject('monitors-changed', () => {
            for (const p of this._pips.values())
                this._place(p, false);
        }, this);
        Main.screenShield?.connectObject('active-changed', () => this._sync(), this);

        // "Picture in Picture" under "Always on Top" in every window menu
        const self = this;
        this._origBuild = WindowMenu.prototype._buildMenu;
        const orig = this._origBuild;
        WindowMenu.prototype._buildMenu = function (window) {
            orig.call(this, window);
            const item = new PopupMenu.PopupMenuItem('Picture in Picture');
            item.connect('activate', () => self.toggle(window));
            if (self._pips.has(window))
                item.setOrnament(PopupMenu.Ornament.CHECK);
            const items = this._getMenuItems();
            const top = items.findIndex(i => i.label?.text === 'Always on Top');
            this.addMenuItem(item, top >= 0 ? top + 1 : undefined);
        };
    }

    // Super+Alt+I: the focused window (or close its PiP if it already has one)
    toggleFocused() {
        const w = global.display.focus_window;
        if (w)
            this.toggle(w);
    }

    toggle(w) {
        if (this._pips.has(w)) {
            this._close(w);
            return;
        }
        const type = w.get_window_type();
        if (type !== Meta.WindowType.NORMAL && type !== Meta.WindowType.DIALOG && type !== Meta.WindowType.UTILITY)
            return;
        if (this._pips.size >= MAX)
            this._close(this._pips.keys().next().value);   // oldest makes room
        this._open(w);
    }

    _open(w) {
        const actor = w.get_compositor_private();
        if (!actor)
            return;
        const pal = readPalette();
        const box = new St.Widget({
            style_class: 'bapirlo-popout',
            style: `border-color: ${hexA(pal.crimson, 0.55)}; box-shadow: 0 8px 28px rgba(0, 0, 0, 0.55), 0 0 0 1px ${hexA(pal.crimson, 0.18)};`,
            reactive: true,
            track_hover: true,
            clip_to_allocation: true,
            opacity: 0,
        });
        const clone = new Clutter.Clone({source: actor});
        box.add_child(clone);

        const bar = new St.BoxLayout({style_class: 'bapirlo-popout-bar', opacity: 0, x_expand: true});
        const button = (icon, tip, cb) => {
            const b = new St.Button({style_class: 'bapirlo-popout-button', accessible_name: tip, child: new St.Icon({icon_name: icon})});
            b.connect('clicked', cb);
            return b;
        };
        bar.add_child(button('view-restore-symbolic', 'Go to window', () => this._goTo(w)));
        bar.add_child(new St.Label({
            text: w.get_title() ?? '', style_class: 'bapirlo-popout-title', x_expand: true, y_align: Clutter.ActorAlign.CENTER,
        }));
        bar.add_child(button('window-close-symbolic', 'Close picture-in-picture', () => this._close(w)));
        box.add_child(bar);

        const pip = {w, box, clone, bar, width: this._last.width, corner: this._freeCorner(), opacity: this._last.opacity, mon: w.get_monitor()};
        this._pips.set(w, pip);
        Main.layoutManager.addChrome(box);
        // under the lock screen (addChrome alone would stack it above the shield)
        Main.layoutManager.uiGroup.set_child_below_sibling(box, Main.layoutManager.screenShieldGroup);

        box.connect('notify::hover', () => bar.ease({opacity: box.hover || pip.drag ? 255 : 0, duration: 150, mode: EASE}));
        this._input(pip);
        w.connectObject(
            'size-changed', () => this._place(pip, false),
            'notify::title', () => (bar.get_child_at_index(1).text = w.get_title() ?? ''),
            'unmanaged', () => this._close(w),
            this);

        // a PiP over a fullscreen game / video needs compositing: no direct scan-out meanwhile
        if (this._pips.size === 1)
            global.compositor.disable_unredirect();
        this._place(pip, false);
        this._sync();
    }

    _close(w) {
        const p = this._pips.get(w);
        if (!p)
            return;
        this._pips.delete(w);
        w.disconnectObject(this);
        p.drag?.grab.dismiss();
        p.box.destroy();
        if (this._pips.size === 0)
            global.compositor.enable_unredirect();
    }

    _goTo(w) {
        Main.overview.hide();
        Main.activateWindow(w);
    }

    _freeCorner() {
        const used = new Set([...this._pips.values()].map(p => p.corner));
        return [this._last.corner, ...CORNERS].find(c => !used.has(c)) ?? this._last.corner;
    }

    _remember(p) {
        this._last = {width: p.width, corner: p.corner, opacity: p.opacity};
        const st = readJson(STATE, {});
        st.popout = this._last;
        writeJson(STATE, st);
    }

    // size from the window's shape, then into its corner of its screen
    _place(p, animate) {
        const f = p.w.get_frame_rect();
        const b = p.w.get_buffer_rect();
        if (f.width < 1 || f.height < 1)
            return;
        const mon = Math.min(p.mon, Main.layoutManager.monitors.length - 1);
        const area = Main.layoutManager.getWorkAreaForMonitor(mon);
        const w = Math.round(Math.max(MIN_W, Math.min(p.width, area.width * 0.6)));
        const s = w / f.width;
        const h = Math.round(Math.min(f.height * s, area.height * 0.7));
        // the clone is the whole buffer (client shadows included): shift the frame into view
        p.clone.set_scale(s, s);
        p.clone.set_position(Math.round((b.x - f.x) * s), Math.round((b.y - f.y) * s));
        p.box.set_size(w, h);
        p.bar.set_size(w, -1);
        const x = p.corner.endsWith('l') ? area.x + MARGIN : area.x + area.width - w - MARGIN;
        const y = p.corner.startsWith('t') ? area.y + MARGIN : area.y + area.height - h - MARGIN;
        if (animate)
            p.box.ease({x, y, duration: 180, mode: EASE});
        else
            p.box.set_position(x, y);
    }

    _input(p) {
        const box = p.box;
        box.connect('button-press-event', (_a, ev) => {
            const btn = ev.get_button();
            if (btn === Clutter.BUTTON_MIDDLE) {
                this._close(p.w);
                return Clutter.EVENT_STOP;
            }
            if (btn !== Clutter.BUTTON_PRIMARY)
                return Clutter.EVENT_PROPAGATE;
            const [sx, sy] = ev.get_coords();
            p.drag = {dx: sx - box.x, dy: sy - box.y, sx, sy, moved: false, grab: global.stage.grab(box)};
            return Clutter.EVENT_STOP;
        });
        box.connect('motion-event', (_a, ev) => {
            const d = p.drag;
            if (!d)
                return Clutter.EVENT_PROPAGATE;
            if (!(ev.get_state() & Clutter.ModifierType.BUTTON1_MASK)) {
                this._endDrag(p);   // the release went somewhere else
                return Clutter.EVENT_STOP;
            }
            const [sx, sy] = ev.get_coords();
            if (!d.moved && Math.hypot(sx - d.sx, sy - d.sy) < 4)
                return Clutter.EVENT_STOP;
            if (!d.moved)
                global.stage.set_cursor_type(Clutter.CursorType.GRABBING);
            d.moved = true;
            box.remove_transition('x');
            box.remove_transition('y');
            box.set_position(Math.round(sx - d.dx), Math.round(sy - d.dy));
            return Clutter.EVENT_STOP;
        });
        box.connect('button-release-event', (_a, ev) => {
            if (!p.drag || ev.get_button() !== Clutter.BUTTON_PRIMARY)
                return Clutter.EVENT_PROPAGATE;
            this._endDrag(p);
            return Clutter.EVENT_STOP;
        });
        box.connect('scroll-event', (_a, ev) => {
            const dir = ev.get_scroll_direction();
            let step = 0;
            if (dir === Clutter.ScrollDirection.UP)
                step = 1;
            else if (dir === Clutter.ScrollDirection.DOWN)
                step = -1;
            else if (dir === Clutter.ScrollDirection.SMOOTH)
                step = -Math.sign(ev.get_scroll_delta()[1]);
            if (!step)
                return Clutter.EVENT_STOP;
            if (ev.get_state() & Clutter.ModifierType.CONTROL_MASK) {
                p.opacity = Math.max(90, Math.min(255, p.opacity + step * 20));
                box.opacity = p.opacity;
            } else {
                p.width = Math.round(p.width * (step > 0 ? 1.1 : 1 / 1.1));
                this._place(p, false);
                p.width = p.box.width;   // clamped
            }
            this._remember(p);
            return Clutter.EVENT_STOP;
        });
    }

    // released: snap to the nearest corner of the screen it was dropped on
    _endDrag(p) {
        const d = p.drag;
        p.drag = null;
        d.grab.dismiss();
        global.stage.set_cursor_type(Clutter.CursorType.DEFAULT);
        if (!p.box.hover)
            p.bar.ease({opacity: 0, duration: 150, mode: EASE});
        // a click that didn't move: two of them close together go to the window (Clutter 51 has
        // no click count on events)
        if (!d.moved) {
            const now = GLib.get_monotonic_time();
            if (now - (p.lastClick ?? 0) < DOUBLE_CLICK_US) {
                p.lastClick = 0;
                this._goTo(p.w);
            } else {
                p.lastClick = now;
            }
            return;
        }
        const cx = p.box.x + p.box.width / 2;
        const cy = p.box.y + p.box.height / 2;
        const mon = global.display.get_monitor_index_for_rect(
            new Mtk.Rectangle({x: Math.round(cx), y: Math.round(cy), width: 1, height: 1}));
        p.mon = mon >= 0 ? mon : p.mon;
        const area = Main.layoutManager.getWorkAreaForMonitor(p.mon);
        p.corner = `${cy < area.y + area.height / 2 ? 't' : 'b'}${cx < area.x + area.width / 2 ? 'l' : 'r'}`;
        this._place(p, true);
        this._remember(p);
    }

    // hidden in the overview and while the screen is locked
    _sync() {
        const hide = Main.overview.visible || Main.screenShield?.locked;
        for (const p of this._pips.values()) {
            if (hide) {
                p.box.hide();
            } else {
                p.box.show();
                p.box.ease({opacity: p.opacity, duration: 160, mode: EASE});
            }
        }
    }

    destroy() {
        WindowMenu.prototype._buildMenu = this._origBuild;
        Main.overview.disconnectObject(this);
        Main.layoutManager.disconnectObject(this);
        Main.screenShield?.disconnectObject(this);
        for (const w of [...this._pips.keys()])
            this._close(w);
    }
}
