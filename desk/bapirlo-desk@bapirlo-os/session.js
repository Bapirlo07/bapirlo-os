// Kuro Desk — session restore: the apps you had open come back after you log in, each window
// on its own workspace, monitor, size and position (maximised / minimised too).
//   SAVING   every 30 s the open app windows are written to ~/.local/state/bapirlo/session/last.json
//            (cheap: a list of ~10 windows). A drop in the number of windows is only kept once it
//            has lasted a whole sample, so the burst of closing windows at log out never
//            overwrites the real session. Nothing is saved until the restore was offered.
//   RESTORE  at login (`session-restore`: auto | ask | off). Apps that are not running are started
//            one by one; every window that shows up in the next 90 s is matched to a saved slot of
//            its app and moved there. Apps that bring back their own windows (browsers, editors)
//            are started once; the rest get a new window per saved one.
//   Never restored: Android (Waydroid) apps, games (Steam), windows without an app, the
//   `session-skip` list. A session older than 7 days is ignored.
// `bapirlo-session` (bin/) shows / switches it; os.bapirlo.Desk.RestoreSession() runs it now.
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as MessageTray from 'resource:///org/gnome/shell/ui/messageTray.js';

import {STATE_DIR, readJson, writeJson} from './util.js';

const FILE = GLib.build_filenamev([STATE_DIR, 'session', 'last.json']);
const SAMPLE_S = 30;
const PLACE_WINDOW_S = 90;
const MAX_AGE_S = 7 * 24 * 3600;
const LAUNCH_GAP_MS = 450;
// these reopen their own windows (or are single-window): start once, never "new window"
const SELF_RESTORE = /^(google-chrome|chromium|firefox|brave|microsoft-edge|code|visual-studio-code|vesktop|discord|spotify|org\.gnome\.Nautilus|steam|obsidian)/i;
const NEVER = /^(waydroid\.|steam_app_|org\.gnome\.Shell\.|gnome-shell|window:)/;

