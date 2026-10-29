// Kuro Game Mode — automatic "game is live" handling for Kuro OS (GNOME Shell 50).
//
// LIVE = a game window exists, or OBS is recording/streaming.
//   game window: any window that went fullscreen and is not a browser / video player / editor
//                (or always: Steam games steam_app_*, Proton/Wine .exe, gamescope),
//                kept until it closes, so alt-tabbing out doesn't flap anything;
//                also any GameMode client (gamemoderun).
//   OBS:         ~/.local/state/bapirlo/obs-live exists (written by the bapirlo-dnd.lua OBS script).
// While LIVE:
//   · Do Not Disturb (notification banners off) — only if it was off; restored afterwards
//   · power-profiles-daemon holds "performance" (games only) — released afterwards, and
//     automatically by the daemon if the shell ever dies
//   · instant replay buffer (bapirlo-replay.service) runs — stopped afterwards if we started it
// Event driven (window/fullscreen signals + one file monitor): no polling, nothing per frame.
// Off switch: gnome-extensions disable bapirlo-game@bapirlo-os
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const NOT_GAMES = /chrom|firefox|brave|vivaldi|opera|epiphany|mpv|vlc|celluloid|totem|showtime|clapper|haruna|smplayer|lectern|code|jetbrains|idea|pycharm|alacritty|ptyxis|kitty|wezterm|ddterm|org\.gnome\.|obs|libreoffice|evince|papers|okular|zoom|teams|discord|vesktop|spotify|youtube|electron|gimp|inkscape|blender|krita|kdenlive|shotwell|loupe|eog|steam$|steamwebhelper/i;
const ALWAYS_GAMES = /^steam_app_|\.exe$|gamescope|^minecraft|^retroarch|^dolphin-emu|^pcsx2|^rpcs3|^yuzu|^ryujinx/i;

const STATE_DIR = GLib.build_filenamev([GLib.get_user_state_dir(), 'bapirlo']);
const OBS_FLAG = 'obs-live';
const DND_FLAG = GLib.build_filenamev([STATE_DIR, 'game-dnd']);   // "we turned DND on" (survives a shell restart)
const REPLAY_UNIT = 'bapirlo-replay.service';
const SETTLE_ON_MS = 1500;    // a game must stay fullscreen this long
const SETTLE_OFF_MS = 4000;   // and be gone this long before we undo

const PPD = 'org.freedesktop.UPower.PowerProfiles';
const PPD_PATH = '/org/freedesktop/UPower/PowerProfiles';

function windowIds(win) {
    const app = Shell.WindowTracker.get_default().get_window_app(win);
    return [win.get_wm_class(), win.get_wm_class_instance(), win.get_sandboxed_app_id(), app?.get_id()]
        .filter(Boolean).join(' ');
}

export default class BapirloGameExtension extends Extension {
    enable() {
        this._games = new Set();
        this._gameModeClients = 0;
        this._obsLive = false;
        this._live = {game: false, obs: false};
        this._holdCookie = 0;
        this._startedReplay = false;
        this._timer = 0;
        this._cancellable = new Gio.Cancellable();
        this._notif = new Gio.Settings({schema_id: 'org.gnome.desktop.notifications'});
        GLib.mkdir_with_parents(STATE_DIR, 0o755);

        // a previous session ended mid-game: put banners back
        if (GLib.file_test(DND_FLAG, GLib.FileTest.EXISTS)) {
            this._notif.set_boolean('show-banners', true);
            GLib.unlink(DND_FLAG);
        }

        global.display.connectObject(
            'in-fullscreen-changed', () => this._scan(),
            'window-created', (_d, win) => this._watchWindow(win),
            this);
        for (const actor of global.get_window_actors())
            this._watchWindow(actor.meta_window);
        this._watchObs();
        this._watchGameMode();
        this._scan();
    }

