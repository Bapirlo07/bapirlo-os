// Bapirlo Media — floating now-playing card for Bapirlo OS (GNOME Shell 50).
// Off switch: gnome-extensions disable bapirlo-media@bapirlo-os
import GLib from 'gi://GLib';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {PlayerManager} from './mpris.js';
import {MediaWidget} from './widget.js';

export default class BapirloMediaExtension extends Extension {
    enable() {
        this._manager = new PlayerManager();
        this._widget = new MediaWidget(this._manager);

        // floating layer: right above all app windows, below the overview, panel menus and
        // system dialogs (the overview simply covers it)
        const ui = Main.layoutManager.uiGroup;
        // the layer itself is not reactive, so clicks around the card fall through to the apps
        ui.insert_child_above(this._widget.actor, global.window_group);

        // fade out while a fullscreen window (video, game, slideshow) is on the widget's monitor
        const queue = () => this._queueCheck();
        this._widget.onMonitorChanged = queue;   // dragged onto another monitor
        global.display.connectObject('in-fullscreen-changed', queue, this);
        global.workspace_manager.connectObject('active-workspace-changed', queue, this);
        this._queueCheck();
    }

    _queueCheck() {
        if (this._checkId)
            return;
        this._checkId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 120, () => {
            this._checkId = 0;
            this._widget?.setSuppressed(!!this._widget.monitor?.inFullscreen);
            return GLib.SOURCE_REMOVE;
        });
    }

    disable() {
        if (this._checkId) {
            GLib.source_remove(this._checkId);
            this._checkId = 0;
        }
        global.display.disconnectObject(this);
        global.workspace_manager.disconnectObject(this);
        this._widget?.destroy();
        this._widget = null;
        this._manager?.destroy();
        this._manager = null;
    }
}
