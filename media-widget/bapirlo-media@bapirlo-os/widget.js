// Bapirlo Media — the desktop card / pill (optional since the top-bar dropdown; setting
// "desktop-widget"). Floats above every app window (layer sits right above global.window_group);
// the layer is not reactive, so only the card and the pill take clicks — the rest falls through.
// Drag the card or the pill anywhere (any monitor); the spot is remembered across logins.
// The player UI itself is view.js (shared with the dropdown).
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Meta from 'gi://Meta';
import Pango from 'gi://Pango';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as Slider from 'resource:///org/gnome/shell/ui/slider.js';

import * as Art from './art.js';
import {PlayerView, cssUrl, iconButton, EASE_IN, EASE_OUT} from './view.js';

const CARD_W = 296;
const ART_W = CARD_W - 2 * 14;          // card padding 14
const MARGIN = 24;                       // gap to the screen edge
const SNAP = 32;                         // dropped this close to an edge → snap to MARGIN
const POS_FILE = GLib.build_filenamev([GLib.get_user_state_dir(), 'bapirlo-media', 'position.json']);
const AUTO_COLLAPSE_S = 180;             // paused this long → shrink to the pill

export class MediaWidget {
    constructor(manager) {
        this._manager = manager;
        this._mode = 'hidden';
        this._suppressed = false;
        this._userCollapsed = false;
        this._autoCollapsed = false;
        this._frost = null;
        this._frostKey = '';
        this._drag = null;
        this._saved = this._loadPosition();
        this._monitorIndex = this._savedMonitor();
        this.onMonitorChanged = null;
        this._cancellable = new Gio.Cancellable();

        this._buildUi();

        Main.layoutManager.connectObject('monitors-changed', () => this._relayout(), this);
        global.display.connectObject('workareas-changed', () => this._relayout(), this);
        this._bgSettings = new Gio.Settings({schema_id: 'org.gnome.desktop.background'});
        this._bgSettings.connectObject('changed', () => this._refreshFrost(), this);

        this._relayout();
        this._update();
    }

    get _player() {
        return this._view?.player ?? null;
    }

    // ---------------------------------------------------------------- UI
    _buildUi() {
        // full work-area layer; not reactive itself, so the desktop around the card still
        // gets its clicks (right-click menu etc.)
        this.actor = new St.Widget({
            name: 'bapirloMediaLayer',
            layout_manager: new Clutter.FixedLayout(),
            reactive: false,
            visible: false,
        });
        this.actor.connect('stage-views-changed', () => this._place());

        // ---- card
        this._stack = new St.Widget({
            layout_manager: new Clutter.BinLayout(),
            visible: false,
            opacity: 0,
        });
        this._stack.set_pivot_point(1, 0.5);
        this._stack.connect('notify::height', () => this._queuePlace());
        this._glow = new St.Widget({style_class: 'bm-glow', x_expand: true, y_expand: true});
        this._card = new St.Widget({
            style_class: 'bm-card',
            layout_manager: new Clutter.BinLayout(),
            reactive: true,
            width: CARD_W,
        });
        this._card.connect('scroll-event', (a, ev) => this._view.onScroll(ev));
        this._makeDraggable(this._card, () => {});   // press + move drags the card
        this._stack.add_child(this._glow);
        this._stack.add_child(this._card);

        this._card.add_child(new St.Widget({
            style_class: 'bm-halftone',
            x_align: Clutter.ActorAlign.END,
            y_align: Clutter.ActorAlign.START,
            x_expand: true,
            y_expand: true,
        }));

        // ---- pill (collapsed)
        this._pill = new St.BoxLayout({
            style_class: 'bm-pill',
            reactive: true,
            visible: false,
            opacity: 0,
        });
        this._pill.connect('scroll-event', (a, ev) => this._view.onScroll(ev));
        this._pill.connect('notify::width', () => this._queuePlace());
        this._pillArt = new St.Widget({style_class: 'bm-pill-art'});
        this._pillTitle = new St.Label({style_class: 'bm-pill-title', y_align: Clutter.ActorAlign.CENTER});
        this._pillTitle.clutter_text.ellipsize = Pango.EllipsizeMode.END;
        const pillInner = new St.BoxLayout({style_class: 'bm-pill-inner'});
        pillInner.add_child(this._pillArt);
        pillInner.add_child(this._pillTitle);
        // click (no drag) on art/title expands back to the card
        const expand = new St.Bin({style_class: 'bm-pill-expand', reactive: true, track_hover: true, child: pillInner});
        this._makeDraggable(this._pill, (x, y) => {
            if (!this._inside(expand, x, y))
                return;
            this._userCollapsed = false;
            this._autoCollapsed = false;
            this._update();
        });
        this._pillPlay = iconButton('media-playback-start-symbolic', 'bm-pill-play', 14);
        this._pillPlay.connect('clicked', () => this._player?.playPause());
        this._pill.add_child(expand);
        this._pill.add_child(this._pillPlay);

        const collapse = iconButton('go-next-symbolic', 'bm-mini', 14);
        collapse.accessible_name = 'Shrink to a pill';
        collapse.connect('clicked', () => {
            this._userCollapsed = true;
            this._update();
        });
        this._view = new PlayerView(this._manager, {
            artWidth: ART_W,
            headerEnd: collapse,
            onTrack: p => {
                this._pillTitle.text = p?.title || p?.identity || '';
                this._place();
            },
            onState: () => this._onPlayerChanged(),
            onArt: (path, info, animate) => {
                this._setAccent(info.accent, animate);
                this._pillArt.set_style(path ? `background-image: ${cssUrl(path)};` : null);
            },
        });
        this._card.add_child(this._view.actor);


        this.actor.add_child(this._pill);
        this.actor.add_child(this._stack);

        this._stack.connect('notify::allocation', () => this._queueFrostPosition());
    }

