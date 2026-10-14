// Bapirlo Live Wallpaper — GPU-drawn embers + sakura petals over the wallpaper (GNOME Shell 51).
//   effect.js   the shader (one Clutter.ShaderEffect per monitor's wallpaper actor)
// Frames are driven at the "fps" setting (30 by default), not the 240 Hz panel rate. The
// animation fades out and the timer stops whenever nobody can see it:
//   a fullscreen / maximised app window covers that monitor · the overview is open · the screen is
//   locked or the session is in the background · on battery · in power-saver (each switchable) ·
//   paused by hand (Super+Alt+W).
// While stopped only a 1 s check runs. The wallpaper itself never changes on disk.
// Off: gnome-extensions disable bapirlo-live@bapirlo-os
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {LiveEffect} from './effect.js';

const NAME = 'bapirlo-live';
const IDLE_CHECK_MS = 1000;
const FADE_S = 0.6;
const WRAP_S = 3600;        // shader time wraps hourly (float precision); hidden by the fade logic
const PARALLAX = {zoom: 1.02, max: 0.008, ease: 0.08};

function hexToRgb(hex, fallback) {
    const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim());
    const v = parseInt(m ? m[1] : fallback, 16);
    return [(v >> 16 & 255) / 255, (v >> 8 & 255) / 255, (v & 255) / 255];
}

