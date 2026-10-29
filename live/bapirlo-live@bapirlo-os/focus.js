// Search focus: the wallpaper follows you while you look for apps (setting "search-focus").
//   · overview  the real wallpaper (a Hanabi video too: Hanabi hooks every BackgroundManager) is drawn
//               behind the overview instead of the flat theme colour. It blurs, darkens and zooms in
//               step with the overview's own animation (desktop → windows → app grid), and a bit more
//               while a search is typed
//   · ArcMenu   the desktop wallpaper does the same while the menu is open (zoom + shift go through
//               the live shader so the art never spills onto another monitor)
//   · parallax  the art drifts toward the highlighted app / result (keyboard or pointer) and slides
//               against the app-grid page you are on
// Frames run only while one of them is open or still easing back; at rest the blur effects are gone.
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Graphene from 'gi://Graphene';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Background from 'resource:///org/gnome/shell/ui/background.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const NAME = 'bapirlo-focus';
const FRAME_MS = 16;
const TAU_S = 0.14;             // easing time constant
const LOOK = {                  // blur radius (px), brightness, zoom
    rest: {blur: 0, dim: 1.0, zoom: 1.0},
    windows: {blur: 28, dim: 0.80, zoom: 1.04},
    grid: {blur: 44, dim: 0.64, zoom: 1.08},
    search: {blur: 60, dim: 0.52, zoom: 1.12},
    menu: {blur: 34, dim: 0.74, zoom: 1.05},
    menuSearch: {blur: 52, dim: 0.58, zoom: 1.09},
};
const SHIFT = {focus: 0.022, page: 0.03};       // max drift, fraction of the monitor

const mix = (a, b, k) => ({blur: a.blur + (b.blur - a.blur) * k, dim: a.dim + (b.dim - a.dim) * k, zoom: a.zoom + (b.zoom - a.zoom) * k});
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

export class SearchFocus {
    // onDesktop() is called whenever desktop.zoom / desktop.move changed (the live shader draws them)
    constructor(settings, onDesktop) {
        this._settings = settings;
        this._onDesktop = onDesktop;
        this._on = settings.get_boolean('search-focus');
        this._menus = new Set();
        this._backdrops = [];
        this._blurred = new Set();          // desktop wallpaper actors carrying our blur
        this._ov = {boost: 0, move: [0, 0]};
        this._menu = {p: 0, boost: 0, move: [0, 0]};
        this.desktop = {zoom: 1, move: [0, 0]};

        settings.connectObject('changed::search-focus', () => {
            this._on = settings.get_boolean('search-focus');
            if (!this._on)
                this._dropBackdrops();
            this._wake();
        }, this);
        Main.overview.connectObject(
            'showing', () => this._on && this._buildBackdrops(),
            'hidden', () => this._dropBackdrops(),
            this);
        Main.layoutManager.connectObject('monitors-changed', () => {
            if (this._backdrops.length)
                this._buildBackdrops();
        }, this);
        // ArcMenu adds each of its menus to uiGroup when it builds them (also after a re-layout)
        Main.uiGroup.connectObject('child-added', (_g, a) => this._watchMenu(a), this);
        Main.uiGroup.get_children().forEach(a => this._watchMenu(a));
        if (this._on && Main.overview.visible)
            this._buildBackdrops();
    }

    destroy() {
        if (this._timer)
            GLib.source_remove(this._timer);
        this._timer = 0;
        this._settings.disconnectObject(this);
        Main.overview.disconnectObject(this);
        Main.layoutManager.disconnectObject(this);
        Main.uiGroup.disconnectObject(this);
        for (const m of this._menus)
            m.disconnectObject(this);
        this._menus.clear();
        this._dropBackdrops();
        this._unblurDesktop();
        this.desktop = {zoom: 1, move: [0, 0]};
    }

