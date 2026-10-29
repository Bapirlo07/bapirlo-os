// Kuro Bar — switchable bar looks (GNOME Shell 51).
//   classic  the floating pill from the shell theme (nothing added)
//   manga    ink panel, paper outline, hard crimson offset shadow, Bangers app name + clock
//   glass    see-through frosted gradient, light hairline, soft shadow
//   islands  no bar: left, centre and right float as three separate pills
//   flat     classic edge-to-edge bar stuck to the top, hairline underneath
// The look is the `bar-look` setting. Switch it with: right-click an empty spot on the bar,
// Super+Alt+L (cycles), the Bar Looks app (~/bapirlo-os/bar-looks), or `bapirlo-bar-look <name|next>`.
// Colours come from Theme Studio's palette (~/.local/state/bapirlo/studio/active.json), so every
// look follows the wallpaper; the CSS is written to ~/.local/state/bapirlo/bar/look.css and
// rewritten when the palette or the look changes. Classes: #panel / #panelBox / #uiGroup .bapirlo-look-<name>.
// The bottom dock (Dash to Dock) follows the same look: leaving classic saves its colour keys to
// ~/.local/state/bapirlo/bar/dock-classic.json, going back to classic puts them back. The keys are
// only touched on a look change (not on disable / lock), so the dock never flickers.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as BoxPointer from 'resource:///org/gnome/shell/ui/boxpointer.js';

export const LOOKS = [
    ['classic', 'Classic', 'The original floating bar'],
    ['manga', 'Manga', 'Ink panel, bold outline, crimson shadow'],
    ['glass', 'Glass', 'See-through frosted bar'],
    ['islands', 'Islands', 'Three separate floating pills'],
    ['flat', 'Flat', 'Edge-to-edge bar at the top'],
];

const STATE = GLib.build_filenamev([GLib.get_user_state_dir(), 'bapirlo']);
const PALETTE = GLib.build_filenamev([STATE, 'studio', 'active.json']);
const LOOK_CSS = GLib.build_filenamev([STATE, 'bar', 'look.css']);
const DOCK_UUID = 'dash-to-dock@micxgx.gmail.com';
const DOCK_SCHEMA = 'org.gnome.shell.extensions.dash-to-dock';
const DOCK_BASELINE = GLib.build_filenamev([STATE, 'bar', 'dock-classic.json']);
const DOCK_APPLIED = GLib.build_filenamev([STATE, 'bar', 'dock-look']);
// what the dock needs for a non-classic look: no inline colour from Dash to Dock (our CSS draws it)
const dockWants = look => ({
    'custom-background-color': new GLib.Variant('b', false),
    'transparency-mode': new GLib.Variant('s', 'DEFAULT'),
    'extend-height': new GLib.Variant('b', look === 'flat'),   // flat: full-width strip
    'always-center-icons': new GLib.Variant('b', look === 'flat'),
});

function readText(path) {
    try {
        return new TextDecoder().decode(GLib.file_get_contents(path)[1]).trim();
    } catch (e) {
        return null;
    }
}

// Kuro defaults, used until Theme Studio has written a palette
const DEFAULTS = {
    ink: '#0E0A0D', night: '#161015', surface: '#251A1A', paper: '#F2E9EC', mist: '#CAB5BF',
    crimson: '#E11D2E', ember: '#FF4655',
};

