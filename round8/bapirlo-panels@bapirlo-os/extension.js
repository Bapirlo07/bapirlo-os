// Bapirlo Panels — manga-panel window open/close (GNOME Shell 50/51). Replaces Burn My Windows' glide.
// Open: the window lands like a panel slapped onto the page — slides in from one side with a small tilt
// and overshoot, an ink frame with a crimson offset edge flashes around it, and a comic SFX burst
// ("BAM!") pops at its top-right corner. Close: the window flicks down and away (SFX optional).
//
// How it hooks in (no stock code is replaced): GNOME's WindowManager decides per window with
// _shouldAnimateActor() and then eases the actor (opacity 0→255 on map, 255→0 on destroy). For NORMAL
// windows we give that actor a one-shot ease() that runs our animation instead and still calls GNOME's
// own onStopped, so _mapWindowDone/_destroyWindowDone (completed_map/completed_destroy) run unchanged.
// Dialogs, fullscreen and skip-taskbar windows, the overview and "Reduce motion" keep GNOME's animation.
// Off switch: gnome-extensions disable bapirlo-panels@bapirlo-os
import Clutter from 'gi://Clutter';
import Meta from 'gi://Meta';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const OPEN_WORDS = ['BAM!', 'POW!', 'DON!', 'ZING!', 'SNAP!', 'KA-CHAK!', 'BOOM!'];
const CLOSE_WORDS = ['FWIP!', 'SHHK!', 'WHOOSH'];
// desktop icons + drop-down terminal: they set skip-taskbar only after mapping and bring their own entrance
const SKIP_APPS = ['com.desktop.ding', 'com.github.amezin.ddterm'];
const SLIDE = 70;           // px the panel travels in from the side
const TILT = 3.5;           // degrees

const pick = list => list[Math.floor(Math.random() * list.length)];

