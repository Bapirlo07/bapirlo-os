// Bapirlo Bar — quick launch.
//   click = focus the app (or open it) · middle-click = new window
//   dot under the icon: ember = running, crimson pill = focused
import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {Group, addLift, attachTooltip, EASE, HOVER_MS} from './util.js';

// first id that exists wins (VS Code ships under a different id per build)
export const APPS = [
    ['com.google.Chrome.desktop', 'google-chrome.desktop'],
    ['code.desktop', 'visual-studio-code.desktop', 'code-oss.desktop'],
    ['org.gnome.Nautilus.desktop'],
    ['Alacritty.desktop', 'org.gnome.Ptyxis.desktop'],
];

const Launcher = GObject.registerClass(
class BapirloLauncher extends St.Button {
    _init(app) {
        super._init({
            style_class: 'bapirlo-launcher',
            can_focus: true,
            track_hover: true,
            button_mask: St.ButtonMask.ONE | St.ButtonMask.TWO,
            accessible_name: app.get_name(),
        });
        this.app = app;
        const box = new St.BoxLayout({
            orientation: Clutter.Orientation.VERTICAL,
            style_class: 'bapirlo-launcher-box',
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._icon = new St.Icon({gicon: app.get_icon(), style_class: 'bapirlo-launcher-icon'});
        this._dot = new St.Widget({style_class: 'bapirlo-launcher-dot', x_align: Clutter.ActorAlign.CENTER});
        box.add_child(this._icon);
        box.add_child(this._dot);
        this.set_child(box);

        addLift(this, this._icon, 1.12);
        attachTooltip(this, () => app.get_name());
        this.connect('clicked', (_b, button) => {
            if (button === Clutter.BUTTON_MIDDLE && app.can_open_new_window())
                app.open_new_window(-1);
            else
                app.activate();
            Main.overview.hide();
        });
        app.connectObject('notify::state', () => this._sync(true), this);
        Shell.WindowTracker.get_default().connectObject('notify::focus-app', () => this._sync(true), this);
        this._sync(false);
    }

    _sync(animate) {
        const running = this.app.state !== Shell.AppState.STOPPED;
        const focused = Shell.WindowTracker.get_default().focus_app === this.app;
        this._dot.remove_style_class_name('focused');
        if (focused)
            this._dot.add_style_class_name('focused');
        const sf = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        const props = {opacity: running ? 255 : 0, width: (focused ? 12 : 4) * sf};
        if (animate && this.get_stage())
            this._dot.ease({...props, duration: HOVER_MS, mode: EASE});
        else
            this._dot.set(props);
    }
});

export const QuickLaunch = GObject.registerClass(
class BapirloQuickLaunch extends Group {
    _init() {
        super._init('Bapirlo quick launch', 'bapirlo-launch', true);
        Shell.AppSystem.get_default().connectObject('installed-changed', () => this._rebuild(), this);
        this._rebuild();
    }

    _rebuild() {
        this.box.destroy_all_children();
        const sys = Shell.AppSystem.get_default();
        for (const ids of APPS) {
            const app = ids.map(id => sys.lookup_app(id)).find(Boolean);
            if (app)
                this.box.add_child(new Launcher(app));
        }
        this.visible = this.box.get_n_children() > 0;
    }

    destroy() {
        Shell.AppSystem.get_default().disconnectObject(this);
        super.destroy();
    }
});
