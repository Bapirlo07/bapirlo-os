// Bapirlo Desk — AirPods battery in the top bar (status capsule).
// BlueZ gives no battery for AirPods; LibrePods (AUR librepods, started hidden after login)
// talks Apple's protocol and publishes "Battery Status: Left: 80%, Right: 75%, Case: 40%" as its
// tray icon's tooltip. This chip finds that tray item on D-Bus (StatusNotifierItem.ToolTip,
// updated on NewToolTip — no polling), shows "L 80 · R 75" with a headphones icon (ember when a
// bud is ≤ 15 %), and hides LibrePods' own plain "NN%" tray icon. Click: left / right / case
// levels + noise control (Off · Transparency · Adaptive · Noise cancelling via librepods-ctl)
// + "LibrePods settings". The chip only exists while AirPods are connected and LibrePods runs.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

import {spawn} from './util.js';

const SNI = 'org.kde.StatusNotifierItem';
const MATCH = /librepods|airpods/i;
const LOW = 15;
const MODES = [['off', 'Off'], ['transparency', 'Transparency'], ['adaptive', 'Adaptive'], ['anc', 'Noise cancelling']];

// "Battery Status: Left: 80%, Right: 75%, Case: 40%" / "Headset: 60%"
export function parseBattery(text) {
    const out = {};
    for (const m of (text ?? '').matchAll(/(Left|Right|Case|Headset):\s*(\d+)%/g))
        out[m[1].toLowerCase()] = parseInt(m[2], 10);
    return Object.keys(out).length ? out : null;
}

const Chip = GObject.registerClass(
class BapirloAirPodsChip extends PanelMenu.Button {
    _init() {
        super._init(0.5, 'AirPods', false);
        this.add_style_class_name('bap-chip');
        const box = new St.BoxLayout({style_class: 'bap-box', y_align: Clutter.ActorAlign.CENTER});
        box.add_child(new St.Icon({icon_name: 'audio-headphones-symbolic', style_class: 'system-status-icon'}));
        this._text = new St.Label({style_class: 'bap-text', y_align: Clutter.ActorAlign.CENTER});
        box.add_child(this._text);
        this.add_child(box);

        this._rows = {};
        for (const [key, name] of [['left', 'Left'], ['right', 'Right'], ['case', 'Case'], ['headset', 'Headphones']]) {
            const item = new PopupMenu.PopupBaseMenuItem({reactive: false, style_class: 'bap-row'});
            item.add_child(new St.Label({text: name, style_class: 'bap-row-name', x_expand: true}));
            const track = new St.Widget({style_class: 'bap-track', layout_manager: new Clutter.BinLayout(),
                y_align: Clutter.ActorAlign.CENTER});
            const fill = new St.Widget({style_class: 'bap-fill', x_expand: true, y_expand: true,
                x_align: Clutter.ActorAlign.START});
            track.add_child(fill);
            item.add_child(track);
            const pct = new St.Label({style_class: 'bap-row-pct', y_align: Clutter.ActorAlign.CENTER});
            item.add_child(pct);
            this.menu.addMenuItem(item);
            this._rows[key] = {item, fill, pct};
        }
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem('Noise control'));
        for (const [cmd, name] of MODES)
            this.menu.addAction(name, () => spawn(['librepods-ctl', `noise:${cmd}`]));
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this.menu.addAction('LibrePods settings…', () => spawn(['librepods']));
    }

    update(b) {
        const buds = ['left', 'right'].filter(k => b[k] > 0);
        if (buds.length)
            this._text.text = buds.map(k => `${k[0].toUpperCase()} ${b[k]}`).join(' · ');
        else
            this._text.text = `${b.headset ?? b.case ?? 0}%`;
        const low = buds.some(k => b[k] <= LOW) || (b.headset !== undefined && b.headset <= LOW);
        if (low)
            this.add_style_class_name('bap-low');
        else
            this.remove_style_class_name('bap-low');
        for (const [k, r] of Object.entries(this._rows)) {
            const v = b[k];
            r.item.visible = v !== undefined && v > 0;
            r.pct.text = `${v ?? 0} %`;
            r.fill.width = Math.max(4, Math.round(84 * (v ?? 0) / 100));
            if (v <= LOW)
                r.fill.add_style_class_name('bap-low');
            else
                r.fill.remove_style_class_name('bap-low');
        }
    }
});

