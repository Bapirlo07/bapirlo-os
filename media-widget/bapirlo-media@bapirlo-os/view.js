// Bapirlo Media — the player view shared by the top-bar dropdown and the desktop card:
// manga "NOW PLAYING" sticker + player switcher, art (square covers, 16:9 video thumbnails),
// title / artist, seek bar with times, transport, volume (per-app stream → MPRIS → system).
// The host decides where it lives and calls setLive(true) while it is on screen; the progress
// timer only runs then, so a closed dropdown costs nothing.
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Gvc from 'gi://Gvc';
import Pango from 'gi://Pango';
import St from 'gi://St';

import * as Slider from 'resource:///org/gnome/shell/ui/slider.js';
import * as Volume from 'resource:///org/gnome/shell/ui/status/volume.js';

import * as Art from './art.js';

const RESYNC_S = 15;                     // re-read Position from the player while playing
export const EASE_IN = Clutter.AnimationMode.EASE_OUT_CUBIC;
export const EASE_OUT = Clutter.AnimationMode.EASE_IN_CUBIC;

const norm = s => (s ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');
const GENERIC = new Set(['client', 'desktop', 'app', 'player', 'instance', 'media']);

export function fmtTime(us) {
    if (!(us > 0))
        return '0:00';
    const t = Math.floor(us / 1e6);
    const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
    const ss = String(s).padStart(2, '0');
    return h ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
}

export function cssUrl(path) {
    return `url("${path.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}")`;
}

export function iconButton(icon, cls, size = 16) {
    return new St.Button({
        style_class: `bm-btn ${cls}`,
        can_focus: true,
        child: new St.Icon({icon_name: icon, icon_size: size}),
    });
}

// short, readable player name for the switcher ("Google Chrome" → "Chrome")
function shortName(p) {
    const n = p.app?.get_name() || p.identity || '';
    return n.replace(/^(Google|Mozilla|GNOME)\s+/i, '').replace(/\s*\(.*\)\s*$/, '').split(/\s+[-–—]\s+/)[0];
}

export class PlayerView {
    // opts: artWidth (px), labelledChips (player switcher shows names), headerEnd (actor placed
    // at the right end of the header), onTrack(player), onState(player), onArt(path, info)
    constructor(manager, opts) {
        this._manager = manager;
        this._opts = opts;
        this._artW = opts.artWidth;
        this._player = null;
        this._live = false;
        this._artPath = null;
        this._artToken = 0;
        this._seeking = false;
        this._settingVol = false;
        this._volStreams = [];
        this._cancellable = new Gio.Cancellable();

        this._build();

        this._mixer = Volume.getMixerControl();
        this._mixer.connectObject(
            'state-changed', () => this._queueVolumeResolve(),
            'stream-added', () => this._queueVolumeResolve(),
            'stream-removed', () => this._queueVolumeResolve(),
            'default-sink-changed', () => this._queueVolumeResolve(), this);
        manager.connectObject(
            'active-changed', () => this._setPlayer(manager.active),
            'players-changed', () => this._syncChips(), this);
        this._setPlayer(manager.active);
    }

    get player() {
        return this._player;
    }

    // ---------------------------------------------------------------- UI
    _build() {
        const box = this.actor = new St.BoxLayout({
            orientation: Clutter.Orientation.VERTICAL,
            style_class: 'bm-box',
            x_expand: true,
        });

        // header: manga sticker + player switcher (+ host button)
        const header = new St.BoxLayout({style_class: 'bm-header'});
        this._tag = new St.Label({style_class: 'bm-tag', text: 'NOW PLAYING', y_align: Clutter.ActorAlign.CENTER});
        this._tag.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;   // short fixed words; Bangers + letter-spacing mis-measures
        this._tag.set_pivot_point(0.5, 0.5);
        this._tag.rotation_angle_z = -4;
        this._chips = new St.BoxLayout({style_class: 'bm-chips', y_align: Clutter.ActorAlign.CENTER});
        header.add_child(this._tag);
        header.add_child(new St.Widget({x_expand: true}));
        header.add_child(this._chips);
        if (this._opts.headerEnd)
            header.add_child(this._opts.headerEnd);
        box.add_child(header);

        // art (two layers for crossfades); the button raises the player's window
        this._artWrap = new St.Widget({
            style_class: 'bm-art-wrap',
            layout_manager: new Clutter.BinLayout(),
            width: this._artW,
            height: this._artW,
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
        this.artButton = new St.Button({
            style_class: 'bm-art-btn',
            can_focus: true,
            track_hover: true,
            accessible_name: 'Open the player',
            child: this._artWrap,
        });
        this.artButton.connect('clicked', () => this._player?.raise());
        box.add_child(this.artButton);

        // title / artist
        this._meta = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, style_class: 'bm-meta'});
        this._title = new St.Label({style_class: 'bm-title'});
        this._artist = new St.Label({style_class: 'bm-artist'});
        for (const l of [this._title, this._artist])
            l.clutter_text.ellipsize = Pango.EllipsizeMode.END;
        this._meta.add_child(this._title);
        this._meta.add_child(this._artist);
        box.add_child(this._meta);

        // progress — drag (or click) to seek
        this._progress = new Slider.Slider(0);
        this._progress.add_style_class_name('bm-progress');
        this._progress.accessible_name = 'Position';
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
        this.playButton = iconButton('media-playback-start-symbolic', 'bm-play', 22);
        this._next = iconButton('media-skip-forward-symbolic', 'bm-skip', 20);
        this._prev.accessible_name = 'Previous';
        this.playButton.accessible_name = 'Play / pause';
        this._next.accessible_name = 'Next';
        this._prev.connect('clicked', () => this._player?.previous());
        this.playButton.connect('clicked', () => this._player?.playPause());
        this._next.connect('clicked', () => this._player?.next());
        // hover feedback that survives an inline accent background: a small lift
        this.playButton.set_pivot_point(0.5, 0.5);
        this.playButton.connect('notify::hover', b => b.ease({
            scale_x: b.hover ? 1.07 : 1, scale_y: b.hover ? 1.07 : 1, duration: 180,
            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
        }));
        this.playButton.track_hover = true;
        controls.add_child(this._prev);
        controls.add_child(this.playButton);
        controls.add_child(this._next);
        box.add_child(controls);

        // volume
        this._volRow = new St.BoxLayout({style_class: 'bm-volume'});
        this._volIcon = new St.Icon({style_class: 'bm-vol-icon', icon_name: 'audio-volume-high-symbolic', icon_size: 14});
        this._vol = new Slider.Slider(0);
        this._vol.add_style_class_name('bm-vol-slider');
        this._vol.accessible_name = 'Volume';
        this._vol.connect('notify::value', () => this._onVolumeSlider());
        this._vol.connect('drag-begin', () => (this._volDragging = true));
        this._vol.connect('drag-end', () => (this._volDragging = false));
        this._volRow.add_child(this._volIcon);
        this._volRow.add_child(this._vol);
        box.add_child(this._volRow);
    }

    // Tint the controls with a cover colour (null → the theme's crimson). The sticker stays
    // crimson: it is the brand mark. Text on the play button flips to ink on light accents.
    setAccent(rgb) {
        if (!rgb) {
            for (const a of [this.playButton, this._progress, this._vol])
                a.set_style(null);
            return;
        }
        const c = `rgb(${rgb.join(',')})`;
        this.playButton.set_style(`background-color: ${c}; color: ${Art.textOn(rgb)}; ` +
            `box-shadow: 0 4px 14px rgba(${rgb.join(',')},0.45);`);
        for (const s of [this._progress, this._vol])
            s.set_style(`-barlevel-active-background-color: ${c};`);
    }

    // ---------------------------------------------------------------- liveness
    setLive(live) {
        this._live = live;
        if (live) {
            this._player?.syncPosition();
            this._tick();
        }
        this._syncTimer();
    }

    // ---------------------------------------------------------------- player binding
    _setPlayer(player) {
        if (player === this._player) {
            this._onPlayerChanged();
            return;
        }
        this._player?.disconnectObject(this);
        const had = !!this._player;
        this._player = player;
        player?.connectObject(
            'changed', () => this._onPlayerChanged(),
            'track-changed', () => this._onTrackChanged(true),
            'seeked', () => this._tick(), this);
        this._syncChips();
        this._onTrackChanged(had);
        this._onPlayerChanged();
        this._queueVolumeResolve();
    }

    _onPlayerChanged() {
        const p = this._player;
        if (p) {
            this.playButton.child.icon_name = p.playing ? 'media-playback-pause-symbolic' : 'media-playback-start-symbolic';
            this.playButton.reactive = p.canPlayPause;
            this._prev.reactive = p.canPrev;
            this._next.reactive = p.canNext;
            this._prev.opacity = p.canPrev ? 255 : 90;
            this._next.opacity = p.canNext ? 255 : 90;
            this._progress.reactive = p.canSeek;
            this._tag.text = p.playing ? 'NOW PLAYING' : p.status === 'Paused' ? 'PAUSED' : 'STOPPED';
            this._tag.style_class = p.playing ? 'bm-tag' : 'bm-tag bm-tag-idle';
            if (this._volMode === 'mpris')
                this._readVolume();
        }
        this._syncChips();
        this._syncTimer();
        this._opts.onState?.(p);
    }

    _onTrackChanged(animate) {
        const p = this._player;
        const title = p?.title || p?.identity || '';
        const artist = p?.artists?.length ? p.artists.join(', ') : p?.identity ?? '';
        const apply = () => {
            this._title.text = title;
            this._artist.text = artist;
            this._total.text = fmtTime(p?.length ?? 0);
            this._tick();
        };
        if (animate && this._live) {
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
        this._opts.onTrack?.(p);
        this._loadArt(animate);
    }

    // ---------------------------------------------------------------- art
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
        animate &&= this._live;
        this._setArt(path, animate);
        this._setAspect(info?.aspect ?? 1, animate);
        this._opts.onArt?.(path, info ?? {aspect: 1, accent: Art.FALLBACK_ACCENT}, animate);
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
        const h = Math.round(this._artW / a);
        if (h === Math.round(this._artWrap.height))
            return;
        this._artWrap.remove_transition('height');
        if (animate)
            this._artWrap.ease({height: h, duration: 320, mode: EASE_IN});
        else
            this._artWrap.height = h;
    }

    // ---------------------------------------------------------------- player switcher
    _syncChips() {
        this._chips.destroy_all_children();
        const list = this._manager.players;
        if (list.length < 2)
            return;
        for (const p of list) {
            const inner = new St.BoxLayout({style_class: 'bm-chip-inner'});
            const icon = new St.Icon({icon_size: 14, y_align: Clutter.ActorAlign.CENTER});
            const gicon = p.app?.get_icon();
            if (gicon)
                icon.gicon = gicon;
            else
                icon.icon_name = 'audio-x-generic-symbolic';
            inner.add_child(icon);
            if (this._opts.labelledChips) {
                const l = new St.Label({style_class: 'bm-chip-label', text: shortName(p), y_align: Clutter.ActorAlign.CENTER});
                l.clutter_text.ellipsize = Pango.EllipsizeMode.END;
                inner.add_child(l);
            }
            const chip = new St.Button({
                style_class: `bm-chip ${this._opts.labelledChips ? 'bm-chip-labelled' : 'bm-chip-square'}`,
                child: inner,
                can_focus: true,
                checked: p === this._player,
                accessible_name: p.identity,
            });
            if (p.playing)
                chip.add_style_class_name('bm-chip-playing');
            chip.connect('clicked', () => this._manager.select(p));
            this._chips.add_child(chip);
        }
    }

    onScroll(ev) {
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
        const want = this._live && this._player?.playing;
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

    destroy() {
        this._cancellable.cancel();
        for (const id of [this._timerId, this._volIdle]) {
            if (id)
                GLib.source_remove(id);
        }
        this._timerId = this._volIdle = 0;
        for (const s of this._volStreams)
            s.disconnectObject(this);
        this._volStreams = [];
        this._player?.disconnectObject(this);
        this._manager.disconnectObject(this);
        this._mixer.disconnectObject(this);
        this.actor.destroy();
        this.actor = null;
    }
}