    // ---------------------------------------------------------------- geometry
    get monitorIndex() {
        const n = Main.layoutManager.monitors.length;
        return this._monitorIndex >= 0 && this._monitorIndex < n
            ? this._monitorIndex : Main.layoutManager.primaryIndex;
    }

    get monitor() {
        return Main.layoutManager.monitors[this.monitorIndex] ?? null;
    }

    _loadPosition() {
        try {
            const [, bytes] = GLib.file_get_contents(POS_FILE);
            const o = JSON.parse(new TextDecoder().decode(bytes));
            if ([o.fx, o.fy].every(v => typeof v === 'number' && v >= 0 && v <= 1))
                return o;
        } catch {}
        return null;
    }

    _savedMonitor() {
        const o = this._saved;
        if (!o || o.primary || !(o.index < Main.layoutManager.monitors.length))
            return -1;   // → primary
        return o.index;
    }

    _savePosition() {
        const wa = this._wa;
        const free = Math.max(1, wa.width - CARD_W);
        this._saved = {
            fx: Math.max(0, Math.min(1, this._pos.x / free)),
            fy: Math.max(0, Math.min(1, this._pos.cy / wa.height)),
            index: this.monitorIndex,
            primary: this.monitorIndex === Main.layoutManager.primaryIndex,
        };
        try {
            GLib.mkdir_with_parents(GLib.path_get_dirname(POS_FILE), 0o755);
            GLib.file_set_contents(POS_FILE, JSON.stringify(this._saved));
        } catch (e) {
            console.warn(`bapirlo-media: could not save position: ${e.message}`);
        }
    }

    _relayout() {
        const mon = this.monitor;
        if (!mon)
            return;
        const wa = Main.layoutManager.getWorkAreaForMonitor(this.monitorIndex);
        this.actor.set_position(wa.x, wa.y);
        this.actor.set_size(wa.width, wa.height);
        this._wa = wa;
        // position = card left edge + card vertical centre, in work-area coords; stored as
        // fractions so it survives resolution / scale changes. Default: right edge, centred.
        const o = this._saved;
        this._pos = o
            ? {x: o.fx * Math.max(0, wa.width - CARD_W), cy: o.fy * wa.height}
            : {x: wa.width - MARGIN - CARD_W, cy: wa.height / 2};
        this._place();
        this._refreshFrost();
    }

