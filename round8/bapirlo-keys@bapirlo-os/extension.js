// Kuro Keys — Super+/ cheat sheet of every keyboard shortcut (GNOME Shell 50/51).
// Read live each time it opens, so it is never out of date:
//   · your custom shortcuts (Settings → Keyboard → Custom Shortcuts: lock, replay, Writer, Vault …)
//   · every ACTIVE extension's hotkeys: keys of its settings schema whose value is a list of
//     accelerators (in-app-only keys such as ddterm's "shortcut-*" tab keys are left out)
//   · GNOME's window / workspace / system keys: a short essentials list + everything you changed
// Type to filter · Esc, Super+/ or a click outside closes it.
// Off switch: gnome-extensions disable bapirlo-keys@bapirlo-os
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const ACCEL = /^(<[A-Za-z0-9_]+>)*[^<>\s]+$/;
const ACTIVE = 1;
// in-app shortcuts (only work inside that app) and hotkeys that are switched off by another key
const SKIP = [/^shortcut-/, /^app-(ctrl-|shift-)?hotkey-/];
const NAMES = {
    'ddterm-toggle-hotkey': 'Drop-down terminal',
    'emoji-keybind': 'Emoji picker',
    'toggle-menu': 'Clipboard history',
};
const GNOME = [
    // [schema, key, group] — always shown (current value); anything else you changed is added too
    ['org.gnome.shell.keybindings', 'toggle-overview', 'System'],
    ['org.gnome.desktop.wm.keybindings', 'panel-run-dialog', 'System'],
    ['org.gnome.shell.keybindings', 'toggle-quick-settings', 'System'],
    ['org.gnome.shell.keybindings', 'toggle-message-tray', 'System'],
    ['org.gnome.desktop.wm.keybindings', 'close', 'Windows'],
    ['org.gnome.desktop.wm.keybindings', 'minimize', 'Windows'],
    ['org.gnome.desktop.wm.keybindings', 'toggle-fullscreen', 'Windows'],
    ['org.gnome.desktop.wm.keybindings', 'move-to-workspace-left', 'Workspaces'],
    ['org.gnome.desktop.wm.keybindings', 'move-to-workspace-right', 'Workspaces'],
];
const GNOME_SCHEMAS = ['org.gnome.desktop.wm.keybindings', 'org.gnome.shell.keybindings',
    'org.gnome.mutter.keybindings', 'org.gnome.mutter.wayland.keybindings',
    'org.gnome.settings-daemon.plugins.media-keys'];
const KEY_NAMES = {
    Page_Up: 'PgUp', Page_Down: 'PgDn', KP_Prior: 'Num PgUp', KP_Next: 'Num PgDn', Return: 'Enter',
    period: '.', comma: ',', slash: '/', backslash: '\\', plus: '+', minus: '−', equal: '=',
    space: 'Space', Print: 'PrtSc', Escape: 'Esc', Left: '←', Right: '→', Up: '↑', Down: '↓',
    XF86Keyboard: 'Layout key', BackSpace: '⌫', Delete: 'Del', grave: '`', Above_Tab: '`',
};
const MODS = {Super: 'Super', Shift: 'Shift', Control: 'Ctrl', Ctrl: 'Ctrl', Primary: 'Ctrl', Alt: 'Alt', Meta: 'Meta'};

function keycaps(accel) {
    const mods = [...accel.matchAll(/<([A-Za-z0-9_]+)>/g)].map(m => MODS[m[1]] ?? m[1]);
    let key = accel.replace(/<[^>]+>/g, '');
    key = KEY_NAMES[key] ?? (key.length === 1 ? key.toUpperCase() : key.replace(/_/g, ' '));
    return [...mods, key];
}

// GNOME summaries: "Keybinding to toggle the quick settings menu." → "Toggle the quick settings menu"
function tidy(summary) {
    const s = summary.replace(/\.$/, '').replace(/^(Keybinding|Shortcut|Keyboard shortcut) (to )?/i, '');
    return s ? s[0].toUpperCase() + s.slice(1) : s;
}

function humanize(key) {
    const s = key.replace(/-/g, ' ');
    return s[0].toUpperCase() + s.slice(1);
}

function settingsFor(id, path = null) {
    const schema = Gio.SettingsSchemaSource.get_default().lookup(id, true);
    if (!schema)
        return null;
    return path ? new Gio.Settings({settings_schema: schema, path}) : new Gio.Settings({settings_schema: schema});
}