    // ---------------------------------------------------------------- detection
    _watchWindow(win) {
        if (!win || win._bapirloGameWatched)
            return;
        win._bapirloGameWatched = true;
        win.connectObject(
            'notify::fullscreen', () => this._scan(),
            'unmanaged', () => {
                this._games.delete(win);
                this._queue();
            }, this);
        // Steam/Proton games count even when windowed; wm_class may arrive a moment later
        win.connectObject('notify::wm-class', () => this._scan(), this);
    }

    _isGame(win) {
        if (win.get_window_type() !== Meta.WindowType.NORMAL)
            return false;
        const ids = windowIds(win);
        if (ALWAYS_GAMES.test(win.get_wm_class() ?? '') || ALWAYS_GAMES.test(win.get_wm_class_instance() ?? ''))
            return true;
        return win.is_fullscreen() && !NOT_GAMES.test(ids);
    }

    _scan() {
        for (const actor of global.get_window_actors()) {
            const win = actor.meta_window;
            if (!this._games.has(win) && this._isGame(win))
                this._games.add(win);
        }
        this._queue();
    }

    _watchObs() {
        this._obsLive = GLib.file_test(GLib.build_filenamev([STATE_DIR, OBS_FLAG]), GLib.FileTest.EXISTS);
        this._obsMonitor = Gio.File.new_for_path(STATE_DIR).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, null);
        this._obsMonitor.connect('changed', (_m, file) => {
            if (file.get_basename() !== OBS_FLAG)
                return;
            this._obsLive = file.query_exists(null);
            this._queue();
        });
    }

    _watchGameMode() {
        const update = () => {
            Gio.DBus.session.call('com.feralinteractive.GameMode', '/com/feralinteractive/GameMode',
                'org.freedesktop.DBus.Properties', 'Get',
                new GLib.Variant('(ss)', ['com.feralinteractive.GameMode', 'ClientCount']),
                null, Gio.DBusCallFlags.NO_AUTO_START, 2000, this._cancellable, (c, r) => {
                    try {
                        this._gameModeClients = c.call_finish(r).deepUnpack()[0].deepUnpack();
                    } catch {
                        this._gameModeClients = 0;
                    }
                    this._queue();
                });
        };
        this._gmWatch = Gio.bus_watch_name(Gio.BusType.SESSION, 'com.feralinteractive.GameMode',
            Gio.BusNameWatcherFlags.NONE, update, () => {
                this._gameModeClients = 0;
                this._queue();
            });
        this._gmSub = Gio.DBus.session.signal_subscribe('com.feralinteractive.GameMode',
            'org.freedesktop.DBus.Properties', 'PropertiesChanged', '/com/feralinteractive/GameMode',
            null, Gio.DBusSignalFlags.NONE, update);
    }

    // ---------------------------------------------------------------- state machine
    _queue() {
        const game = this._games.size > 0 || this._gameModeClients > 0;
        const obs = this._obsLive;
        if (this._timer)
            GLib.source_remove(this._timer);
        const turningOn = (game && !this._live.game) || (obs && !this._live.obs);
        this._timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, turningOn ? SETTLE_ON_MS : SETTLE_OFF_MS, () => {
            this._timer = 0;
            // re-check: the fullscreen window may have closed or left fullscreen during the wait
            for (const w of [...this._games]) {
                if (!w.get_display())
                    this._games.delete(w);
            }
            this._apply({game: this._games.size > 0 || this._gameModeClients > 0, obs: this._obsLive});
            return GLib.SOURCE_REMOVE;
        });
    }

    _apply(next) {
        const wasLive = this._live.game || this._live.obs;
        const isLive = next.game || next.obs;
        if (next.game !== this._live.game)
            next.game ? this._holdTurbo() : this._releaseTurbo();
        if (isLive !== wasLive) {
            this._setDnd(isLive);
            this._setReplay(isLive);
        }
        this._live = next;
    }

    _setDnd(on) {
        if (on) {
            if (!this._notif.get_boolean('show-banners'))
                return;    // you already had DND on — leave it to you
            this._notif.set_boolean('show-banners', false);
            GLib.file_set_contents(DND_FLAG, '1');
        } else if (GLib.file_test(DND_FLAG, GLib.FileTest.EXISTS)) {
            this._notif.set_boolean('show-banners', true);
            GLib.unlink(DND_FLAG);
        }
    }

    _holdTurbo() {
        if (this._holdCookie)
            return;
        Gio.DBus.system.call(PPD, PPD_PATH, PPD, 'HoldProfile',
            new GLib.Variant('(sss)', ['performance', 'Game running', 'bapirlo-game']),
            new GLib.VariantType('(u)'), Gio.DBusCallFlags.NONE, 5000, this._cancellable, (c, r) => {
                try {
                    [this._holdCookie] = c.call_finish(r).deepUnpack();
                    if (!this._live.game)    // game ended while we waited
                        this._releaseTurbo();
                } catch (e) {
                    logError(e, 'bapirlo-game: HoldProfile');
                }
            });
    }

    _releaseTurbo() {
        if (!this._holdCookie)
            return;
        const cookie = this._holdCookie;
        this._holdCookie = 0;
        Gio.DBus.system.call(PPD, PPD_PATH, PPD, 'ReleaseProfile', new GLib.Variant('(u)', [cookie]),
            null, Gio.DBusCallFlags.NONE, 5000, null, (c, r) => {
                try {
                    c.call_finish(r);
                } catch {}
            });
    }

    _systemd(method, unit, cb) {
        Gio.DBus.session.call('org.freedesktop.systemd1', '/org/freedesktop/systemd1',
            'org.freedesktop.systemd1.Manager', method,
            method === 'GetUnit' ? new GLib.Variant('(s)', [unit]) : new GLib.Variant('(ss)', [unit, 'replace']),
            // a stop must still go out while disable() cancels everything else
            null, Gio.DBusCallFlags.NONE, 5000, method === 'StopUnit' ? null : this._cancellable, (c, r) => {
                let res = null;
                try {
                    res = c.call_finish(r);
                } catch {}
                cb?.(res);
            });
    }

    _setReplay(on) {
        if (on) {
            // only start (and later stop) it if you hadn't started it yourself
            this._unitActive(active => {
                if (active)
                    return;
                this._systemd('StartUnit', REPLAY_UNIT, res => (this._startedReplay = !!res));
            });
        } else if (this._startedReplay) {
            this._startedReplay = false;
            this._systemd('StopUnit', REPLAY_UNIT);
        }
    }

    _unitActive(cb) {
        this._systemd('GetUnit', REPLAY_UNIT, res => {
            if (!res)
                return cb(false);   // not loaded = not running
            const [path] = res.deepUnpack();
            Gio.DBus.session.call('org.freedesktop.systemd1', path, 'org.freedesktop.DBus.Properties', 'Get',
                new GLib.Variant('(ss)', ['org.freedesktop.systemd1.Unit', 'ActiveState']),
                null, Gio.DBusCallFlags.NONE, 5000, this._cancellable, (c, r) => {
                    try {
                        cb(['active', 'activating'].includes(c.call_finish(r).deepUnpack()[0].deepUnpack()));
                    } catch {
                        cb(false);
                    }
                });
        });
    }

    disable() {
        // locking the screen disables extensions (session mode): undo everything we did
        if (this._timer)
            GLib.source_remove(this._timer);
        this._timer = 0;
        this._apply({game: false, obs: false});
        this._cancellable.cancel();
        global.display.disconnectObject(this);
        for (const actor of global.get_window_actors()) {
            actor.meta_window.disconnectObject(this);
            delete actor.meta_window._bapirloGameWatched;
        }
        this._obsMonitor?.cancel();
        this._obsMonitor = null;
        if (this._gmWatch)
            Gio.bus_unwatch_name(this._gmWatch);
        if (this._gmSub)
            Gio.DBus.session.signal_unsubscribe(this._gmSub);
        this._gmWatch = this._gmSub = 0;
        this._games.clear();
        this._notif = null;
    }
}