export class SessionKeeper {
    constructor(settings) {
        this._settings = settings;
        this._committed = readJson(FILE, null);
        this._lastCount = -1;
        this._ready = false;       // saving starts once the restore was offered / done / declined
        this._pending = null;
        this._sampleId = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, SAMPLE_S, () => {
            this._sample();
            return GLib.SOURCE_CONTINUE;
        });
    }

    // ------------------------------------------------------------ saving
    _skip(id) {
        return !id || NEVER.test(id) || this._settings.get_strv('session-skip').includes(id);
    }

    _snapshot() {
        const tracker = Shell.WindowTracker.get_default();
        const out = [];
        for (const actor of global.get_window_actors()) {
            const w = actor.meta_window;
            if (w.get_window_type() !== Meta.WindowType.NORMAL || w.is_skip_taskbar() || w.is_attached_dialog())
                continue;
            const app = tracker.get_window_app(w);
            const id = app?.get_id();
            if (!app || app.is_window_backed() || this._skip(id))
                continue;
            const r = w.get_frame_rect();
            out.push({
                app: id,
                ws: w.on_all_workspaces ? -1 : (w.get_workspace()?.index() ?? 0),
                monitor: w.get_monitor(),
                rect: [r.x, r.y, r.width, r.height],
                max: w.is_maximized(),
                min: w.minimized,
                stamp: w.get_user_time(),
            });
        }
        // keep the stacking order of each app stable (oldest first) so slots match launch order
        out.sort((a, b) => a.stamp - b.stamp);
        return out;
    }

    _sample() {
        if (!this._ready || this._pending || Main.sessionMode.isLocked)
            return;
        const wins = this._snapshot();
        const committedCount = this._committed?.windows?.length ?? 0;
        // more (or as many) windows → save now; fewer → only once the drop has lasted a sample
        if (wins.length >= committedCount || wins.length === this._lastCount) {
            const data = {saved: Math.floor(GLib.get_real_time() / 1e6),
                workspaces: global.workspace_manager.n_workspaces, windows: wins};
            if (JSON.stringify(data.windows) !== JSON.stringify(this._committed?.windows)) {
                writeJson(FILE, data);
                this._committed = data;
            }
        }
        this._lastCount = wins.length;
    }

    // ------------------------------------------------------------ at login
    loginRestore() {
        const mode = this._settings.get_string('session-restore');
        const saved = this._usable();
        if (mode === 'off' || !saved) {
            this._ready = true;
            return;
        }
        const apps = new Set(saved.windows.map(w => w.app)).size;
        if (mode === 'auto') {
            this.restore();
            this._notify(`Bringing back ${apps === 1 ? 'your app' : `${apps} apps`} from last time`, null);
            return;
        }
        this._notify(`Bring back ${apps === 1 ? 'the app' : `the ${apps} apps`} you had open?`, [
            ['Restore', () => this.restore()],
            ['Not now', () => (this._ready = true)],
        ]);
        // ignored → start saving again after 10 min (the old session stays until then)
        this._askId = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, 600, () => {
            this._askId = 0;
            this._ready = true;
            return GLib.SOURCE_REMOVE;
        });
    }

    skipLogin() {
        this._ready = true;
    }

    _usable() {
        const s = readJson(FILE, null);
        if (!s?.windows?.length || GLib.get_real_time() / 1e6 - (s.saved ?? 0) > MAX_AGE_S)
            return null;
        return s;
    }

    _notify(title, actions) {
        try {
            const source = MessageTray.getSystemSource();
            const n = new MessageTray.Notification({source, title, body: 'Session restore · Kuro Desk',
                iconName: 'view-restore-symbolic'});
            for (const [name, cb] of actions ?? [])
                n.addAction(name, cb);
            source.addNotification(n);
        } catch (e) {
            logError(e, 'bapirlo-desk: session notification');
        }
    }

    // ------------------------------------------------------------ restore
    restore() {
        const saved = this._usable();
        if (!saved || this._pending)
            return;
        this._ready = true;
        if (this._askId)
            GLib.source_remove(this._askId);
        this._askId = 0;

        const appSys = Shell.AppSystem.get_default();
        const tracker = Shell.WindowTracker.get_default();
        // slots per app, in the order their windows were opened
        const slots = new Map();
        for (const s of saved.windows) {
            if (this._skip(s.app) || !appSys.lookup_app(s.app))
                continue;
            if (!slots.has(s.app))
                slots.set(s.app, []);
            slots.get(s.app).push(s);
        }
        if (!slots.size)
            return;
        this._pending = slots;
        this._placed = new WeakSet();
        // keep empty in-between workspaces alive while windows arrive out of order
        Main.wm._workspaceTracker?.blockUpdates();

        // windows that are already open (autostarted apps) take their slots first
        for (const actor of global.get_window_actors())
            this._claim(actor.meta_window, tracker);

        global.display.connectObject('window-created', (_d, w) => {
            // the app is known once the window is shown
            const id = w.connect('shown', () => {
                w.disconnect(id);
                this._claim(w, tracker);
            });
        }, this);

        // start the apps that are not running, a little apart
        const toStart = [...slots.keys()].filter(id => appSys.lookup_app(id).get_state() === Shell.AppState.STOPPED);
        let i = 0;
        const next = () => {
            if (!this._pending || i >= toStart.length) {
                this._launchId = 0;
                return GLib.SOURCE_REMOVE;
            }
            const app = appSys.lookup_app(toStart[i++]);
            try {
                app.launch(0, -1, Shell.AppLaunchGpu.APP_PREF);
            } catch (e) {
                logError(e, `bapirlo-desk: session restore could not start ${app.get_id()}`);
            }
            return GLib.SOURCE_CONTINUE;
        };
        next();
        this._launchId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, LAUNCH_GAP_MS, next);

        // apps that don't reopen their own windows: ask for the missing ones
        this._extraId = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, 15, () => {
            this._extraId = 0;
            for (const [id, left] of this._pending ?? []) {
                const app = appSys.lookup_app(id);
                if (!left.length || SELF_RESTORE.test(id) || !app?.can_open_new_window() ||
                    app.get_state() !== Shell.AppState.RUNNING)
                    continue;
                for (let k = 0; k < Math.min(left.length, 3); k++)
                    app.open_new_window(-1);
            }
            return GLib.SOURCE_REMOVE;
        });
        this._doneId = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, PLACE_WINDOW_S, () => {
            this._doneId = 0;
            this._finish();
            return GLib.SOURCE_REMOVE;
        });
    }

    _claim(w, tracker) {
        if (!this._pending || w.get_window_type() !== Meta.WindowType.NORMAL || w.is_attached_dialog() ||
            this._placed.has(w))
            return;
        const id = tracker.get_window_app(w)?.get_id();
        const left = this._pending.get(id);
        if (!left?.length)
            return;
        this._placed.add(w);
        const slot = left.shift();
        // let the app finish its own first placement, then move it
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, 250, () => {
            this._place(w, slot);
            return GLib.SOURCE_REMOVE;
        });
        if ([...this._pending.values()].every(l => !l.length))
            this._finishId ??= GLib.timeout_add_seconds(GLib.PRIORITY_LOW, 2, () => {
                this._finishId = null;
                this._finish();
                return GLib.SOURCE_REMOVE;
            });
    }

    _place(w, s) {
        try {
            if (!w.get_compositor_private())
                return;   // closed meanwhile
            const wm = global.workspace_manager;
            if (s.ws >= 0) {
                while (wm.n_workspaces <= s.ws)
                    wm.append_new_workspace(false, global.get_current_time());
                w.change_workspace_by_index(s.ws, false);
            }
            if (s.monitor < global.display.get_n_monitors() && w.get_monitor() !== s.monitor)
                w.move_to_monitor(s.monitor);
            if (s.max) {
                w.maximize();
            } else {
                if (w.is_maximized())
                    w.unmaximize();
                const [x, y, width, height] = s.rect;
                w.move_resize_frame(true, x, y, width, height);
            }
            if (s.min)
                w.minimize();
        } catch (e) {
            logError(e, 'bapirlo-desk: session restore placing a window');
        }
    }

    _finish() {
        if (!this._pending)
            return;
        this._pending = null;
        global.display.disconnectObject(this);
        for (const id of [this._launchId, this._extraId, this._doneId, this._finishId]) {
            if (id)
                GLib.source_remove(id);
        }
        this._launchId = this._extraId = this._doneId = 0;
        this._finishId = null;
        const tracker = Main.wm._workspaceTracker;
        tracker?.unblockUpdates();
        tracker?._queueCheckWorkspaces?.();   // tidy up workspaces that stayed empty
    }

    destroy() {
        this._finish();
        for (const id of [this._sampleId, this._askId]) {
            if (id)
                GLib.source_remove(id);
        }
        this._sampleId = this._askId = 0;
    }
}