export class AirPodsChip {
    constructor() {
        this._chip = new Chip();
        this._chip.visible = false;
        Main.panel.addToStatusArea('bapirlo-airpods', this._chip, 0, 'right');
        this._cancel = new Gio.Cancellable();
        this._item = null;     // {bus, path, sub}
        this._hidden = new Set();
        // tray icons come and go: re-scan when the panel's right box changes
        Main.panel._rightBox.connectObject('child-added', () => this._queueScan(), 'child-removed', () => this._queueScan(), this);
        this._queueScan();
    }

    _queueScan() {
        if (this._scanId)
            return;
        this._scanId = GLib.timeout_add(GLib.PRIORITY_LOW, 300, () => {
            this._scanId = 0;
            this._scan();
            return GLib.SOURCE_REMOVE;
        });
    }

    // find LibrePods among the AppIndicator extension's tray icons
    _scan() {
        let found = null;
        for (const [role, ind] of Object.entries(Main.panel.statusArea)) {
            if (!role.startsWith('appindicator-') || !ind)
                continue;
            const app = ind._indicator;
            const tag = `${app?.id ?? ''} ${app?.title ?? ''} ${role}`;
            if (!MATCH.test(tag))
                continue;
            found = {bus: app?._proxy?.g_name ?? app?.busName, path: app?._proxy?.g_object_path ?? '/StatusNotifierItem'};
            // LibrePods' own icon (white "NN%" text) — this chip replaces it
            const c = ind.container ?? ind;
            if (c.visible) {
                c.hide();
                this._hidden.add(c);
            }
            c.connectObject('notify::visible', () => c.visible && c.hide(),
                'destroy', () => this._hidden.delete(c), this);
        }
        if (found?.bus !== this._item?.bus)
            this._follow(found);
        else if (!found)
            this._chip.visible = false;
    }

    _follow(found) {
        this._unfollow();
        this._item = found;
        if (!found?.bus) {
            this._chip.visible = false;
            return;
        }
        found.sub = Gio.DBus.session.signal_subscribe(found.bus, SNI, 'NewToolTip', found.path, null,
            Gio.DBusSignalFlags.NONE, () => this._read());
        // LibrePods quits / AirPods tray item goes away → chip goes with it
        found.watch = Gio.bus_watch_name_on_connection(Gio.DBus.session, found.bus, Gio.BusNameWatcherFlags.NONE,
            null, () => {
                this._follow(null);
                this._queueScan();
            });
        this._read();
    }

    _unfollow() {
        if (this._item?.sub)
            Gio.DBus.session.signal_unsubscribe(this._item.sub);
        if (this._item?.watch)
            Gio.bus_unwatch_name(this._item.watch);
        this._item = null;
    }

    _read() {
        const it = this._item;
        if (!it)
            return;
        Gio.DBus.session.call(it.bus, it.path, 'org.freedesktop.DBus.Properties', 'Get',
            new GLib.Variant('(ss)', [SNI, 'ToolTip']), null, Gio.DBusCallFlags.NONE, 3000, this._cancel,
            (conn, res) => {
                let b = null;
                try {
                    // ToolTip: (s icon, a(iiay) pixmaps, s title, s text)
                    const [, , title, text] = conn.call_finish(res).deepUnpack()[0].deepUnpack();
                    b = parseBattery(`${title} ${text}`);
                } catch {}
                this._chip.visible = !!b;
                if (b)
                    this._chip.update(b);
            });
    }

    destroy() {
        this._cancel.cancel();
        if (this._scanId)
            GLib.source_remove(this._scanId);
        this._scanId = 0;
        this._unfollow();
        Main.panel._rightBox.disconnectObject(this);
        for (const ind of Object.values(Main.panel.statusArea))
            (ind?.container ?? ind)?.disconnectObject?.(this);
        for (const c of this._hidden)
            c.show();
        this._hidden.clear();
        this._chip.destroy();
    }
}