export default class BapirloPanelsExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._hooked = new Set();       // actors carrying our one-shot ease()
        this._extras = new Set();       // frames + SFX bursts on screen
        const self = this;
        const wm = Main.wm;
        this._origShouldAnimate = wm._shouldAnimateActor;
        wm._shouldAnimateActor = function (actor, types) {
            const ok = self._origShouldAnimate.call(this, actor, types);
            if (ok && self._wants(actor))
                self._hook(actor);
            return ok;
        };
    }

    disable() {
        Main.wm._shouldAnimateActor = this._origShouldAnimate;
        this._origShouldAnimate = null;
        for (const actor of this._hooked)
            delete actor.ease;
        this._hooked.clear();
        for (const a of this._extras)
            a.destroy();
        this._extras.clear();
        this._settings = null;
    }

    _wants(actor) {
        const win = actor.meta_window;
        if (!win || Main.wm._getAnimationWindowType(actor) !== Meta.WindowType.NORMAL || win.is_fullscreen() ||
            win.is_skip_taskbar() || St.Settings.get().reducedMotion === St.ReducedMotion.REDUCE)
            return false;
        if (SKIP_APPS.includes(win.get_gtk_application_id()) || SKIP_APPS.includes(win.get_wm_class()))
            return false;
        // a window covering its whole monitor (panel included) is a desktop/backdrop, not a panel
        const r = win.get_frame_rect();
        const mon = global.display.get_monitor_geometry(win.get_monitor());
        return !(r.x <= mon.x && r.y <= mon.y && r.width >= mon.width && r.height >= mon.height);
    }

    // One-shot override: the next ease() on this actor is either GNOME's map/destroy animation (ours
    // instead) or something else (passed through untouched).
    _hook(actor) {
        if (this._hooked.has(actor))
            return;
        this._hooked.add(actor);
        const wm = Main.wm;
        actor.ease = params => {
            delete actor.ease;
            this._hooked.delete(actor);
            if (wm._mapping.has(actor) && params.opacity === 255)
                return this._open(actor, params.onStopped);
            if (wm._destroying.has(actor) && params.opacity === 0)
                return this._close(actor, params.onStopped);
            return actor.ease(params);
        };
    }

    _open(actor, done) {
        const ms = this._settings.get_int('open-time');
        const rect = actor.meta_window.get_frame_rect();
        const dir = Math.random() < 0.5 ? -1 : 1;
        actor.remove_all_transitions();
        actor.set_pivot_point(0.5, 0.5);
        actor.set({scale_x: 0.94, scale_y: 0.94, translation_x: dir * SLIDE, rotation_angle_z: dir * TILT, opacity: 0});
        actor.ease({opacity: 255, duration: Math.round(ms * 0.45), mode: Clutter.AnimationMode.EASE_OUT_QUAD});
        actor.ease({
            scale_x: 1, scale_y: 1, translation_x: 0, rotation_angle_z: 0,
            duration: ms, mode: Clutter.AnimationMode.EASE_OUT_BACK,
            onStopped: () => {
                actor.rotation_angle_z = 0;
                done?.();
            },
        });
        this._frame(actor, rect, dir, ms);
        if (this._settings.get_boolean('sfx'))
            this._burst(rect, pick(OPEN_WORDS), Math.round(ms * 0.35));
    }

    _close(actor, done) {
        const ms = this._settings.get_int('close-time');
        const rect = actor.meta_window.get_frame_rect();
        const dir = Math.random() < 0.5 ? -1 : 1;
        actor.remove_all_transitions();
        actor.set_pivot_point(0.5, 0.5);
        actor.ease({opacity: 0, duration: ms, mode: Clutter.AnimationMode.EASE_IN_QUAD});
        actor.ease({
            scale_x: 0.9, scale_y: 0.9, translation_y: 48, rotation_angle_z: dir * 4,
            duration: ms, mode: Clutter.AnimationMode.EASE_IN_BACK,
            onStopped: () => done?.(),
        });
        if (this._settings.get_boolean('sfx-on-close'))
            this._burst(rect, pick(CLOSE_WORDS), 0);
    }

    // Ink frame + crimson offset edges that ride along with the window, then fade once it has landed.
    _frame(actor, rect, dir, ms) {
        const frame = new St.Widget({style_class: 'bapirlo-panel-frame', x: rect.x, y: rect.y,
            width: rect.width, height: rect.height});
        frame.add_child(new St.Widget({style_class: 'bapirlo-panel-edge', x: rect.width, y: 6,
            width: 6, height: rect.height}));
        frame.add_child(new St.Widget({style_class: 'bapirlo-panel-edge', x: 6, y: rect.height,
            width: rect.width, height: 6}));
        global.window_group.add_child(frame);
        global.window_group.set_child_above_sibling(frame, actor);
        this._extras.add(frame);
        frame.connect('destroy', () => this._extras.delete(frame));
        actor.connectObject('destroy', () => frame.destroy(), frame);
        frame.set_pivot_point(0.5, 0.5);
        frame.set({scale_x: 0.94, scale_y: 0.94, translation_x: dir * SLIDE, rotation_angle_z: dir * TILT});
        frame.ease({
            scale_x: 1, scale_y: 1, translation_x: 0, rotation_angle_z: 0,
            duration: ms, mode: Clutter.AnimationMode.EASE_OUT_BACK,
            onComplete: () => frame.ease({
                opacity: 0, delay: 90, duration: 220, mode: Clutter.AnimationMode.EASE_OUT_QUAD,
                onStopped: () => frame.destroy(),
            }),
        });
    }

    // Comic SFX: a crimson starburst with the word on it, popping at the window's top-right corner.
    _burst(rect, word, delay) {
        const W = 150, H = 96;
        const box = new St.Widget({style_class: 'bapirlo-sfx', width: W, height: H, reactive: false,
            layout_manager: new Clutter.BinLayout()});
        const star = new St.DrawingArea({width: W, height: H});
        star.connect('repaint', area => {
            const cr = area.get_context();
            const [w, h] = area.get_surface_size();
            const n = 14, cx = w / 2, cy = h / 2;
            cr.moveTo(cx + w * 0.48, cy);
            for (let i = 1; i <= n * 2; i++) {
                const a = Math.PI * i / n;
                const r = i % 2 ? 0.62 : (i % 4 ? 0.98 : 0.86);
                cr.lineTo(cx + Math.cos(a) * w * 0.48 * r, cy + Math.sin(a) * h * 0.48 * r);
            }
            cr.closePath();
            cr.setSourceRGBA(0xE1 / 255, 0x1D / 255, 0x2E / 255, 1);
            cr.fillPreserve();
            cr.setSourceRGBA(0x0E / 255, 0x0A / 255, 0x0D / 255, 1);
            cr.setLineWidth(3);
            cr.setLineJoin(1);  // ROUND
            cr.stroke();
            cr.$dispose();
        });
        box.add_child(star);
        const text = new St.Label({text: word, style_class: 'bapirlo-sfx-word',
            x_align: Clutter.ActorAlign.CENTER, y_align: Clutter.ActorAlign.CENTER});
        text.clutter_text.ellipsize = 0;    // Pango.EllipsizeMode.NONE
        box.add_child(text);
        const mon = global.display.get_monitor_geometry(global.display.get_monitor_index_for_rect(rect));
        const x = Math.min(rect.x + rect.width - W * 0.7, mon.x + mon.width - W);
        const y = Math.max(rect.y - H * 0.35, mon.y);
        box.set({x, y, opacity: 0, scale_x: 0.2, scale_y: 0.2, rotation_angle_z: -16});
        box.set_pivot_point(0.5, 0.5);
        Main.layoutManager.uiGroup.add_child(box);
        this._extras.add(box);
        box.connect('destroy', () => this._extras.delete(box));
        box.ease({
            opacity: 255, scale_x: 1, scale_y: 1, rotation_angle_z: -7,
            delay, duration: 220, mode: Clutter.AnimationMode.EASE_OUT_BACK,
            onComplete: () => box.ease({
                opacity: 0, scale_x: 1.18, scale_y: 1.18,
                delay: 260, duration: 160, mode: Clutter.AnimationMode.EASE_IN_QUAD,
                onStopped: () => box.destroy(),
            }),
        });
    }
}
