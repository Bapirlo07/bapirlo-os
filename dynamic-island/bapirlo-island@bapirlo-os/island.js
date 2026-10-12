// Bapirlo Island — the pill itself.
// At rest the centre of the top bar (clock + weather) wears a dark capsule. An event grows an overlay
// out of that capsule (same spot, same shape), shows its view, then shrinks back into it.
// Only Clutter implicit transitions while something is on screen — nothing runs when idle.
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const GROW_MS = 420;
const SHRINK_MS = 300;
const FADE_MS = 140;
const REST_CLASS = 'bapirlo-island-rest';

export class Island {
    constructor() {
        this._queue = [];
        this._current = null;   // {kind, key, view, width, height, timeout, sticky}
        this._timer = 0;
        this._hovered = false;
        this._state = 'rest';   // rest | open | closing

        this.actor = new St.Widget({
            style_class: 'bapirlo-island',
            reactive: true,
            track_hover: true,
            clip_to_allocation: true,
            visible: false,
            layout_manager: new Clutter.BinLayout(),
        });
        this.actor.connect('notify::hover', () => {
            this._hovered = this.actor.hover;
            if (this._hovered)
                this._stopTimer();
            else if (this._state === 'open')
                this._startTimer(1500);
        });
        this.actor.connect('button-release-event', (a, ev) => {
            const v = this._current;
            if (!v)
                return Clutter.EVENT_PROPAGATE;
            // buttons inside a view: media controls keep it open, notification actions close it
            for (let a = ev.get_source(); a && a !== this.actor; a = a.get_parent()) {
                if (a._islandKeepOpen) {
                    this._startTimer(v.timeout);
                    return Clutter.EVENT_STOP;
                }
                if (a instanceof St.Button) {
                    this.close();
                    return Clutter.EVENT_STOP;
                }
            }
            if (ev.get_button() === Clutter.BUTTON_SECONDARY || ev.get_button() === Clutter.BUTTON_MIDDLE) {
                v.onDismiss?.();
            } else {
                v.onClick?.();
            }
            this.close();
            return Clutter.EVENT_STOP;
        });
        // right above the panel, below nothing else of ours
        Main.layoutManager.uiGroup.insert_child_above(this.actor, Main.layoutManager.panelBox);

        this._centre = Main.panel._centerBox;
        this.setRestPill(true);
    }

    setRestPill(on) {
        if (on)
            this._centre.add_style_class_name(REST_CLASS);
        else
            this._centre.remove_style_class_name(REST_CLASS);
    }

    get busy() {
        return this._state !== 'rest';
    }

    // Capsule rectangle in stage coordinates (what the overlay grows from and shrinks back to).
    _restRect() {
        const [x, y] = this._centre.get_transformed_position();
        const [w, h] = this._centre.get_transformed_size();
        const node = this._centre.get_theme_node();
        // the capsule is drawn inside the box's margin, so match its painted area
        const m = node.get_margin(St.Side.TOP);
        return {x: Math.round(x), y: Math.round(y), w: Math.round(w), h: Math.round(h), m};
    }

    // spec: {kind, key, build() -> actor, width, height, timeout ms, onClick, onDismiss, update(spec)}
    show(spec) {
        // same kind+key already showing → update in place (volume ticks, a track change …)
        if (this._current && this._state === 'open' && this._current.key === spec.key && this._current.update) {
            this._current.update(spec);
            this._startTimer(spec.timeout);
            return;
        }
        if (spec.urgent || this._state === 'rest') {
            this._queue = this._queue.filter(q => q.key !== spec.key);
            this._open(spec);
        } else {
            this._queue = this._queue.filter(q => q.key !== spec.key);
            this._queue.push(spec);
            // a level/OSD change never waits behind a notification: it takes over now, and what it
            // interrupted comes back right after it (unless that was only a level too)
            if (this._state === 'open' && !this._hovered && spec.kind === 'level') {
                const interrupted = this._current;
                this._swap(this._queue.pop());
                if (interrupted && interrupted.kind !== 'level')
                    this._queue.unshift(interrupted);
            }
        }
    }

