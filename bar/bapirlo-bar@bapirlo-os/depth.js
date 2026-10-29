// Bapirlo Bar — 3D wallpaper button.
//   click = 3D depth effect on / off (bapirlo-live setting "depth"). Red "3D" while on, dim while off.
//   Hidden when bapirlo-live (and so its schema) isn't installed.
// bapirlo-live re-reads its settings on 'changed', so the switch is instant — no restart.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {Group, attachTooltip, addLift} from './util.js';

const LIVE_UUID = 'bapirlo-live@bapirlo-os';
const LIVE_SCHEMA = 'org.gnome.shell.extensions.bapirlo-live';

function liveSettings() {
    const dir = GLib.build_filenamev([GLib.get_user_data_dir(), 'gnome-shell', 'extensions', LIVE_UUID, 'schemas']);
    if (!GLib.file_test(GLib.build_filenamev([dir, 'gschemas.compiled']), GLib.FileTest.EXISTS))
        return null;
    const src = Gio.SettingsSchemaSource.new_from_directory(dir, Gio.SettingsSchemaSource.get_default(), false);
    const schema = src.lookup(LIVE_SCHEMA, false);
    return schema?.has_key('depth') ? new Gio.Settings({settings_schema: schema}) : null;
}

export const DepthButton = GObject.registerClass(
class BapirloDepthButton extends Group {
    _init() {
        super._init('Bapirlo 3D wallpaper', 'bapirlo-depth');
        this._label = new St.Label({text: '3D', style_class: 'bapirlo-depth-label', y_align: Clutter.ActorAlign.CENTER});
        this._btn = new St.Button({
            style_class: 'bapirlo-depth-btn', can_focus: true, track_hover: true,
            child: this._label, y_align: Clutter.ActorAlign.CENTER,
        });
        this.box.add_child(this._btn);
        addLift(this._btn, this._label);
        attachTooltip(this._btn, () => this._settings?.get_boolean('depth')
            ? '3D wallpaper on — click to turn it off'
            : '3D wallpaper off — click to turn it on');
        this._btn.connect('clicked', () => {
            if (this._settings)
                this._settings.set_boolean('depth', !this._settings.get_boolean('depth'));
        });

        try {
            this._settings = liveSettings();
        } catch (e) {
            logError(e, 'bapirlo-bar: bapirlo-live settings');
        }
        this._settings?.connectObject('changed::depth', () => this._sync(), this);
        this._sync();
    }

    _sync() {
        this.visible = !!this._settings;
        if (this._settings?.get_boolean('depth'))
            this._btn.add_style_class_name('on');
        else
            this._btn.remove_style_class_name('on');
    }

    destroy() {
        this._settings?.disconnectObject(this);
        this._settings = null;
        super.destroy();
    }
});
