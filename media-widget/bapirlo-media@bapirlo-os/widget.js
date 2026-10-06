// Bapirlo Media — the desktop card / pill.
// Floats above every app window (layer sits right above global.window_group); the layer is not
// reactive, so only the card and the pill take clicks — the rest falls through to the apps.
// Drag the card or the pill anywhere (any monitor); the spot is remembered across logins.
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Gvc from 'gi://Gvc';
import Meta from 'gi://Meta';
import Pango from 'gi://Pango';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as Slider from 'resource:///org/gnome/shell/ui/slider.js';
import * as Volume from 'resource:///org/gnome/shell/ui/status/volume.js';

import * as Art from './art.js';

const CARD_W = 296;
const ART_W = CARD_W - 2 * 14;          // card padding 14
const MARGIN = 24;                       // gap to the screen edge
const SNAP = 32;                         // dropped this close to an edge → snap to MARGIN
const POS_FILE = GLib.build_filenamev([GLib.get_user_state_dir(), 'bapirlo-media', 'position.json']);
const AUTO_COLLAPSE_S = 180;             // paused this long → shrink to the pill
const RESYNC_S = 15;                     // re-read Position from the player while playing
const EASE_IN = Clutter.AnimationMode.EASE_OUT_CUBIC;
const EASE_OUT = Clutter.AnimationMode.EASE_IN_CUBIC;

