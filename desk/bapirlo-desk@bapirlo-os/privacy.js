// Bapirlo Desk — privacy dots in the top bar (system capsule, left of the Control Centre icons).
//   red   = an app is recording from a microphone
//   green = the camera is in use
//   blue  = the screen is being shared / cast (portal screencast, remote desktop)
// The state comes from GNOME's own privacy indicators (status/volume.js InputIndicator,
// status/camera.js, status/remoteAccess.js) — no polling. Their three grey icons are tucked away
// while the dots exist (the indicators keep working, only their icons leave the bar), so each
// thing shows once. GNOME's "Stop sharing" button stays. Hover = which app category is active.
import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

const KINDS = [
    {key: 'mic', find: qs => qs._volumeInput, what: 'Microphone'},
    {key: 'camera', find: qs => qs._camera, what: 'Camera'},
    {key: 'screen', find: qs => qs._remoteAccess, what: 'Screen sharing'},
];

const Dots = GObject.registerClass(
class BapirloPrivacyDots extends PanelMenu.Button {
    _init() {
        super._init(0.5, 'Privacy', true);
        this.add_style_class_name('bpd-button');
        this.reactive = false;   // just a light; nothing to click
        this._box = new St.BoxLayout({style_class: 'bpd-box', y_align: Clutter.ActorAlign.CENTER});
        this.add_child(this._box);
        this.dots = {};
        for (const k of KINDS) {
            const dot = new St.Widget({style_class: `bpd-dot bpd-${k.key}`, y_align: Clutter.ActorAlign.CENTER, visible: false});
            this._box.add_child(dot);
            this.dots[k.key] = dot;
        }
        this.visible = false;
    }

    sync() {
        this.visible = Object.values(this.dots).some(d => d.visible);
        const on = KINDS.filter(k => this.dots[k.key].visible).map(k => k.what);
        this.accessible_name = on.length ? `In use: ${on.join(', ')}` : 'Privacy';
    }
});

export class PrivacyDots {
    constructor() {
        this._button = new Dots();
        Main.panel.addToStatusArea('bapirlo-privacy', this._button, 0, 'right');
        this._holder = new St.Widget({visible: false});   // where GNOME's icons wait, off-stage
        Main.uiGroup.add_child(this._holder);
        this._moved = [];
        this._tries = 0;
        this._attach();
    }

    _attach() {
        const qs = Main.panel.statusArea.quickSettings;
        // the stock indicators are created asynchronously at startup
        if (!qs?._volumeInput || !qs._camera || !qs._remoteAccess) {
            if (++this._tries < 40)
                this._retry = setTimeout(() => this._attach(), 250);
            return;
        }
        for (const k of KINDS) {
            const ind = k.find(qs);
            const icon = ind?._indicator;
            if (!icon)
                continue;
            const dot = this._button.dots[k.key];
            const sync = () => {
                dot.visible = icon.visible;
                this._button.sync();
            };
            icon.connectObject('notify::visible', sync, this);
            sync();
            // tuck GNOME's own grey icon away (remember where it was)
            const parent = ind.get_parent();
            if (parent) {
                this._moved.push({actor: ind, parent, index: parent.get_children().indexOf(ind)});
                parent.remove_child(ind);
                this._holder.add_child(ind);
            }
        }
    }

    destroy() {
        clearTimeout(this._retry);
        const qs = Main.panel.statusArea.quickSettings;
        for (const k of KINDS)
            k.find(qs ?? {})?._indicator?.disconnectObject(this);
        // put GNOME's icons back where they were
        for (const {actor, parent, index} of this._moved.reverse()) {
            this._holder.remove_child(actor);
            parent.insert_child_at_index(actor, Math.min(index, parent.get_n_children()));
        }
        this._moved = [];
        this._holder.destroy();
        this._button.destroy();
    }
}
