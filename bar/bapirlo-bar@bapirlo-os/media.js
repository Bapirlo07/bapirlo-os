// Bapirlo Bar — mini media player: cover · "Title · Artist" · play/pause.
// Previous / next slide out while hovered. Click the title to raise the player,
// scroll over it to switch between players. Hidden when nothing is playing or paused.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import Pango from 'gi://Pango';
import St from 'gi://St';

import * as Art from './art.js';
import {Group, addLift, attachTooltip, EASE, HOVER_MS} from './util.js';

function cssUrl(path) {
    return `url("${path.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}")`;
}

function iconButton(icon, cls) {
    const b = new St.Button({
        style_class: `bapirlo-mini-btn ${cls}`,
        can_focus: true,
        track_hover: true,
        child: new St.Icon({icon_name: icon, style_class: 'bapirlo-mini-icon'}),
    });
    addLift(b, b.child, 1.15);
    return b;
}

export const MiniPlayer = GObject.registerClass(
class BapirloMiniPlayer extends Group {
    _init(manager) {
        super._init('Bapirlo mini player', 'bapirlo-mini');
        this._manager = manager;
        this._player = null;
        this._cancellable = new Gio.Cancellable();
        this.track_hover = true;

        this._art = new St.Bin({style_class: 'bapirlo-mini-art', y_align: Clutter.ActorAlign.CENTER});
        this._title = new St.Label({style_class: 'bapirlo-mini-title', y_align: Clutter.ActorAlign.CENTER});
        this._title.clutter_text.ellipsize = Pango.EllipsizeMode.END;
        this._titleBtn = new St.Button({
            style_class: 'bapirlo-mini-titlebtn', can_focus: true, track_hover: true,
            child: new St.BoxLayout({style_class: 'bapirlo-mini-info', y_align: Clutter.ActorAlign.CENTER}),
        });
        this._titleBtn.child.add_child(this._art);
        this._titleBtn.child.add_child(this._title);
        this._titleBtn.connect('clicked', () => this._player?.raise());
        attachTooltip(this._titleBtn, () => this._player
            ? `${this._player.identity} — click to open${this._manager.players.length > 1 ? ', scroll to switch' : ''}`
            : '');

        this._prev = iconButton('media-skip-backward-symbolic', 'bapirlo-mini-prev');
        this._play = iconButton('media-playback-start-symbolic', 'bapirlo-mini-play');
        this._next = iconButton('media-skip-forward-symbolic', 'bapirlo-mini-next');
        this._prev.connect('clicked', () => this._player?.previous());
        this._play.connect('clicked', () => this._player?.playPause());
        this._next.connect('clicked', () => this._player?.next());

        // prev / next live in a clipped box that grows on hover
        this._extra = new St.BoxLayout({style_class: 'bapirlo-mini-extra', clip_to_allocation: true, width: 0, opacity: 0});
        this._extra.add_child(this._prev);
        this._extra.add_child(this._next);

        this.box.add_child(this._titleBtn);
        this.box.add_child(this._play);
        this.box.add_child(this._extra);

        this.connect('notify::hover', () => this._reveal(this.hover));
        this.connect('scroll-event', (_a, ev) => {
            const d = ev.get_scroll_direction();
            if (d === Clutter.ScrollDirection.UP || d === Clutter.ScrollDirection.LEFT)
                this._manager.cycle(-1);
            else if (d === Clutter.ScrollDirection.DOWN || d === Clutter.ScrollDirection.RIGHT)
                this._manager.cycle(1);
            return Clutter.EVENT_STOP;
        });

        manager.connectObject('active-changed', () => this._bind(), this);
        this._bind();
    }

    // prev/next slide in while the title gives up the same width, so the bar never reflows
    _reveal(on) {
        for (const a of [this._extra, this._title])
            a.remove_all_transitions();
        // the box has a fixed width (0 when hidden), so measure the buttons themselves
        const extraW = this._extra.get_children().reduce((w, c) => w + c.get_preferred_width(-1)[1], 0);
        this._title.width = -1;
        const [, titleW] = this._title.get_preferred_width(-1);
        const ms = HOVER_MS + 40;
        if (on) {
            this._title.width = titleW;
            this._title.ease({width: Math.max(40, titleW - extraW), duration: ms, mode: EASE});
        } else {
            this._title.width = Math.max(40, titleW - extraW);
            this._title.ease({width: titleW, duration: ms, mode: EASE,
                onComplete: () => (this._title.width = -1)});
        }
        this._extra.ease({width: on ? extraW : 0, opacity: on ? 255 : 0, duration: ms, mode: EASE});
    }

    _bind() {
        this._player?.disconnectObject(this);
        this._player = this._manager.active;
        this._player?.connectObject(
            'changed', () => this._syncState(),
            'track-changed', () => this._syncTrack(),
            this);
        this._syncTrack();
        this._syncState();
    }

    _syncState() {
        const p = this._player;
        const show = !!p && !!p.title && p.status !== 'Stopped';
        if (show !== this.visible) {
            if (show) {
                this.opacity = 0;
                this.show();
                this.ease({opacity: 255, duration: HOVER_MS, mode: EASE});
            } else {
                this.hide();
            }
        }
        if (!p)
            return;
        this._play.child.icon_name = p.playing ? 'media-playback-pause-symbolic' : 'media-playback-start-symbolic';
        this._play.reactive = p.canPlayPause;
        this._prev.reactive = p.canPrev;
        this._next.reactive = p.canNext;
        this._titleBtn.child.remove_style_class_name('paused');
        if (!p.playing)
            this._titleBtn.child.add_style_class_name('paused');
    }

    async _syncTrack() {
        const p = this._player;
        if (!p) {
            this._syncState();
            return;
        }
        const artist = p.artists.join(', ');
        this._title.text = artist ? `${p.title}  ·  ${artist}` : p.title;
        if (!this.hover)
            this._title.width = -1;
        this._syncState();
        const url = p.artUrl;
        let path = null;
        try {
            path = await Art.resolveArt(url, this._cancellable);
        } catch {}
        if (this._player !== p || p.artUrl !== url)
            return;
        this._art.child = null;
        if (path) {
            this._art.set_style(`background-image: ${cssUrl(path)};`);
        } else {
            this._art.set_style(null);
            this._art.child = new St.Icon({
                gicon: p.app?.get_icon() ?? null,
                icon_name: p.app ? null : 'audio-x-generic-symbolic',
                style_class: 'bapirlo-mini-art-icon',
            });
        }
    }

    destroy() {
        this._cancellable.cancel();
        this._player?.disconnectObject(this);
        this._manager.disconnectObject(this);
        super.destroy();
    }
});
