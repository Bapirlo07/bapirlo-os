// Bapirlo Desk — the login briefing.
// A few seconds AFTER the session is up (never during login), a card slides in under the top bar
// on the right: greeting with your name · today's weather for your location (Open-Meteo, from
// ~/.config/bapirlo/location.json) · today's events · anything due in the next 3 days · battery
// · pending updates. Closes on click, Esc, or after 15 s (paused while the pointer is on it).
// Shows by itself only on the FIRST login of the day; the chip in its footer switches between
// "first login of the day" → "every login" → "off" (setting briefing-mode). Super+Alt+B shows
// it any time. Everything is fetched asynchronously at low priority after the card is already
// on screen, so it can't hold anything up; the update check is niced to the bottom.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import Soup from 'gi://Soup?version=3.0';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {HOME, dayName, hhmm, label, readJson, run, startOfDay} from './util.js';

const SHOW_MS = 15000;
const WIDTH = 400;
const MODES = {
    'first-login': 'First login of the day',
    'every-login': 'Every login',
    'off': 'Off — Super+Alt+B only',
};
const NEXT_MODE = {'first-login': 'every-login', 'every-login': 'off', 'off': 'first-login'};

// WMO weather codes (Open-Meteo) → text + GNOME weather icon
export function weatherOf(code, isDay = true) {
    const night = isDay ? '' : '-night';
    if (code === 0)
        return ['Clear', `weather-clear${night}-symbolic`];
    if (code <= 2)
        return ['Partly cloudy', `weather-few-clouds${night}-symbolic`];
    if (code === 3)
        return ['Cloudy', 'weather-overcast-symbolic'];
    if (code <= 48)
        return ['Fog', 'weather-fog-symbolic'];
    if (code <= 57)
        return ['Drizzle', 'weather-showers-scattered-symbolic'];
    if (code <= 67 || (code >= 80 && code <= 82))
        return ['Rain', 'weather-showers-symbolic'];
    if (code <= 77 || code === 85 || code === 86)
        return ['Snow', 'weather-snow-symbolic'];
    return ['Thunderstorms', 'weather-storm-symbolic'];
}

export function greeting(h) {
    if (h < 5)
        return 'Up late';
    if (h < 12)
        return 'Good morning';
    if (h < 18)
        return 'Good afternoon';
    return 'Good evening';
}

const UPOWER = 'org.freedesktop.UPower';
const BatteryProxy = Gio.DBusProxy.makeProxyWrapper(`<node><interface name="org.freedesktop.UPower.Device">
  <property name="Percentage" type="d" access="read"/>
  <property name="State" type="u" access="read"/>
  <property name="IsPresent" type="b" access="read"/>
  <property name="TimeToEmpty" type="x" access="read"/>
</interface></node>`);

export class Briefing {
    constructor(settings, agenda) {
        this._settings = settings;
        this._agenda = agenda;
        this.actor = null;
    }

