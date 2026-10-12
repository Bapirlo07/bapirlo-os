// Bapirlo Island — a Dynamic-Island-style pill in the centre of the top bar.
// Volume/brightness OSDs, notification banners, now-playing changes, charger plug/unplug and
// screenshots appear in the pill instead of GNOME's own popups.
// Game-safe: while the main screen is fullscreen nothing is intercepted (GNOME's normal behaviour,
// which already holds banners back in fullscreen), and nothing here polls — it is all signals.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as MessageTray from 'resource:///org/gnome/shell/ui/messageTray.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {Island} from './island.js';
import * as Views from './views.js';
import {PlayerManager} from './mpris.js';
import {resolveArt} from './art.js';

const UPowerIface = `<node><interface name="org.freedesktop.UPower.Device">
  <property name="State" type="u" access="read"/>
  <property name="Percentage" type="d" access="read"/>
  <property name="IsPresent" type="b" access="read"/>
  <property name="Type" type="u" access="read"/>
</interface></node>`;
const UPowerProxy = Gio.DBusProxy.makeProxyWrapper(UPowerIface);
const UP = {CHARGING: 1, DISCHARGING: 2, EMPTY: 3, FULL: 4, PENDING_CHARGE: 5, PENDING_DISCHARGE: 6};

const fullscreen = () => Main.layoutManager.primaryMonitor?.inFullscreen ?? false;