    // ---------------------------------------------------------------- ArcMenu
    _watchMenu(actor) {
        const menu = actor._delegate;
        if (!menu || this._menus.has(menu) || !actor.has_style_class_name?.('arcmenu-menu'))
            return;
        this._menus.add(menu);
        menu.connectObject(
            'open-state-changed', () => this._wake(),
            'destroy', () => this._menus.delete(menu),
            this);
    }

    _openMenu() {
        for (const m of this._menus) {
            if (m.isOpen)
                return m;
        }
        return null;
    }

    // ---------------------------------------------------------------- overview backdrop
    _buildBackdrops() {
        this._dropBackdrops();
        Main.layoutManager.monitors.forEach((m, i) => {
            const clip = new St.Widget({clip_to_allocation: true, x: m.x, y: m.y, width: m.width, height: m.height});
            const art = new St.Widget({
                layout_manager: new Clutter.BinLayout(), width: m.width, height: m.height,
                pivot_point: new Graphene.Point({x: 0.5, y: 0.5}),
            });
            clip.add_child(art);
            const mgr = new Background.BackgroundManager({container: art, monitorIndex: i, controlPosition: false, useContentSize: false});
            const blur = new Shell.BlurEffect({mode: Shell.BlurMode.ACTOR, radius: 0, brightness: 1, enabled: false});
            clip.add_effect_with_name(NAME, blur);
            Main.layoutManager.overviewGroup.insert_child_below(clip, null);
            this._backdrops.push({clip, art, mgr, blur, monitor: m});
        });
        this._ov = {boost: 0, move: [0, 0]};
        this._wake();
    }

    _dropBackdrops() {
        for (const b of this._backdrops) {
            b.mgr.destroy();
            b.clip.destroy();
        }
        this._backdrops = [];
    }

    _overviewLook() {
        const controls = Main.overview._overview?._controls;
        const s = clamp(controls?._stateAdjustment?.value ?? 1, 0, 2);
        const base = s <= 1 ? mix(LOOK.rest, LOOK.windows, s) : mix(LOOK.windows, LOOK.grid, s - 1);
        return mix(base, LOOK.search, this._ov.boost);
    }

    // app-grid page as -1 … 1 (0 with a single page or outside the grid)
    _gridPage() {
        const controls = Main.overview._overview?._controls;
        const adj = controls?._appDisplay?._adjustment;
        if (!adj || !adj.page_size || Main.overview.searchController?.searchActive)
            return 0;
        const pages = Math.round(adj.upper / adj.page_size);
        if (pages < 2)
            return 0;
        const toGrid = clamp((controls._stateAdjustment?.value ?? 0) - 1, 0, 1);
        return (clamp(adj.value / adj.page_size / (pages - 1), 0, 1) * 2 - 1) * toGrid;
    }

    // ---------------------------------------------------------------- parallax target
    // where the highlighted thing is: key focus inside `root`, else ArcMenu's active item, else the pointer
    _focusPoint(root, menu) {
        let a = global.stage.key_focus;
        if (!a || !root?.contains(a) || a instanceof St.Entry || a instanceof Clutter.Text)
            a = menu?._menuButton?._menuLayout?.activeMenuItem ?? null;
        if (a?.get_transformed_extents && a.mapped) {
            const r = a.get_transformed_extents();
            if (r.get_width() > 0)
                return [r.get_x() + r.get_width() / 2, r.get_y() + r.get_height() / 2];
        }
        const [x, y] = global.get_pointer();
        return [x, y];
    }

    _towards(point, m) {
        const nx = clamp((point[0] - m.x - m.width / 2) / (m.width / 2), -1, 1);
        const ny = clamp((point[1] - m.y - m.height / 2) / (m.height / 2), -1, 1);
        return [nx * SHIFT.focus, ny * SHIFT.focus];
    }

