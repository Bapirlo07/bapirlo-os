// Bapirlo Desk — Launchpad: a Mac-style full-screen app grid.
// Opens with Super+G or the dock's Launchpad icon (os.bapirlo.Launchpad.desktop → D-Bus).
// Blurred, dimmed wallpaper (like the lock screen: only the wallpaper is blurred, not live windows —
// cheap on the iGPU), pages of icons that zoom in, page dots, a search field that is focused at
// once (just start typing; Enter opens the first hit), and folders — GNOME's own app folders
// (org.gnome.desktop.app-folders, e.g. "Tools"), which open in a zooming panel.
// Keys: Esc closes (or leaves a folder / clears the search) · PgUp/PgDn, ←/→ (empty search), the
// mouse wheel and the dots switch pages · Super+G closes. Click empty space to close.
// Click = open/focus the app, middle- or Ctrl+click = a new window.
// Nothing exists while closed; the app list is rebuilt on every open (installed apps change).
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import Graphene from 'gi://Graphene';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Background from 'resource:///org/gnome/shell/ui/background.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {label} from './util.js';

const SELF = 'os.bapirlo.Launchpad.desktop';
const OPEN_MS = 280;
const PAGE_MS = 380;
const FOLDER_COLS = 5;

function appCategories(app) {
    return (app.app_info?.get_categories?.() ?? '').split(';').filter(Boolean);
}

export class Launchpad {
    constructor() {
        this._appSys = Shell.AppSystem.get_default();
        this.overlay = null;
    }

    toggle() {
        if (this.overlay)
            this.close();
        else
            this.open();
    }

    // ------------------------------------------------------------ data
    _collect() {
        const seen = new Set();
        const apps = [];
        for (const info of this._appSys.get_installed()) {
            const id = info.get_id();
            if (seen.has(id) || id === SELF || !info.should_show())
                continue;
            const app = this._appSys.lookup_app(id);
            if (!app)
                continue;
            seen.add(id);
            apps.push(app);
        }

        const folders = [];
        const inFolder = new Set();
        const root = new Gio.Settings({schema_id: 'org.gnome.desktop.app-folders'});
        for (const fid of root.get_strv('folder-children')) {
            const f = new Gio.Settings({schema_id: 'org.gnome.desktop.app-folders.folder',
                path: `/org/gnome/desktop/app-folders/folders/${fid}/`});
            let name = f.get_string('name');
            if (f.get_boolean('translate'))
                name = Shell.util_get_translated_folder_name(name) ?? name;
            const listed = new Set(f.get_strv('apps'));
            const cats = f.get_strv('categories');
            const excluded = new Set(f.get_strv('excluded-apps'));
            const members = apps.filter(a => !excluded.has(a.id) &&
                (listed.has(a.id) || (cats.length && appCategories(a).some(c => cats.includes(c)))));
            if (members.length === 0)
                continue;
            members.forEach(a => inFolder.add(a.id));
            folders.push({name, apps: members.sort((x, y) => x.get_name().localeCompare(y.get_name()))});
        }
        folders.sort((x, y) => x.name.localeCompare(y.name));
        const loose = apps.filter(a => !inFolder.has(a.id)).sort((x, y) => x.get_name().localeCompare(y.get_name()));
        return {apps, items: [...folders.map(f => ({folder: f})), ...loose.map(a => ({app: a}))]};
    }

