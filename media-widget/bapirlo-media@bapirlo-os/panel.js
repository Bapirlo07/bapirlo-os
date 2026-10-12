// Bapirlo Media — top-bar button + dropdown player.
// Button: cover thumbnail + "Title · Artist" in a fixed-width window that fades at the right edge
// (the bar never jumps when the track changes). Nothing playing → just a note icon (or hidden,
// setting "hide-when-idle"). Click / Super+Alt+M opens the dropdown; click again, Esc or a click
// outside closes it (standard panel menu: grab, keyboard focus, slide + fade). Middle-click the
// button = play/pause, scroll over it = switch player.
// Dropdown: blurred cover backdrop + the shared PlayerView (view.js), accent tinted from the cover.
import Clutter from 'gi://Clutter';
import Cogl from 'gi://Cogl';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import Pango from 'gi://Pango';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

import * as Art from './art.js';
import {PlayerView, cssUrl, EASE_IN} from './view.js';

const PANEL_W = 360;
const PAD = 16;
const BACKDROP_H = 260;
const FADE_PX = 28;
const BACKDROP_OPACITY = 150;   // blurred cover strength (St has no CSS opacity)

// Fades the right edge of whatever it is attached to (alpha → 0 over the last FADE_PX).
const EdgeFade = GObject.registerClass(
class BapirloMediaEdgeFade extends Clutter.ShaderEffect {
    // GNOME 51 removed Shell.GLSLEffect; Clutter.ShaderEffect takes a static Cogl snippet
    vfunc_get_static_snippet() {
        return Cogl.Snippet.new(Cogl.SnippetHook.FRAGMENT,
            'uniform float fade_start;',
            'cogl_color_out *= 1.0 - smoothstep(fade_start, 1.0, cogl_tex_coord_in[0].x);');
    }

    setWidth(width) {
        const start = width > FADE_PX ? 1 - FADE_PX / width : 0;
        this.set_uniform_float('fade_start', 1, [start]);
        this.queue_repaint();
    }
});

