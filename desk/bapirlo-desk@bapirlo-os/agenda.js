// Bapirlo Desk — calendar data for the widgets and the briefing.
// bin/bapirlo-agenda (Python + libecal, Evolution Data Server = GNOME Online Accounts' Google
// Calendar/Tasks) runs as a short niced process; the shell never loads libecal itself and does
// not touch GNOME's own calendar-server range (that one belongs to the clock menu).
// Range: first day of this month → max(end of month, today + 8 days). Refreshed every 15 min
// while someone listens, and on demand.
import GLib from 'gi://GLib';

import * as Signals from 'resource:///org/gnome/shell/misc/signals.js';

import {BIN, run, startOfDay} from './util.js';

const REFRESH_S = 15 * 60;

export class Agenda extends Signals.EventEmitter {
    constructor() {
        super();
        this.events = [];      // {summary, start: Date, end: Date, allDay, calendar}
        this.tasks = [];       // {summary, due: Date}
        this.loaded = false;
        this._users = 0;
        this._busy = null;
    }

    // a part that shows calendar data holds a ref while it exists (timer only runs if someone does)
    hold() {
        if (this._users++ === 0) {
            this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, REFRESH_S, () => {
                this.refresh();
                return GLib.SOURCE_CONTINUE;
            });
        }
        if (!this.loaded)
            this.refresh();
    }

    release() {
        if (--this._users === 0 && this._timer) {
            GLib.source_remove(this._timer);
            this._timer = 0;
        }
    }

    refresh() {
        if (this._busy)
            return this._busy;
        const now = new Date();
        const from = new Date(now.getFullYear(), now.getMonth(), 1);
        const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 1);
        const soon = new Date(startOfDay(now).getTime() + 8 * 86400000);
        const to = monthEnd > soon ? monthEnd : soon;
        this._busy = run(['nice', '-n', '10', `${BIN}/bapirlo-agenda`,
            '--from', `${Math.floor(from / 1000)}`, '--to', `${Math.floor(to / 1000)}`], {timeoutS: 20})
            .then(out => {
                const data = JSON.parse(out);
                this.events = data.events.map(e => ({...e, start: new Date(e.start * 1000), end: new Date(e.end * 1000)}));
                this.tasks = data.tasks.map(t => ({...t, due: new Date(t.due * 1000)}));
                this.loaded = true;
                this.emit('changed');
            })
            .catch(e => log(`bapirlo-desk: agenda: ${e.message}`))
            .finally(() => (this._busy = null));
        return this._busy;
    }

    eventsBetween(a, b) {
        return this.events.filter(e => e.start < b && e.end > a);
    }

    // timed events and all-day items starting in [now, now + days) — plus tasks due by then
    upcoming(days, now = new Date()) {
        const end = new Date(startOfDay(now).getTime() + (days + 1) * 86400000);
        const items = this.events
            .filter(e => e.end > now && e.start < end)
            .map(e => ({summary: e.summary, when: e.start < now ? now : e.start, allDay: e.allDay, kind: 'event'}));
        for (const t of this.tasks) {
            if (t.due < end)
                items.push({summary: t.summary, when: t.due, allDay: true, kind: 'task', overdue: t.due < startOfDay(now)});
        }
        return items.sort((x, y) => x.when - y.when);
    }

    hasEventsOn(day) {
        const a = startOfDay(day);
        const b = new Date(a.getTime() + 86400000);
        return this.events.some(e => e.start < b && e.end > a) || this.tasks.some(t => t.due >= a && t.due < b);
    }

    destroy() {
        if (this._timer)
            GLib.source_remove(this._timer);
        this._timer = 0;
    }
}
