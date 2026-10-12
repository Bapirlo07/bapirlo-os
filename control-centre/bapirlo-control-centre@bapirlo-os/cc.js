// Bapirlo Control Centre — the drop-down panel (a PopupMenu anchored to the stock quick-settings
// button). Grid of tiles, a detail page that slides in for an expanded tile, an edit mode
// (drag to reorder, − to remove, + to add) and a footer (settings, lock, power, edit, classic).
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import St from 'gi://St';

import * as BoxPointer from 'resource:///org/gnome/shell/ui/boxpointer.js';
import * as DND from 'resource:///org/gnome/shell/ui/dnd.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

import * as T from './tiles.js';

const COLS = 4;
const STAGGER_MS = 16;
const PAGE_MS = 220;

const NAMES = {
    wifi: 'Wi-Fi', bluetooth: 'Bluetooth', dnd: 'Do Not Disturb', nightlight: 'Night Light',
    power: 'Power Mode', caffeine: 'Caffeine', record: 'Screen Rec', darkmode: 'Dark Style',
    volume: 'Volume', brightness: 'Brightness', battery: 'Battery', media: 'Now Playing', storage: 'Storage',
};
export const ALL_TILES = Object.keys(NAMES);

function makeTile(id, cc) {
    switch (id) {
    case 'wifi': return new T.MirrorTile(id, 'wide', cc, {find: T.FIND.wifi, title: 'Wi-Fi', icon: 'network-wireless-symbolic'});
    case 'bluetooth': return new T.MirrorTile(id, 'wide', cc, {find: T.FIND.bluetooth, title: 'Bluetooth', icon: 'bluetooth-active-symbolic'});
    case 'dnd': return new T.MirrorTile(id, 'wide', cc, {find: T.FIND.dnd, title: 'Do Not Disturb', icon: 'notifications-disabled-symbolic'});
    case 'nightlight': return new T.MirrorTile(id, 'small', cc, {find: T.FIND.nightlight, title: 'Night Light', icon: 'night-light-symbolic'});
    case 'darkmode': return new T.MirrorTile(id, 'small', cc, {find: T.FIND.darkmode, title: 'Dark Style', icon: 'dark-mode-symbolic'});
    case 'caffeine': return new T.MirrorTile(id, 'small', cc, {find: T.FIND.caffeine, title: 'Caffeine', icon: 'my-caffeine-off-symbolic'});
    case 'power': return new T.PowerTile(id, cc);
    case 'record': return new T.RecordTile(id, cc);
    case 'battery': return new T.BatteryTile(id, cc);
    case 'storage': return new T.StorageTile(id, cc);
    case 'media': return new T.MediaTile(id, cc);
    case 'volume': return new T.SliderTile(id, cc, {find: T.FIND.volume, title: 'Sound', icon: 'audio-volume-high-symbolic'});
    case 'brightness': return new T.SliderTile(id, cc, {find: T.FIND.brightness, title: 'Display', icon: 'display-brightness-symbolic'});
    }
    return null;
}