    // ------------------------------------------------------------ open / close
    open() {
        if (this.overlay)
            return;
        if (Main.overview.visible)
            Main.overview.hide();
        const m = Main.layoutManager.currentMonitor;
        const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        this._monitor = m;
        this._iconSize = m.width >= 1600 ? 96 : 80;
        this._cellW = this._iconSize + 72;
        this._cellH = this._iconSize + 64;
        this._data = this._collect();

        const overlay = new St.Widget({
            style_class: 'blp-overlay', reactive: true,
            x: m.x, y: m.y, width: m.width, height: m.height,
            layout_manager: new Clutter.BinLayout(),
        });
        this.overlay = overlay;

        // wallpaper, blurred + darkened
        const bg = new St.Widget({x_expand: true, y_expand: true,
            effect: new Shell.BlurEffect({name: 'blur', radius: 60 * scale, brightness: 0.5})});
        this._bgManager = new Background.BackgroundManager({container: bg, monitorIndex: m.index, controlPosition: false});
        overlay.add_child(bg);
        overlay.add_child(new St.Widget({style_class: 'blp-scrim', x_expand: true, y_expand: true}));

        // empty-space click catcher (items sit above it and take their own clicks)
        const catcher = new St.Widget({reactive: true, x_expand: true, y_expand: true});
        const click = new Clutter.ClickGesture();
        click.connect('recognize', () => this.close());
        catcher.add_action(click);
        overlay.add_child(catcher);

        // search · pages · dots
        this._content = new St.BoxLayout({style_class: 'blp-content', orientation: Clutter.Orientation.VERTICAL,
            x_expand: true, y_expand: true, pivot_point: new Graphene.Point({x: 0.5, y: 0.5})});
        this._search = new St.Entry({style_class: 'blp-search', hint_text: 'Search', can_focus: true,
            x_align: Clutter.ActorAlign.CENTER,
            primary_icon: new St.Icon({icon_name: 'system-search-symbolic', style_class: 'blp-search-icon'})});
        this._search.clutter_text.connect('text-changed', () => this._onSearch());
        this._search.clutter_text.connect('activate', () => this._launchFirst());
        this._content.add_child(this._search);

        this._viewport = new St.Widget({style_class: 'blp-viewport', x_expand: true, y_expand: true,
            clip_to_allocation: true, reactive: false, layout_manager: new Clutter.BinLayout()});
        this._strip = new St.BoxLayout({y_align: Clutter.ActorAlign.CENTER, x_align: Clutter.ActorAlign.START,
            x_expand: true, y_expand: true});
        this._viewport.add_child(this._strip);
        this._content.add_child(this._viewport);
        this._dots = new St.BoxLayout({style_class: 'blp-dots', x_align: Clutter.ActorAlign.CENTER});
        this._content.add_child(this._dots);
        overlay.add_child(this._content);

        const scroll = new Clutter.ScrollController({
            flags: Clutter.ScrollControllerFlags.DISCRETE | Clutter.ScrollControllerFlags.SCROLL_VERTICAL |
                Clutter.ScrollControllerFlags.SCROLL_HORIZONTAL});
        scroll.connect('scroll', (_c, _s, _src, dx, dy) => {
            if (this._folder)
                return Clutter.EVENT_STOP;
            const d = dy || dx;
            if (d)
                this._goTo(this._page + (d > 0 ? 1 : -1));
            return Clutter.EVENT_STOP;
        });
        overlay.add_action(scroll);

        const keys = new Clutter.KeyController();
        keys.connect('key-press', () => this._onKey(keys) ? Clutter.EVENT_STOP : Clutter.EVENT_PROPAGATE);
        this._search.clutter_text.add_action(keys);

        Main.layoutManager.uiGroup.add_child(overlay);
        this._grab = Main.pushModal(overlay, {actionMode: Shell.ActionMode.POPUP});

        this._page = 0;
        this._layoutPages(this._data.items);
        this._search.grab_key_focus();

        // zoom in: icons come from slightly larger, the backdrop fades in
        overlay.opacity = 0;
        this._content.set_scale(1.12, 1.12);
        overlay.ease({opacity: 255, duration: OPEN_MS, mode: Clutter.AnimationMode.EASE_OUT_QUAD});
        this._content.ease({scale_x: 1, scale_y: 1, duration: OPEN_MS + 60, mode: Clutter.AnimationMode.EASE_OUT_QUART});
    }

    close() {
        const overlay = this.overlay;
        if (!overlay || this._closing)
            return;
        this._closing = true;
        if (this._grab) {
            Main.popModal(this._grab);
            this._grab = null;
        }
        overlay.reactive = false;
        this._content.ease({scale_x: 1.08, scale_y: 1.08, duration: 200, mode: Clutter.AnimationMode.EASE_IN_QUAD});
        overlay.ease({opacity: 0, duration: 200, mode: Clutter.AnimationMode.EASE_IN_QUAD,
            onStopped: () => this._destroyOverlay()});
    }

    _destroyOverlay() {
        this._bgManager?.destroy();
        this._bgManager = null;
        this.overlay?.destroy();
        this.overlay = null;
        this._folder = null;
        this._closing = false;
    }

