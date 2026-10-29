// Bapirlo Desk — radial launcher: Super+Alt+O opens a ring of up to 8 apps around the pointer.
// Point in a direction (the slice under the pointer lights up) and click, or press 1–8, or
// ←/→ + Enter. Esc, a click in the middle, or the keys again close it. A running app is focused,
// a stopped one is started. The apps are `radial-apps` (empty = the first 8 dock favourites).
// It wears the top bar's look (classic · manga · glass · islands · flat) in the wallpaper's colours.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import Graphene from 'gi://Graphene';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {readPalette} from './widgets.js';
import {label} from './util.js';

const MAX = 8;
const RADIUS = 118;       // bubble centres
const BUBBLE = 68;
const ICON = 42;
const HUB = 92;
const DEAD = 40;          // pointer this close to the centre = nothing picked
const BAR_UUID = 'bapirlo-bar@bapirlo-os';
const BAR_SCHEMA = 'org.gnome.shell.extensions.bapirlo-bar';

function rgba(hex, a = 1) {
    const [r, g, b] = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));
    return `rgba(${r}, ${g}, ${b}, ${a})`;
}

function barLook() {
    try {
        const dir = Main.extensionManager.lookup(BAR_UUID)?.dir?.get_child('schemas').get_path();
        if (!dir)
            return 'classic';
        const src = Gio.SettingsSchemaSource.new_from_directory(dir, Gio.SettingsSchemaSource.get_default(), false);
        const schema = src.lookup(BAR_SCHEMA, false);
        return schema ? new Gio.Settings({settings_schema: schema}).get_string('bar-look') : 'classic';
    } catch {
        return 'classic';
    }
}

// inline styles for: ring (background disc), bubble, bubble:selected, hub, name label
function lookStyles(look, p) {
    const round = r => `border-radius: ${r}px;`;
    const ringD = 2 * RADIUS + BUBBLE + 28;
    const base = {
        ring: `${round(ringD / 2)} background-color: ${rgba(p.night, 0.9)}; border: 1px solid ${rgba(p.crimson, 0.3)}; box-shadow: 0 18px 48px rgba(0,0,0,0.55);`,
        bubble: `${round(BUBBLE / 2)} background-color: ${rgba(p.paper, 0.06)};`,
        selected: `${round(BUBBLE / 2)} background-color: ${rgba(p.crimson, 0.9)}; box-shadow: 0 0 18px ${rgba(p.crimson, 0.55)};`,
        hub: `${round(HUB / 2)} background-color: ${rgba(p.paper, 0.05)}; border: 1px solid ${rgba(p.paper, 0.12)};`,
        name: `color: ${p.paper}; font-family: "Inter", sans-serif; font-size: 10pt; font-weight: 700; text-align: center;`,
        key: `color: ${rgba(p.paper, 0.5)}; font-size: 8pt; text-align: center;`,
    };
    switch (look) {
    case 'manga':
        return {...base,
            ring: `${round(ringD / 2)} background-color: ${p.night}; border: 3px solid ${p.paper}; box-shadow: 7px 7px 0 ${p.crimson};`,
            bubble: `${round(BUBBLE / 2)} background-color: ${rgba(p.paper, 0.04)}; border: 2px solid ${rgba(p.paper, 0.55)};`,
            selected: `${round(BUBBLE / 2)} background-color: ${p.crimson}; border: 2px solid ${p.paper}; box-shadow: 4px 4px 0 ${p.paper};`,
            hub: `${round(HUB / 2)} background-color: ${p.crimson}; border: 3px solid ${p.paper};`,
            name: `color: #ffffff; font-family: Bangers, sans-serif; font-size: 15pt; letter-spacing: 1px; text-align: center;`,
            key: `color: ${rgba('#FFFFFF', 0.75)}; font-size: 8pt; text-align: center;`};
    case 'glass':
        return {...base,
            ring: `${round(ringD / 2)} background-gradient-direction: vertical; background-gradient-start: ${rgba(p.paper, 0.22)}; background-gradient-end: ${rgba(p.paper, 0.08)}; border: 1px solid ${rgba(p.paper, 0.28)}; box-shadow: 0 18px 48px rgba(0,0,0,0.35);`,
            bubble: `${round(BUBBLE / 2)} background-color: ${rgba(p.paper, 0.10)}; border: 1px solid ${rgba(p.paper, 0.18)};`,
            selected: `${round(BUBBLE / 2)} background-color: ${rgba(p.ember, 0.75)}; border: 1px solid ${rgba(p.paper, 0.5)};`,
            hub: `${round(HUB / 2)} background-color: ${rgba(p.night, 0.55)}; border: 1px solid ${rgba(p.paper, 0.22)};`};
    case 'islands':
        return {...base,
            ring: 'background-color: transparent;',
            bubble: `${round(BUBBLE / 2)} background-color: ${rgba(p.night, 0.92)}; border: 1px solid ${rgba(p.crimson, 0.35)}; box-shadow: 0 8px 20px rgba(0,0,0,0.5);`,
            selected: `${round(BUBBLE / 2)} background-color: ${p.crimson}; box-shadow: 0 8px 24px ${rgba(p.crimson, 0.6)};`,
            hub: `${round(HUB / 2)} background-color: ${rgba(p.night, 0.94)}; border: 1px solid ${rgba(p.crimson, 0.35)}; box-shadow: 0 8px 20px rgba(0,0,0,0.5);`};
    case 'flat':
        return {...base,
            ring: `${round(28)} background-color: ${rgba(p.night, 0.97)}; border: 1px solid ${rgba(p.paper, 0.10)};`,
            bubble: `${round(16)} background-color: transparent;`,
            selected: `${round(16)} background-color: ${rgba(p.crimson, 0.85)};`,
            hub: `${round(16)} background-color: ${rgba(p.paper, 0.05)};`};
    default:
        return base;
    }
}

