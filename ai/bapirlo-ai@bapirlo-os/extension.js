// Bapirlo AI — Super+A summons a floating Claude Code terminal from anywhere.
//
//   no assistant window yet      → opens Alacritty (class "bapirlo-ai") running `claude`,
//                                  centred near the top of the monitor under the pointer
//   window exists, not focused   → brings it to this workspace + monitor, focuses it
//   window focused               → hides it (minimise) — the conversation keeps running
// When claude exits you land in a fish prompt in the same window; close the window to end it.
// Costs nothing while idle: one keybinding and one window-created listener.
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as Util from 'resource:///org/gnome/shell/misc/util.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const WM_CLASS = 'bapirlo-ai';

export default class BapirloAI extends Extension {
    enable() {
        this._settings = this.getSettings();
        Main.wm.addKeybinding('toggle', this._settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW, () => this._toggle());
        global.display.connectObject('window-created', (_d, win) => this._watch(win), this);
        this._pending = 0;
    }

    disable() {
        Main.wm.removeKeybinding('toggle');
        global.display.disconnectObject(this);
        if (this._pending)
            GLib.source_remove(this._pending);
        this._pending = 0;
        this._settings = null;
    }

    _find() {
        return global.get_window_actors().map(a => a.meta_window)
            .find(w => w.get_wm_class() === WM_CLASS);
    }

    _toggle() {
        const win = this._find();
        if (!win) {
            this._spawn();
            return;
        }
        if (win.has_focus() && !win.minimized) {
            win.minimize();
            return;
        }
        if (Main.overview.visible)
            Main.overview.hide();
        const ws = global.workspace_manager.get_active_workspace();
        if (!win.is_on_all_workspaces() && win.get_workspace() !== ws)
            win.change_workspace(ws);
        if (win.get_monitor() !== global.display.get_current_monitor())
            this._place(win);
        if (win.minimized)
            win.unminimize();
        win.activate(global.get_current_time());
    }

    _spawn() {
        if (this._pending)          // already starting — ignore a double press
            return;
        // fish: no greeting/fastfetch, not counted by the session saver, then run the assistant
        const init = 'function fish_greeting; end; functions -e __bapirlo_save_pwd; ' +
            'set -q __bapirlo_shell_file; and rm -f $__bapirlo_shell_file; ' +
            this._settings.get_string('command');
        Util.spawn(['alacritty', '--class', WM_CLASS, '--title', 'Claude · Bapirlo',
            '--working-directory', GLib.get_home_dir(), '-e', 'fish', '-C', init]);
        this._pending = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 10, () => {
            this._pending = 0;
            return GLib.SOURCE_REMOVE;
        });
    }

    _watch(win) {
        const check = () => {
            if (win.get_wm_class() !== WM_CLASS)
                return false;
            const actor = win.get_compositor_private();
            if (actor)
                actor.connectObject('first-frame', () => this._place(win), this);
            else
                this._place(win);
            return true;
        };
        if (!check()) {     // Wayland clients may set their app_id a moment later
            const id = win.connect('notify::wm-class', () => {
                if (check())
                    win.disconnect(id);
            });
            win.connect('unmanaged', () => {
                try {
                    win.disconnect(id);
                } catch {}
            });
        }
    }

    _place(win) {
        if (this._pending) {
            GLib.source_remove(this._pending);
            this._pending = 0;
        }
        const mon = global.display.get_current_monitor();
        const area = win.get_work_area_for_monitor(mon);
        const w = Math.round(area.width * this._settings.get_double('width'));
        const h = Math.round(area.height * this._settings.get_double('height'));
        if (win.is_maximized())
            win.unmaximize();
        win.move_to_monitor(mon);
        win.move_resize_frame(false, area.x + Math.round((area.width - w) / 2), area.y + 16, w, h);
        if (this._settings.get_boolean('keep-above'))
            win.make_above();
        win.activate(global.get_current_time());
    }
}
