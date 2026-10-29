// Kuro Bar — the bar over fullscreen apps.
// GNOME already hides the bar while the primary monitor shows a fullscreen window (games, videos).
// Push the pointer against the top edge and it slides in over the app; it slides away again once
// the pointer has left it and no dropdown is open.
// Cost: a pressure barrier exists only while something is fullscreen and nothing runs until it is
// hit (games that lock the pointer never hit it). The short leave-check timer runs only while the
// bar is actually revealed.
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as Layout from 'resource:///org/gnome/shell/ui/layout.js';

const PRESSURE = 60;       // px of push against the edge …
const PRESSURE_MS = 1000;  // … within this time
const SLIDE_MS = 200;
const LEAVE_CHECK_MS = 250;
const LEAVE_GRACE = 2;     // checks in a row outside the bar before it hides (≈ 0.5 s)
const MARGIN = 12;         // px below the bar that still count as "on it"

export class FullscreenReveal {
    constructor() {
        this._lm = Main.layoutManager;
        this._pressure = new Layout.PressureBarrier(PRESSURE, PRESSURE_MS, Shell.ActionMode.NORMAL);
        this._pressure.connect('trigger', () => this._reveal());
        this._barrier = null;
        this._revealed = false;
        this._lm.connectObject('monitors-changed', () => this._sync(true), this);
        global.display.connectObject('in-fullscreen-changed', () => this._sync(false), this);
        Main.overview.connectObject('showing', () => this._conceal(false), this);
        this._sync(false);
    }

    _primaryFullscreen() {
        return this._lm.primaryMonitor?.inFullscreen ?? false;
    }

    _sync(monitorsChanged) {
        if (monitorsChanged)
            this._dropBarrier();
        const fs = this._primaryFullscreen();
        if (fs && !this._barrier) {
            const m = this._lm.primaryMonitor;
            this._barrier = new Meta.Barrier({
                backend: global.backend,
                x1: m.x, x2: m.x + m.width, y1: m.y, y2: m.y,
                directions: Meta.BarrierDirection.POSITIVE_Y,
            });
            this._pressure.addBarrier(this._barrier);
        } else if (!fs) {
            this._dropBarrier();
            this._conceal(false);
        }
    }

    _dropBarrier() {
        if (!this._barrier)
            return;
        this._pressure.removeBarrier(this._barrier);
        this._barrier.destroy();
        this._barrier = null;
    }

    _trackedPanel() {
        return this._lm._trackedActors?.find(a => a.actor === this._lm.panelBox) ?? null;
    }

    _reveal() {
        if (this._revealed || !this._primaryFullscreen() || Main.overview.visible)
            return;
        const data = this._trackedPanel();
        if (!data)
            return;
        this._revealed = true;
        // keep GNOME from hiding it again while it is out; struts are untouched (GNOME computes
        // them from the panel box whether it is visible or not), so no window gets resized
        data.trackFullscreen = false;
        const panel = Main.panel;
        this._lm.panelBox.show();
        panel.remove_all_transitions();
        panel.set({translation_y: -(panel.height + 12), opacity: 0});
        panel.ease({translation_y: 0, opacity: 255, duration: SLIDE_MS, mode: Clutter.AnimationMode.EASE_OUT_QUAD});

        this._outside = 0;
        this._leaveId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, LEAVE_CHECK_MS, () => {
            if (this._pointerOnBar() || Main.panel.menuManager.activeMenu) {
                this._outside = 0;
                return GLib.SOURCE_CONTINUE;
            }
            if (++this._outside < LEAVE_GRACE)
                return GLib.SOURCE_CONTINUE;
            this._leaveId = 0;
            this._conceal(true);
            return GLib.SOURCE_REMOVE;
        });
    }

    _pointerOnBar() {
        const [, y] = global.get_pointer();
        const box = this._lm.panelBox;
        const [, by] = box.get_transformed_position();
        return y <= by + box.height + MARGIN;
    }

    _conceal(animate) {
        if (!this._revealed)
            return;
        this._revealed = false;
        if (this._leaveId)
            GLib.source_remove(this._leaveId);
        this._leaveId = 0;
        const panel = Main.panel;
        const done = () => {
            if (this._revealed)   // pushed again while it was sliding away
                return;
            panel.set({translation_y: 0, opacity: 255});
            const data = this._trackedPanel();
            if (data)
                data.trackFullscreen = true;
            this._lm._updateVisibility();
        };
        panel.remove_all_transitions();
        if (!animate) {
            done();
            return;
        }
        panel.ease({
            translation_y: -(panel.height + 12), opacity: 0,
            duration: SLIDE_MS, mode: Clutter.AnimationMode.EASE_IN_QUAD,
            onStopped: done,
        });
    }

    destroy() {
        this._conceal(false);
        this._dropBarrier();
        this._pressure.destroy();
        this._lm.disconnectObject(this);
        global.display.disconnectObject(this);
        Main.overview.disconnectObject(this);
    }
}