    // size changes arrive mid-allocation, where moving actors is lost → re-place before the frame
    _queuePlace() {
        if (this._placeLater)
            return;
        this._placeLater = global.compositor.get_laters().add(Meta.LaterType.BEFORE_REDRAW, () => {
            this._placeLater = 0;
            this._place();
            return GLib.SOURCE_REMOVE;
        });
    }

    // card height (natural; also valid while hidden)
    _cardHeight() {
        return this._stack.get_preferred_height(CARD_W)[1];
    }

    _onLeft() {
        return this._pos.x + CARD_W / 2 < this._wa.width / 2;
    }

    // clamp the card inside the work area
    _clamped(pos) {
        const wa = this._wa, h = this._cardHeight();
        const x = Math.max(0, Math.min(wa.width - CARD_W, pos.x));
        const cy = h >= wa.height ? h / 2 : Math.max(h / 2, Math.min(wa.height - h / 2, pos.cy));
        return {x, cy};
    }

    // lay out card + pill from this._pos. While dragging nothing is clamped (the card may
    // cross onto another monitor); the drop then clamps, snaps and eases into place.
    _place(animate = false) {
        if (!this._wa || !this._pos || !this.actor.get_stage())
            return;   // not in the stage yet → re-run on 'stage-views-changed'
        const {x, cy} = this._drag?.moved ? this._pos : this._clamped(this._pos);
        const h = this._cardHeight();
        const [, pw] = this._pill.get_preferred_width(-1);
        const [, ph] = this._pill.get_preferred_height(pw);
        const left = this._onLeft();
        // collapse/expand slides toward the near screen edge; the pill hugs that edge of the card
        this._stack.set_pivot_point(left ? 0 : 1, 0.5);
        const spots = [
            [this._stack, Math.round(x), Math.round(cy - h / 2)],
            [this._pill, Math.round(left ? x : x + CARD_W - pw), Math.round(cy - ph / 2)],
        ];
        for (const [a, ax, ay] of spots) {
            a.remove_transition('x');
            a.remove_transition('y');
            if (animate)
                a.ease({x: ax, y: ay, duration: 220, mode: EASE_IN});
            else
                a.set_position(ax, ay);
        }
    }

    _inside(actor, sx, sy) {
        const [ok, x, y] = actor.transform_stage_point(sx, sy);
        return ok && x >= 0 && y >= 0 && x < actor.width && y < actor.height;
    }

    // St.Button / Slider presses bubble up here too (gesture-based in GNOME 50) — leave them alone
    _onControl(ev, root) {
        for (let a = global.stage.get_event_actor(ev); a && a !== root; a = a.get_parent()) {
            if (a instanceof St.Button || a instanceof Slider.Slider)
                return true;
        }
        return false;
    }

    // press → stage grab; moving past the drag threshold drags, otherwise it is a click
    _makeDraggable(actor, onClick) {
        actor.connect('button-press-event', (a, ev) => {
            if (ev.get_button() !== Clutter.BUTTON_PRIMARY || this._drag || this._onControl(ev, actor))
                return Clutter.EVENT_PROPAGATE;
            const [x, y] = ev.get_coords();
            this._drag = {
                actor, onClick, x0: x, y0: y, pos: {...this._pos}, moved: false,
                grab: global.stage.grab(actor),
            };
            return Clutter.EVENT_STOP;
        });
        actor.connect('motion-event', (a, ev) => {
            const d = this._drag;
            if (d?.actor !== actor)
                return Clutter.EVENT_PROPAGATE;
            if (!(ev.get_state() & Clutter.ModifierType.BUTTON1_MASK)) {
                this._endDrag(null);   // release went elsewhere (grab broken)
                return Clutter.EVENT_STOP;
            }
            const [x, y] = ev.get_coords();
            if (!d.moved) {
                const t = St.Settings.get().drag_threshold;
                if (Math.abs(x - d.x0) < t && Math.abs(y - d.y0) < t)
                    return Clutter.EVENT_STOP;
                d.moved = true;
                actor.add_style_pseudo_class('dragging');
                global.stage.set_cursor_type(Clutter.CursorType.GRABBING);
            }
            this._pos = {x: d.pos.x + x - d.x0, cy: d.pos.cy + y - d.y0};
            this._place();
            return Clutter.EVENT_STOP;
        });
        actor.connect('button-release-event', (a, ev) => {
            if (this._drag?.actor !== actor || ev.get_button() !== Clutter.BUTTON_PRIMARY)
                return Clutter.EVENT_PROPAGATE;
            this._endDrag(ev.get_coords());
            return Clutter.EVENT_STOP;
        });
    }

