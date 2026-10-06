// Bapirlo Bar — workspace dots.
//   active = crimson pill · has windows = ember dot · empty = hollow ring
//   click a dot = go there (click the active one = overview) · scroll = previous / next
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {Group, attachTooltip, EASE} from './util.js';

const DOT = 8;
const PILL = 22;
const MOVE_MS = 220;

export const WorkspaceDots = GObject.registerClass(
class BapirloWorkspaceDots extends Group {
    _init() {
        super._init('Bapirlo workspaces', 'bapirlo-ws');
        this._dots = [];
        this._workspaces = [];
        this._syncId = 0;
        this._scrollAcc = 0;
        this._scrollLock = 0;

        global.workspace_manager.connectObject(
            'notify::n-workspaces', () => this._rebuild(),
            'active-workspace-changed', () => this._sync(true),
            this);
        this.connect('scroll-event', (_a, ev) => this._onScroll(ev));
        this._rebuild();
    }

    _rebuild() {
        for (const ws of this._workspaces)
            ws.disconnectObject(this);
        this.box.destroy_all_children();
        this._dots = [];
        this._workspaces = [];

        const wm = global.workspace_manager;
        for (let i = 0; i < wm.n_workspaces; i++) {
            const ws = wm.get_workspace_by_index(i);
            ws.connectObject(
                'window-added', () => this._queueSync(),
                'window-removed', () => this._queueSync(),
                this);
            const dot = new St.Widget({
                style_class: 'bapirlo-ws-dot',
                x_align: Clutter.ActorAlign.CENTER,
                y_align: Clutter.ActorAlign.CENTER,
            });
            const hit = new St.Button({
                style_class: 'bapirlo-ws-hit',
                child: dot,
                can_focus: true,
                track_hover: true,
                accessible_name: `Workspace ${i + 1}`,
            });
            hit.connect('clicked', () => {
                if (ws.active)
                    Main.overview.toggle();
                else
                    ws.activate(global.get_current_time());
            });
            attachTooltip(hit, () => `Workspace ${i + 1}${ws.active ? ' — click for overview' : ''}`);
            this.box.add_child(hit);
            this._dots.push(dot);
            this._workspaces.push(ws);
        }
        this._sync(false);
    }

    _queueSync() {
        if (this._syncId)
            return;
        // window-added fires before the window is fully set up (skip_taskbar etc.)
        this._syncId = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._syncId = 0;
            this._sync(true);
            return GLib.SOURCE_REMOVE;
        });
    }

    _sync(animate) {
        this._workspaces.forEach((ws, i) => {
            const dot = this._dots[i];
            const occupied = ws.list_windows().some(w =>
                !w.skip_taskbar && !w.is_on_all_workspaces() &&
                w.get_window_type() !== Meta.WindowType.DESKTOP);
            dot.remove_style_class_name('active');
            dot.remove_style_class_name('occupied');
            if (ws.active)
                dot.add_style_class_name('active');
            else if (occupied)
                dot.add_style_class_name('occupied');

            const width = (ws.active ? PILL : DOT) *
                St.ThemeContext.get_for_stage(global.stage).scale_factor;
            dot.remove_transition('width');
            if (animate && dot.get_stage())
                dot.ease({width, duration: MOVE_MS, mode: EASE});
            else
                dot.width = width;
        });
    }

    _onScroll(ev) {
        let dir = 0;
        switch (ev.get_scroll_direction()) {
        case Clutter.ScrollDirection.UP:
        case Clutter.ScrollDirection.LEFT:
            dir = -1;
            break;
        case Clutter.ScrollDirection.DOWN:
        case Clutter.ScrollDirection.RIGHT:
            dir = 1;
            break;
        case Clutter.ScrollDirection.SMOOTH: {
            const [dx, dy] = ev.get_scroll_delta();
            this._scrollAcc += Math.abs(dy) > Math.abs(dx) ? dy : dx;
            if (Math.abs(this._scrollAcc) < 1)
                return Clutter.EVENT_STOP;
            dir = Math.sign(this._scrollAcc);
            this._scrollAcc = 0;
            break;
        }
        }
        const now = GLib.get_monotonic_time();
        if (!dir || now - this._scrollLock < 150000)   // one step per flick on touchpads
            return Clutter.EVENT_STOP;
        this._scrollLock = now;
        const wm = global.workspace_manager;
        const i = Math.max(0, Math.min(wm.get_active_workspace_index() + dir, wm.n_workspaces - 1));
        wm.get_workspace_by_index(i).activate(global.get_current_time());
        return Clutter.EVENT_STOP;
    }

    destroy() {
        if (this._syncId)
            GLib.source_remove(this._syncId);
        this._syncId = 0;
        for (const ws of this._workspaces)
            ws.disconnectObject(this);
        global.workspace_manager.disconnectObject(this);
        super.destroy();
    }
});