    // ------------------------------------------------------------ pages
    _grid() {
        const vw = this._monitor.width * 0.86;
        const vh = this._monitor.height - 300;
        const cols = Math.max(4, Math.min(7, Math.floor(vw / this._cellW)));
        const rows = Math.max(3, Math.min(5, Math.floor(vh / this._cellH)));
        return {cols, rows, per: cols * rows};
    }

    _layoutPages(items) {
        this._strip.destroy_all_children();
        this._dots.destroy_all_children();
        const {cols, per} = this._grid();
        const pageW = this._monitor.width;
        this._pageW = pageW;
        const pages = Math.max(1, Math.ceil(items.length / per));
        this._pages = pages;
        for (let p = 0; p < pages; p++) {
            const gl = new Clutter.GridLayout({column_homogeneous: true, row_homogeneous: true});
            const grid = new St.Widget({style_class: 'blp-grid', layout_manager: gl,
                x_align: Clutter.ActorAlign.CENTER, y_align: Clutter.ActorAlign.START, x_expand: true});
            items.slice(p * per, (p + 1) * per).forEach((it, i) =>
                gl.attach(it.folder ? this._folderTile(it.folder) : this._appTile(it.app), i % cols, Math.floor(i / cols), 1, 1));
            const page = new St.Widget({width: pageW, layout_manager: new Clutter.BinLayout(), y_expand: true});
            page.add_child(grid);
            this._strip.add_child(page);
            const dot = new St.Button({style_class: 'blp-dot', can_focus: false});
            dot.connect('clicked', () => this._goTo(p));
            this._dots.add_child(dot);
        }
        this._dots.visible = pages > 1;
        this._goTo(Math.min(this._page, pages - 1), false);
    }

    _goTo(page, animate = true) {
        page = Math.max(0, Math.min(this._pages - 1, page));
        this._page = page;
        const x = -page * this._pageW;
        if (animate)
            this._strip.ease({translation_x: x, duration: PAGE_MS, mode: Clutter.AnimationMode.EASE_OUT_CUBIC});
        else
            this._strip.translation_x = x;
        this._dots.get_children().forEach((d, i) => (i === page ? d.add_style_pseudo_class('checked') : d.remove_style_pseudo_class('checked')));
    }

