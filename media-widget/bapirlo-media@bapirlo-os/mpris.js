// Kuro Media — MPRIS player tracking.
// One Player per org.mpris.MediaPlayer2.* bus name; PlayerManager picks the one to show.
// Position is extrapolated locally (MPRIS never signals it) and re-synced on events,
// so nothing polls D-Bus on a tight loop.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Shell from 'gi://Shell';

const PREFIX = 'org.mpris.MediaPlayer2.';
const PATH = '/org/mpris/MediaPlayer2';
const IGNORED = new Set([`${PREFIX}playerctld`]);   // mirrors other players

const RootIface = `<node><interface name="org.mpris.MediaPlayer2">
  <method name="Raise"/>
  <property name="CanRaise" type="b" access="read"/>
  <property name="Identity" type="s" access="read"/>
  <property name="DesktopEntry" type="s" access="read"/>
</interface></node>`;

const PlayerIface = `<node><interface name="org.mpris.MediaPlayer2.Player">
  <method name="Next"/>
  <method name="Previous"/>
  <method name="PlayPause"/>
  <method name="Seek"><arg direction="in" type="x" name="Offset"/></method>
  <method name="SetPosition">
    <arg direction="in" type="o" name="TrackId"/><arg direction="in" type="x" name="Position"/>
  </method>
  <signal name="Seeked"><arg type="x" name="Position"/></signal>
  <property name="PlaybackStatus" type="s" access="read"/>
  <property name="Rate" type="d" access="read"/>
  <property name="Metadata" type="a{sv}" access="read"/>
  <property name="Volume" type="d" access="readwrite"/>
  <property name="CanGoNext" type="b" access="read"/>
  <property name="CanGoPrevious" type="b" access="read"/>
  <property name="CanPlay" type="b" access="read"/>
  <property name="CanPause" type="b" access="read"/>
  <property name="CanSeek" type="b" access="read"/>
  <property name="CanControl" type="b" access="read"/>
</interface></node>`;

const RootProxy = Gio.DBusProxy.makeProxyWrapper(RootIface);
const PlayerProxy = Gio.DBusProxy.makeProxyWrapper(PlayerIface);

function unpackString(v) {
    return typeof v === 'string' ? v : '';
}