export default class BapirloIsland extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._island = new Island();
        this._island.setRestPill(this._settings.get_boolean('rest-pill'));
        this._settings.connectObject('changed::rest-pill',
            () => this._island.setRestPill(this._settings.get_boolean('rest-pill')), this);
        this._cancel = new Gio.Cancellable();
        this._on = k => this._settings.get_boolean(k);

        this._hookOsd();
        this._hookNotifications();
        this._hookMedia();
        this._hookPower();
        this._hookScreenshots();
    }

    disable() {
        this._cancel.cancel();
        this._unhookOsd();
        this._unhookNotifications();
        if (this._armId)
            GLib.source_remove(this._armId);
        this._armId = 0;
        this._players?.destroy();
        this._players = null;
        this._trackPlayer?.disconnectObject(this);
        this._trackPlayer = null;
        this._power = null;
        if (this._powerId)
            Gio.DBus.system.signal_unsubscribe(this._powerId);
        this._powerId = 0;
        Main.screenshotUI?.disconnectObject(this);
        this._shotMonitor?.cancel();
        this._shotMonitor = null;
        this._settings.disconnectObject(this);
        this._island.destroy();
        this._island = null;
        this._settings = null;
    }

    // ---------- volume / brightness OSD ----------
    _hookOsd() {
        const osd = Main.osdWindowManager;
        this._osdOrig = {show: osd.show, showAll: osd.showAll, showOne: osd.showOne};
        const take = () => this._on('osd') && !fullscreen();
        const self = this;
        osd.showAll = function (icon, label, level, maxLevel) {
            if (!take())
                return self._osdOrig.showAll.call(this, icon, label, level, maxLevel);
            return self._island.push(Views.levelView({icon, label, level, maxLevel}));
        };
        // brightness: per-monitor levels; the island shows the primary's (or the first given)
        osd.show = function (icon, label, levels) {
            if (!take())
                return self._osdOrig.show.call(this, icon, label, levels);
            const primary = Main.layoutManager.primaryIndex;
            const lv = levels[primary] ?? Object.values(levels).find(Boolean);
            return self._island.push(Views.levelView({icon, label, level: lv?.level, maxLevel: lv?.maxLevel ?? -1}));
        };
        osd.showOne = function (monitorIndex, icon, label, level, maxLevel) {
            if (!take())
                return self._osdOrig.showOne.call(this, monitorIndex, icon, label, level, maxLevel);
            return self._island.push(Views.levelView({icon, label, level, maxLevel}));
        };
    }

    _unhookOsd() {
        // the overrides are own properties shadowing the class methods — deleting them restores GNOME's
        for (const k of Object.keys(this._osdOrig ?? {}))
            delete Main.osdWindowManager[k];
        this._osdOrig = null;
    }

    // ---------- notification banners ----------
    // MessageTray only calls _showNotification when a banner may be shown (DND, fullscreen and the
    // per-app "banners" switch are already applied), so taking over there respects all of them.
    _hookNotifications() {
        const tray = Main.messageTray;
        const self = this;
        this._trayOrig = tray._showNotification;
        tray._showNotification = function () {
            const next = this._notificationQueue[0];
            if (!self._on('notifications') || fullscreen() ||
                next.urgency === MessageTray.Urgency.CRITICAL)
                return self._trayOrig.call(this);
            // drain everything that is queued into the island (it queues them itself)
            while (this._notificationQueue.length) {
                const n = this._notificationQueue.shift();
                if (n.urgency === MessageTray.Urgency.CRITICAL) {
                    this._notificationQueue.unshift(n);
                    break;
                }
                self._notify(n);
            }
            this.emit('queue-changed');
            return undefined;
        };
    }

    _notify(n) {
        // GNOME's own "Screenshot captured" banner — the screenshot view covers it
        if (this._on('screenshots') && n.source?.title === 'Screen Capture')
            return;
        this._island.push(Views.notificationView(n, {
            onClick: () => n.activate(),
            onDismiss: () => n.destroy(MessageTray.NotificationDestroyedReason.DISMISSED),
        }));
    }

    _unhookNotifications() {
        if (this._trayOrig)
            delete Main.messageTray._showNotification;   // instance override → class method again
        this._trayOrig = null;
    }

    // ---------- now playing ----------
    _hookMedia() {
        this._players = new PlayerManager();
        const follow = () => {
            this._trackPlayer?.disconnectObject(this);
            this._trackPlayer = this._players.active;
            this._trackPlayer?.connectObject(
                'track-changed', () => this._mediaChanged(),
                'changed', () => this._mediaStatus(), this);
            this._lastPlaying = this._trackPlayer?.playing ?? false;
            // a player that shows up already playing (app started, or switched to) counts as a start;
            // the very first pick at login doesn't
            if (this._lastPlaying && this._mediaArmed)
                this._mediaChanged();
        };
        this._players.connectObject('active-changed', follow, this);
        follow();
        this._mediaArmed = false;
        this._armId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 5, () => {
            this._armId = 0;
            this._mediaArmed = true;
            return GLib.SOURCE_REMOVE;
        });
    }

    _mediaStatus() {
        const p = this._trackPlayer;
        const playing = p?.playing ?? false;
        // started playing (not on pause — that's just a tap of the media key)
        if (playing && !this._lastPlaying)
            this._mediaChanged();
        this._lastPlaying = playing;
    }

    async _mediaChanged() {
        const p = this._trackPlayer;
        if (!p || !p.playing || !p.title || !this._on('media') || fullscreen())
            return;
        const key = `${p.title}\u0000${p.artists?.join()}`;
        if (key === this._lastTrack && this._island.busy)
            return;
        this._lastTrack = key;
        let art = null;
        try {
            art = await resolveArt(p.artUrl, this._cancel);
        } catch {}
        if (!this._island || this._trackPlayer !== p)
            return;
        this._island.push(Views.mediaView(p, art, {onClick: () => p.raise()}));
    }

    // ---------- charger / battery ----------
    _hookPower() {
        this._power = new UPowerProxy(Gio.DBus.system, 'org.freedesktop.UPower',
            '/org/freedesktop/UPower/devices/DisplayDevice', (proxy, error) => {
                if (error || !this._power)
                    return;
                this._powerState = proxy.State;
                this._lowShown = 100;
                proxy.connectObject('g-properties-changed', () => this._powerChanged(), this);
            }, this._cancel);
    }

    _powerChanged() {
        const p = this._power;
        if (!p?.IsPresent || !this._on('charging'))
            return;
        const state = p.State, pct = p.Percentage;
        const was = this._powerState;
        this._powerState = state;
        const plugged = s => s === UP.CHARGING || s === UP.FULL || s === UP.PENDING_CHARGE;
        const level = Math.min(100, Math.round(pct / 10) * 10);
        const lvl = String(level).padStart(3, '0');
        if (fullscreen())
            return;
        if (plugged(state) && !plugged(was)) {
            const title = state === UP.CHARGING ? 'Charging' : state === UP.FULL ? 'Fully charged' : 'Plugged in · limit reached';
            this._island.push(Views.powerView({title, percent: pct, icon: `battery-level-${lvl}-charging-symbolic`, tone: 'good'}));
            this._lowShown = 100;
        } else if (!plugged(state) && plugged(was)) {
            this._island.push(Views.powerView({title: 'On battery', percent: pct, icon: `battery-level-${lvl}-symbolic`}));
        } else if (state === UP.DISCHARGING) {
            // one nudge at 20 % and one at 10 %
            for (const mark of [10, 20]) {
                if (pct <= mark && this._lowShown > mark) {
                    this._lowShown = mark;
                    this._island.push(Views.powerView({title: mark === 10 ? 'Battery very low' : 'Battery low',
                        percent: pct, icon: `battery-level-${lvl}-symbolic`, tone: 'warn'}));
                    break;
                }
            }
        }
    }

    // ---------- screenshots ----------
    // GNOME's screenshot UI signals directly; bapirlo-capture/Satty (portal) save into
    // ~/Pictures/Screenshots, which a directory monitor picks up.
    _hookScreenshots() {
        this._shotSeen = new Map();
        Main.screenshotUI?.connectObject('screenshot-taken', (ui, file) => this._shot(file), this);
        const dir = GLib.build_filenamev([GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES) ??
            GLib.build_filenamev([GLib.get_home_dir(), 'Pictures']), 'Screenshots']);
        try {
            const f = Gio.File.new_for_path(dir);
            this._shotMonitor = f.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, this._cancel);
            this._shotMonitor.connect('changed', (m, file, other, ev) => {
                if (ev === Gio.FileMonitorEvent.CHANGES_DONE_HINT || ev === Gio.FileMonitorEvent.MOVED_IN)
                    this._shot(file);
            });
        } catch (e) {
            console.warn(`bapirlo-island: no screenshot folder monitor: ${e.message}`);
        }
    }

    _shot(file) {
        if (!file || !this._on('screenshots') || fullscreen())
            return;
        const path = file.get_path();
        if (!path || !/\.(png|jpe?g|webp)$/i.test(path))
            return;
        // the same file is reported by the signal and the monitor (and again when Satty saves edits)
        const now = GLib.get_monotonic_time();
        if (now - (this._shotSeen.get(path) ?? 0) < 15e6)
            return;
        this._shotSeen.set(path, now);
        this._island.push(Views.screenshotView(file, {
            onClick: () => Gio.AppInfo.launch_default_for_uri(file.get_uri(), null),
        }));
    }
}