    // ---------------------------------------------------------------- frames
    _wake() {
        if (this._timer)
            return;
        this._lastUs = GLib.get_monotonic_time();
        this._timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, FRAME_MS, () => {
            if (this._tick())
                return GLib.SOURCE_CONTINUE;
            this._timer = 0;
            return GLib.SOURCE_REMOVE;
        });
        GLib.Source.set_name_by_id(this._timer, '[bapirlo-live] search focus');
    }

    // returns whether another frame is needed
    _tick() {
        const now = GLib.get_monotonic_time();
        const dt = Math.min((now - this._lastUs) / 1e6, 0.1);
        this._lastUs = now;
        const k = 1 - Math.exp(-dt / TAU_S);
        const ease = (v, t) => Math.abs(t - v) < 1e-4 ? t : v + (t - v) * k;
        let busy = false;

        // overview: level follows GNOME's own state animation; search boost + drift are eased
        if (this._backdrops.length) {
            busy = true;
            const searching = Main.overview.searchController?.searchActive ? 1 : 0;
            this._ov.boost = ease(this._ov.boost, searching);
            const look = this._overviewLook();
            const room = (look.zoom - 1) / 2 * 0.9;
            const page = this._gridPage();
            for (const b of this._backdrops) {
                const f = this._towards(this._focusPoint(Main.overview._overview, null), b.monitor);
                const target = [clamp(f[0] - page * SHIFT.page, -room, room), clamp(f[1], -room, room)];
                this._ov.move = this._ov.move.map((v, i) => clamp(ease(v, target[i]), -room, room));
                b.art.set_scale(look.zoom, look.zoom);
                b.art.translation_x = this._ov.move[0] * b.monitor.width;
                b.art.translation_y = this._ov.move[1] * b.monitor.height;
                b.blur.radius = Math.round(look.blur);
                b.blur.brightness = look.dim;
                b.blur.enabled = look.blur >= 1 || look.dim < 0.995;
            }
        }

        // ArcMenu over the desktop
        const menu = this._on && !Main.overview.visible ? this._openMenu() : null;
        const st = this._menu;
        const before = [st.p, st.boost, ...st.move];
        st.p = ease(st.p, menu ? 1 : 0);
        st.boost = ease(st.boost, menu?._menuButton?._menuLayout?.searchEntry?.getText?.() ? 1 : 0);
        const look = mix(LOOK.rest, mix(LOOK.menu, LOOK.menuSearch, st.boost), st.p);
        const room = (look.zoom - 1) / 2 * 0.9;
        const m = Main.layoutManager.primaryMonitor;
        const target = menu && m ? this._towards(this._focusPoint(menu.actor, menu), m) : [0, 0];
        st.move = st.move.map((v, i) => clamp(ease(v, target[i]), -room, room));
        const changed = [st.p, st.boost, ...st.move].some((v, i) => v !== before[i]);
        if (changed || menu) {
            this._blurDesktop(look);
            this.desktop = {zoom: look.zoom, move: [...st.move]};
            if (changed)
                this._onDesktop();
        }
        if (st.p === 0 && !menu)
            this._unblurDesktop();
        return busy || !!menu || changed;
    }

    _blurDesktop(look) {
        for (const mgr of Main.layoutManager._bgManagers ?? []) {
            const actor = mgr.backgroundActor;
            if (!actor)
                continue;
            let fx = actor.get_effect(NAME);
            if (!fx) {
                fx = new Shell.BlurEffect({mode: Shell.BlurMode.ACTOR});
                actor.add_effect_with_name(NAME, fx);
                // the blur must run before the live shader: after it, the shader's offscreen pass hides it
                const live = actor.get_effect('bapirlo-live');
                if (live) {
                    actor.remove_effect(live);
                    actor.add_effect_with_name('bapirlo-live', live);
                }
                this._blurred.add(actor);
                actor.connectObject('destroy', () => this._blurred.delete(actor), this);
            }
            fx.radius = Math.round(look.blur);
            fx.brightness = look.dim;
        }
    }

    _unblurDesktop() {
        for (const actor of this._blurred) {
            actor.disconnectObject(this);
            const fx = actor.get_effect(NAME);
            if (fx)
                actor.remove_effect(fx);
        }
        this._blurred.clear();
    }
}
