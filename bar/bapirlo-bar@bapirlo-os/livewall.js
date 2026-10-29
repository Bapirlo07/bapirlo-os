// Kuro Bar — live wallpaper button.
//   click = live wallpaper on / off (bapirlo-wallpaper live toggle). Red while the video plays,
//   dim while the still frame shows. Hidden when the current wallpaper is a picture.
// State comes from ~/.config/bapirlo/wallpaper.json (keys `live` + `current`), watched for changes,
// so the Control Centre tile and the CLI keep it in sync.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {Group, attachTooltip, addLift} from './util.js';

const CONF = GLib.build_filenamev([GLib.get_user_config_dir(), 'bapirlo', 'wallpaper.json']);
const CLI = GLib.build_filenamev([GLib.get_home_dir(), 'bapirlo-os', 'bin', 'bapirlo-wallpaper']);
const VID_EXT = ['.mp4', '.webm', '.mkv', '.mov', '.gif'];   // = VID_EXT in lib/bapirlo_wallpaper.py

export const LiveWallButton = GObject.registerClass(
class BapirloLiveWallButton extends Group {
    _init() {
        super._init('Kuro live wallpaper', 'bapirlo-livewall');
        this._icon = new St.Icon({style_class: 'system-status-icon bapirlo-livewall-icon'});
        this._btn = new St.Button({
            style_class: 'bapirlo-livewall-btn', can_focus: true, track_hover: true,
            child: this._icon, y_align: Clutter.ActorAlign.CENTER,
        });
        this.box.add_child(this._btn);
        addLift(this._btn, this._icon);
        attachTooltip(this._btn, () => this._live
            ? 'Live wallpaper on — click for the still frame'
            : 'Live wallpaper off — click to play it');
        this._btn.connect('clicked', () => this._toggle());

        this._live = true;
        this.visible = false;
        // the CLI saves by rename (tmp → wallpaper.json): watch moves too
        this._monitor = Gio.File.new_for_path(CONF).monitor_file(Gio.FileMonitorFlags.WATCH_MOVES, null);
        this._monitor.connect('changed', () => this._queueSync());
        this._sync();
    }

    _queueSync() {
        if (this._syncId)
            return;
        this._syncId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 150, () => {
            this._syncId = 0;
            this._sync();
            return GLib.SOURCE_REMOVE;
        });
    }

    _sync() {
        let conf = {};
        try {
            const [, bytes] = GLib.file_get_contents(CONF);
            conf = JSON.parse(new TextDecoder().decode(bytes));
        } catch {}
        const current = (conf.current ?? '').toLowerCase();
        this._live = conf.live ?? true;
        this.visible = VID_EXT.some(ext => current.endsWith(ext));
        this._icon.icon_name = this._live ? 'video-display-symbolic' : 'image-x-generic-symbolic';
        if (this._live)
            this._btn.add_style_class_name('on');
        else
            this._btn.remove_style_class_name('on');
    }

    _toggle() {
        try {
            Gio.Subprocess.new([CLI, 'live', 'toggle'], Gio.SubprocessFlags.NONE);
        } catch (e) {
            logError(e, 'bapirlo-bar: live wallpaper toggle');
        }
    }

    destroy() {
        if (this._syncId)
            GLib.source_remove(this._syncId);
        this._syncId = 0;
        this._monitor?.cancel();
        this._monitor = null;
        super.destroy();
    }
});
