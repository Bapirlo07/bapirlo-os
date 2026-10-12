// Bapirlo Desk — widgets on the wallpaper (primary screen), behind every window.
//   CALENDAR  month grid, today in crimson, a dot under days with events (Google Calendar via EDS)
//   UP NEXT   the next 7 days: events + tasks due, today/tomorrow/overdue in ember
//   SYSTEM    CPU · memory · temperature · free disk, small bars
// Lives in Main.layoutManager._backgroundGroup, so windows, the desktop icons' window and the
// dock all sit above it and it never takes a click. Lightweight: stats tick every 5 s ONLY while
// the desktop on the primary screen can be seen (no fullscreen / maximised window covering it,
// not in a game); the calendar only redraws on agenda changes and at midnight.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {dayName, hhmm, label, startOfDay} from './util.js';

const TICK_S = 5;
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December'];
const MARGIN = 24;
const DOCK_CLEAR = 96;   // keep the row above the (intellihide) dock

function card(title) {
    const box = new St.BoxLayout({style_class: 'bdw-card', orientation: Clutter.Orientation.VERTICAL});
    box.add_child(label(title, 'bdw-title', false));
    return box;
}

function meter(name) {
    const row = new St.BoxLayout({style_class: 'bdw-meter', orientation: Clutter.Orientation.VERTICAL});
    const top = new St.BoxLayout({x_expand: true});
    top.add_child(label(name, 'bdw-meter-name', false));
    const value = label('–', 'bdw-meter-value', false);
    value.x_expand = true;
    value.x_align = Clutter.ActorAlign.END;
    top.add_child(value);
    const track = new St.Widget({style_class: 'bdw-track', x_expand: true, layout_manager: new Clutter.BinLayout()});
    const fill = new St.Widget({style_class: 'bdw-fill', x_expand: true, y_expand: true,
        x_align: Clutter.ActorAlign.START});
    track.add_child(fill);
    row.add_child(top);
    row.add_child(track);
    let last = 0;
    const draw = () => {
        if (track.width > 0)
            fill.width = Math.max(4, Math.round(track.width * last));
    };
    track.connect('notify::width', draw);   // the first values arrive before the first layout
    return {row, value, track, fill, set(frac, text, hot = false) {
        value.text = text;
        last = Math.min(1, Math.max(0, frac));
        draw();
        if (hot)
            fill.add_style_class_name('bdw-hot');
        else
            fill.remove_style_class_name('bdw-hot');
    }};
}

