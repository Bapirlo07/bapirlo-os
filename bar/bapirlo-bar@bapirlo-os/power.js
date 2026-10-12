// Bapirlo Bar — power-mode chip (power-profiles-daemon).
//   click = cycle Eco → Balanced → Turbo · right-click = open MControlCenter
//   a gamepad shows while a game holds Turbo (bapirlo-game extension)
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Pango from 'gi://Pango';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {Group, addLift, attachTooltip} from './util.js';

const BUS = 'org.freedesktop.UPower.PowerProfiles';
const PATH = '/org/freedesktop/UPower/PowerProfiles';
const Iface = `<node><interface name="${BUS}">
  <property name="ActiveProfile" type="s" access="readwrite"/>
  <property name="ActiveProfileHolds" type="aa{sv}" access="read"/>
</interface></node>`;
const Proxy = Gio.DBusProxy.makeProxyWrapper(Iface);

const ORDER = ['power-saver', 'balanced', 'performance'];
const LOOK = {
    'power-saver': {label: 'Eco', icon: 'power-profile-power-saver-symbolic', cls: 'eco'},
    'balanced': {label: 'Balanced', icon: 'power-profile-balanced-symbolic', cls: 'balanced'},
    'performance': {label: 'Turbo', icon: 'power-profile-performance-symbolic', cls: 'turbo'},
};

export const PowerChip = GObject.registerClass(
class BapirloPowerChip extends Group {
    _init() {
        super._init('Bapirlo power mode', 'bapirlo-power', true);
        this._chip = new St.Button({
            style_class: 'bapirlo-power-chip', can_focus: true, track_hover: true,
            button_mask: St.ButtonMask.ONE | St.ButtonMask.THREE,
            child: new St.BoxLayout({style_class: 'bapirlo-power-box', y_align: Clutter.ActorAlign.CENTER}),
        });
        this._icon = new St.Icon({style_class: 'bapirlo-power-icon'});
        this._label = new St.Label({style_class: 'bapirlo-power-label', y_align: Clutter.ActorAlign.CENTER});
        // short fixed words — never ellipsize them
        this._label.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;
        this._game = new St.Icon({icon_name: 'input-gaming-symbolic', style_class: 'bapirlo-power-game', visible: false});
        this._chip.child.add_child(this._icon);
        this._chip.child.add_child(this._label);
        this._chip.child.add_child(this._game);
        this.box.add_child(this._chip);
        addLift(this._chip, this._icon, 1.15);
        attachTooltip(this._chip, () => this._tooltip());
        this._chip.connect('clicked', (_b, button) => {
            if (button === Clutter.BUTTON_SECONDARY)
                Shell.AppSystem.get_default().lookup_app('mcontrolcenter.desktop')?.activate();
            else
                this._cycle();
        });

        this.visible = false;
        this._cancellable = new Gio.Cancellable();
        this._proxy = new Proxy(Gio.DBus.system, BUS, PATH, (p, e) => {
            if (e) {
                logError(e, 'bapirlo-bar: power-profiles-daemon unavailable');
                return;
            }
            this._proxy.connectObject('g-properties-changed', () => this._sync(), this);
            this._sync();
        }, this._cancellable);
    }

    get _profile() {
        return this._proxy?.ActiveProfile ?? null;
    }

    get _gameHold() {
        return (this._proxy?.ActiveProfileHolds ?? []).some(h =>
            h.ApplicationId?.deepUnpack?.() === 'bapirlo-game');
    }

    _sync() {
        const look = LOOK[this._profile];
        this.visible = !!look;
        if (!look)
            return;
        this._icon.icon_name = look.icon;
        this._label.text = look.label;
        for (const l of Object.values(LOOK))
            this._chip.remove_style_class_name(l.cls);
        this._chip.add_style_class_name(look.cls);
        this._game.visible = this._gameHold;
    }

    _tooltip() {
        const look = LOOK[this._profile];
        if (!look)
            return '';
        const hold = this._gameHold ? ' (game running)' : '';
        return `Power: ${look.label}${hold} — click to switch, right-click for MSI Control Center`;
    }

    _cycle() {
        const i = ORDER.indexOf(this._profile);
        const next = ORDER[(i + 1) % ORDER.length];
        Gio.DBus.system.call(BUS, PATH, 'org.freedesktop.DBus.Properties', 'Set',
            new GLib.Variant('(ssv)', [BUS, 'ActiveProfile', new GLib.Variant('s', next)]),
            null, Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION, 5000, this._cancellable, (c, r) => {
                try {
                    c.call_finish(r);
                } catch (e) {
                    logError(e, 'bapirlo-bar: could not set power profile');
                }
            });
    }

    destroy() {
        this._cancellable.cancel();
        this._proxy?.disconnectObject(this);
        this._proxy = null;
        super.destroy();
    }
});
