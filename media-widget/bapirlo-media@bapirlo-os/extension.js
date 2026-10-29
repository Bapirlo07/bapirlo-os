// Kuro Media — now playing for Kuro OS (GNOME Shell 50, Wayland).
//   top bar: cover + title button; click or Super+Alt+M opens the dropdown player (panel.js)
//   desktop: the floating card (widget.js) — OFF by default, setting "desktop-widget"
// Off switch:  gnome-extensions disable bapirlo-media@bapirlo-os
// Desktop card back on:  gsettings --schemadir ~/.local/share/gnome-shell/extensions/bapirlo-media@bapirlo-os/schemas \
//                          set org.gnome.shell.extensions.bapirlo-media desktop-widget true
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {PlayerManager} from './mpris.js';
import {MediaButton} from './panel.js';
import {MediaWidget} from './widget.js';

export default class BapirloMediaExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._manager = new PlayerManager();

        // role 'bapirlo-media': bapirlo-bar puts it in its place on the right (after Vitals)
        this._button = new MediaButton(this._manager, this._settings);
        Main.panel.addToStatusArea('bapirlo-media', this._button, 0, 'right');
        Main.wm.addKeybinding('toggle-panel', this._settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW | Shell.ActionMode.POPUP,
            () => this._button?.toggle());

        this._settings.connectObject('changed::desktop-widget', () => this._syncWidget(), this);
        this._syncWidget();
    }

    _syncWidget() {
        const want = this._settings.get_boolean('desktop-widget');
        if (want && !this._widget)
            this._createWidget();
        else if (!want && this._widget)
            this._destroyWidget();
    }

    _createWidget() {
        this._widget = new MediaWidget(this._manager);
        // floating layer: right above all app windows, below the overview, panel menus and
        // system dialogs (the overview simply covers it); not reactive itself, so clicks around
        // the card fall through to the apps
        Main.layoutManager.uiGroup.insert_child_above(this._widget.actor, global.window_group);

        // fade out while a fullscreen window (video, game, slideshow) is on the widget's monitor
        const queue = () => this._queueCheck();
        this._widget.onMonitorChanged = queue;   // dragged onto another monitor
        global.display.connectObject('in-fullscreen-changed', queue, this);
        global.workspace_manager.connectObject('active-workspace-changed', queue, this);
        this._queueCheck();
    }

    _destroyWidget() {
        if (this._checkId) {
            GLib.source_remove(this._checkId);
            this._checkId = 0;
        }
        global.display.disconnectObject(this);
        global.workspace_manager.disconnectObject(this);
        this._widget?.destroy();
        this._widget = null;
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
        Main.wm.removeKeybinding('toggle-panel');
        this._settings.disconnectObject(this);
        this._destroyWidget();
        this._button?.destroy();
        this._button = null;
        this._manager?.destroy();
        this._manager = null;
        this._settings = null;
    }
}