export class DeskWidgets {
    constructor(settings, agenda) {
        this._settings = settings;
        this._agenda = agenda;
        this._cancel = new Gio.Cancellable();
        this._prevCpu = null;
        this._tempPath = this._findTemp();

        this.actor = new St.BoxLayout({style_class: 'bdw-row', reactive: false});
        this._buildCalendar();
        this._buildUpNext();
        this._buildSystem();
        Main.layoutManager._backgroundGroup.add_child(this.actor);

        Main.layoutManager.connectObject('monitors-changed', () => this._place(), this);
        this._settings.connectObject('changed::widgets-corner', () => this._place(), this);
        this.actor.connectObject('notify::size', () => this._place(), this);
        // the background group gets rebuilt (wallpaper change, monitors) — stay on top of it
        Main.layoutManager._backgroundGroup.connectObject('child-added', (_g, child) => {
            if (child !== this.actor)
                Main.layoutManager._backgroundGroup.set_child_above_sibling(this.actor, null);
        }, this);
        this._agenda.connectObject('changed', () => this._syncAgenda(), this);
        this._agenda.hold();

        this._place();
        this._syncAgenda();
        this._scheduleMidnight();
        this._tick();
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, TICK_S, () => {
            this._tick();
            return GLib.SOURCE_CONTINUE;
        });
    }

    // ------------------------------------------------------------ placement
    _place() {
        const m = Main.layoutManager.primaryMonitor;
        if (!m)
            return;
        const top = Main.panel.height + MARGIN;
        const [w, h] = [this.actor.width, this.actor.height];
        const corner = this._settings.get_string('widgets-corner');
        const x = corner.endsWith('right') ? m.x + m.width - w - MARGIN : m.x + MARGIN;
        const y = corner.startsWith('top') ? m.y + top : m.y + m.height - h - DOCK_CLEAR;
        this.actor.set_position(Math.round(x), Math.round(y));
    }

    // ------------------------------------------------------------ calendar
    _buildCalendar() {
        const c = card('');
        c.add_style_class_name('bdw-calendar');
        this._calTitle = c.get_first_child();
        this._calYear = label('', 'bdw-sub', false);
        this._grid = new St.Widget({style_class: 'bdw-grid', layout_manager: new Clutter.GridLayout({
            column_homogeneous: true, row_homogeneous: true})});
        c.add_child(this._calYear);
        c.add_child(this._grid);
        this.actor.add_child(c);
    }

    _drawCalendar() {
        const now = new Date();
        const today = startOfDay(now);
        this._calTitle.text = MONTHS[now.getMonth()].toUpperCase();
        this._calYear.text = `${now.getFullYear()}`;
        this._grid.destroy_all_children();
        const gl = this._grid.layout_manager;
        ['M', 'T', 'W', 'T', 'F', 'S', 'S'].forEach((d, i) =>
            gl.attach(label(d, 'bdw-dow', false), i, 0, 1, 1));
        const first = new Date(now.getFullYear(), now.getMonth(), 1);
        const lead = (first.getDay() + 6) % 7;   // Monday first (UK)
        const start = new Date(first.getFullYear(), first.getMonth(), 1 - lead);
        const weeks = Math.ceil((lead + new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()) / 7);
        for (let i = 0; i < weeks * 7; i++) {
            const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            const cell = new St.BoxLayout({style_class: 'bdw-day', orientation: Clutter.Orientation.VERTICAL,
                x_align: Clutter.ActorAlign.CENTER});
            const num = label(`${d.getDate()}`, 'bdw-day-num', false);
            num.x_align = Clutter.ActorAlign.CENTER;
            if (d.getMonth() !== now.getMonth())
                cell.add_style_class_name('bdw-other');
            if (d.getTime() === today.getTime())
                cell.add_style_class_name('bdw-today');
            cell.add_child(num);
            const dot = new St.Widget({style_class: 'bdw-dot', x_align: Clutter.ActorAlign.CENTER,
                opacity: this._agenda.hasEventsOn(d) ? 255 : 0});
            cell.add_child(dot);
            gl.attach(cell, i % 7, 1 + Math.floor(i / 7), 1, 1);
        }
    }

    // ------------------------------------------------------------ up next
    _buildUpNext() {
        const c = card('UP NEXT');
        c.add_style_class_name('bdw-upnext');
        this._sub = label('Next 7 days', 'bdw-sub', false);
        this._list = new St.BoxLayout({style_class: 'bdw-list', orientation: Clutter.Orientation.VERTICAL});
        c.add_child(this._sub);
        c.add_child(this._list);
        this.actor.add_child(c);
    }

    _drawUpNext() {
        this._list.destroy_all_children();
        const now = new Date();
        const items = this._agenda.upcoming(7, now);
        if (!this._agenda.loaded) {
            this._list.add_child(label('Reading your calendar…', 'bdw-empty'));
            return;
        }
        if (items.length === 0) {
            this._list.add_child(label('Nothing due this week', 'bdw-empty'));
            return;
        }
        for (const it of items.slice(0, 5)) {
            const row = new St.BoxLayout({style_class: 'bdw-item'});
            const day = dayName(it.when, now);
            const chip = label(it.overdue ? 'Overdue' : day, 'bdw-chip', false);
            if (it.overdue || day === 'Today' || day === 'Tomorrow')
                chip.add_style_class_name('bdw-urgent');
            row.add_child(chip);
            const text = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, x_expand: true});
            text.add_child(label(it.summary, 'bdw-item-title'));
            text.add_child(label(it.kind === 'task' ? 'Due' : it.allDay ? 'All day' : hhmm(it.when), 'bdw-item-time', false));
            row.add_child(text);
            this._list.add_child(row);
        }
        if (items.length > 5)
            this._list.add_child(label(`+ ${items.length - 5} more`, 'bdw-more', false));
    }

    _syncAgenda() {
        this._drawCalendar();
        this._drawUpNext();
    }

    _scheduleMidnight() {
        const now = new Date();
        const next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 5);
        this._midnight = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, Math.ceil((next - now) / 1000), () => {
            this._agenda.refresh();
            this._syncAgenda();
            this._scheduleMidnight();
            return GLib.SOURCE_REMOVE;
        });
    }

    // ------------------------------------------------------------ system
    _buildSystem() {
        const c = card('SYSTEM');
        c.add_style_class_name('bdw-system');
        this._host = label(GLib.get_host_name(), 'bdw-sub', false);
        c.add_child(this._host);
        this._cpu = meter('CPU');
        this._mem = meter('Memory');
        this._temp = meter('Temperature');
        this._disk = meter('Disk free');
        for (const m of [this._cpu, this._mem, this._temp, this._disk])
            c.add_child(m.row);
        this.actor.add_child(c);
    }

    _findTemp() {
        // Intel package temperature (coretemp "Package id 0"), else the x86_pkg_temp zone
        try {
            const dir = Gio.File.new_for_path('/sys/class/hwmon');
            const en = dir.enumerate_children('standard::name', Gio.FileQueryInfoFlags.NONE, null);
            for (let info; (info = en.next_file(null));) {
                const base = `/sys/class/hwmon/${info.get_name()}`;
                const [, name] = GLib.file_get_contents(`${base}/name`);
                if (new TextDecoder().decode(name).trim() === 'coretemp')
                    return `${base}/temp1_input`;
            }
        } catch {}
        for (let i = 0; i < 16; i++) {
            try {
                const [, t] = GLib.file_get_contents(`/sys/class/thermal/thermal_zone${i}/type`);
                if (new TextDecoder().decode(t).trim() === 'x86_pkg_temp')
                    return `/sys/class/thermal/thermal_zone${i}/temp`;
            } catch {
                break;
            }
        }
        return null;
    }

    _desktopVisible() {
        if (Main.sessionMode.isLocked)
            return false;
        const primary = Main.layoutManager.primaryIndex;
        const ws = global.workspace_manager.get_active_workspace();
        // only real app windows count (DING's desktop window is a maximised DESKTOP-type window)
        return !ws.list_windows().some(w => !w.minimized && w.get_window_type() === Meta.WindowType.NORMAL &&
            w.get_monitor() === primary &&
            (w.is_fullscreen() || w.is_maximized()));
    }

    _read(path) {
        try {
            const [ok, b] = GLib.file_get_contents(path);
            return ok ? new TextDecoder().decode(b) : '';
        } catch {
            return '';
        }
    }

    _tick() {
        if (!this._desktopVisible())
            return;
        // CPU (all cores, since last tick)
        const f = this._read('/proc/stat').split('\n')[0].trim().split(/\s+/).slice(1).map(Number);
        const idle = f[3] + (f[4] ?? 0);
        const total = f.reduce((a, b) => a + b, 0);
        if (this._prevCpu) {
            const dt = total - this._prevCpu.total;
            const busy = dt > 0 ? 1 - (idle - this._prevCpu.idle) / dt : 0;
            this._cpu.set(busy, `${Math.round(busy * 100)} %`, busy > 0.85);
        }
        this._prevCpu = {idle, total};
        // memory
        const mi = {};
        for (const line of this._read('/proc/meminfo').split('\n')) {
            const [k, v] = line.split(':');
            if (v)
                mi[k] = parseInt(v, 10);
        }
        if (mi.MemTotal) {
            const used = 1 - mi.MemAvailable / mi.MemTotal;
            this._mem.set(used, `${((mi.MemTotal - mi.MemAvailable) / 1048576).toFixed(1)} / ${(mi.MemTotal / 1048576).toFixed(0)} GB`, used > 0.9);
        }
        // temperature
        if (this._tempPath) {
            const c = parseInt(this._read(this._tempPath), 10) / 1000;
            if (c > 0)
                this._temp.set((c - 30) / 70, `${Math.round(c)} °C`, c >= 85);
        } else {
            this._temp.row.hide();
        }
        // disk (async; the root filesystem)
        Gio.File.new_for_path('/').query_filesystem_info_async('filesystem::free,filesystem::size',
            GLib.PRIORITY_LOW, this._cancel, (file, res) => {
                try {
                    const info = file.query_filesystem_info_finish(res);
                    const free = info.get_attribute_uint64('filesystem::free');
                    const size = info.get_attribute_uint64('filesystem::size');
                    this._disk.set(free / size, `${(free / 1e9).toFixed(0)} GB`, free < 15e9);
                } catch {}
            });
    }

    destroy() {
        this._cancel.cancel();
        for (const id of [this._timer, this._midnight]) {
            if (id)
                GLib.source_remove(id);
        }
        this._timer = this._midnight = 0;
        this._agenda.disconnectObject(this);
        this._agenda.release();
        this._settings.disconnectObject(this);
        Main.layoutManager.disconnectObject(this);
        Main.layoutManager._backgroundGroup.disconnectObject(this);
        this.actor.destroy();
    }
}