export function readPalette() {
    const pal = {...DEFAULTS};
    try {
        const [, bytes] = GLib.file_get_contents(PALETTE);
        const got = JSON.parse(new TextDecoder().decode(bytes)).palette ?? {};
        for (const k of Object.keys(pal)) {
            if (/^#[0-9a-fA-F]{6}$/.test(got[k] ?? ''))
                pal[k] = got[k];
        }
    } catch (e) {
        // no Studio palette yet: Kuro defaults
    }
    return pal;
}

function cssFor(look, pal) {
    const c = (name, a = 1) => {
        const h = pal[name];
        const [r, g, b] = [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
        return a === 1 ? h : `rgba(${r}, ${g}, ${b}, ${a})`;
    };
    const bar = barCss(look, c);
    return bar && `${bar}\n${dockCss(look, c)}\n${notifCss(look, c)}`;
}

// notifications wear the look too. Here they open in the Dynamic Island (bapirlo-island, grown out
// of the bar's centre capsule); GNOME's own banner gets the same shape for when the island is off.
// The island clips to its allocation, so no offset shadows: manga uses a thick crimson edge instead.
// The shell theme styles banners with !important, so these need it as well.
function notifCss(look, c) {
    const U = `#uiGroup.bapirlo-look-${look}`;
    const box = `${U} > .bapirlo-island, ${U} .message.notification-banner`;
    const inner = `${U} > .bapirlo-island .island-notif`;
    const title = `${U} > .bapirlo-island .island-title, ${U} .notification-banner .message-title`;
    const shape = (r, body) => `${box} {\n  border-radius: ${r} !important;\n${body}}\n${inner} { border-radius: ${r}; }`;
    switch (look) {
    case 'manga': return `${shape('18px 18px 18px 4px', `  background-gradient-direction: none !important;
  background-color: ${c('ink', 0.98)} !important;
  border: 2px solid ${c('paper', 0.92)} !important;
  border-right: 5px solid ${c('crimson')} !important;
  border-bottom: 5px solid ${c('crimson')} !important;
`)}
${title} { font-family: "Bangers"; font-size: 13pt; font-weight: 400; letter-spacing: 1px; color: ${c('paper')}; }`;
    case 'glass': return shape('22px', `  background-color: ${c('night', 0.55)} !important;
  background-gradient-direction: vertical !important;
  background-gradient-start: ${c('paper', 0.20)} !important;
  background-gradient-end: ${c('paper', 0.07)} !important;
  border: 1px solid ${c('paper', 0.32)} !important;
`);
    case 'islands': return shape('28px', `  background-gradient-direction: none !important;
  background-color: ${c('ink', 0.95)} !important;
  border: 1px solid ${c('crimson', 0.34)} !important;
`);
    case 'flat': return shape('0', `  background-gradient-direction: none !important;
  background-color: ${c('night', 0.98)} !important;
  border: 0 !important;
  border-left: 3px solid ${c('crimson')} !important;
`);
    default: return '';
    }
}

// the dock (Dash to Dock) wears the same look. Its own custom colour is switched off for these
// looks (dockWants), so this CSS draws the whole background; #uiGroup carries the class because
// Dash to Dock rebuilds its dock actors whenever its settings change.
function dockCss(look, c) {
    const B = `#uiGroup.bapirlo-look-${look} #dashtodockContainer #dash .dash-background`;
    switch (look) {
    case 'manga': return `${B} {
  border-radius: 6px;
  background-color: ${c('ink', 0.97)};
  border: 2px solid ${c('paper', 0.92)};
  box-shadow: 5px 5px 0 ${c('crimson')};
}`;
    case 'glass': return `${B} {
  border-radius: 22px;
  background-gradient-direction: vertical;
  background-gradient-start: ${c('paper', 0.20)};
  background-gradient-end: ${c('paper', 0.07)};
  border: 1px solid ${c('paper', 0.30)};
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.28);
}`;
    case 'islands': return `${B} {
  border-radius: 999px;
  background-color: ${c('ink', 0.90)};
  border: 1px solid ${c('crimson', 0.30)};
  box-shadow: 0 6px 18px rgba(0, 0, 0, 0.38);
}`;
    case 'flat': return `${B} {
  border-radius: 0;
  background-color: ${c('night', 0.97)};
  border-width: 1px 0 0 0;
  border-color: ${c('crimson', 0.38)};
  box-shadow: 0 -2px 10px rgba(0, 0, 0, 0.35);
}`;
    default: return '';
    }
}

function barCss(look, c) {
    const P = `#panel.bapirlo-look-${look}`;
    // every look still goes clear in the overview / on the lock and login screens
    const clear = `
${P}:overview, ${P}.unlock-screen, ${P}.login-screen {
  background-gradient-direction: none;
  background-color: transparent;
  border-color: transparent;
  box-shadow: none;
}`;
    switch (look) {
    case 'manga': return `${clear}
#panelBox.bapirlo-look-manga { padding: 6px 13px 0 8px; }   /* room for the offset shadow */
${P} {
  border-radius: 6px;
  background-color: ${c('ink', 0.97)};
  border: 2px solid ${c('paper', 0.92)};
  box-shadow: 5px 5px 0 ${c('crimson')};
}
${P} .panel-button { border-radius: 4px; }
${P} .panel-button:hover, ${P} .panel-button:focus { box-shadow: inset 0 0 0 100px ${c('paper', 0.14)}; }
${P} .panel-button:active, ${P} .panel-button:checked,
${P} .panel-button:active:hover, ${P} .panel-button:checked:hover { box-shadow: inset 0 0 0 100px ${c('crimson', 0.55)}; }
${P} .bapirlo-capsule {
  border-radius: 4px;
  background-color: ${c('paper', 0.05)};
  border: 1px solid ${c('paper', 0.38)};
}
${P} .bapirlo-capsule .panel-button { border-radius: 3px; }
${P} .bapirlo-ws-dot { border-radius: 3px; }
${P} .bapirlo-ws-dot.active { border: 1px solid ${c('paper', 0.9)}; }
${P} .bapirlo-appname-label {
  font-family: Bangers, sans-serif;   /* St: one quoted family max, else the rule is dropped */
  font-weight: normal;
  font-size: 14pt;   /* no letter-spacing here: St leaves it out of the width, so the name gets cut */
  max-width: 260px;
}
${P} .clock { font-family: Bangers, sans-serif;   /* St: one quoted family max, else the rule is dropped */ font-weight: normal; font-size: 14pt; letter-spacing: 1px; }
${P} #panelCenter.bapirlo-island-rest {
  border-radius: 4px;
  background-color: ${c('ink')};
  border: 2px solid ${c('crimson')};
  box-shadow: none;
}`;
    case 'glass': return `${clear}
${P} {
  border-radius: 18px;
  background-gradient-direction: vertical;
  background-gradient-start: ${c('paper', 0.20)};
  background-gradient-end: ${c('paper', 0.07)};
  border: 1px solid ${c('paper', 0.30)};
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.28);
}
${P} .panel-button { text-shadow: 0 1px 3px rgba(0, 0, 0, 0.75); }
${P} .panel-button StIcon, ${P} .panel-button .system-status-icon { icon-shadow: 0 1px 3px rgba(0, 0, 0, 0.75); }
${P} .panel-button:hover, ${P} .panel-button:focus { box-shadow: inset 0 0 0 100px ${c('paper', 0.18)}; }
${P} .panel-button:active, ${P} .panel-button:checked,
${P} .panel-button:active:hover, ${P} .panel-button:checked:hover { box-shadow: inset 0 0 0 100px ${c('paper', 0.28)}; }
${P} .bapirlo-capsule {
  background-color: ${c('paper', 0.10)};
  border: 1px solid ${c('paper', 0.18)};
}
${P} .bapirlo-ws-num, ${P} .bapirlo-appname-label { text-shadow: 0 1px 3px rgba(0, 0, 0, 0.75); }
${P} #panelCenter.bapirlo-island-rest {
  background-color: ${c('ink', 0.38)};
  border: 1px solid ${c('paper', 0.24)};
  box-shadow: none;
}`;
    case 'islands': {
        const pill = `
  background-color: ${c('ink', 0.90)};
  border: 1px solid ${c('crimson', 0.30)};
  border-radius: 16px;
  box-shadow: 0 6px 18px rgba(0, 0, 0, 0.38);`;
        return `${clear}
${P} {
  background-color: transparent;
  border-color: transparent;
  box-shadow: none;
}
${P} #panelLeft { ${pill} padding: 0 4px 0 3px; }
${P} #panelRight { ${pill} padding: 0 3px 0 4px; }
${P} #panelCenter, ${P} #panelCenter.bapirlo-island-rest { ${pill} margin: 0; padding: 0 10px; }
${P}:overview #panelLeft, ${P}:overview #panelRight, ${P}:overview #panelCenter,
${P}:overview #panelCenter.bapirlo-island-rest {
  background-color: transparent;
  border-color: transparent;
  box-shadow: none;
}`;
    }
    case 'flat': return `${clear}
#panelBox.bapirlo-look-flat { padding: 0; }
${P} {
  height: 40px !important;
  border-radius: 0;
  border-width: 0 0 1px 0;
  border-color: ${c('crimson', 0.38)};
  background-color: ${c('night', 0.97)};
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.35);
}
${P} .panel-button { border-radius: 8px; margin: 4px 1px; }
${P} .bapirlo-capsule { border-radius: 8px; margin: 4px 0; }
${P} .bapirlo-capsule .panel-button { border-radius: 6px; }
${P} #panelCenter.bapirlo-island-rest {
  border-radius: 8px;
  margin: 4px 0;
  background-color: ${c('paper', 0.06)};
  border: 1px solid ${c('paper', 0.10)};
  box-shadow: none;
}`;
    default: return '';
    }
}

export class BarLooks {
    constructor(settings) {
        this._settings = settings;
        this._look = null;
        this._loaded = null;
        this._menu = null;
        this._menuManager = new PopupMenu.PopupMenuManager(Main.panel);

        settings.connectObject('changed::bar-look', () => this._apply(), this);
        this._palMonitor = Gio.File.new_for_path(PALETTE).monitor_file(Gio.FileMonitorFlags.WATCH_MOVES, null);
        this._palMonitor.connect('changed', () => this._queueApply());
        // right-click on an empty spot of the bar (not on a button) opens the look menu.
        // captured-event: the panel's own click gesture takes the press before button-press-event
        Main.panel.connectObject('captured-event', (_a, ev) => {
            if (ev.type() !== Clutter.EventType.BUTTON_PRESS || ev.get_button() !== Clutter.BUTTON_SECONDARY ||
                !this._isBarBackground(global.stage.get_event_actor(ev)))
                return Clutter.EVENT_PROPAGATE;
            this._openMenu(...ev.get_coords());
            return Clutter.EVENT_STOP;
        }, this);
        this._apply();
    }

    _isBarBackground(actor) {
        const p = Main.panel;
        return actor === p || actor === p._leftBox || actor === p._centerBox || actor === p._rightBox ||
            actor?.has_style_class_name?.('bapirlo-capsule');
    }

    get look() {
        const look = this._settings.get_string('bar-look');
        return LOOKS.some(([id]) => id === look) ? look : 'classic';
    }

    next() {
        const i = LOOKS.findIndex(([id]) => id === this.look);
        this._settings.set_string('bar-look', LOOKS[(i + 1) % LOOKS.length][0]);
        this._flash();
    }

    _queueApply() {
        if (this._applyId)
            return;
        this._applyId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 400, () => {
            this._applyId = 0;
            this._apply();
            return GLib.SOURCE_REMOVE;
        });
    }

    _apply() {
        const look = this.look;
        if (look !== this._look)
            this._applyDock(look);
        for (const actor of [Main.panel, Main.layoutManager.panelBox, Main.uiGroup]) {
            if (this._look)
                actor.remove_style_class_name(`bapirlo-look-${this._look}`);
            actor.add_style_class_name(`bapirlo-look-${look}`);
        }
        this._look = look;
        this._unload();
        const css = cssFor(look, readPalette());
        if (!css)
            return;
        try {
            GLib.mkdir_with_parents(GLib.path_get_dirname(LOOK_CSS), 0o755);
            GLib.file_set_contents(LOOK_CSS, `/* written by bapirlo-bar (looks.js) — look: ${look} */\n${css}\n`);
            const file = Gio.File.new_for_path(LOOK_CSS);
            St.ThemeContext.get_for_stage(global.stage).get_theme().load_stylesheet(file);
            this._loaded = file;
        } catch (e) {
            logError(e, 'bapirlo-bar: bar look stylesheet');
        }
    }

    _dockSettings() {
        const dir = Main.extensionManager.lookup(DOCK_UUID)?.dir?.get_child('schemas').get_path();
        if (!dir || !GLib.file_test(GLib.build_filenamev([dir, 'gschemas.compiled']), GLib.FileTest.EXISTS))
            return null;
        const src = Gio.SettingsSchemaSource.new_from_directory(dir, Gio.SettingsSchemaSource.get_default(), false);
        const schema = src.lookup(DOCK_SCHEMA, false);
        return schema ? new Gio.Settings({settings_schema: schema}) : null;
    }

    _applyDock(look) {
        try {
            const dock = this._dockSettings();
            if (!dock)
                return;
            const prev = readText(DOCK_APPLIED) ?? 'classic';
            const keys = Object.keys(dockWants(look));
            if (look === 'classic') {
                const saved = JSON.parse(readText(DOCK_BASELINE) ?? 'null');
                if (prev !== 'classic' && saved) {
                    for (const k of keys) {
                        if (saved[k] !== undefined)
                            dock.set_value(k, GLib.Variant.parse(null, saved[k], null, null));
                    }
                }
            } else {
                if (prev === 'classic' || !GLib.file_test(DOCK_BASELINE, GLib.FileTest.EXISTS)) {
                    const saved = Object.fromEntries(keys.map(k => [k, dock.get_value(k).print(true)]));
                    GLib.mkdir_with_parents(GLib.path_get_dirname(DOCK_BASELINE), 0o755);
                    GLib.file_set_contents(DOCK_BASELINE, JSON.stringify(saved, null, 1));
                }
                for (const [k, v] of Object.entries(dockWants(look))) {
                    if (!dock.get_value(k).equal(v))
                        dock.set_value(k, v);
                }
            }
            GLib.mkdir_with_parents(GLib.path_get_dirname(DOCK_APPLIED), 0o755);
            GLib.file_set_contents(DOCK_APPLIED, look);
        } catch (e) {
            logError(e, 'bapirlo-bar: dock look');
        }
    }

    _unload() {
        if (!this._loaded)
            return;
        St.ThemeContext.get_for_stage(global.stage).get_theme().unload_stylesheet(this._loaded);
        this._loaded = null;
    }

    // ------------------------------------------------------------ right-click menu

    _openMenu(x, y) {
        this._closeMenu();
        // a 1px anchor under the pointer so the menu opens where the click was
        this._anchor = new St.Widget({width: 1, height: 1, reactive: false});
        Main.uiGroup.add_child(this._anchor);
        const [, py] = Main.panel.get_transformed_position();
        this._anchor.set_position(Math.round(x), Math.round(py + Main.panel.height - 1));

        const menu = new PopupMenu.PopupMenu(this._anchor, 0.5, St.Side.TOP);
        menu.actor.add_style_class_name('bapirlo-ws-menu');
        const title = new PopupMenu.PopupMenuItem('Bar look', {reactive: false});
        title.add_style_class_name('bapirlo-ws-menu-title');
        menu.addMenuItem(title);
        for (const [id, name, hint] of LOOKS) {
            const item = new PopupMenu.PopupMenuItem(name);
            item.label.x_expand = true;
            item.add_child(new St.Label({text: hint, style_class: 'bapirlo-ws-accel', y_align: Clutter.ActorAlign.CENTER}));
            item.setOrnament(id === this.look ? PopupMenu.Ornament.DOT : PopupMenu.Ornament.NONE);
            item.connect('activate', () => GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
                this._settings.set_string('bar-look', id);
                return GLib.SOURCE_REMOVE;
            }));
            menu.addMenuItem(item);
        }
        menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        const app = Shell.AppSystem.get_default().lookup_app('os.bapirlo.BarLooks.desktop');
        if (app) {
            const open = new PopupMenu.PopupImageMenuItem('Open Bar Looks…', 'preferences-desktop-appearance-symbolic');
            open.connect('activate', () => app.activate());
            menu.addMenuItem(open);
        }
        const hint = new PopupMenu.PopupMenuItem('Super+Alt+L cycles through them', {reactive: false});
        hint.add_style_class_name('bapirlo-ws-menu-title');
        menu.addMenuItem(hint);

        Main.uiGroup.add_child(menu.actor);
        this._menuManager.addMenu(menu);
        menu.connect('open-state-changed', (_m, open) => {
            if (!open && this._menu === menu)
                GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
                    if (this._menu === menu)
                        this._closeMenu();
                    return GLib.SOURCE_REMOVE;
                });
        });
        this._menu = menu;
        menu.open(BoxPointer.PopupAnimation.FULL);
    }

    _closeMenu() {
        if (this._menu) {
            this._menuManager.removeMenu(this._menu);
            this._menu.destroy();
            this._menu = null;
        }
        this._anchor?.destroy();
        this._anchor = null;
    }

    // short label under the bar after Super+Alt+L, so you see which look you landed on
    _flash() {
        const name = LOOKS.find(([id]) => id === this.look)[1];
        if (!this._label) {
            this._label = new St.Label({style_class: 'bapirlo-tooltip bapirlo-look-flash'});
            Main.uiGroup.add_child(this._label);
        }
        const label = this._label;
        label.text = `Bar look: ${name}`;
        label.remove_all_transitions();
        label.opacity = 255;
        label.show();
        const mon = Main.layoutManager.primaryMonitor;
        const [w] = label.get_preferred_width(-1);
        label.set_position(Math.round(mon.x + (mon.width - w) / 2),
            Math.round(Main.layoutManager.panelBox.y + Main.layoutManager.panelBox.height + 12));
        if (this._flashId)
            GLib.source_remove(this._flashId);
        this._flashId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1200, () => {
            this._flashId = 0;
            label.ease({opacity: 0, duration: 250, onComplete: () => label.hide()});
            return GLib.SOURCE_REMOVE;
        });
    }

    destroy() {
        this._closeMenu();
        if (this._applyId)
            GLib.source_remove(this._applyId);
        this._applyId = 0;
        if (this._flashId)
            GLib.source_remove(this._flashId);
        this._flashId = 0;
        this._label?.destroy();
        this._label = null;
        this._palMonitor?.cancel();
        this._palMonitor = null;
        this._settings.disconnectObject(this);
        Main.panel.disconnectObject(this);
        this._unload();
        if (this._look) {
            for (const actor of [Main.panel, Main.layoutManager.panelBox, Main.uiGroup])
                actor.remove_style_class_name(`bapirlo-look-${this._look}`);
        }
        this._look = null;
    }
}
