// Bapirlo Bar — capsule layout of the whole top bar (GNOME Shell 51).
//   left:   [Bapirlo logo menu] [workspace numbers] (quick launch · power chip) [focused app name]
//   centre: clock + date — the Dynamic Island's resting capsule
//   right:  (media · AirPods · weather · Vitals)  (updates · replay · places · drives · lock keys ·
//           tray icons · the rest)  (Control Centre)
// ( ) = a soft capsule: a St.BoxLayout the item containers are moved into, so related things sit
// together. Other extensions keep adding their buttons to the panel boxes; every child-added
// queues one idle re-layout that sorts newcomers into place. A capsule hides when nothing in it
// is visible. disable() puts every container back into the plain panel boxes.
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const LEFT = ['LogoMenu', 'ArcMenu', 'bapirlo-ws'];   // ArcMenu's button is hidden when Logo Menu runs
const LAUNCH = ['bapirlo-launch', 'bapirlo-power'];
const AFTER_LAUNCH = ['bapirlo-appname'];   // last on the left: its width changes, nothing after it moves
const STATUS = ['bapirlo-media', 'bapirlo-airpods', 'simple-weather@romanlefler.com', 'vitalsMenu'];
const EXTRAS_FIRST = ['ArchUpdateIndicator', 'bapirlo-replay', 'places-menu', 'drive-menu', 'lockkeys'];
const SYSTEM = ['bapirlo-privacy', 'screenRecording', 'screenSharing', 'dwellClick', 'a11y', 'keyboard', 'quickSettings'];
export const HIDDEN = ['clipboardIndicator'];   // Super+V still opens its menu (see states.js)

export class CapsuleLayout {
    constructor() {
        const panel = Main.panel;
        this._boxes = [panel._leftBox, panel._centerBox, panel._rightBox];
        this._caps = {};
        for (const name of ['launch', 'status', 'extras', 'system']) {
            const cap = new St.BoxLayout({
                style_class: `bapirlo-capsule bapirlo-capsule-${name}`,
                y_align: Clutter.ActorAlign.CENTER,
                visible: false,
            });
            cap.connectObject(
                'child-added', (_c, child) => this._watch(child),
                'child-removed', (_c, child) => this._unwatch(child),
                this);
            this._caps[name] = cap;
        }
        this._watched = new Set();
        this._hidden = new Set();
        for (const box of this._boxes)
            box.connectObject('child-added', () => this.queue(), this);
        this._layout();
    }

    get capsules() {
        return this._caps;
    }