export const MediaButton = GObject.registerClass(
class BapirloMediaButton extends PanelMenu.Button {
    _init(manager, settings) {
        super._init(0.5, 'Media player', false);
        this._manager = manager;
        this._settings = settings;
        this._cancellable = new Gio.Cancellable();
        this._backdropToken = 0;
        this.add_style_class_name('bmb-button');
        this.accessible_name = 'Media player';

        // ---- face in the bar
        const face = new St.BoxLayout({style_class: 'bmb-face', y_align: Clutter.ActorAlign.CENTER});
        this._thumb = new St.Bin({style_class: 'bmb-thumb', y_align: Clutter.ActorAlign.CENTER});
        this._note = new St.Icon({icon_name: 'emblem-music-symbolic', style_class: 'bmb-note'});
        this._title = new St.Label({style_class: 'bmb-title', y_align: Clutter.ActorAlign.CENTER});
        this._title.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;
        this._clip = new St.BoxLayout({style_class: 'bmb-clip', clip_to_allocation: true, y_align: Clutter.ActorAlign.CENTER});
        this._clip.add_child(this._title);
        this._fade = new EdgeFade();
        this._clip.add_effect(this._fade);
        this._clip.connect('notify::width', () => this._syncFade());
        this._title.connect('notify::width', () => this._syncFade());
        face.add_child(this._thumb);
        face.add_child(this._clip);
        this.add_child(face);
        this.connect('scroll-event', (_a, ev) => this._view.onScroll(ev));
        // GNOME 50 panel buttons toggle their menu from a Clutter.ClickGesture that takes ANY
        // button: keep it for the primary button (and touch), give middle-click to play/pause
        for (const g of this.get_actions()) {
            if (g instanceof Clutter.ClickGesture)
                g.required_button = Clutter.BUTTON_PRIMARY;
        }
        const middle = new Clutter.ClickGesture({required_button: Clutter.BUTTON_MIDDLE});
        middle.connect('recognize', () => this._view?.player?.playPause());
        this.add_action(middle);

        // ---- dropdown
        this.menu.actor.add_style_class_name('bmp-menu');
        this.menu.box.add_style_class_name('bmp-menu-box');
        this._panel = new St.Widget({
            style_class: 'bmp-panel',
            layout_manager: new Clutter.BinLayout(),
            width: PANEL_W,
        });
        this._backdrop = new St.Widget({
            style_class: 'bmp-backdrop', height: BACKDROP_H, x_expand: true, y_expand: true,
            y_align: Clutter.ActorAlign.START, opacity: 0,
        });
        this._scrim = new St.Widget({
            style_class: 'bmp-scrim', height: BACKDROP_H, x_expand: true, y_expand: true,
            y_align: Clutter.ActorAlign.START,
        });
        this._halftone = new St.Widget({
            style_class: 'bm-halftone bmp-halftone',
            x_align: Clutter.ActorAlign.END, y_align: Clutter.ActorAlign.START,
            x_expand: true, y_expand: true,
        });
        this._view = new PlayerView(manager, {
            artWidth: PANEL_W - 2 * PAD,
            labelledChips: true,
            onTrack: () => this._syncFace(),
            onState: () => this._syncFace(),
            onArt: (path, info, animate) => this._onArt(path, info, animate),
        });
        this._view.actor.add_style_class_name('bmp-view');
        this._view.artButton.connect('clicked', () => this.menu.close());   // raising the player = done here

        this._empty = new St.BoxLayout({
            style_class: 'bmp-empty', orientation: Clutter.Orientation.VERTICAL,
            x_expand: true, visible: false,
        });
        const emptyTag = new St.Label({style_class: 'bm-tag bm-tag-idle bmp-empty-tag', text: 'SILENCE…', x_align: Clutter.ActorAlign.CENTER});
        emptyTag.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;
        emptyTag.set_pivot_point(0.5, 0.5);
        emptyTag.rotation_angle_z = -4;
        this._empty.add_child(emptyTag);
        this._empty.add_child(new St.Icon({icon_name: 'emblem-music-symbolic', icon_size: 48, style_class: 'bmp-empty-icon', x_align: Clutter.ActorAlign.CENTER}));
        this._empty.add_child(new St.Label({style_class: 'bmp-empty-title', text: 'Nothing playing', x_align: Clutter.ActorAlign.CENTER}));
        const hint = new St.Label({
            style_class: 'bmp-empty-hint', x_align: Clutter.ActorAlign.CENTER,
            text: 'Play something in Spotify, Chrome, VLC or any app with media controls — it shows up here.',
        });
        hint.clutter_text.line_wrap = true;
        hint.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;
        this._empty.add_child(hint);

        for (const a of [this._backdrop, this._scrim, this._halftone, this._view.actor, this._empty])
            this._panel.add_child(a);
        this.menu.box.add_child(this._panel);

        this.menu.connect('open-state-changed', (_m, open) => {
            if (!this._view)
                return;   // closing while being destroyed
            this._view.setLive(open);
            if (open) {
                this._panel.remove_all_transitions();
                this._panel.translation_y = -14;
                this._panel.opacity = 0;
                this._panel.ease({translation_y: 0, opacity: 255, duration: 280, mode: EASE_IN});
            }
        });

        settings.connectObject(
            'changed::hide-when-idle', () => this._syncFace(),
            'changed::tint-from-art', () => this._applyAccent(), this);
        this._syncFace();
    }

    toggle() {
        if (!this.visible)
            this.show();   // even when hidden while idle: the shortcut still opens the empty panel
        this.menu.toggle();
    }

    _syncFade() {
        const w = this._clip.width;
        const overflow = this._title.width > w + 1;
        this._fade.enabled = overflow;
        if (overflow)
            this._fade.setWidth(w);
    }

    _syncFace() {
        if (!this._view || !this._empty)
            return;   // PlayerView reports its first state while it is still being built
        const p = this._view.player;
        const active = !!p && !!p.title && p.status !== 'Stopped';
        if (p) {
            const artist = p.artists.join(', ');
            this._title.text = artist ? `${p.title}  ·  ${artist}` : p.title;
        }
        this._clip.visible = active;
        this.remove_style_class_name('bmb-paused');
        this.remove_style_class_name('bmb-idle');
        if (!active)
            this.add_style_class_name('bmb-idle');
        else if (!p.playing)
            this.add_style_class_name('bmb-paused');
        if (!active || !this._thumbPath) {
            this._thumb.set_style(null);
            this._thumb.child = this._note;
        }
        const hideIdle = this._settings.get_boolean('hide-when-idle');
        this.visible = active || !hideIdle || this.menu.isOpen;
        this._view.actor.visible = !!p;
        this._empty.visible = !p;
        this._halftone.visible = !!p;
    }

    async _onArt(path, info, animate) {
        this._thumbPath = path;
        this._accent = info.accent;
        if (path) {
            this._thumb.child = null;
            this._thumb.set_style(`background-image: ${cssUrl(path)};`);
        }
        this._syncFace();
        this._applyAccent();

        const token = ++this._backdropToken;
        let blur = null;
        try {
            blur = path ? await Art.blurredArt(path, PANEL_W, BACKDROP_H, this._cancellable) : null;
        } catch {}
        if (token !== this._backdropToken)
            return;
        const show = () => {
            this._backdrop.set_style(blur ? `background-image: ${cssUrl(blur)};` : null);
            this._backdrop.ease({opacity: blur ? BACKDROP_OPACITY : 0, duration: animate ? 420 : 0, mode: EASE_IN});
        };
        if (animate && this._backdrop.opacity > 0)
            this._backdrop.ease({opacity: 0, duration: 160, mode: EASE_IN, onComplete: show});
        else
            show();
    }

    _applyAccent() {
        const tint = this._settings.get_boolean('tint-from-art') && this._accent;
        this._view.setAccent(tint ? this._accent : null);
        const rgb = (tint ? this._accent : Art.FALLBACK_ACCENT).join(',');
        // a glow of the accent bleeding in from the top of the panel, over the blurred cover
        this._scrim.set_style(`background-gradient-start: rgba(${rgb},0.16);`);
    }

    destroy() {
        this._cancellable.cancel();
        this._settings.disconnectObject(this);
        this._view.destroy();
        this._view = null;
        super.destroy();
    }
});
