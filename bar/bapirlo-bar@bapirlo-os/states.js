// Bapirlo Bar — red only where it matters, tooltips on other extensions' icons, and small fixes.
//   low battery (≤ 20 %, discharging) → battery icon + % turn ember   (.bapirlo-low-battery)
//   Do Not Disturb on, Caffeine on, screen recording / sharing → GNOME's own icon for it in the
//   system icons turns ember (.bapirlo-alert) — those icons only show while the state is on
//   instant replay → the replay dot (replay.js)
// GNOME's own power-mode gauge is taken out of the system icons: the power chip on the left
// already shows the mode (its Quick Settings toggle stays).
// Clipboard Indicator's button is hidden (layout.js); Super+V opens its menu under the
// extras capsule instead of at the hidden button.
import Gio from 'gi://Gio';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {attachTooltip} from './util.js';

const UP_BUS = 'org.freedesktop.UPower';
const UP_PATH = '/org/freedesktop/UPower/devices/DisplayDevice';
const DeviceIface = `<node><interface name="org.freedesktop.UPower.Device">
  <property name="Percentage" type="d" access="read"/>
  <property name="State" type="u" access="read"/>
  <property name="IsPresent" type="b" access="read"/>
</interface></node>`;
const DeviceProxy = Gio.DBusProxy.makeProxyWrapper(DeviceIface);
const LOW = 20;
const DISCHARGING = 2;

// role → tooltip text (only icon-only items, or items whose meaning isn't obvious)
const TIPS = {
    'ArcMenu': () => 'Start — Super',
    'quickSettings': () => 'Control Centre — Super+S · scroll for volume',
    'bapirlo-media': b => b.has_style_class_name('bmb-idle') ? 'Media — nothing playing'
        : `${b._title?.text ?? 'Media'} — middle-click to play / pause`,
    'vitalsMenu': () => 'CPU · temperature · memory (every 3 s) — click for more',
    'ArchUpdateIndicator': b => {
        const n = parseInt(b.label?.text ?? '', 10);
        return n > 0 ? `${n} update${n > 1 ? 's' : ''} available — click to see them` : 'System is up to date';
    },
};

export class BarStates {
    constructor(capsules) {
        this._caps = capsules;
        this._tipped = new Set();
        this._cancellable = new Gio.Cancellable();

        // low battery
        this._battery = new DeviceProxy(Gio.DBus.system, UP_BUS, UP_PATH, (p, e) => {
            if (e)
                return;
            this._battery.connectObject('g-properties-changed', () => this._syncBattery(), this);
            this._syncBattery();
        }, this._cancellable);

        this.refresh();
    }

    // re-run after every re-layout: indicators of other extensions come and go
    refresh() {
        this._syncBattery();
        this._hideProfileGauge();
        this._markAlerts();
        this._anchorClipboard();
        this._addTips();
    }

    _syncBattery() {
        const sys = Main.panel.statusArea.quickSettings?._system;
        if (!sys)
            return;
        const b = this._battery;
        const low = !!b?.IsPresent && b.State === DISCHARGING && b.Percentage <= LOW;
        if (low)
            sys.add_style_class_name('bapirlo-low-battery');
        else
            sys.remove_style_class_name('bapirlo-low-battery');
    }

    _hideProfileGauge() {
        const qs = Main.panel.statusArea.quickSettings;
        const gauge = qs?._powerProfiles;
        if (!gauge || this._gauge || gauge.get_parent() !== qs._indicators)
            return;
        this._gaugeIndex = qs._indicators.get_children().indexOf(gauge);
        qs._indicators.remove_child(gauge);
        this._gauge = gauge;
    }

    _markAlerts() {
        const indicators = Main.panel.statusArea.quickSettings?._indicators;
        if (!indicators)
            return;
        if (!this._indicatorsWatched) {
            indicators.connectObject('child-added', () => this._markAlerts(), this);
            this._indicatorsWatched = indicators;
        }
        for (const child of indicators.get_children()) {
            const icons = child.get_children().map(i => i.icon_name ?? '');
            if (child.constructor.name === 'Caffeine' || child.constructor.name === 'RemoteAccessApplet' ||
                icons.includes('notifications-disabled-symbolic'))
                child.add_style_class_name('bapirlo-alert');
        }
    }

    _anchorClipboard() {
        const clip = Main.panel.statusArea.clipboardIndicator;
        const bp = clip?.menu?._boxPointer;
        if (!bp || bp._bapirloSetPosition)
            return;
        const caps = this._caps;
        bp._bapirloSetPosition = bp.setPosition;
        bp.setPosition = function (actor, alignment) {
            const anchor = actor?.mapped ? actor
                : [caps.extras, caps.system].find(a => a?.mapped) ?? actor;
            return this._bapirloSetPosition(anchor, anchor === actor ? alignment : 0.5);
        };
        this._clipBoxPointer = bp;
    }

    _addTips() {
        const area = Main.panel.statusArea;
        for (const [role, text] of Object.entries(TIPS)) {
            const button = area[role];
            if (!button || this._tipped.has(button))
                continue;
            attachTooltip(button, () => text(button), this);
            this._tipped.add(button);
            button.connectObject('destroy', () => this._tipped.delete(button), this);
        }
    }

    destroy() {
        this._cancellable.cancel();
        this._battery?.disconnectObject(this);
        this._battery = null;
        Main.panel.statusArea.quickSettings?._system?.remove_style_class_name('bapirlo-low-battery');
        const indicators = Main.panel.statusArea.quickSettings?._indicators;
        if (this._gauge && indicators && !this._gauge.get_parent())
            indicators.insert_child_at_index(this._gauge, this._gaugeIndex);
        this._gauge = null;
        this._indicatorsWatched?.disconnectObject(this);
        for (const child of this._indicatorsWatched?.get_children() ?? [])
            child.remove_style_class_name('bapirlo-alert');
        this._indicatorsWatched = null;
        const bp = this._clipBoxPointer;
        if (bp?._bapirloSetPosition) {
            delete bp.setPosition;   // the prototype's method shows through again
            delete bp._bapirloSetPosition;
        }
        this._clipBoxPointer = null;
        for (const button of this._tipped) {
            button.disconnectObject(this);
            button.menu?.disconnectObject?.(this);
        }
        this._tipped.clear();
    }
}