    queue() {
        if (this._idleId)
            return;
        this._idleId = GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
            this._idleId = 0;
            this._layout();
            return GLib.SOURCE_REMOVE;
        });
    }

    // move `actor` to `parent` at `index` — only when it is not there already, so a re-layout
    // that changes nothing emits no child-added (and never loops)
    _put(actor, parent, index) {
        if (!actor)
            return index;
        const old = actor.get_parent();
        if (old !== parent) {
            old?.remove_child(actor);
            parent.insert_child_at_index(actor, index);
        } else if (parent.get_child_at_index(index) !== actor) {
            parent.set_child_at_index(actor, Math.min(index, parent.get_n_children() - 1));
        }
        return index + 1;
    }

    _layout() {
        const area = Main.panel.statusArea;
        const c = role => area[role]?.container ?? null;
        const [left, centre, right] = this._boxes;
        const caps = this._caps;
        const known = new Set([...LEFT, ...LAUNCH, ...AFTER_LAUNCH, ...STATUS, ...EXTRAS_FIRST,
            ...SYSTEM, ...HIDDEN, 'dateMenu'].map(c).filter(Boolean));

        // left
        let i = 0;
        for (const role of LEFT)
            i = c(role) ? this._put(c(role), left, i) : i;
        i = this._put(caps.launch, left, i);
        for (const role of AFTER_LAUNCH)
            i = c(role) ? this._put(c(role), left, i) : i;
        let j = 0;
        for (const role of LAUNCH)
            j = c(role) ? this._put(c(role), caps.launch, j) : j;

        // centre: only the clock (+ date) stays in the island capsule
        this._put(c('dateMenu'), centre, 0);

        // right: three capsules, in this order
        this._put(caps.status, right, 0);
        this._put(caps.extras, right, 1);
        this._put(caps.system, right, 2);
        j = 0;
        for (const role of STATUS)
            j = c(role) ? this._put(c(role), caps.status, j) : j;
        j = 0;
        for (const role of SYSTEM)
            j = c(role) ? this._put(c(role), caps.system, j) : j;
        j = 0;
        for (const role of [...EXTRAS_FIRST, ...HIDDEN])
            j = c(role) ? this._put(c(role), caps.extras, j) : j;
        // everything else that landed in the centre or right box (tray icons, GSConnect, ddterm …)
        for (const box of [centre, right]) {
            for (const child of box.get_children()) {
                if (child === caps.status || child === caps.extras || child === caps.system ||
                    known.has(child))
                    continue;
                this._put(child, caps.extras, caps.extras.get_n_children());
            }
        }

        for (const role of HIDDEN) {
            const h = c(role);
            if (h) {
                h.hide();
                this._hidden.add(h);
            }
        }
        this._syncCapsules();
    }

    // ------------------------------------------------------------ capsule visibility

    _watch(container) {
        if (this._watched.has(container))
            return;
        this._watched.add(container);
        const sync = () => this._queueSync();
        container.connectObject('notify::visible', sync, 'destroy', () => this._watched.delete(container), this);
        container.get_first_child?.()?.connectObject('notify::visible', sync, this);
        this._queueSync();
    }

    _unwatch(container) {
        if (!this._watched.delete(container))
            return;
        container.disconnectObject(this);
        container.get_first_child?.()?.disconnectObject(this);
        this._queueSync();
    }

    _queueSync() {
        if (this._syncId)
            return;
        this._syncId = GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
            this._syncId = 0;
            this._syncCapsules();
            return GLib.SOURCE_REMOVE;
        });
    }

    _syncCapsules() {
        for (const cap of Object.values(this._caps)) {
            const shown = cap.get_children().filter(ch => ch.visible && (ch.get_first_child?.()?.visible ?? true));
            cap.visible = shown.length > 0;
            // first/last visible child get rounded ends of their own hover highlight
            for (const ch of cap.get_children()) {
                ch.remove_style_class_name('bapirlo-cap-first');
                ch.remove_style_class_name('bapirlo-cap-last');
            }
            shown[0]?.add_style_class_name('bapirlo-cap-first');
            shown.at(-1)?.add_style_class_name('bapirlo-cap-last');
        }
    }

    destroy() {
        for (const id of [this._idleId, this._syncId]) {
            if (id)
                GLib.source_remove(id);
        }
        this._idleId = this._syncId = 0;
        for (const box of this._boxes)
            box.disconnectObject(this);
        for (const container of this._watched) {
            container.disconnectObject(this);
            container.get_first_child?.()?.disconnectObject(this);
        }
        this._watched.clear();
        for (const h of this._hidden)
            h.show?.();
        this._hidden.clear();

        // give every container back to a plain panel box, in the order it was shown
        const [left, , right] = this._boxes;
        for (const [name, cap] of Object.entries(this._caps)) {
            cap.disconnectObject(this);
            const target = name === 'launch' ? left : right;
            let index = cap.get_parent() === target ? target.get_children().indexOf(cap) : target.get_n_children();
            for (const child of cap.get_children()) {
                child.remove_style_class_name('bapirlo-cap-first');
                child.remove_style_class_name('bapirlo-cap-last');
                cap.remove_child(child);
                target.insert_child_at_index(child, index++);
            }
            cap.destroy();
        }
        this._caps = {};
    }
}