export default class BapirloLiveExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._effects = new Map();          // monitor index → {effect, actor, amount}
        this._managers = new Set();
        this._t = 0;
        this._shift = [0, 0];
        this._lastUs = GLib.get_monotonic_time();
        this._readSettings();

        this._settings.connectObject('changed', () => {
            this._readSettings();
            this._schedule();
        }, this);
        Main.layoutManager.connectObject('monitors-changed', () => this._attachAll(), this);

        this._upower = this._proxy(Gio.DBus.system, 'org.freedesktop.UPower', '/org/freedesktop/UPower', 'org.freedesktop.UPower');
        this._ppd = this._proxy(Gio.DBus.system, 'net.hadess.PowerProfiles', '/net/hadess/PowerProfiles', 'net.hadess.PowerProfiles');
        this._login = this._proxy(Gio.DBus.system, 'org.freedesktop.login1', '/org/freedesktop/login1/session/auto', 'org.freedesktop.login1.Session');

        Main.wm.addKeybinding('live-toggle', this._settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW, () => {
                const paused = !this._settings.get_boolean('paused');
                this._settings.set_boolean('paused', paused);
                Main.osdWindowManager.showAll(Gio.ThemedIcon.new(paused ? 'media-playback-pause-symbolic' : 'weather-clear-night-symbolic'),
                    paused ? 'Live wallpaper paused' : 'Live wallpaper on', null, null);
            });

        this._attachAll();
        this._schedule();
    }

    disable() {
        Main.wm.removeKeybinding('live-toggle');
        if (this._timer)
            GLib.source_remove(this._timer);
        this._timer = 0;
        this._settings.disconnectObject(this);
        Main.layoutManager.disconnectObject(this);
        for (const mgr of this._managers)
            mgr.disconnectObject?.(this);
        this._managers.clear();
        for (const {actor, effect} of this._effects.values()) {
            if (actor.get_effect(NAME) === effect)
                actor.remove_effect(effect);
        }
        this._effects.clear();
        this._upower = this._ppd = this._login = null;
        this._settings = null;
    }

    _proxy(bus, name, path, iface) {
        try {
            return Gio.DBusProxy.new_sync(bus, Gio.DBusProxyFlags.DO_NOT_AUTO_START, null, name, path, iface, null);
        } catch {
            return null;
        }
    }

    _readSettings() {
        const s = this._settings;
        this._cfg = {
            paused: s.get_boolean('paused'),
            embers: s.get_boolean('embers'),
            petals: s.get_boolean('petals'),
            glow: s.get_boolean('glow'),
            parallax: s.get_boolean('parallax'),
            density: s.get_double('density'),
            speed: s.get_double('speed'),
            fps: s.get_int('fps'),
            emberCol: hexToRgb(s.get_string('ember-color'), 'FF4655'),
            petalCol: hexToRgb(s.get_string('petal-color'), 'F08AA4'),
            battery: s.get_boolean('pause-on-battery'),
            saver: s.get_boolean('pause-in-power-saver'),
        };
    }

    // ---------------------------------------------------------------- wallpaper actors
    _attachAll() {
        // BackgroundManager swaps in a new actor whenever the picture changes (day ↔ night): follow it
        for (const mgr of Main.layoutManager._bgManagers ?? []) {
            if (!this._managers.has(mgr)) {
                this._managers.add(mgr);
                mgr.connectObject('changed', () => this._attachAll(), this);
            }
        }
        const live = new Set(Main.layoutManager._bgManagers ?? []);
        for (const mgr of this._managers) {
            if (!live.has(mgr))
                this._managers.delete(mgr);
        }

        const seen = new Set();
        (Main.layoutManager._bgManagers ?? []).forEach((mgr, i) => {
            const actor = mgr.backgroundActor;
            if (!actor)
                return;
            seen.add(i);
            const cur = this._effects.get(i);
            if (cur?.actor === actor)
                return;
            let effect = actor.get_effect(NAME);
            if (!effect) {
                effect = new LiveEffect();
                actor.add_effect_with_name(NAME, effect);
            }
            this._effects.set(i, {actor, effect, amount: cur?.amount ?? 0});
            this._push(i);
        });
        for (const i of [...this._effects.keys()]) {
            if (!seen.has(i))
                this._effects.delete(i);
        }
        this._schedule();
    }

    // ---------------------------------------------------------------- visibility / power
    _globallyAllowed() {
        const c = this._cfg;
        if (c.paused || !(c.embers || c.petals || c.glow))
            return false;
        if (Main.sessionMode.isLocked || Main.overview.visible)
            return false;
        if (this._login?.get_cached_property('Active')?.unpack() === false)
            return false;
        if (c.battery && this._upower?.get_cached_property('OnBattery')?.unpack())
            return false;
        if (c.saver && this._ppd?.get_cached_property('ActiveProfile')?.unpack() === 'power-saver')
            return false;
        return true;
    }

    _coveredMonitors() {
        const covered = new Set();
        const ws = global.workspace_manager.get_active_workspace();
        for (const w of ws.list_windows()) {
            // only real app windows count (DING's desktop window is a maximised DESKTOP-type window)
            if (!w.minimized && w.get_window_type() === Meta.WindowType.NORMAL && w.showing_on_its_workspace?.() !== false &&
                (w.is_fullscreen() || w.is_maximized()))
                covered.add(w.get_monitor());
        }
        return covered;
    }

    // ---------------------------------------------------------------- frames
    _schedule() {
        if (!this._settings)
            return;
        const want = this._anyVisible() ? Math.round(1000 / this._cfg.fps) : IDLE_CHECK_MS;
        if (this._timer && this._interval === want)
            return;
        if (this._timer)
            GLib.source_remove(this._timer);
        this._interval = want;
        this._lastUs = GLib.get_monotonic_time();
        this._timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, want, () => {
            this._tick();
            return GLib.SOURCE_CONTINUE;
        });
        GLib.Source.set_name_by_id(this._timer, '[bapirlo-live] frame');
    }

    _anyVisible() {
        // still fading out counts as visible, so the fade finishes at full frame rate
        if (this._globallyAllowed()) {
            const covered = this._coveredMonitors();
            if ([...this._effects.keys()].some(i => !covered.has(i)))
                return true;
        }
        return [...this._effects.values()].some(e => e.amount > 0);
    }

    _tick() {
        const now = GLib.get_monotonic_time();
        const dt = Math.min((now - this._lastUs) / 1e6, 0.25);
        this._lastUs = now;

        const allowed = this._globallyAllowed();
        const covered = allowed ? this._coveredMonitors() : null;
        let moving = false;
        for (const [i, e] of this._effects) {
            const target = allowed && !covered.has(i) ? 1 : 0;
            const before = e.amount;
            if (target > e.amount)
                e.amount = Math.min(target, e.amount + dt / FADE_S);
            else if (target < e.amount)
                e.amount = Math.max(target, e.amount - dt / FADE_S);
            if (e.amount > 0)
                moving = true;
            e.dirty = e.amount !== before || e.amount > 0;
        }
        if (moving) {
            this._t = (this._t + dt * this._cfg.speed) % WRAP_S;
            this._updateParallax();
        }
        for (const [i, e] of this._effects) {
            if (e.dirty)
                this._push(i);
        }
        this._schedule();
    }

    _updateParallax() {
        let target = [0, 0];
        if (this._cfg.parallax) {
            const [px, py] = global.get_pointer();
            const m = Main.layoutManager.primaryMonitor;
            if (m) {
                const nx = Math.max(-1, Math.min(1, (px - m.x - m.width / 2) / (m.width / 2)));
                const ny = Math.max(-1, Math.min(1, (py - m.y - m.height / 2) / (m.height / 2)));
                target = [-nx * PARALLAX.max, -ny * PARALLAX.max];
            }
        }
        this._shift = this._shift.map((v, k) => v + (target[k] - v) * PARALLAX.ease);
    }

    _push(i) {
        const e = this._effects.get(i);
        if (!e)
            return;
        const c = this._cfg;
        const w = e.actor.width || 16, h = e.actor.height || 10;
        const zoom = c.parallax ? PARALLAX.zoom : 1;
        e.effect.update({
            t: this._t,
            aspect: w / h,
            amount: e.amount,
            density: c.density,
            embers: c.embers ? 1 : 0,
            petals: c.petals ? 1 : 0,
            glow: c.glow ? 1 : 0,
            zoom,
            shift: c.parallax ? this._shift : [0, 0],
            emberCol: c.emberCol,
            petalCol: c.petalCol,
        });
    }
}