    // ------------------------------------------------------------ tiles
    _tile(child, name, onClick) {
        const box = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, style_class: 'blp-tile-box',
            x_align: Clutter.ActorAlign.CENTER});
        child.x_align = Clutter.ActorAlign.CENTER;
        box.add_child(child);
        const l = label(name, 'blp-name');
        l.x_align = Clutter.ActorAlign.CENTER;
        box.add_child(l);
        const btn = new St.Button({style_class: 'blp-tile', child: box, can_focus: true, width: this._cellW,
            height: this._cellH, button_mask: St.ButtonMask.PRIMARY | St.ButtonMask.MIDDLE,
            pivot_point: new Graphene.Point({x: 0.5, y: 0.5})});
        btn.connect('clicked', (_b, button) => onClick(button));
        return btn;
    }

    _appTile(app) {
        const icon = app.create_icon_texture(this._iconSize);
        return this._tile(icon, app.get_name(), button => this._launch(app, button));
    }

    _folderTile(folder) {
        const mini = new St.Widget({style_class: 'blp-folder-icon', width: this._iconSize, height: this._iconSize,
            layout_manager: new Clutter.GridLayout({column_homogeneous: true, row_homogeneous: true})});
        const small = Math.floor((this._iconSize - 24) / 3);
        folder.apps.slice(0, 9).forEach((a, i) => {
            const t = a.create_icon_texture(small);
            t.x_align = t.y_align = Clutter.ActorAlign.CENTER;
            mini.layout_manager.attach(t, i % 3, Math.floor(i / 3), 1, 1);
        });
        return this._tile(mini, folder.name, () => this._openFolder(folder));
    }

    _launch(app, button) {
        const [, , mods] = global.get_pointer();
        if (button === 2 || (mods & Clutter.ModifierType.CONTROL_MASK))
            app.open_new_window(-1);
        else
            app.activate();
        this.close();
    }

    // ------------------------------------------------------------ folders
    _openFolder(folder) {
        this._closeFolder(false);
        const layer = new St.Widget({x_expand: true, y_expand: true, reactive: true, layout_manager: new Clutter.BinLayout()});
        const out = new Clutter.ClickGesture();
        out.connect('recognize', () => this._closeFolder());
        layer.add_action(out);

        const panel = new St.BoxLayout({style_class: 'blp-folder', orientation: Clutter.Orientation.VERTICAL,
            x_align: Clutter.ActorAlign.CENTER, y_align: Clutter.ActorAlign.CENTER, reactive: true,
            pivot_point: new Graphene.Point({x: 0.5, y: 0.5})});
        // clicks inside the panel (between icons) must not close it
        panel.add_action(new Clutter.ClickGesture());
        const title = label(folder.name, 'blp-folder-title', false);
        title.x_align = Clutter.ActorAlign.CENTER;
        panel.add_child(title);
        const gl = new Clutter.GridLayout({column_homogeneous: true, row_homogeneous: true});
        const grid = new St.Widget({layout_manager: gl, x_align: Clutter.ActorAlign.CENTER});
        folder.apps.forEach((a, i) => gl.attach(this._appTile(a), i % FOLDER_COLS, Math.floor(i / FOLDER_COLS), 1, 1));
        panel.add_child(grid);
        layer.add_child(panel);
        this.overlay.add_child(layer);
        this._folder = layer;

        this._content.ease({opacity: 90, duration: 200, mode: Clutter.AnimationMode.EASE_OUT_QUAD});
        panel.set_scale(0.8, 0.8);
        panel.opacity = 0;
        panel.ease({scale_x: 1, scale_y: 1, opacity: 255, duration: 260, mode: Clutter.AnimationMode.EASE_OUT_BACK});
    }

    _closeFolder(animate = true) {
        const layer = this._folder;
        if (!layer)
            return;
        this._folder = null;
        this._content.ease({opacity: 255, duration: 200, mode: Clutter.AnimationMode.EASE_OUT_QUAD});
        if (!animate) {
            layer.destroy();
            return;
        }
        layer.reactive = false;
        layer.ease({opacity: 0, duration: 160, mode: Clutter.AnimationMode.EASE_IN_QUAD, onStopped: () => layer.destroy()});
    }

    // ------------------------------------------------------------ search + keys
    _results() {
        const text = this._search.get_text().trim();
        if (!text)
            return null;
        const ids = Shell.AppSystem.search(text.toLowerCase()).flat();
        const byId = new Map(this._data.apps.map(a => [a.id, a]));
        return ids.map(id => byId.get(id)).filter(Boolean);
    }

    _onSearch() {
        this._closeFolder(false);
        const res = this._results();
        this._page = 0;
        this._layoutPages(res ? res.map(a => ({app: a})) : this._data.items);
        if (res && res.length === 0) {
            const none = label('No apps match', 'blp-none', false);
            none.x_align = Clutter.ActorAlign.CENTER;
            this._strip.get_first_child()?.add_child(none);
        }
    }

    _launchFirst() {
        const res = this._results();
        if (res?.length)
            this._launch(res[0], 1);
    }

    _onKey(controller) {
        const [, sym] = controller.get_key();
        const [, pressed, latched, locked] = controller.get_state();
        const state = pressed | latched | locked;
        const empty = this._search.get_text() === '';
        if (sym === Clutter.KEY_Escape) {
            if (this._folder)
                this._closeFolder();
            else if (!empty)
                this._search.set_text('');
            else
                this.close();
            return true;
        }
        if ((sym === Clutter.KEY_g || sym === Clutter.KEY_G) && (state & Clutter.ModifierType.SUPER_MASK)) {
            this.close();
            return true;
        }
        if (sym === Clutter.KEY_Page_Down || (empty && sym === Clutter.KEY_Right)) {
            this._goTo(this._page + 1);
            return true;
        }
        if (sym === Clutter.KEY_Page_Up || (empty && sym === Clutter.KEY_Left)) {
            this._goTo(this._page - 1);
            return true;
        }
        return false;
    }

    destroy() {
        if (this._grab) {
            Main.popModal(this._grab);
            this._grab = null;
        }
        this.overlay?.remove_all_transitions();
        this._destroyOverlay();
    }
}
