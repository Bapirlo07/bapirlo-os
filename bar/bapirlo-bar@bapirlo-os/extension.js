// Kuro Bar — the Kuro OS top bar layout and its own pieces (GNOME Shell 50/51).
//   left:   [ArcMenu logo] [workspace numbers] (quick launch · power chip) [focused app name]
//   centre: clock + date (the Dynamic Island capsule; Do Not Disturb moon when on) · focus timer while one runs
//   right:  (media · weather · Vitals)  (updates · replay dot · fullscreen · live wallpaper · tray icons)  (Control Centre)
// Capsules: layout.js · red states + tooltips: states.js · bar over fullscreen apps: reveal.js
// Keys: Super+Shift+N / Ctrl+Super+D add a workspace · Super+Shift+W / Ctrl+Super+F4 remove the current one
//       Super+Alt+F start / stop a focus session (focus.js)
//       Super+Alt+L next bar look · right-click an empty spot on the bar picks one (looks.js)
// Also loads the wallpaper accent stylesheet written by bapirlo-autotheme
// (~/.local/state/bapirlo/accent/shell.css) and reloads it when it changes.
// Off switch: gnome-extensions disable bapirlo-bar@bapirlo-os
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {WorkspaceDots} from './workspaces.js';
import {QuickLaunch} from './launchers.js';
import {PowerChip} from './power.js';
import {ReplayDot} from './replay.js';
import {FullscreenButton} from './fullscreen.js';
import {LiveWallButton} from './livewall.js';
import {DepthButton} from './depth.js';
import {FocusTimer} from './focus.js';
import {AppName} from './appname.js';
import {CapsuleLayout} from './layout.js';
import {BarStates} from './states.js';
import {FullscreenReveal} from './reveal.js';
import {BarLooks} from './looks.js';
import {AccentPulse} from './accent.js';
import {destroyTooltip} from './util.js';

const ACCENT_CSS = GLib.build_filenamev([GLib.get_user_state_dir(), 'bapirlo', 'accent', 'shell.css']);

export default class BapirloBarExtension extends Extension {
    enable() {
        this._items = [];
        const add = (role, item, pos, box) => {
            Main.panel.addToStatusArea(`bapirlo-${role}`, item, pos, box);
            this._items.push(item);
        };

        // the workspace numbers replace the Activities button (Super opens ArcMenu,
        // clicking the active number opens the overview)
        this._activities = Main.panel.statusArea.activities?.container;
        this._activities?.hide();
        this._ws = new WorkspaceDots();
        add('ws', this._ws, -1, 'left');
        this._settings = this.getSettings();
        const keyModes = Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW;
        Main.wm.addKeybinding('add-workspace', this._settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            keyModes, () => this._ws.addWorkspace());
        Main.wm.addKeybinding('remove-workspace', this._settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            keyModes, () => this._ws.removeWorkspace());
        add('launch', new QuickLaunch(), -1, 'left');
        add('power', new PowerChip(), -1, 'left');
        add('appname', new AppName(), -1, 'left');
        add('replay', new ReplayDot(), 0, 'right');
        add('fullscreen', new FullscreenButton(), 0, 'right');
        add('livewall', new LiveWallButton(), 0, 'right');
        add('depth', new DepthButton(), 0, 'right');
        this._focus = new FocusTimer(this._settings);
        add('focus', this._focus, -1, 'center');
        Main.wm.addKeybinding('focus-toggle', this._settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            keyModes, () => this._focus.toggle());

        // panel-box placement of everyone (ours and other extensions') lives in layout.js
        this._layout = new CapsuleLayout();
        this._states = new BarStates(this._layout.capsules);
        for (const box of [Main.panel._leftBox, Main.panel._centerBox, Main.panel._rightBox])
            box.connectObject('child-added', () => this._queueRefresh(), this);
        this._reveal = new FullscreenReveal();
        this._looks = new BarLooks(this._settings);
        Main.wm.addKeybinding('next-look', this._settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            keyModes, () => this._looks.next());
        this._pulse = new AccentPulse(this._settings, this._ws);

        this._watchAccent();
    }

    // newcomers (another extension enabled later, tray icons) get their tooltip / tweaks too
    _queueRefresh() {
        if (this._refreshId)
            return;
        this._refreshId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, () => {
            this._refreshId = 0;
            this._states?.refresh();
            return GLib.SOURCE_REMOVE;
        });
    }

    _watchAccent() {
        const file = Gio.File.new_for_path(ACCENT_CSS);
        GLib.mkdir_with_parents(GLib.path_get_dirname(ACCENT_CSS), 0o755);
        this._accentMonitor = file.monitor_file(Gio.FileMonitorFlags.WATCH_MOVES, null);
        this._accentMonitor.connect('changed', (_m, _f, _o, ev) => {
            if (ev === Gio.FileMonitorEvent.CHANGES_DONE_HINT || ev === Gio.FileMonitorEvent.DELETED ||
                ev === Gio.FileMonitorEvent.MOVED_IN || ev === Gio.FileMonitorEvent.RENAMED)
                this._queueAccent();
        });
        this._loadAccent();
    }

    _queueAccent() {
        if (this._accentId)
            return;
        this._accentId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => {
            this._accentId = 0;
            this._loadAccent();
            return GLib.SOURCE_REMOVE;
        });
    }

    _loadAccent() {
        const theme = St.ThemeContext.get_for_stage(global.stage).get_theme();
        if (this._accentLoaded) {
            theme.unload_stylesheet(this._accentLoaded);
            this._accentLoaded = null;
        }
        const file = Gio.File.new_for_path(ACCENT_CSS);
        if (!file.query_exists(null))
            return;
        try {
            theme.load_stylesheet(file);
            this._accentLoaded = file;
        } catch (e) {
            logError(e, 'bapirlo-bar: accent stylesheet');
        }
    }

    disable() {
        Main.wm.removeKeybinding('add-workspace');
        Main.wm.removeKeybinding('remove-workspace');
        Main.wm.removeKeybinding('focus-toggle');
        Main.wm.removeKeybinding('next-look');
        this._pulse?.destroy();
        this._pulse = null;
        this._looks?.destroy();
        this._looks = null;
        this._focus = null;
        this._settings = null;
        this._ws = null;
        if (this._accentId)
            GLib.source_remove(this._accentId);
        this._accentId = 0;
        this._accentMonitor?.cancel();
        this._accentMonitor = null;
        if (this._accentLoaded)
            St.ThemeContext.get_for_stage(global.stage).get_theme().unload_stylesheet(this._accentLoaded);
        this._accentLoaded = null;

        if (this._refreshId)
            GLib.source_remove(this._refreshId);
        this._refreshId = 0;
        for (const box of [Main.panel._leftBox, Main.panel._centerBox, Main.panel._rightBox])
            box.disconnectObject(this);
        this._reveal?.destroy();
        this._reveal = null;
        this._states?.destroy();
        this._states = null;
        this._layout?.destroy();
        this._layout = null;
        for (const item of this._items ?? [])
            item.destroy();
        this._items = [];
        destroyTooltip();
        this._activities?.show();
        this._activities = null;
    }
}