    // called once, when the session finished starting
    scheduleLogin() {
        const mode = this._settings.get_string('briefing-mode');
        const today = GLib.DateTime.new_now_local().format('%F');
        if (mode === 'off' || (mode === 'first-login' && this._settings.get_string('briefing-last') === today))
            return;
        this._delay = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, this._settings.get_int('briefing-delay'), () => {
            this._delay = 0;
            // logged straight into a game / fullscreen video: don't jump in
            if (global.display.focus_window?.is_fullscreen())
                return GLib.SOURCE_REMOVE;
            this._settings.set_string('briefing-last', today);
            this.show();
            return GLib.SOURCE_REMOVE;
        });
    }

    show({manual = false} = {}) {
        if (this.actor) {
            if (manual)
                this.close();
            return;
        }
        this._cancel = new Gio.Cancellable();
        this._build();
        this._fill();
        this._grabEscape();
        this._startTimer();
    }

    // ------------------------------------------------------------ card
    _build() {
        const m = Main.layoutManager.primaryMonitor;
        const card = new St.BoxLayout({
            style_class: 'bdb-card', orientation: Clutter.Orientation.VERTICAL,
            reactive: true, track_hover: true, width: WIDTH,
        });
        this.actor = card;

        const now = new Date();
        const name = GLib.get_real_name().split(' ')[0] || GLib.get_user_name();
        card.add_child(label(`${greeting(now.getHours())}, ${name}`.toUpperCase(), 'bdb-hello', false));
        card.add_child(label(now.toLocaleDateString('en-GB', {weekday: 'long', day: 'numeric', month: 'long'}), 'bdb-date', false));

        // weather row
        const w = new St.BoxLayout({style_class: 'bdb-weather'});
        this._wIcon = new St.Icon({icon_name: 'weather-few-clouds-symbolic', style_class: 'bdb-weather-icon'});
        const wText = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, y_align: Clutter.ActorAlign.CENTER});
        this._wMain = label('Weather…', 'bdb-weather-main', false);
        this._wSub = label('', 'bdb-weather-sub');
        wText.add_child(this._wMain);
        wText.add_child(this._wSub);
        w.add_child(this._wIcon);
        w.add_child(wText);
        card.add_child(w);

        card.add_child(label('TODAY', 'bdb-section', false));
        this._today = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, style_class: 'bdb-list'});
        card.add_child(this._today);
        card.add_child(label('DUE IN THE NEXT 3 DAYS', 'bdb-section', false));
        this._due = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, style_class: 'bdb-list'});
        card.add_child(this._due);

        // battery · updates
        const stats = new St.BoxLayout({style_class: 'bdb-stats'});
        this._batIcon = new St.Icon({icon_name: 'battery-good-symbolic', style_class: 'bdb-stat-icon'});
        this._bat = label('–', 'bdb-stat', false);
        this._updIcon = new St.Icon({icon_name: 'software-update-available-symbolic', style_class: 'bdb-stat-icon'});
        this._upd = label('Checking updates…', 'bdb-stat', false);
        for (const a of [this._batIcon, this._bat, new St.Widget({style_class: 'bdb-gap'}), this._updIcon, this._upd])
            stats.add_child(a);
        card.add_child(stats);

        // footer: when it shows (does not close the card) · hint
        const foot = new St.BoxLayout({style_class: 'bdb-foot'});
        this._modeBtn = new St.Button({style_class: 'bdb-mode', can_focus: true, label: ''});
        this._syncMode();
        this._modeBtn.connect('clicked', () => {
            const next = NEXT_MODE[this._settings.get_string('briefing-mode')];
            this._settings.set_string('briefing-mode', next);
            this._syncMode();
            this._startTimer();
        });
        foot.add_child(this._modeBtn);
        const hint = label('Esc · click to close', 'bdb-hint', false);
        hint.x_expand = true;
        hint.x_align = Clutter.ActorAlign.END;
        foot.add_child(hint);
        card.add_child(foot);

        // a click anywhere on the card except the mode chip closes it
        const click = new Clutter.ClickGesture();
        click.connect('recognize', () => {
            if (!this._modeBtn.hover)
                this.close();
        });
        card.add_action(click);
        card.connect('notify::hover', () => (card.hover ? this._stopTimer() : this._startTimer()));

        Main.layoutManager.addTopChrome(card);
        const x = m.x + m.width - WIDTH - 24;
        const y = m.y + Main.panel.height + 16;
        card.set_position(x, y);
        card.opacity = 0;
        card.translation_x = WIDTH + 48;
        card.ease({translation_x: 0, opacity: 255, duration: 520, mode: Clutter.AnimationMode.EASE_OUT_EXPO});
    }

    _syncMode() {
        this._modeBtn.label = `Shows: ${MODES[this._settings.get_string('briefing-mode')]}`;
    }

    _row(list, when, text, urgent = false) {
        const row = new St.BoxLayout({style_class: 'bdb-row'});
        const t = label(when, 'bdb-when', false);
        if (urgent)
            t.add_style_class_name('bdb-urgent');
        row.add_child(t);
        const s = label(text, 'bdb-what');
        s.x_expand = true;
        row.add_child(s);
        list.add_child(row);
    }

    _drawAgenda() {
        if (!this.actor)
            return;
        this._today.destroy_all_children();
        this._due.destroy_all_children();
        const now = new Date();
        const a = startOfDay(now);
        const b = new Date(a.getTime() + 86400000);
        if (!this._agenda.loaded) {
            this._today.add_child(label('Reading your calendar…', 'bdb-empty'));
            return;
        }
        const today = this._agenda.eventsBetween(a, b).filter(e => e.end > now);
        if (today.length === 0)
            this._today.add_child(label('Nothing else on today', 'bdb-empty'));
        for (const e of today.slice(0, 4))
            this._row(this._today, e.allDay ? 'All day' : hhmm(e.start), e.summary, !e.allDay && e.start - now < 3600000);
        if (today.length > 4)
            this._today.add_child(label(`+ ${today.length - 4} more`, 'bdb-empty'));

        // due soon: from tomorrow to +3 days, and tasks due today/overdue
        const due = this._agenda.upcoming(3, now).filter(it => it.kind === 'task' || it.when >= b);
        if (due.length === 0)
            this._due.add_child(label('Nothing due — clear runway', 'bdb-empty'));
        for (const it of due.slice(0, 4)) {
            const day = it.overdue ? 'Overdue' : dayName(it.when, now);
            this._row(this._due, day, it.summary, it.overdue || day === 'Today' || day === 'Tomorrow');
        }
    }

    // ------------------------------------------------------------ data (all async, after the card is up)
    _fill() {
        this._drawAgenda();
        this._agenda.connectObject('changed', () => this._drawAgenda(), this);
        this._agenda.refresh();
        this._weather();
        this._battery();
        this._updates();
    }

    _weather() {
        const loc = readJson(`${HOME}/.config/bapirlo/location.json`, null);
        if (!loc) {
            this._wMain.text = 'No location set';
            return;
        }
        const url = `https://api.open-meteo.com/v1/forecast?latitude=${loc.lat}&longitude=${loc.lon}` +
            '&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min,' +
            'precipitation_probability_max&forecast_days=1&timezone=auto';
        const session = new Soup.Session({timeout: 10});
        const msg = Soup.Message.new('GET', url);
        session.send_and_read_async(msg, GLib.PRIORITY_LOW, this._cancel, (s, res) => {
            try {
                const bytes = s.send_and_read_finish(res);
                if (msg.get_status() !== 200)
                    throw new Error(`HTTP ${msg.get_status()}`);
                const d = JSON.parse(new TextDecoder().decode(bytes.get_data()));
                const [text, icon] = weatherOf(d.current.weather_code, d.current.is_day === 1);
                this._wIcon.icon_name = icon;
                this._wMain.text = `${Math.round(d.current.temperature_2m)}°  ${text}`;
                this._wSub.text = `${loc.name} · H ${Math.round(d.daily.temperature_2m_max[0])}°  L ${Math.round(d.daily.temperature_2m_min[0])}°` +
                    ` · rain ${d.daily.precipitation_probability_max[0] ?? 0}%`;
            } catch (e) {
                if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED)) {
                    this._wMain.text = `${loc.name}`;
                    this._wSub.text = 'Weather unavailable (offline?)';
                }
            }
        });
    }

    _battery() {
        new BatteryProxy(Gio.DBus.system, UPOWER, '/org/freedesktop/UPower/devices/DisplayDevice', (p, e) => {
            if (e || !this.actor)
                return;
            if (!p.IsPresent) {
                this._bat.text = 'On mains';
                return;
            }
            const pct = Math.round(p.Percentage);
            // 1 charging · 2 discharging · 4 fully charged · 5 pending charge (held at the 80 % limit)
            const state = {1: 'charging', 2: '', 4: 'full', 5: 'plugged in'}[p.State] ?? '';
            let extra = state;
            if (p.State === 2 && p.TimeToEmpty > 0)
                extra = `${Math.floor(p.TimeToEmpty / 3600)} h ${Math.round(p.TimeToEmpty % 3600 / 60)} min left`;
            this._bat.text = `${pct} %${extra ? ` · ${extra}` : ''}`;
            const level = pct <= 10 ? 'empty' : pct <= 30 ? 'low' : pct <= 60 ? 'good' : 'full';
            this._batIcon.icon_name = `battery-${level}${p.State === 1 ? '-charging' : ''}-symbolic`;
            if (pct <= 20 && p.State === 2)
                this._bat.add_style_class_name('bdb-urgent');
        }, this._cancel);
    }

    async _updates() {
        const count = async argv => {
            try {
                const out = await run(argv, {timeoutS: 40, cancellable: this._cancel});
                return out.split('\n').filter(l => l.trim()).length;
            } catch {
                return null;   // checkupdates exits 2 when there is nothing to update
            }
        };
        const low = ['nice', '-n', '19', 'ionice', '-c', '3'];
        const [repo, aur] = await Promise.all([
            count([...low, 'checkupdates', '--nocolor']),
            GLib.find_program_in_path('paru') ? count([...low, 'paru', '-Qua']) : Promise.resolve(0),
        ]);
        if (!this.actor)
            return;
        const n = (repo ?? 0) + (aur ?? 0);
        this._upd.text = n === 0 ? 'Up to date' : `${n} update${n > 1 ? 's' : ''} waiting`;
        if (n === 0)
            this._updIcon.icon_name = 'emblem-ok-symbolic';
    }

    // ------------------------------------------------------------ closing
    _startTimer() {
        this._stopTimer();
        this._timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, SHOW_MS, () => {
            this._timer = 0;
            this.close();
            return GLib.SOURCE_REMOVE;
        });
    }

    _stopTimer() {
        if (this._timer)
            GLib.source_remove(this._timer);
        this._timer = 0;
    }

    // Esc closes it without taking the keyboard from the app you're in: Escape is grabbed as a
    // global accelerator only for the few seconds the card is up
    _grabEscape() {
        this._escAction = global.display.grab_accelerator('Escape', Meta.KeyBindingFlags.NONE);
        if (this._escAction === Meta.KeyBindingAction.NONE) {
            this._escAction = 0;
            return;
        }
        this._escName = Meta.external_binding_name_for_action(this._escAction);
        Main.wm.allowKeybinding(this._escName, Shell.ActionMode.ALL);
        global.display.connectObject('accelerator-activated', (_d, action) => {
            if (action === this._escAction)
                this.close();
        }, this);
    }

    _ungrabEscape() {
        global.display.disconnectObject(this);
        if (this._escAction) {
            global.display.ungrab_accelerator(this._escAction);
            Main.wm.allowKeybinding(this._escName, Shell.ActionMode.NONE);
        }
        this._escAction = 0;
    }

    close() {
        if (!this.actor)
            return;
        this._stopTimer();
        this._ungrabEscape();
        this._cancel?.cancel();
        this._agenda.disconnectObject(this);
        const card = this.actor;
        this.actor = null;
        card.reactive = false;
        card.ease({translation_x: WIDTH + 48, opacity: 0, duration: 320, mode: Clutter.AnimationMode.EASE_IN_QUAD,
            onStopped: () => {
                Main.layoutManager.removeChrome(card);
                card.destroy();
            }});
    }

    destroy() {
        if (this._delay)
            GLib.source_remove(this._delay);
        this._delay = 0;
        if (this.actor) {
            const card = this.actor;
            this.close();
            card.remove_all_transitions();
            if (card.get_parent()) {
                Main.layoutManager.removeChrome(card);
                card.destroy();
            }
        }
    }
}