export const Player = GObject.registerClass({
    Signals: {
        'ready': {},
        'changed': {},          // status / capabilities / volume
        'track-changed': {},    // title / artist / art / length
        'seeked': {},
    },
}, class BapirloMprisPlayer extends GObject.Object {
    constructor(busName) {
        super();
        this.busName = busName;
        this.identity = busName.slice(PREFIX.length).split('.')[0];
        this.desktopEntry = '';
        this.app = null;
        this.status = 'Stopped';
        this.title = '';
        this.artists = [];
        this.artUrl = '';
        this.trackId = '';
        this.length = 0;           // µs
        this.lastActive = 0;       // monotonic µs of last switch to Playing
        this._pos = 0;
        this._posStamp = GLib.get_monotonic_time();
        this._rate = 1;
        this._ready = false;
        this._cancellable = new Gio.Cancellable();

        const flags = Gio.DBusProxyFlags.DO_NOT_AUTO_START;
        this._root = new RootProxy(Gio.DBus.session, busName, PATH, (p, e) => {
            if (e)
                return;
            this.identity = this._root.Identity || this.identity;
            this.desktopEntry = this._root.DesktopEntry || '';
            this.app = this._lookupApp();
            this.emit('changed');
        }, this._cancellable, flags);
        this._player = new PlayerProxy(Gio.DBus.session, busName, PATH, (p, e) => {
            if (e)
                return;
            this._player.connectObject('g-properties-changed',
                (_p, changed) => this._onPropsChanged(changed.deepUnpack()), this);
            this._seekedId = this._player.connectSignal('Seeked', (_p, _s, [pos]) => {
                this._setPos(Number(pos));
                this.emit('seeked');
            });
            this._readMetadata();
            this.status = this._player.PlaybackStatus || 'Stopped';
            this._rate = this._player.Rate ?? 1;
            if (this.status === 'Playing')
                this.lastActive = GLib.get_monotonic_time();
            this._ready = true;
            this.syncPosition();
            this.emit('ready');
        }, this._cancellable, flags);
    }

    get ready() {
        return this._ready;
    }

    get playing() {
        return this.status === 'Playing';
    }

    get canNext() {
        return !!this._player?.CanGoNext;
    }

    get canPrev() {
        return !!this._player?.CanGoPrevious;
    }

    get canPlayPause() {
        return !!(this._player?.CanPlay || this._player?.CanPause);
    }

    get canSeek() {
        return !!this._player?.CanSeek && this.length > 0;
    }

    // MPRIS volume, or null when the player doesn't expose a usable one
    get mprisVolume() {
        const v = this._player?.Volume;
        if (typeof v !== 'number' || !this._player.CanControl)
            return null;
        return Math.max(0, Math.min(1, v));
    }

    get position() {
        let p = this._pos;
        if (this.playing)
            p += (GLib.get_monotonic_time() - this._posStamp) * this._rate;
        return this.length > 0 ? Math.max(0, Math.min(p, this.length)) : Math.max(0, p);
    }

    _lookupApp() {
        const sys = Shell.AppSystem.get_default();
        const names = [this.desktopEntry, this.identity, this.busName.slice(PREFIX.length).split('.')[0]];
        for (const n of names.filter(Boolean)) {
            const app = sys.lookup_app(`${n}.desktop`) ?? sys.lookup_startup_wmclass(n) ??
                sys.lookup_desktop_wmclass(n);
            if (app)
                return app;
        }
        return null;
    }

    _setPos(us) {
        this._pos = us;
        this._posStamp = GLib.get_monotonic_time();
    }

    _readMetadata() {
        const md = {};
        const raw = this._player.Metadata ?? {};
        for (const k in raw)
            md[k] = raw[k].deepUnpack();
        const artists = Array.isArray(md['xesam:artist'])
            ? md['xesam:artist'].filter(a => typeof a === 'string')
            : typeof md['xesam:artist'] === 'string' ? [md['xesam:artist']] : [];
        const next = {
            title: unpackString(md['xesam:title']),
            artists,
            artUrl: unpackString(md['mpris:artUrl']),
            trackId: unpackString(md['mpris:trackid']),
            length: Number(md['mpris:length'] ?? 0) || 0,
        };
        const changed = next.title !== this.title || next.artUrl !== this.artUrl ||
            next.trackId !== this.trackId || next.artists.join() !== this.artists.join() ||
            next.length !== this.length;
        Object.assign(this, next);
        return changed;
    }

    _onPropsChanged(changed) {
        let track = false;
        if ('Metadata' in changed) {
            track = this._readMetadata();
            if (track)
                this._setPos(0);
        }
        if ('Rate' in changed)
            this._rate = this._player.Rate ?? 1;
        if ('PlaybackStatus' in changed) {
            const s = this._player.PlaybackStatus || 'Stopped';
            // freeze the extrapolated position at the moment of the change
            this._setPos(this.position);
            if (s === 'Playing' && this.status !== 'Playing')
                this.lastActive = GLib.get_monotonic_time();
            this.status = s;
        }
        if (track || 'PlaybackStatus' in changed)
            this.syncPosition();
        if (track)
            this.emit('track-changed');
        this.emit('changed');
    }

    // Position is not cached by the proxy (players don't emit it) — ask explicitly
    syncPosition() {
        Gio.DBus.session.call(this.busName, PATH, 'org.freedesktop.DBus.Properties', 'Get',
            new GLib.Variant('(ss)', ['org.mpris.MediaPlayer2.Player', 'Position']),
            null, Gio.DBusCallFlags.NONE, 1000, this._cancellable, (conn, res) => {
                try {
                    const [v] = conn.call_finish(res).deepUnpack();
                    this._setPos(Number(v.deepUnpack()));
                    this.emit('seeked');
                } catch {
                    // player has no Position (e.g. some browsers on live streams)
                }
            });
    }

    _call(method, ...args) {
        this._player?.[`${method}Async`](...args).catch(() => {});
    }

    playPause() {
        this._call('PlayPause');
    }

    next() {
        this._call('Next');
    }

    previous() {
        this._call('Previous');
    }

    seekTo(us) {
        if (!this.canSeek)
            return;
        us = Math.max(0, Math.min(Math.round(us), this.length - 1));
        if (this.trackId && this.trackId !== '/org/mpris/MediaPlayer2/TrackList/NoTrack')
            this._call('SetPosition', this.trackId, us);
        else
            this._call('Seek', Math.round(us - this.position));
        this._setPos(us);
    }

    setMprisVolume(v) {
        Gio.DBus.session.call(this.busName, PATH, 'org.freedesktop.DBus.Properties', 'Set',
            new GLib.Variant('(ssv)', ['org.mpris.MediaPlayer2.Player', 'Volume',
                new GLib.Variant('d', v)]),
            null, Gio.DBusCallFlags.NONE, 1000, this._cancellable, (c, r) => {
                try {
                    c.call_finish(r);
                } catch {}
            });
    }

    raise() {
        if (this.app)
            this.app.activate();
        else if (this._root?.CanRaise)
            this._root.RaiseAsync().catch(() => {});
    }

    destroy() {
        this._cancellable.cancel();
        if (this._player) {
            this._player.disconnectObject(this);
            if (this._seekedId)
                this._player.disconnectSignal(this._seekedId);
        }
        this._player = null;
        this._root = null;
    }
});

