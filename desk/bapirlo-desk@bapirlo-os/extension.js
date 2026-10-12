// Bapirlo Desk — the "smart desktop" of Bapirlo OS (GNOME Shell 51).
//   launchpad.js  Mac-style full-screen app grid: folders, search, zoom (Super+G, dock icon)
//   widgets.js    calendar · upcoming deadlines · system stats on the wallpaper, behind windows
//   briefing.js   card a few seconds after login: greeting, weather, today, due soon, battery, updates
//   pip.js        picture-in-picture (Chrome/Firefox) + Live Captions stay on top, remember position
//   privacy.js    red/green/blue dots in the bar while mic / camera / screen sharing are in use
//   airpods.js    AirPods battery chip in the bar (from LibrePods' tray item) + noise control
// Each part follows its own setting and can be switched off alone. Nothing polls while unseen:
// the widgets tick only while the desktop can be seen, the calendar is read by a short-lived
// helper (bin/bapirlo-agenda) every 15 minutes.
// D-Bus (on the shell's own connection): /os/bapirlo/Desk os.bapirlo.Desk.Launchpad() / .Briefing()
import Gio from 'gi://Gio';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {Agenda} from './agenda.js';
import {Launchpad} from './launchpad.js';
import {DeskWidgets} from './widgets.js';
import {Briefing} from './briefing.js';
import {PipKeeper} from './pip.js';
import {PrivacyDots} from './privacy.js';
import {AirPodsChip} from './airpods.js';

const IFACE = `<node><interface name="os.bapirlo.Desk">
  <method name="Launchpad"/>
  <method name="Briefing"/>
</interface></node>`;

export default class BapirloDesk extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._agenda = new Agenda();
        this._launchpad = new Launchpad();
        this._briefing = new Briefing(this._settings, this._agenda);
        this._parts = {};

        const toggle = (key, make) => {
            const sync = () => {
                const on = this._settings.get_boolean(key);
                if (on && !this._parts[key])
                    this._parts[key] = make();
                else if (!on && this._parts[key]) {
                    this._parts[key].destroy();
                    delete this._parts[key];
                }
            };
            this._settings.connectObject(`changed::${key}`, sync, this);
            sync();
        };
        toggle('widgets', () => new DeskWidgets(this._settings, this._agenda));
        toggle('pip-on-top', () => new PipKeeper());
        toggle('privacy-dots', () => new PrivacyDots());
        toggle('airpods', () => new AirPodsChip());

        Main.wm.addKeybinding('launchpad-toggle', this._settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW, () => this._launchpad.toggle());
        Main.wm.addKeybinding('briefing-show', this._settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW, () => this._briefing.show({manual: true}));

        this._dbus = Gio.DBusExportedObject.wrapJSObject(IFACE, {
            Launchpad: () => this._launchpad.toggle(),
            Briefing: () => this._briefing.show({manual: true}),
        });
        this._dbus.export(Gio.DBus.session, '/os/bapirlo/Desk');

        // the login briefing: only when the extension comes up WITH the session (not on re-enable)
        if (Main.layoutManager._startingUp) {
            Main.layoutManager.connectObject('startup-complete', () => {
                Main.layoutManager.disconnectObject(this);
                this._briefing.scheduleLogin();
            }, this);
        }
    }

    disable() {
        Main.layoutManager.disconnectObject(this);
        this._settings.disconnectObject(this);
        Main.wm.removeKeybinding('launchpad-toggle');
        Main.wm.removeKeybinding('briefing-show');
        this._dbus?.unexport();
        this._dbus = null;
        for (const part of Object.values(this._parts))
            part.destroy();
        this._parts = {};
        this._briefing.destroy();
        this._launchpad.destroy();
        this._agenda.destroy();
        this._briefing = this._launchpad = this._agenda = null;
        this._settings = null;
    }
}