    _endDrag(coords) {
        const d = this._drag;
        this._drag = null;
        d.grab?.dismiss();
        if (!d.moved) {
            if (coords)
                d.onClick(...coords);
            return;
        }
        d.actor.remove_style_pseudo_class('dragging');
        global.stage.set_cursor_type(Clutter.CursorType.DEFAULT);

        // dropped on another monitor? re-home the layer there, keeping the card where it is
        const sx = this._wa.x + this._pos.x + CARD_W / 2, sy = this._wa.y + this._pos.cy;
        const target = Main.layoutManager.monitors.findIndex(m =>
            sx >= m.x && sx < m.x + m.width && sy >= m.y && sy < m.y + m.height);
        if (target >= 0 && target !== this.monitorIndex) {
            this._monitorIndex = target;
            const wa = Main.layoutManager.getWorkAreaForMonitor(target);
            this._pos = {x: this._pos.x + this._wa.x - wa.x, cy: this._pos.cy + this._wa.y - wa.y};
            this._wa = wa;
            this.actor.set_position(wa.x, wa.y);
            this.actor.set_size(wa.width, wa.height);
            this._refreshFrost();
            this.onMonitorChanged?.();
        }

        // clamp, then snap to the standard margin near edges
        const wa = this._wa, h = this._cardHeight();
        let {x, cy} = this._clamped(this._pos);
        if (x < MARGIN + SNAP)
            x = MARGIN;
        else if (x > wa.width - CARD_W - MARGIN - SNAP)
            x = wa.width - CARD_W - MARGIN;
        if (h + 2 * MARGIN < wa.height) {
            if (cy - h / 2 < MARGIN + SNAP)
                cy = MARGIN + h / 2;
            else if (cy + h / 2 > wa.height - MARGIN - SNAP)
                cy = wa.height - MARGIN - h / 2;
        }
        this._pos = {x, cy};
        this._place(true);
        this._savePosition();
    }

    async _refreshFrost() {
        const mon = this.monitor;
        if (!mon || !this._wa)
            return;
        try {
            // whole-monitor frost; the card just shifts background-position → stays right while dragging
            this._frost = await Art.frostStrip(mon, 0, mon.width, this._cancellable);
        } catch (e) {
            if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                console.warn(`bapirlo-media: frost failed: ${e.message}`);
            this._frost = null;
        }
        this._frostKey = '';
        this._queueFrostPosition();
    }

    _queueFrostPosition() {
        if (this._frostLater)
            return;
        // before the next frame, so the frost tracks the card while it is dragged / eased
        this._frostLater = global.compositor.get_laters().add(Meta.LaterType.BEFORE_REDRAW, () => {
            this._frostLater = 0;
            this._applyFrost();
            return GLib.SOURCE_REMOVE;
        });
    }

    _applyFrost() {
        const mon = this.monitor;
        if (!mon || !this._wa || !this.actor)
            return;
        const x = Math.round(this.actor.x + this._stack.x - mon.x);
        const y = Math.round(this.actor.y + this._stack.y - mon.y);
        const key = `${this._frost}|${x}|${y}`;
        if (key === this._frostKey)
            return;
        this._frostKey = key;
        this._card.set_style(this._frost
            ? `background-image: ${cssUrl(this._frost)}; background-size: ${mon.width}px ${mon.height}px; ` +
              `background-position: ${-x}px ${-y}px;`
            : null);
    }