export default class BapirloKeysExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        Main.wm.addKeybinding('keys-toggle', this._settings, Meta.KeyBindingFlags.NONE,
            Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW, () => this._toggle());
    }

    disable() {
        Main.wm.removeKeybinding('keys-toggle');
        this._close(true);
        this._settings = null;
    }

    _toggle() {
        if (this._overlay)
            this._close();
        else
            this._open();
    }

    // ---------------------------------------------------------------- data
    _collect() {
        const groups = new Map();
        const add = (group, label, accels) => {
            accels = accels.filter(a => a && ACCEL.test(a));
            if (!accels.length)
                return;
            if (!groups.has(group))
                groups.set(group, []);
            if (!groups.get(group).some(r => r.label === label))
                groups.get(group).push({label, accels});
        };

        add('Kuro', 'This cheat sheet', this._settings.get_strv('keys-toggle'));

        // custom shortcuts
        const mk = settingsFor('org.gnome.settings-daemon.plugins.media-keys');
        for (const path of mk?.get_strv('custom-keybindings') ?? []) {
            const c = settingsFor('org.gnome.settings-daemon.plugins.media-keys.custom-keybinding', path);
            const name = c.get_string('name').replace(/^bapirlo-/, '');
            add('Launch & tools', name[0].toUpperCase() + name.slice(1), [c.get_string('binding')]);
        }

        // extensions
        for (const uuid of Main.extensionManager.getUuids()) {
            const ext = Main.extensionManager.lookup(uuid);
            const id = ext?.metadata?.['settings-schema'];
            if (!id || ext.state !== ACTIVE || uuid === this.uuid)
                continue;
            let schema;
            try {
                const dir = ext.dir.get_child('schemas');
                const src = dir.query_exists(null)
                    ? Gio.SettingsSchemaSource.new_from_directory(dir.get_path(), Gio.SettingsSchemaSource.get_default(), false)
                    : Gio.SettingsSchemaSource.get_default();
                schema = src.lookup(id, true);
            } catch {
                continue;
            }
            if (!schema)
                continue;
            const s = new Gio.Settings({settings_schema: schema});
            const group = uuid.endsWith('@bapirlo-os') ? 'Kuro' : 'Extensions';
            for (const key of schema.list_keys()) {
                if (SKIP.some(r => r.test(key)) || s.get_value(key).get_type_string() !== 'as')
                    continue;
                const accels = s.get_strv(key).filter(Boolean);
                if (!accels.length || !accels.every(a => ACCEL.test(a) && a.includes('<')))
                    continue;
                const summary = schema.get_key(key).get_summary();
                const label = NAMES[key] ?? (summary && tidy(summary)) ?? humanize(key);
                add(group, group === 'Extensions' ? `${label} · ${ext.metadata.name}` : label, accels);
            }
        }

        // GNOME: essentials + whatever you changed
        const gnomeGroup = (id, key) => /workspace/.test(key) ? 'Workspaces'
            : id.endsWith('media-keys') || /screenshot|screencast/.test(key) ? 'System'
                : /window|maximize|tiled|minimize|close|fullscreen|move|resize|switch-(applications|group|panels)|cycle/.test(key) ? 'Windows' : 'System';
        const schemas = new Map(GNOME_SCHEMAS.map(id => [id, settingsFor(id)]));
        const gnomeRow = (id, key, group) => {
            const s = schemas.get(id);
            if (!s || !s.settings_schema.has_key(key) || s.get_value(key).get_type_string() !== 'as')
                return;
            const summary = s.settings_schema.get_key(key).get_summary();
            add(group ?? gnomeGroup(id, key), (summary && tidy(summary)) ?? humanize(key), s.get_strv(key));
        };
        for (const [id, key, group] of GNOME)
            gnomeRow(id, key, group);
        for (const [id, s] of schemas) {
            for (const key of s?.settings_schema.list_keys() ?? []) {
                if (key !== 'custom-keybindings' && s.get_user_value(key) !== null)
                    gnomeRow(id, key);
            }
        }
        const order = ['Kuro', 'Launch & tools', 'Windows', 'Workspaces', 'System', 'Extensions'];
        return [...groups].sort((a, b) => order.indexOf(a[0]) - order.indexOf(b[0]));
    }

    // ---------------------------------------------------------------- UI
    _open() {
        let groups;
        try {
            groups = this._collect();
        } catch (e) {
            console.error(`bapirlo-keys: could not read shortcuts: ${e}`);
            return;
        }
        const mon = Main.layoutManager.primaryMonitor;
        this._overlay = new St.Widget({style_class: 'bk-overlay', reactive: true, can_focus: true,
            x: mon.x, y: mon.y, width: mon.width, height: mon.height, opacity: 0,
            layout_manager: new Clutter.BinLayout()});
        const page = new St.BoxLayout({style_class: 'bk-page', orientation: Clutter.Orientation.VERTICAL,
            x_align: Clutter.ActorAlign.CENTER, y_align: Clutter.ActorAlign.CENTER, reactive: true});
        page.set_width(Math.min(mon.width - 80, 1320));
        page.set_height(Math.min(mon.height - 80, 900));

        const head = new St.BoxLayout({style_class: 'bk-head'});
        const titles = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, x_expand: true});
        titles.add_child(new St.Label({text: 'KEYS', style_class: 'bk-title'}));
        titles.add_child(new St.Label({text: 'Every shortcut on Kuro OS · type to filter · Esc to close',
            style_class: 'bk-sub'}));
        head.add_child(titles);
        this._entry = new St.Entry({style_class: 'bk-search', hint_text: 'Filter…', can_focus: true,
            y_align: Clutter.ActorAlign.CENTER});
        this._entry.set_primary_icon(new St.Icon({icon_name: 'edit-find-symbolic', style_class: 'bk-search-icon'}));
        head.add_child(this._entry);
        page.add_child(head);

        const cols = new St.BoxLayout({style_class: 'bk-cols', x_expand: true});
        const columns = [0, 1, 2].map(() => {
            const c = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, style_class: 'bk-col', x_expand: true});
            cols.add_child(c);
            return c;
        });
        const heights = [0, 0, 0];
        this._cards = [];
        for (const [group, rows] of groups) {
            const card = new St.BoxLayout({style_class: 'bk-card', orientation: Clutter.Orientation.VERTICAL});
            card.add_child(new St.Label({text: group.toUpperCase(), style_class: 'bk-card-title'}));
            const items = rows.map(r => {
                const accels = r.accels.slice(0, 2);
                // long combos (two alternatives of 3 keys…) go on their own line under the label
                const wide = accels.reduce((n, a) => n + keycaps(a).length, 0) > 5;
                const row = new St.BoxLayout({style_class: 'bk-row',
                    orientation: wide ? Clutter.Orientation.VERTICAL : Clutter.Orientation.HORIZONTAL});
                const lbl = new St.Label({text: r.label, style_class: 'bk-label', x_expand: true,
                    y_align: Clutter.ActorAlign.CENTER});
                lbl.clutter_text.ellipsize = 3;     // END
                row.add_child(lbl);
                const caps = wide ? new St.BoxLayout({style_class: 'bk-caps', x_align: Clutter.ActorAlign.END}) : row;
                if (wide)
                    row.add_child(caps);
                accels.forEach((a, i) => {
                    if (i)
                        caps.add_child(new St.Label({text: 'or', style_class: 'bk-or', y_align: Clutter.ActorAlign.CENTER}));
                    for (const k of keycaps(a))
                        caps.add_child(new St.Label({text: k, style_class: 'bk-key', y_align: Clutter.ActorAlign.CENTER}));
                });
                card.add_child(row);
                return {row, text: `${r.label} ${r.accels.map(a => keycaps(a).join(' ')).join(' ')}`.toLowerCase()};
            });
            const i = heights.indexOf(Math.min(...heights));     // shortest column first
            columns[i].add_child(card);
            heights[i] += rows.length + 2;
            this._cards.push({card, items});
        }
        const scroll = new St.ScrollView({style_class: 'bk-scroll', x_expand: true, y_expand: true,
            hscrollbar_policy: St.PolicyType.NEVER, vscrollbar_policy: St.PolicyType.AUTOMATIC});
        scroll.set_child(cols);
        page.add_child(scroll);
        this._overlay.add_child(page);

        this._entry.clutter_text.connect('text-changed', () => this._filter(this._entry.get_text().trim().toLowerCase()));
        this._overlay.connect('button-press-event', (a, ev) => {
            const [x, y] = ev.get_coords();
            const [px, py] = page.get_transformed_position();
            const [pw, ph] = page.get_transformed_size();
            if (x < px || y < py || x > px + pw || y > py + ph)
                this._close();
            return Clutter.EVENT_STOP;
        });
        // capture phase: the filter entry's input method would otherwise type Super+/ as "/"
        this._overlay.connect('captured-event', (a, ev) =>
            ev.type() === Clutter.EventType.KEY_PRESS ? this._onKey(ev) : Clutter.EVENT_PROPAGATE);

        Main.layoutManager.addTopChrome(this._overlay);
        this._grab = Main.pushModal(this._overlay, {actionMode: Shell.ActionMode.SYSTEM_MODAL});
        this._entry.grab_key_focus();
        this._overlay.ease({opacity: 255, duration: 160, mode: Clutter.AnimationMode.EASE_OUT_QUAD});
        page.set_pivot_point(0.5, 0.5);
        page.set({scale_x: 0.96, scale_y: 0.96});
        page.ease({scale_x: 1, scale_y: 1, duration: 220, mode: Clutter.AnimationMode.EASE_OUT_BACK});
    }

    _onKey(ev) {
        const sym = ev.get_key_symbol();
        const superHeld = ev.get_state() & (Clutter.ModifierType.MOD4_MASK | Clutter.ModifierType.SUPER_MASK);
        if (sym === Clutter.KEY_Escape || (superHeld && sym === Clutter.KEY_slash)) {
            this._close();
            return Clutter.EVENT_STOP;
        }
        return Clutter.EVENT_PROPAGATE;
    }

    _filter(q) {
        for (const {card, items} of this._cards) {
            let any = false;
            for (const {row, text} of items) {
                row.visible = !q || q.split(/\s+/).every(w => text.includes(w));
                any ||= row.visible;
            }
            card.visible = any;
        }
    }

    _close(now = false) {
        const overlay = this._overlay;
        if (!overlay)
            return;
        this._overlay = null;
        this._cards = null;
        this._entry = null;
        if (this._grab) {
            Main.popModal(this._grab);
            this._grab = null;
        }
        if (now) {
            overlay.destroy();
            return;
        }
        overlay.reactive = false;
        overlay.ease({opacity: 0, duration: 140, mode: Clutter.AnimationMode.EASE_IN_QUAD,
            onStopped: () => overlay.destroy()});
    }
}