const norm = s => (s ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');
const GENERIC = new Set(['client', 'desktop', 'app', 'player', 'instance', 'media']);

function fmtTime(us) {
    if (!(us > 0))
        return '0:00';
    const t = Math.floor(us / 1e6);
    const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
    const ss = String(s).padStart(2, '0');
    return h ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
}

function cssUrl(path) {
    return `url("${path.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}")`;
}

function iconButton(icon, cls, size = 16) {
    return new St.Button({
        style_class: `bm-btn ${cls}`,
        can_focus: true,
        child: new St.Icon({icon_name: icon, icon_size: size}),
    });
}

export class MediaWidget {
    constructor(manager) {
        this._manager = manager;
        this._player = null;
        this._mode = 'hidden';
        this._suppressed = false;
        this._userCollapsed = false;
        this._autoCollapsed = false;
        this._artPath = null;
        this._artToken = 0;
        this._accent = Art.FALLBACK_ACCENT;
        this._aspect = 1;
        this._frost = null;
        this._frostKey = '';
        this._drag = null;
        this._saved = this._loadPosition();
        this._monitorIndex = this._savedMonitor();
        this.onMonitorChanged = null;
        this._seeking = false;
        this._settingVol = false;
        this._volStreams = [];
        this._cancellable = new Gio.Cancellable();

        this._buildUi();

        this._mixer = Volume.getMixerControl();
        this._mixer.connectObject(
            'state-changed', () => this._queueVolumeResolve(),
            'stream-added', () => this._queueVolumeResolve(),
            'stream-removed', () => this._queueVolumeResolve(),
            'default-sink-changed', () => this._queueVolumeResolve(), this);

        manager.connectObject(
            'active-changed', () => this._setPlayer(manager.active),
            'players-changed', () => this._syncChips(), this);

        Main.layoutManager.connectObject('monitors-changed', () => this._relayout(), this);
        global.display.connectObject('workareas-changed', () => this._relayout(), this);
        this._bgSettings = new Gio.Settings({schema_id: 'org.gnome.desktop.background'});
        this._bgSettings.connectObject('changed', () => this._refreshFrost(), this);

        this._relayout();
        this._setPlayer(manager.active);
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
        this._card.connect('scroll-event', (a, ev) => this._onScroll(ev));
        // press + move drags; a plain click on the art raises the player
        this._makeDraggable(this._card, (x, y) => {
            if (this._inside(this._artWrap, x, y))
                this._player?.raise();
        });
        this._stack.add_child(this._glow);
        this._stack.add_child(this._card);

        const halftone = new St.Widget({
            style_class: 'bm-halftone',
            x_align: Clutter.ActorAlign.END,
            y_align: Clutter.ActorAlign.START,
            x_expand: true,
            y_expand: true,
        });
        this._card.add_child(halftone);

        const box = new St.BoxLayout({
            orientation: Clutter.Orientation.VERTICAL,
            style_class: 'bm-box',
            x_expand: true,
        });
        this._card.add_child(box);

        // header: manga sticker + player chips + collapse
        const header = new St.BoxLayout({style_class: 'bm-header'});
        this._tag = new St.Label({style_class: 'bm-tag', text: 'NOW PLAYING', y_align: Clutter.ActorAlign.CENTER});
        this._tag.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;   // short fixed words; Bangers + letter-spacing mis-measures
        this._tag.set_pivot_point(0.5, 0.5);
        this._tag.rotation_angle_z = -4;
        this._chips = new St.BoxLayout({style_class: 'bm-chips', y_align: Clutter.ActorAlign.CENTER});
        const collapse = iconButton('go-next-symbolic', 'bm-mini', 14);
        collapse.connect('clicked', () => {
            this._userCollapsed = true;
            this._update();
        });
        header.add_child(this._tag);
        header.add_child(new St.Widget({x_expand: true}));
        header.add_child(this._chips);
        header.add_child(collapse);
        box.add_child(header);

        // art (two layers for crossfades) — click raises the player (handled by the card's drag)
        this._artWrap = new St.Widget({
            style_class: 'bm-art-wrap',
            layout_manager: new Clutter.BinLayout(),
            width: ART_W,
            height: ART_W,
        });
        this._artIcon = new St.Icon({
            style_class: 'bm-art-icon',
            icon_name: 'audio-x-generic-symbolic',
            icon_size: 64,
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._artWrap.add_child(this._artIcon);
        this._artLayer = null;
        box.add_child(new St.Bin({
            style_class: 'bm-art-btn',
            reactive: true,
            track_hover: true,
            child: this._artWrap,
        }));

        // title / artist
        this._meta = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, style_class: 'bm-meta'});
        this._title = new St.Label({style_class: 'bm-title'});
        this._artist = new St.Label({style_class: 'bm-artist'});
        for (const l of [this._title, this._artist])
            l.clutter_text.ellipsize = Pango.EllipsizeMode.END;
        this._meta.add_child(this._title);
        this._meta.add_child(this._artist);
        box.add_child(this._meta);

        // progress
        this._progress = new Slider.Slider(0);
        this._progress.add_style_class_name('bm-progress');
        this._progress.connect('drag-begin', () => (this._seeking = true));
        this._progress.connect('drag-end', () => {
            this._seeking = false;
            if (this._player)
                this._player.seekTo(this._progress.value * this._player.length);
        });
        this._progress.connect('scroll-event', () => Clutter.EVENT_STOP);
        const seek = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, style_class: 'bm-seek'});
        seek.add_child(this._progress);
        const times = new St.BoxLayout({style_class: 'bm-times'});
        this._elapsed = new St.Label({style_class: 'bm-time', text: '0:00'});
        this._total = new St.Label({style_class: 'bm-time', text: '0:00'});
        times.add_child(this._elapsed);
        times.add_child(new St.Widget({x_expand: true}));
        times.add_child(this._total);
        seek.add_child(times);
        box.add_child(seek);

        // transport
        const controls = new St.BoxLayout({style_class: 'bm-controls', x_align: Clutter.ActorAlign.CENTER});
        this._prev = iconButton('media-skip-backward-symbolic', 'bm-skip', 20);
        this._play = iconButton('media-playback-start-symbolic', 'bm-play', 22);
        this._next = iconButton('media-skip-forward-symbolic', 'bm-skip', 20);
        this._prev.connect('clicked', () => this._player?.previous());
        this._play.connect('clicked', () => this._player?.playPause());
        this._next.connect('clicked', () => this._player?.next());
        controls.add_child(this._prev);
        controls.add_child(this._play);
        controls.add_child(this._next);
        box.add_child(controls);

        // volume
        this._volRow = new St.BoxLayout({style_class: 'bm-volume'});
        this._volIcon = new St.Icon({style_class: 'bm-vol-icon', icon_name: 'audio-volume-high-symbolic', icon_size: 14});
        this._vol = new Slider.Slider(0);
        this._vol.add_style_class_name('bm-vol-slider');
        this._vol.connect('notify::value', () => this._onVolumeSlider());
        this._vol.connect('drag-begin', () => (this._volDragging = true));
        this._vol.connect('drag-end', () => (this._volDragging = false));
        this._volRow.add_child(this._volIcon);
        this._volRow.add_child(this._vol);
        box.add_child(this._volRow);

        // ---- pill (collapsed)
        this._pill = new St.BoxLayout({
            style_class: 'bm-pill',
            reactive: true,
            visible: false,
            opacity: 0,
        });
        this._pill.connect('scroll-event', (a, ev) => this._onScroll(ev));
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

    // ---------------------------------------------------------------- player binding
    _setPlayer(player) {
        if (player === this._player) {
            this._update();
            return;
        }
        this._player?.disconnectObject(this);
        const had = !!this._player;
        this._player = player;
        if (player) {
            player.connectObject(
                'changed', () => this._onPlayerChanged(),
                'track-changed', () => this._onTrackChanged(true),
                'seeked', () => this._tick(), this);
        }
        this._autoCollapsed = false;
        this._syncChips();
        this._onTrackChanged(had);
        this._onPlayerChanged();
        this._queueVolumeResolve();
    }

    _onPlayerChanged() {
        const p = this._player;
        if (p) {
            const icon = p.playing ? 'media-playback-pause-symbolic' : 'media-playback-start-symbolic';
            this._play.child.icon_name = icon;
            this._pillPlay.child.icon_name = icon;
            this._play.reactive = p.canPlayPause;
            this._prev.reactive = p.canPrev;
            this._next.reactive = p.canNext;
            this._prev.opacity = p.canPrev ? 255 : 90;
            this._next.opacity = p.canNext ? 255 : 90;
            this._progress.reactive = p.canSeek;
            this._tag.text = p.playing ? 'NOW PLAYING' : p.status === 'Paused' ? 'PAUSED' : 'STOPPED';
            this._tag.style_class = p.playing ? 'bm-tag' : 'bm-tag bm-tag-idle';
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
            if (this._volMode === 'mpris')
                this._readVolume();
        }
        this._syncChips();
        this._update();
    }

    _onTrackChanged(animate) {
        const p = this._player;
        const title = p?.title || p?.identity || '';
        const artist = p?.artists?.length ? p.artists.join(', ') : p?.identity ?? '';
        const apply = () => {
            this._title.text = title;
            this._artist.text = artist;
            this._pillTitle.text = title;
            this._place();
            this._total.text = fmtTime(p?.length ?? 0);
            this._tick();
        };
        if (animate && this._mode === 'card') {
            this._meta.remove_all_transitions();
            this._meta.ease({
                opacity: 0,
                translation_x: -14,
                duration: 140,
                mode: EASE_OUT,
                onComplete: () => {
                    apply();
                    this._meta.translation_x = 14;
                    this._meta.ease({opacity: 255, translation_x: 0, duration: 260, mode: EASE_IN});
                },
            });
        } else {
            apply();
        }
        this._loadArt(animate);
    }

    // ---------------------------------------------------------------- art + glow
    async _loadArt(animate) {
        const token = ++this._artToken;
        const p = this._player;
        let path = null, info = null;
        try {
            path = await Art.resolveArt(p?.artUrl, this._cancellable);
            if (path)
                info = await Art.analyseArt(path, this._cancellable);
        } catch {
            path = null;
        }
        if (token !== this._artToken)
            return;    // a newer track arrived meanwhile
        if (path === this._artPath && path)
            return;
        this._artPath = path;
        this._setArt(path, animate);
        this._setAspect(info?.aspect ?? 1, animate);
        this._setAccent(info?.accent ?? Art.FALLBACK_ACCENT, animate);
        this._pillArt.set_style(path ? `background-image: ${cssUrl(path)};` : null);
    }

    _setArt(path, animate) {
        const old = this._artLayer;
        let layer = null;
        if (path) {
            layer = new St.Widget({
                style_class: 'bm-art',
                style: `background-image: ${cssUrl(path)};`,
                x_expand: true,
                y_expand: true,
                opacity: animate ? 0 : 255,
            });
            this._artWrap.add_child(layer);
            if (animate)
                layer.ease({opacity: 255, duration: 420, mode: Clutter.AnimationMode.EASE_IN_OUT_QUAD});
        }
        this._artLayer = layer;
        const icon = this._player?.app?.get_icon();
        if (icon)
            this._artIcon.gicon = icon;
        else
            this._artIcon.icon_name = 'audio-x-generic-symbolic';
        this._artIcon.visible = !path;
        if (old) {
            if (animate) {
                old.ease({
                    opacity: 0,
                    duration: 420,
                    mode: Clutter.AnimationMode.EASE_IN_OUT_QUAD,
                    onComplete: () => old.destroy(),
                });
            } else {
                old.destroy();
            }
        }
    }

    _setAspect(aspect, animate) {
        // square covers stay square; video thumbnails go down to 16:9, never taller than wide
        const a = Math.max(1, Math.min(aspect, 16 / 9));
        const h = Math.round(ART_W / a);
        if (h === Math.round(this._artWrap.height))
            return;
        this._artWrap.remove_transition('height');
        if (animate && this._mode === 'card')
            this._artWrap.ease({height: h, duration: 320, mode: EASE_IN});
        else
            this._artWrap.height = h;
    }

    _setAccent(rgb, animate) {
        const same = rgb.every((v, i) => v === this._accent[i]);
        this._accent = rgb;
        const style = `box-shadow: 0 0 38px 2px rgba(${rgb.join(',')},0.42);`;
        if (!animate || same || this._mode !== 'card') {
            this._glow.set_style(style);
            return;
        }
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

    // ---------------------------------------------------------------- chips
    _syncChips() {
        this._chips.destroy_all_children();
        const list = this._manager.players;
        if (list.length < 2)
            return;
        for (const p of list) {
            const icon = new St.Icon({icon_size: 14});
            const gicon = p.app?.get_icon();
            if (gicon)
                icon.gicon = gicon;
            else
                icon.icon_name = 'audio-x-generic-symbolic';
            const chip = new St.Button({
                style_class: 'bm-chip',
                child: icon,
                toggle_mode: false,
                checked: p === this._player,
                accessible_name: p.identity,
            });
            if (p.playing)
                chip.add_style_class_name('bm-chip-playing');
            chip.connect('clicked', () => this._manager.select(p));
            this._chips.add_child(chip);
        }
    }

    _onScroll(ev) {
        const dir = ev.get_scroll_direction();
        if (dir === Clutter.ScrollDirection.UP)
            this._manager.cycle(-1);
        else if (dir === Clutter.ScrollDirection.DOWN)
            this._manager.cycle(1);
        return Clutter.EVENT_STOP;
    }

    // ---------------------------------------------------------------- volume
    _queueVolumeResolve() {
        if (this._volIdle)
            return;
        this._volIdle = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, () => {
            this._volIdle = 0;
            this._resolveVolume();
            return GLib.SOURCE_REMOVE;
        });
    }

    _playerKeys(p) {
        const keys = new Set();
        const add = s => {
            const n = norm(s);
            if (n.length >= 3 && !GENERIC.has(n))
                keys.add(n);
        };
        add(p.identity);
        add(p.desktopEntry);
        add(p.desktopEntry.split('.').pop());
        add(p.busName.split('.')[3]);
        if (p.app) {
            add(p.app.get_name());
            add(p.app.get_id().replace(/\.desktop$/, ''));
        }
        return keys;
    }

    _resolveVolume() {
        for (const s of this._volStreams)
            s.disconnectObject(this);
        this._volStreams = [];
        this._volMode = null;
        const p = this._player;
        const ready = this._mixer.get_state() === Gvc.MixerControlState.READY;
        if (p && ready) {
            const keys = this._playerKeys(p);
            this._volStreams = this._mixer.get_sink_inputs().filter(s => {
                if (s.is_event_stream)
                    return false;
                const sk = [s.get_application_id(), s.get_name(), s.get_icon_name()].map(norm).filter(Boolean);
                return sk.some(k => [...keys].some(pk => k === pk || k.includes(pk) || (k.length >= 4 && pk.includes(k))));
            });
            if (this._volStreams.length)
                this._volMode = 'app';
        }
        if (!this._volMode && p?.mprisVolume !== null && p?.mprisVolume !== undefined)
            this._volMode = 'mpris';
        if (!this._volMode && ready && this._mixer.get_default_sink()) {
            this._volMode = 'system';
            this._volStreams = [this._mixer.get_default_sink()];
        }
        for (const s of this._volStreams)
            s.connectObject('notify::volume', () => this._readVolume(), 'notify::is-muted', () => this._readVolume(), this);
        this._volRow.visible = !!this._volMode;
        this._volRow.style_class = `bm-volume${this._volMode === 'system' ? ' bm-volume-system' : ''}`;
        this._readVolume();
    }

    _readVolume() {
        let v = 0;
        if (this._volMode === 'mpris') {
            v = this._player?.mprisVolume ?? 0;
        } else if (this._volStreams.length) {
            const max = this._mixer.get_vol_max_norm();
            v = Math.max(...this._volStreams.map(s => (s.is_muted ? 0 : s.volume / max)));
        }
        v = Math.max(0, Math.min(1, v));
        this._settingVol = true;
        if (!this._volDragging)
            this._vol.value = v;
        this._settingVol = false;
        this._setVolIcon(v);
    }

    _setVolIcon(v) {
        this._volIcon.icon_name = v <= 0 ? 'audio-volume-muted-symbolic'
            : v < 0.34 ? 'audio-volume-low-symbolic'
                : v < 0.67 ? 'audio-volume-medium-symbolic' : 'audio-volume-high-symbolic';
    }

    _onVolumeSlider() {
        if (this._settingVol)
            return;
        const v = this._vol.value;
        this._setVolIcon(v);
        if (this._volMode === 'mpris') {
            this._player?.setMprisVolume(v);
        } else if (this._volStreams.length) {
            const max = this._mixer.get_vol_max_norm();
            for (const s of this._volStreams) {
                s.volume = Math.round(v * max);
                if (s.is_muted && v > 0)
                    s.change_is_muted(false);
                s.push_volume();
            }
        }
    }

    // ---------------------------------------------------------------- progress ticking
    _tick() {
        const p = this._player;
        if (!p || this._seeking)
            return;
        const pos = p.position;
        this._elapsed.text = fmtTime(pos);
        this._total.text = fmtTime(p.length);
        this._progress.value = p.length > 0 ? pos / p.length : 0;
    }

    _syncTimer() {
        const want = this._mode === 'card' && !this._suppressed && this._player?.playing;
        if (want && !this._timerId) {
            let n = 0;
            this._timerId = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, 1, () => {
                if (++n % RESYNC_S === 0)
                    this._player?.syncPosition();
                this._tick();
                return GLib.SOURCE_CONTINUE;
            });
            this._tick();
        } else if (!want && this._timerId) {
            GLib.source_remove(this._timerId);
            this._timerId = 0;
        }
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
            if (mode === 'card') {
                this._tick();
                this._queueFrostPosition();
            }
        }
        this._syncTimer();
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
        this._placeLater = 0;
        for (const id of [this._timerId, this._collapseId, this._volIdle]) {
            if (id)
                GLib.source_remove(id);
        }
        this._timerId = this._collapseId = this._frostLater = this._volIdle = 0;
        for (const s of this._volStreams)
            s.disconnectObject(this);
        this._volStreams = [];
        this._player?.disconnectObject(this);
        this._manager.disconnectObject(this);
        this._mixer.disconnectObject(this);
        this._bgSettings.disconnectObject(this);
        Main.layoutManager.disconnectObject(this);
        global.display.disconnectObject(this);
        this.actor.destroy();
        this.actor = null;
    }
}