export const PlayerManager = GObject.registerClass({
    Signals: {
        'players-changed': {},
        'active-changed': {},
    },
}, class BapirloPlayerManager extends GObject.Object {
    constructor() {
        super();
        this._players = new Map();
        this._pinned = null;     // bus name the user switched to
        this._pinnedAt = 0;
        this._active = null;
        this._cancellable = new Gio.Cancellable();

        this._ownerSub = Gio.DBus.session.signal_subscribe('org.freedesktop.DBus',
            'org.freedesktop.DBus', 'NameOwnerChanged', '/org/freedesktop/DBus', PREFIX.slice(0, -1),
            Gio.DBusSignalFlags.MATCH_ARG0_NAMESPACE, (c, s, p, i, sig, params) => {
                const [name, oldOwner, newOwner] = params.deepUnpack();
                if (!name.startsWith(PREFIX))
                    return;
                if (oldOwner)
                    this._remove(name);
                if (newOwner)
                    this._add(name);
            });
        Gio.DBus.session.call('org.freedesktop.DBus', '/org/freedesktop/DBus',
            'org.freedesktop.DBus', 'ListNames', null, null, Gio.DBusCallFlags.NONE, -1,
            this._cancellable, (c, r) => {
                try {
                    const [names] = c.call_finish(r).deepUnpack();
                    names.filter(n => n.startsWith(PREFIX)).forEach(n => this._add(n));
                } catch {}
            });
    }

    get players() {
        return [...this._players.values()].filter(p => p.ready);
    }

    get active() {
        return this._active;
    }

    _add(name) {
        if (IGNORED.has(name) || this._players.has(name))
            return;
        const p = new Player(name);
        this._players.set(name, p);
        p.connect('ready', () => this._update(true));
        p.connect('changed', () => this._update(false));
    }

    _remove(name) {
        const p = this._players.get(name);
        if (!p)
            return;
        this._players.delete(name);
        if (this._pinned === name)
            this._pinned = null;
        p.destroy();
        this._update(true);
    }

    // most recently started player wins; a manual pick sticks until another player starts
    _pick() {
        const list = this.players;
        if (!list.length)
            return null;
        const pinned = this._pinned && this._players.get(this._pinned);
        if (pinned?.ready && !list.some(p => p !== pinned && p.playing && p.lastActive > this._pinnedAt))
            return pinned;
        this._pinned = null;
        return list.reduce((best, p) => {
            const score = q => (q.playing ? 2 : q.status === 'Paused' ? 1 : 0);
            if (score(p) !== score(best))
                return score(p) > score(best) ? p : best;
            return p.lastActive > best.lastActive ? p : best;
        });
    }

    _update(listChanged) {
        if (listChanged)
            this.emit('players-changed');
        const next = this._pick();
        if (next !== this._active) {
            this._active = next;
            this.emit('active-changed');
        }
    }

    select(player) {
        this._pinned = player.busName;
        this._pinnedAt = GLib.get_monotonic_time();
        this._update(false);
    }

    cycle(dir) {
        const list = this.players;
        if (list.length < 2)
            return;
        const i = list.indexOf(this._active);
        this.select(list[(i + dir + list.length) % list.length]);
    }

    destroy() {
        this._cancellable.cancel();
        Gio.DBus.session.signal_unsubscribe(this._ownerSub);
        for (const p of this._players.values())
            p.destroy();
        this._players.clear();
        this._active = null;
    }
});