    // ---------------------------------------------------------------- player state
    _onPlayerChanged() {
        const p = this._player;
        if (p) {
            this._pillPlay.child.icon_name = p.playing ? 'media-playback-pause-symbolic' : 'media-playback-start-symbolic';
            if (p.playing) {
                this._autoCollapsed = false;
                this._clearCollapseTimer();
            } else if (!this._collapseId) {
                this._collapseId = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, AUTO_COLLAPSE_S, () => {
                    this._collapseId = 0;
                    this._autoCollapsed = true;
                    this._update();
                    return GLib.SOURCE_REMOVE;
                });
            }
        }
        this._update();
    }

    _setAccent(rgb, animate) {
        const style = `box-shadow: 0 0 38px 2px rgba(${rgb.join(',')},0.42);`;
        if (!animate || this._mode !== 'card' || style === this._glowStyle) {
            this._glowStyle = style;
            this._glow.set_style(style);
            return;
        }
        this._glowStyle = style;
        this._glow.remove_all_transitions();
        this._glow.ease({
            opacity: 0,
            duration: 220,
            mode: EASE_OUT,
            onComplete: () => {
                this._glow.set_style(style);
                this._glow.ease({opacity: 255, duration: 520, mode: EASE_IN});
            },
        });
    }

    _clearCollapseTimer() {
        if (this._collapseId) {
            GLib.source_remove(this._collapseId);
            this._collapseId = 0;
        }
    }

    // ---------------------------------------------------------------- visibility
    setSuppressed(s) {
        if (s === this._suppressed)
            return;
        this._suppressed = s;
        this._update();
    }

    _wantedMode() {
        const p = this._player;
        if (!p || (!p.title && p.status === 'Stopped'))
            return 'hidden';
        if (this._userCollapsed || (this._autoCollapsed && !p.playing))
            return 'pill';
        return 'card';
    }

    _update() {
        const mode = this._wantedMode();
        // layer fade for "a maximised window is in the way"
        const layerOn = mode !== 'hidden' && !this._suppressed;
        if (layerOn && !this.actor.visible) {
            this.actor.opacity = 0;
            this.actor.show();
        }
        this.actor.remove_transition('opacity');
        this.actor.ease({
            opacity: layerOn ? 255 : 0,
            duration: layerOn ? 300 : 200,
            mode: layerOn ? EASE_IN : EASE_OUT,
            onComplete: () => {
                if (!layerOn)
                    this.actor.hide();
            },
        });

        if (mode !== this._mode) {
            const prev = this._mode;
            this._mode = mode;
            const dir = this._wa && this._onLeft() ? -1 : 1;   // slide toward the near edge
            this._place();
            this._showPart(this._stack, mode === 'card', dir * (prev === 'hidden' ? 56 : 28));
            this._showPart(this._pill, mode === 'pill', dir * 28);
            if (mode === 'card')
                this._queueFrostPosition();
        }
        this._view?.setLive(mode === 'card' && !this._suppressed);
    }

    _showPart(actor, on, dx) {
        actor.remove_all_transitions();
        if (on) {
            if (!actor.visible) {
                actor.opacity = 0;
                actor.translation_x = dx;
                actor.scale_x = actor.scale_y = 0.96;
                actor.show();
            }
            actor.ease({
                opacity: 255,
                translation_x: 0,
                scale_x: 1,
                scale_y: 1,
                duration: 380,
                mode: EASE_IN,
            });
        } else if (actor.visible) {
            actor.ease({
                opacity: 0,
                translation_x: dx,
                scale_x: 0.96,
                scale_y: 0.96,
                duration: 240,
                mode: EASE_OUT,
                onComplete: () => actor.hide(),
            });
        }
    }

    destroy() {
        this._cancellable.cancel();
        if (this._drag)
            this._endDrag(null);
        for (const id of [this._frostLater, this._placeLater]) {
            if (id)
                global.compositor.get_laters().remove(id);
        }
        this._frostLater = this._placeLater = 0;
        this._clearCollapseTimer();
        this._view.destroy();
        this._view = null;
        this._bgSettings.disconnectObject(this);
        Main.layoutManager.disconnectObject(this);
        global.display.disconnectObject(this);
        this.actor.destroy();
        this.actor = null;
    }
}