export class ControlCentre extends PopupMenu.PopupMenu {
    constructor(sourceActor, settings, {openStock}) {
        super(sourceActor, 0.5, St.Side.TOP);
        this._settings = settings;
        this._openStock = openStock;
        this.editing = false;
        this.actor.add_style_class_name('bcc-menu panel-menu');
        this.box.add_style_class_name('bcc-box');
        Main.uiGroup.add_child(this.actor);
        this.actor.hide();

        // ---- pages: main (grid) and detail, side by side in a clipped stack
        this._stack = new St.Widget({style_class: 'bcc-stack', layout_manager: new Clutter.BinLayout(),
            clip_to_allocation: true, x_expand: true});
        this._main = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, x_expand: true, style_class: 'bcc-main'});
        const gl = new Clutter.GridLayout({column_homogeneous: true, row_spacing: 10, column_spacing: 10});
        this._grid = new St.Widget({style_class: 'bcc-grid', layout_manager: gl, x_expand: true});
        this._main.add_child(this._grid);

        // edit tray: tiles that are not shown
        this._tray = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, style_class: 'bcc-tray', visible: false});
        this._tray.add_child(new St.Label({text: 'ADD TILES', style_class: 'bcc-tray-title'}));
        this._trayFlow = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, style_class: 'bcc-tray-rows', x_expand: true});
        this._tray.add_child(this._trayFlow);
        this._main.add_child(this._tray);

        this._detail = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, x_expand: true, y_expand: true,
            style_class: 'bcc-detail', visible: false});
        const head = new St.BoxLayout({style_class: 'bcc-detail-head'});
        const back = new St.Button({style_class: 'bcc-round', can_focus: true, child: new St.Icon({icon_name: 'go-previous-symbolic', icon_size: 16})});
        back.connect('clicked', () => this.closeDetail());
        this._detailIcon = new St.Icon({style_class: 'bcc-detail-icon'});
        this._detailTitle = new St.Label({style_class: 'bcc-detail-title', y_align: Clutter.ActorAlign.CENTER});
        head.add_child(back);
        head.add_child(this._detailIcon);
        head.add_child(this._detailTitle);
        this._detail.add_child(head);
        this._detailScroll = new St.ScrollView({style_class: 'bcc-detail-scroll', hscrollbar_policy: St.PolicyType.NEVER,
            vscrollbar_policy: St.PolicyType.AUTOMATIC, overlay_scrollbars: true, x_expand: true, y_expand: true});
        this._detailBody = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, x_expand: true});
        this._detailScroll.child = this._detailBody;
        this._detail.add_child(this._detailScroll);

        this._stack.add_child(this._main);
        this._stack.add_child(this._detail);
        this.box.add_child(this._stack);

        // ---- footer
        const foot = new St.BoxLayout({style_class: 'bcc-footer', x_expand: true});
        const fbtn = (icon, tip, fn) => {
            const b = new St.Button({style_class: 'bcc-round', can_focus: true, accessible_name: tip,
                child: new St.Icon({icon_name: icon, icon_size: 16})});
            b.connect('clicked', fn);
            foot.add_child(b);
            return b;
        };
        fbtn('emblem-system-symbolic', 'Settings', () => {
            this.close();
            T.spawnApp(['gnome-control-center']);
        });
        fbtn('system-lock-screen-symbolic', 'Lock', () => {
            this.close();
            T.spawn([GLib.build_filenamev([GLib.get_home_dir(), 'bapirlo-os', 'bin', 'bapirlo-lockd']), '--lock-now']);
        });
        fbtn('system-shutdown-symbolic', 'Power off / Restart / Log out', () => this._openPowerMenu());
        foot.add_child(new St.Widget({x_expand: true}));
        this._editBtn = fbtn('document-edit-symbolic', 'Edit tiles', () => this.setEditing(!this.editing));
        this._classicBtn = new St.Button({style_class: 'bcc-pill', can_focus: true, label: 'Classic'});
        this._classicBtn.connect('clicked', () => {
            this.close(BoxPointer.PopupAnimation.NONE);
            this._openStock();
        });
        foot.add_child(this._classicBtn);
        this.box.add_child(foot);

        this._tiles = new Map();
        this._settings.connectObject('changed::tiles', () => this._rebuild(), this);
        this._rebuild();
    }

    // ------------------------------------------------------------ tiles
    get _order() {
        return this._settings.get_strv('tiles').filter(id => NAMES[id]);
    }

    _rebuild() {
        const order = this._order;
        for (const [id, t] of this._tiles) {
            if (!order.includes(id)) {
                t.destroy();
                this._tiles.delete(id);
            }
        }
        for (const id of order) {
            if (this._tiles.has(id))
                continue;
            const t = makeTile(id, this);
            if (!t)
                continue;
            t.connect('expand', () => this.openDetail(t));
            t.connect('notify::visible', () => this._place());
            // GNOME 51: a DnD gesture blocks clicks even when disabled → attached only while editing
            t._drag = DND.makeDraggable(t, {restoreOnSuccess: false, dragActorOpacity: 200});
            if (!this.editing)
                t.remove_action(t._drag.startGesture);
            t.getDragActor = () => new Clutter.Clone({source: t, width: t.width, height: t.height});
            t.getDragActorSource = () => t;
            this._tiles.set(id, t);
        }
        this._place();
        this._fillTray();
    }

    // dense first-fit placement on a 4-column grid
    _place() {
        const inPanel = a => !!a && this.actor.contains(a);
        const hadFocus = this.isOpen && inPanel(global.stage.get_key_focus());
        const gl = this._grid.layout_manager;
        for (const c of this._grid.get_children())
            this._grid.remove_child(c);
        const rows = [];
        const fits = (r, c, span) => {
            for (let i = 0; i < span; i++) {
                if (c + i >= COLS || rows[r]?.[c + i])
                    return false;
            }
            return true;
        };
        for (const id of this._order) {
            const t = this._tiles.get(id);
            if (!t || !t.visible)
                continue;
            let placed = false;
            for (let r = 0; !placed; r++) {
                rows[r] ??= [];
                for (let c = 0; c + t.span <= COLS && !placed; c++) {
                    if (fits(r, c, t.span)) {
                        for (let i = 0; i < t.span; i++)
                            rows[r][c + i] = id;
                        this._grid.add_child(t);
                        gl.attach(t, c, r, t.span, 1);
                        placed = true;
                    }
                }
            }
        }
        if (hadFocus && !inPanel(global.stage.get_key_focus()))
            this.actor.grab_key_focus();
        // invisible tiles still need a parent so they can come back
        for (const id of this._order) {
            const t = this._tiles.get(id);
            if (t && !t.visible && !t.get_parent())
                this._grid.add_child(t);
        }
    }

    _fillTray() {
        this._trayFlow.destroy_all_children();
        const hidden = ALL_TILES.filter(id => !this._order.includes(id));
        let row = null;
        hidden.forEach((id, i) => {
            if (i % 3 === 0) {
                row = new St.BoxLayout({style_class: 'bcc-tray-row'});
                this._trayFlow.add_child(row);
            }
            const box = new St.BoxLayout({style_class: 'bcc-chip-box'});
            box.add_child(new St.Icon({icon_name: 'list-add-symbolic', icon_size: 12}));
            box.add_child(new St.Label({text: NAMES[id]}));
            const chip = new St.Button({style_class: 'bcc-chip', can_focus: true, child: box});
            chip.connect('clicked', () => this._settings.set_strv('tiles', [...this._order, id]));
            row.add_child(chip);
        });
        this._tray.visible = this.editing;
        this._trayFlow.visible = hidden.length > 0;
    }

    removeTile(id) {
        this._settings.set_strv('tiles', this._order.filter(x => x !== id));
    }

    moveTile(id, beforeId) {
        const o = this._order.filter(x => x !== id);
        o.splice(o.indexOf(beforeId), 0, id);
        this._settings.set_strv('tiles', o);
    }

    setEditing(on) {
        if (on)
            this.closeDetail(false);
        this.editing = on;
        for (const t of this._tiles.values()) {
            t.setEditing(on);
            const g = t._drag.startGesture;
            if (on && !t.get_actions().includes(g))
                t.add_action(g);
            else if (!on && t.get_actions().includes(g))
                t.remove_action(g);
        }
        if (on)
            this._editBtn.add_style_pseudo_class('checked');
        else
            this._editBtn.remove_style_pseudo_class('checked');
        this._editBtn.child.icon_name = on ? 'object-select-symbolic' : 'document-edit-symbolic';
        this._fillTray();
        for (const t of this._tiles.values())
            t.onOpen();   // re-sync reactive state
    }

    // ------------------------------------------------------------ detail page
    openDetail(tile) {
        if (this.editing)
            return;
        // close the current page FIRST: it may hold the very menu the new page borrows
        this.closeDetail(false);
        const d = tile.buildDetail();
        if (!d)
            return;
        this._detailInfo = d;
        if (d.gicon)
            this._detailIcon.gicon = d.gicon;
        else
            this._detailIcon.icon_name = d.icon ?? null;
        this._detailTitle.text = d.title;
        this._detailBody.add_child(d.actor);
        this._slide(this._main, this._detail, 1);
    }

    closeDetail(animate = true) {
        const d = this._detailInfo;
        if (!d)
            return;
        this._detailInfo = null;
        const finish = () => {
            d.onClose?.();
            this._detailBody.destroy_all_children();
        };
        if (animate) {
            this._slide(this._detail, this._main, -1, finish);
        } else {
            this._detail.hide();
            this._main.show();
            this._main.translation_x = 0;
            this._main.opacity = 255;
            finish();
        }
    }

    _slide(from, to, dir, done) {
        const w = this._stack.width || 380;
        from.remove_all_transitions();
        to.remove_all_transitions();
        to.show();
        to.translation_x = dir * w * 0.25;
        to.opacity = 0;
        from.ease({translation_x: -dir * w * 0.25, opacity: 0, duration: PAGE_MS, mode: T.EASE,
            onComplete: () => {
                from.hide();
                from.translation_x = 0;
                from.opacity = 255;
                done?.();
            }});
        to.ease({translation_x: 0, opacity: 255, duration: PAGE_MS, mode: T.EASE});
    }

    _openPowerMenu() {
        const menu = T.FIND.power();
        if (!menu)
            return;
        const fake = {menu};
        const d = T.borrowMenu(fake, 'Power Off', {icon_name: 'system-shutdown-symbolic'});
        // reuse openDetail's page handling with an already-built detail
        this.openDetail({buildDetail: () => d});
    }

    // ------------------------------------------------------------ open / close
    open(animate) {
        if (this.isOpen)
            return;
        for (const t of this._tiles.values())
            t.onOpen();
        super.open(animate);
        // tiles fade + scale in with a small stagger
        let i = 0;
        for (const id of this._order) {
            const t = this._tiles.get(id);
            if (!t?.visible)
                continue;
            t.remove_all_transitions();
            t.opacity = 0;
            t.scale_x = t.scale_y = 0.92;
            t.ease({opacity: 255, scale_x: 1, scale_y: 1, delay: 40 + i++ * STAGGER_MS, duration: 240, mode: T.EASE});
        }
    }

    close(animate) {
        if (!this.isOpen)
            return;
        super.close(animate);
        if (this.editing)
            this.setEditing(false);
        this.closeDetail(false);
        for (const t of this._tiles.values())
            t.onClose?.();
    }

    destroy() {
        this.closeDetail(false);
        this._settings.disconnectObject(this);
        for (const t of this._tiles.values())
            t.destroy();
        this._tiles.clear();
        super.destroy();
    }
}
