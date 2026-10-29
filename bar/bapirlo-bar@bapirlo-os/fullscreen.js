// Kuro Bar — fullscreen button for the focused window (made for Waydroid's Android window,
// works for any normal window).
//   click = fullscreen on / off. While fullscreen, push the pointer against the top edge
//   (reveal.js) to bring the bar back and click again to leave.
// Hidden when nothing is focused (desktop) and in the overview.
import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {Group, attachTooltip, addLift} from './util.js';

export const FullscreenButton = GObject.registerClass(
class BapirloFullscreenButton extends Group {
    _init() {
        super._init('Kuro fullscreen', 'bapirlo-fullscreen');
        this._icon = new St.Icon({style_class: 'system-status-icon', icon_name: 'view-fullscreen-symbolic'});
        this._btn = new St.Button({
            style_class: 'bapirlo-fullscreen-btn', can_focus: true, track_hover: true,
            child: this._icon, y_align: Clutter.ActorAlign.CENTER,
        });
        this.box.add_child(this._btn);
        addLift(this._btn, this._icon);
        attachTooltip(this._btn, () => this._win?.is_fullscreen()
            ? 'Leave fullscreen'
            : `Make ${this._win?.get_title() || 'this window'} fullscreen`);
        // the panel never takes keyboard focus, so focus_window is still the app's window here
        this._btn.connect('clicked', () => this._toggle());

        global.display.connectObject('notify::focus-window', () => this._track(), this);
        Main.overview.connectObject('showing', () => this._sync(), 'hidden', () => this._sync(), this);
        this._track();
    }

    _track() {
        this._win?.disconnectObject(this);
        const win = global.display.focus_window;
        this._win = win?.get_window_type() === Meta.WindowType.NORMAL ? win : null;
        this._win?.connectObject('notify::fullscreen', () => this._sync(),
            'unmanaged', () => {
                this._win.disconnectObject(this);
                this._win = null;
                this._sync();
            }, this);
        this._sync();
    }

    _sync() {
        const full = this._win?.is_fullscreen() ?? false;
        this._icon.icon_name = full ? 'view-restore-symbolic' : 'view-fullscreen-symbolic';
        this.visible = !!this._win && !Main.overview.visible;
    }

    _toggle() {
        const win = this._win;
        if (!win)
            return;
        if (win.is_fullscreen()) {
            win.unmake_fullscreen();
        } else {
            win.make_fullscreen();
            win.activate(global.get_current_time());
        }
    }

    destroy() {
        this._win?.disconnectObject(this);
        this._win = null;
        global.display.disconnectObject(this);
        Main.overview.disconnectObject(this);
        super.destroy();
    }
});