export class RadialLauncher {
    constructor(settings) {
        this._settings = settings;
        this._ui = null;
    }

    get isOpen() {
        return !!this._ui;
    }

    toggle() {
        if (this._ui)
            this.close();
        else
            this.open();
    }

    _apps() {
        const sys = Shell.AppSystem.get_default();
        let ids = this._settings.get_strv('radial-apps');
        if (!ids.length)
            ids = global.settings.get_strv('favorite-apps');
        return ids.map(id => sys.lookup_app(id)).filter(a => a).slice(0, MAX);
    }

    open() {
        if (this._ui || Main.sessionMode.isLocked || Main.modalCount > 0)
            return;
        const apps = this._apps();
        if (!apps.length) {
            Main.notify('Radial launcher', 'No apps — pin some to the dock, or set radial-apps');
            return;
        }
        Main.overview.hide();
        const st = lookStyles(barLook(), readPalette());
        const [px, py] = global.get_pointer();
        const mon = Main.layoutManager.monitors[global.display.get_current_monitor()] ?? Main.layoutManager.primaryMonitor;
        const reach = RADIUS + BUBBLE / 2 + 20;
        const cx = Math.min(Math.max(px, mon.x + reach), mon.x + mon.width - reach);
        const cy = Math.min(Math.max(py, mon.y + reach), mon.y + mon.height - reach);

        const overlay = new St.Widget({reactive: true, can_focus: true, x: 0, y: 0,
            width: global.stage.width, height: global.stage.height, opacity: 0});
        Main.layoutManager.uiGroup.add_child(overlay);

        const ringD = 2 * RADIUS + BUBBLE + 28;
        const ring = new St.Widget({style: st.ring, width: ringD, height: ringD,
            x: cx - ringD / 2, y: cy - ringD / 2, pivot_point: new Graphene.Point({x: 0.5, y: 0.5}),
            scale_x: 0.85, scale_y: 0.85});
        overlay.add_child(ring);

        const hub = new St.BoxLayout({style: st.hub, width: HUB, height: HUB, x: cx - HUB / 2, y: cy - HUB / 2,
            orientation: Clutter.Orientation.VERTICAL, y_align: Clutter.ActorAlign.CENTER});
        const name = label('', null, true);
        name.style = st.name;
        name.x_expand = true;
        name.y_expand = true;
        name.x_align = Clutter.ActorAlign.CENTER;
        name.y_align = Clutter.ActorAlign.END;
        const key = label('', null, false);
        key.style = st.key;
        key.x_align = Clutter.ActorAlign.CENTER;
        key.y_expand = true;
        key.y_align = Clutter.ActorAlign.START;
        name.width = HUB - 12;
        hub.add_child(name);
        hub.add_child(key);
        overlay.add_child(hub);

        const items = apps.map((app, i) => {
            const a = -Math.PI / 2 + i * 2 * Math.PI / apps.length;
            const bx = cx + RADIUS * Math.cos(a) - BUBBLE / 2;
            const by = cy + RADIUS * Math.sin(a) - BUBBLE / 2;
            const bubble = new St.Bin({style: st.bubble, width: BUBBLE, height: BUBBLE,
                x: cx - BUBBLE / 2, y: cy - BUBBLE / 2, scale_x: 0.3, scale_y: 0.3, opacity: 0,
                pivot_point: new Graphene.Point({x: 0.5, y: 0.5}),
                child: app.create_icon_texture(ICON)});
            overlay.add_child(bubble);
            bubble.ease({x: bx, y: by, scale_x: 1, scale_y: 1, opacity: 255, duration: 170, delay: i * 14,
                mode: Clutter.AnimationMode.EASE_OUT_BACK});
            return {app, angle: a, bubble};
        });

        this._ui = {overlay, ring, hub, name, key, items, st, cx, cy, sel: -2};
        this._grab = Main.pushModal(overlay, {actionMode: Shell.ActionMode.POPUP});
        if (!this._grab) {
            this.close();
            return;
        }
        global.stage.set_key_focus(overlay);
        overlay.ease({opacity: 255, duration: 120, mode: Clutter.AnimationMode.EASE_OUT_QUAD});
        ring.ease({scale_x: 1, scale_y: 1, duration: 180, mode: Clutter.AnimationMode.EASE_OUT_BACK});

        overlay.connect('motion-event', (_a, ev) => {
            const [x, y] = ev.get_coords();
            this._select(this._pick(x, y));
            return Clutter.EVENT_STOP;
        });
        overlay.connect('button-release-event', (_a, ev) => {
            const [x, y] = ev.get_coords();
            const i = this._pick(x, y);
            if (i >= 0)
                this._launch(i);
            else
                this.close();
            return Clutter.EVENT_STOP;
        });
        overlay.connect('key-press-event', (_a, ev) => {
            const sym = ev.get_key_symbol();
            const n = this._ui.items.length;
            if (sym === Clutter.KEY_Escape) {
                this.close();
            } else if (sym >= Clutter.KEY_1 && sym < Clutter.KEY_1 + n) {
                this._launch(sym - Clutter.KEY_1);
            } else if (sym >= Clutter.KEY_KP_1 && sym < Clutter.KEY_KP_1 + n) {
                this._launch(sym - Clutter.KEY_KP_1);
            } else if (sym === Clutter.KEY_Right || sym === Clutter.KEY_Down || sym === Clutter.KEY_Tab) {
                this._select((this._ui.sel + 1 + n) % n);
            } else if (sym === Clutter.KEY_Left || sym === Clutter.KEY_Up || sym === Clutter.KEY_ISO_Left_Tab) {
                this._select((Math.max(this._ui.sel, 0) - 1 + n) % n);
            } else if (sym === Clutter.KEY_Return || sym === Clutter.KEY_KP_Enter || sym === Clutter.KEY_space) {
                if (this._ui.sel >= 0)
                    this._launch(this._ui.sel);
                else
                    this.close();
            } else {
                return Clutter.EVENT_PROPAGATE;
            }
            return Clutter.EVENT_STOP;
        });
        this._select(this._pick(px, py));
    }