    _open(spec) {
        const r = this._restRect();
        if (this._state === 'rest') {
            this.actor.remove_all_transitions();
            this.actor.set_position(r.x, r.y + r.m);
            this.actor.set_size(r.w, r.h - 2 * r.m);
            this.actor.opacity = 255;
            this.actor.show();
            this._centre.ease({opacity: 0, duration: FADE_MS, mode: Clutter.AnimationMode.EASE_OUT_QUAD});
        }
        this._state = 'open';
        this._swap(spec);
    }

    _swap(spec) {
        const r = this._restRect();
        const old = this._current;
        this._current = spec;
        const view = spec.build();
        view.opacity = 0;
        view.x_expand = view.y_expand = true;
        if (old?.view) {
            const v = old.view;
            v.ease({opacity: 0, duration: FADE_MS, mode: Clutter.AnimationMode.EASE_OUT_QUAD,
                onStopped: () => v.destroy()});
        }
        this.actor.add_child(view);
        spec.view = view;
        const w = spec.width, h = spec.height;
        this.actor.ease({
            x: Math.round(r.x + r.w / 2 - w / 2), y: r.y + r.m, width: w, height: h,
            duration: GROW_MS, mode: Clutter.AnimationMode.EASE_OUT_BACK,
        });
        view.ease({opacity: 255, delay: GROW_MS / 2.5, duration: 200, mode: Clutter.AnimationMode.EASE_OUT_QUAD});
        this._startTimer(spec.timeout);
    }

    close() {
        if (this._state !== 'open')
            return;
        this._stopTimer();
        const next = this._queue.shift();
        if (next) {
            this._swap(next);
            return;
        }
        this._state = 'closing';
        const r = this._restRect();
        const cur = this._current;
        cur?.view?.ease({opacity: 0, duration: FADE_MS, mode: Clutter.AnimationMode.EASE_OUT_QUAD});
        this.actor.ease({
            x: r.x, y: r.y + r.m, width: r.w, height: r.h - 2 * r.m,
            delay: FADE_MS / 2, duration: SHRINK_MS, mode: Clutter.AnimationMode.EASE_IN_OUT_CUBIC,
            onStopped: () => {
                if (this._state !== 'closing')
                    return;          // re-opened mid-shrink
                this._centre.ease({opacity: 255, duration: FADE_MS, mode: Clutter.AnimationMode.EASE_OUT_QUAD});
                this.actor.ease({
                    opacity: 0, duration: FADE_MS, mode: Clutter.AnimationMode.EASE_OUT_QUAD,
                    onStopped: () => {
                        if (this._state !== 'closing')
                            return;
                        this.actor.hide();
                        this.actor.destroy_all_children();
                        this._current = null;
                        this._state = 'rest';
                        const late = this._queue.shift();
                        if (late)
                            this._open(late);
                    },
                });
            },
        });
    }

    // closing → open again (event arrives during the shrink)
    _revive(spec) {
        this.actor.remove_all_transitions();
        this.actor.opacity = 255;
        this._state = 'open';
        this._swap(spec);
    }

    push(spec) {
        if (this._state === 'closing') {
            this._revive(spec);
            return;
        }
        this.show(spec);
    }

    _startTimer(ms) {
        this._stopTimer();
        if (this._hovered || !ms)
            return;
        this._timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
            this._timer = 0;
            this.close();
            return GLib.SOURCE_REMOVE;
        });
    }

    _stopTimer() {
        if (this._timer)
            GLib.source_remove(this._timer);
        this._timer = 0;
    }

    destroy() {
        this._stopTimer();
        this._queue = [];
        this.setRestPill(false);
        this._centre.remove_all_transitions();
        this._centre.opacity = 255;
        this.actor.destroy();
    }
}
