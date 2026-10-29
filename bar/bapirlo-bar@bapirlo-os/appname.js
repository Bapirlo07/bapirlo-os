// Kuro Bar — the focused app's name, Mac style (last item on the left).
//   click = small menu: New Window · Show All Windows · Quit
//   no focused app (desktop) = "Desktop"; hidden in the overview
//   apps without a launcher (e.g. a terminal with its own window class) get a readable name
import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import Pango from 'gi://Pango';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const KNOWN = {'bapirlo-ai': 'Kuro AI', 'bapirlo-update': 'Updates'};

// "bapirlo-ai" → "Kuro AI" (table), "my_tool.app" → "My Tool App"
function appName(app) {
    const name = app.get_name();
    if (app.get_app_info())
        return name;
    return KNOWN[name] ?? name.replace(/[-_.]+/g, ' ').replace(/\b\w/g, ch => ch.toUpperCase());
}

export const AppName = GObject.registerClass(
class BapirloAppName extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'Kuro app name');
        this.add_style_class_name('bapirlo-appname');
        this._label = new St.Label({style_class: 'bapirlo-appname-label', y_align: Clutter.ActorAlign.CENTER});
        this._label.clutter_text.ellipsize = Pango.EllipsizeMode.END;
        this.add_child(this._label);
        this.label_actor = this._label;

        this._title = new PopupMenu.PopupMenuItem('', {reactive: false});
        this._title.add_style_class_name('bapirlo-appname-title');
        this.menu.addMenuItem(this._title);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._newWindow = this.menu.addAction('New Window', () => this._app?.open_new_window(-1));
        this._allWindows = this.menu.addAction('Show All Windows', () => Main.overview.show());
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._quit = this.menu.addAction('Quit', () => this._app?.request_quit());
        this.menu.connect('open-state-changed', (_m, open) => {
            if (open)
                this._syncMenu();
        });

        Shell.WindowTracker.get_default().connectObject('notify::focus-app', () => this._sync(), this);
        Main.overview.connectObject('showing', () => this._sync(), 'hidden', () => this._sync(), this);
        this._sync();
    }

    _sync() {
        const app = Shell.WindowTracker.get_default().focus_app;
        this._app = app;
        this._label.text = app ? appName(app) : 'Desktop';
        this.reactive = !!app;
        this.visible = !Main.overview.visible;
        if (!app)
            this.menu.close();
    }

    _syncMenu() {
        const app = this._app;
        this._title.label.text = app ? appName(app) : '';
        this._newWindow.setSensitive(!!app?.can_open_new_window());
        this._quit.label.text = app ? `Quit ${appName(app)}` : 'Quit';
        this._quit.setSensitive(!!app);
    }

    destroy() {
        Shell.WindowTracker.get_default().disconnectObject(this);
        Main.overview.disconnectObject(this);
        super.destroy();
    }
});
