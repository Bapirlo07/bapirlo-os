// Kuro Control Centre — a Mac-style control centre for the Kuro OS top bar.
// It replaces what the quick-settings button (and Super+S) opens; GNOME's original menu is left
// intact and still opens from the "Classic" footer button or Shift+Super+S.
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {ControlCentre} from './cc.js';

export default class BapirloControlCentre extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._tries = 0;
        // the stock indicators are created asynchronously at startup
        this._waitId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 150, () => {
            const qs = Main.panel.statusArea.quickSettings;
            if (qs?._system || ++this._tries > 40) {
                this._waitId = 0;
                if (qs)
                    this._setup(qs);
                return GLib.SOURCE_REMOVE;
            }
            return GLib.SOURCE_CONTINUE;
        });
    }

    _setup(qs) {
        this._qs = qs;
        const stock = qs.menu;
        this._stock = stock;
        this._cc = new ControlCentre(qs, this._settings, {openStock: () => this._openStock()});
        Main.panel.menuManager.addMenu(this._cc);
        this._preferMenu(this._cc);
        this._cc.connect('open-state-changed', (_m, open) => {
            if (open)
                qs.add_style_pseudo_class('checked');
            else
                qs.remove_style_pseudo_class('checked');
        });

        // whatever opens the stock menu (click, Super+S, keyboard) opens the Control Centre instead
        this._allowStock = false;
        stock.open = (...args) => {
            if (this._allowStock)
                return Object.getPrototypeOf(stock).open.call(stock, ...args);
            if (this._cc.isOpen)
                this._cc.close();
            else
                this._cc.open();
            return true;
        };
        stock.connectObject('open-state-changed', (_m, open) => {
            if (!open) {
                this._allowStock = false;
                this._preferMenu(this._cc);
            }
        }, this);

        Main.wm.addKeybinding('open-classic', this._settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW | Shell.ActionMode.POPUP,
            () => (this._stock.isOpen ? this._stock.close() : this._openStock()));
    }

    // Both menus share the quick-settings button as source; the menu manager picks the FIRST one
    // it finds for hover/focus switching, so the menu in use has to come first.
    _preferMenu(menu) {
        const list = Main.panel.menuManager._menus;
        const i = list.indexOf(menu);
        if (i > 0) {
            list.splice(i, 1);
            list.unshift(menu);
        }
    }

    _openStock() {
        this._cc.close();
        this._preferMenu(this._stock);
        this._allowStock = true;
        this._stock.open();
    }

    disable() {
        if (this._waitId)
            GLib.source_remove(this._waitId);
        this._waitId = 0;
        if (this._stock) {
            delete this._stock.open;   // back to PopupMenu.prototype.open
            this._stock.disconnectObject(this);
            Main.wm.removeKeybinding('open-classic');
        }
        if (this._cc) {
            Main.panel.menuManager.removeMenu(this._cc);
            this._cc.destroy();
            this._qs?.remove_style_pseudo_class('checked');
        }
        this._cc = this._stock = this._qs = null;
        this._settings = null;
    }
}
