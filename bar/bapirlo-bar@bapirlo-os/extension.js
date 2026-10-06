// Bapirlo Bar — the extra top-bar pieces for Bapirlo OS (GNOME Shell 50).
//   left:  [ArcMenu logo] [workspace dots] | [quick launch] | [power chip]
//   right: [mini player] [replay dot] … the existing indicators
// Also loads the wallpaper accent stylesheet written by bapirlo-autotheme
// (~/.local/state/bapirlo/accent/shell.css) and reloads it when it changes.
// Off switch: gnome-extensions disable bapirlo-bar@bapirlo-os
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {PlayerManager} from './mpris.js';
import {WorkspaceDots} from './workspaces.js';
import {QuickLaunch} from './launchers.js';
import {MiniPlayer} from './media.js';
import {PowerChip} from './power.js';
import {ReplayDot} from './replay.js';
import {destroyTooltip} from './util.js';

const ACCENT_CSS = GLib.build_filenamev([GLib.get_user_state_dir(), 'bapirlo', 'accent', 'shell.css']);

export default class BapirloBarExtension extends Extension {
    enable() {
        this._items = [];
        const add = (role, item, pos, box) => {
            Main.panel.addToStatusArea(`bapirlo-${role}`, item, pos, box);
            this._items.push(item);
        };

        // the workspace dots replace the Activities button (Super opens ArcMenu,
        // clicking the active dot opens the overview)
        this._activities = Main.panel.statusArea.activities?.container;
        this._activities?.hide();
        add('ws', new WorkspaceDots(), -1, 'left');
        add('launch', new QuickLaunch(), -1, 'left');
        add('power', new PowerChip(), -1, 'left');

        this._players = new PlayerManager();
        add('replay', new ReplayDot(), 0, 'right');
        add('mini', new MiniPlayer(this._players), 0, 'right');
        this._front = ['mini', 'replay'].map(r => Main.panel.statusArea[`bapirlo-${r}`].container);
        // extensions enabled after us insert at index 0/1 too — keep ours first
        Main.panel._rightBox.connectObject('child-added', () => this._keepFront(), this);

        this._watchAccent();
    }

    _keepFront() {
        const box = Main.panel._rightBox;
        this._front.forEach((c, i) => {
            if (c.get_parent() === box && box.get_child_at_index(i) !== c)
                box.set_child_at_index(c, i);
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
        if (this._accentId)
            GLib.source_remove(this._accentId);
        this._accentId = 0;
        this._accentMonitor?.cancel();
        this._accentMonitor = null;
        if (this._accentLoaded)
            St.ThemeContext.get_for_stage(global.stage).get_theme().unload_stylesheet(this._accentLoaded);
        this._accentLoaded = null;

        Main.panel._rightBox.disconnectObject(this);
        this._front = [];
        for (const item of this._items ?? [])
            item.destroy();
        this._items = [];
        this._players?.destroy();
        this._players = null;
        destroyTooltip();
        this._activities?.show();
        this._activities = null;
    }
}