    // which slice is the pointer in (-1 = the middle)
    _pick(x, y) {
        const u = this._ui;
        const dx = x - u.cx, dy = y - u.cy;
        if (Math.hypot(dx, dy) < DEAD)
            return -1;
        const n = u.items.length;
        const step = 2 * Math.PI / n;
        let a = Math.atan2(dy, dx) + Math.PI / 2 + step / 2;   // 0 = straight up, centred on item 0
        a = ((a % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI);
        return Math.floor(a / step) % n;
    }

    _select(i) {
        const u = this._ui;
        if (!u || i === u.sel)
            return;
        if (u.sel >= 0) {
            const b = u.items[u.sel].bubble;
            b.style = u.st.bubble;
            b.ease({scale_x: 1, scale_y: 1, duration: 110, mode: Clutter.AnimationMode.EASE_OUT_QUAD});
        }
        u.sel = i;
        if (i < 0) {
            u.name.text = '';
            u.key.text = 'Esc';
            return;
        }
        const it = u.items[i];
        it.bubble.style = u.st.selected;
        it.bubble.ease({scale_x: 1.16, scale_y: 1.16, duration: 130, mode: Clutter.AnimationMode.EASE_OUT_BACK});
        u.name.text = it.app.get_name();
        u.key.text = `${i + 1}${it.app.get_state() === Shell.AppState.RUNNING ? ' · open' : ''}`;
    }

    _launch(i) {
        const app = this._ui?.items[i]?.app;
        this.close();
        if (!app)
            return;
        try {
            app.activate();
        } catch (e) {
            logError(e, `bapirlo-desk: radial launcher ${app.get_id()}`);
        }
    }

    close() {
        const u = this._ui;
        if (!u)
            return;
        this._ui = null;
        if (this._grab)
            Main.popModal(this._grab);
        this._grab = null;
        u.overlay.reactive = false;
        u.overlay.ease({opacity: 0, duration: 110, mode: Clutter.AnimationMode.EASE_OUT_QUAD,
            onStopped: () => u.overlay.destroy()});
    }

    destroy() {
        const u = this._ui;
        this.close();
        u?.overlay.destroy();
    }
}
