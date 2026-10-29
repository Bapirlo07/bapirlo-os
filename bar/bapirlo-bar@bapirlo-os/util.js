// Kuro Bar — shared bits: a panel "group" (a PanelMenu.Button without menu whose children
// get their own hover instead of one big highlight) and a small tooltip under the bar.
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

export const HOVER_MS = 180;
export const EASE = Clutter.AnimationMode.EASE_OUT_QUAD;

export const Group = GObject.registerClass(
class BapirloGroup extends PanelMenu.Button {
    _init(name, extraClass = '', separator = false) {
        super._init(0.5, name, true);
        this.add_style_class_name(`bapirlo-group ${extraClass}`.trim());
        const outer = new St.BoxLayout({style_class: 'bapirlo-group-outer', y_align: Clutter.ActorAlign.CENTER});
        if (separator)
            outer.add_child(new St.Widget({style_class: 'bapirlo-sep', y_align: Clutter.ActorAlign.CENTER}));
        this.box = new St.BoxLayout({style_class: 'bapirlo-group-box', y_align: Clutter.ActorAlign.CENTER});
        outer.add_child(this.box);
        this.add_child(outer);
    }
});

// One tooltip actor shared by every widget of the extension.
let _tip = null;
let _tipTimer = 0;

// `tracker` (default: the actor) owns the signal connections, so tooltips put on other
// extensions' buttons can be taken off again with actor.disconnectObject(tracker).
export function attachTooltip(actor, textFn, tracker = actor) {
    const menuOpen = () => actor.menu?.isOpen ?? false;
    actor.connectObject('notify::hover', () => {
        if (_tipTimer) {
            GLib.source_remove(_tipTimer);
            _tipTimer = 0;
        }
        if (!actor.hover) {
            hideTooltip();
            return;
        }
        _tipTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 450, () => {
            _tipTimer = 0;
            const text = textFn();
            if (text && actor.hover && actor.get_stage() && !menuOpen())
                showTooltip(actor, text);
            return GLib.SOURCE_REMOVE;
        });
    }, 'destroy', () => hideTooltip(), tracker);
    // a dropdown opening from the item replaces its tooltip
    actor.menu?.connectObject?.('open-state-changed', (_m, open) => {
        if (open)
            hideTooltip();
    }, tracker);
}

function showTooltip(actor, text) {
    if (!_tip) {
        _tip = new St.Label({style_class: 'bapirlo-tooltip', opacity: 0, reactive: false});
        Main.layoutManager.uiGroup.add_child(_tip);
    }
    _tip.text = text;
    const [x, y] = actor.get_transformed_position();
    const [w, h] = actor.get_transformed_size();
    const [, tw] = _tip.get_preferred_width(-1);
    const mon = Main.layoutManager.findMonitorForActor(actor) ?? Main.layoutManager.primaryMonitor;
    const tx = Math.max(mon.x + 8, Math.min(Math.round(x + w / 2 - tw / 2), mon.x + mon.width - tw - 8));
    _tip.set_position(tx, Math.round(y + h + 10));
    _tip.translation_y = -4;
    _tip.show();
    _tip.ease({opacity: 255, translation_y: 0, duration: HOVER_MS, mode: EASE});
}

export function hideTooltip() {
    if (_tip?.visible)
        _tip.ease({opacity: 0, duration: 120, mode: EASE, onComplete: () => _tip?.hide()});
}

export function destroyTooltip() {
    if (_tipTimer) {
        GLib.source_remove(_tipTimer);
        _tipTimer = 0;
    }
    _tip?.destroy();
    _tip = null;
}

// Hover "lift": scale up a little and rise 1px. Used by every clickable icon in the bar.
export function addLift(button, target, scale = 1.1) {
    target.set_pivot_point(0.5, 0.5);
    button.connectObject('notify::hover', () => {
        const on = button.hover;
        target.ease({
            scale_x: on ? scale : 1, scale_y: on ? scale : 1, translation_y: on ? -1 : 0,
            duration: HOVER_MS, mode: EASE,
        });
    }, button);
}
