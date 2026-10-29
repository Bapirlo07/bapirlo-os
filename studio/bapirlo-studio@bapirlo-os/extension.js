// Kuro Theme Studio — the part that has to live inside GNOME Shell.
//   · D-Bus org.bapirlo.Studio on /org/bapirlo/Studio (session bus, owned by gnome-shell):
//       Freeze(timeout_ms)       freeze the picture: a screenshot of the whole stage goes on top of
//                                everything, so the theme can change underneath without flicker
//       Thaw(stylesheet, fade_ms) load the recoloured stylesheet of the Kuro extensions (or none),
//                                wait for the new shell theme, then cross-fade to the new look
//     A frozen screen thaws by itself after timeout_ms (max 6 s) — it can never get stuck.
//   · loads the active preset's stylesheet at login and asks Theme Studio to rebuild it when a
//     Kuro script changed one of the themes it is made from (bapirlo-studio refresh).
// Off switch: gnome-extensions disable bapirlo-studio@bapirlo-os (themes stay; no fade).
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

Gio._promisify(Shell.Screenshot.prototype, 'screenshot_stage_to_content');

const IFACE = `<node><interface name="org.bapirlo.Studio">
  <method name="Freeze"><arg type="u" direction="in" name="timeout_ms"/></method>
  <method name="Thaw"><arg type="s" direction="in" name="stylesheet"/><arg type="u" direction="in" name="fade_ms"/></method>
</interface></node>`;
const STATE = GLib.build_filenamev([GLib.get_user_state_dir(), 'bapirlo', 'studio']);
const STUDIO_CLI = GLib.build_filenamev([GLib.get_home_dir(), 'bapirlo-os', 'studio', 'bapirlo-studio']);

export default class BapirloStudioExtension extends Extension {
    enable() {
        this._dbus = Gio.DBusExportedObject.wrapJSObject(IFACE, this);
        this._dbus.export(Gio.DBus.session, '/org/bapirlo/Studio');
        this._timers = new Set();
        this._loadStylesheet(this._activeStylesheet());
        // a Kuro script may have rebuilt a theme this preset was made from: rebuild quietly
        this._later(4000, () => {
            if (this._activeStylesheet())
                this._spawn([STUDIO_CLI, 'refresh']);
        });
    }

    disable() {
        this._dbus?.unexport();
        this._dbus = null;
        for (const id of this._timers)
            GLib.source_remove(id);
        this._timers.clear();
        if (this._themeId) {
            St.ThemeContext.get_for_stage(global.stage).disconnect(this._themeId);
            this._themeId = 0;
        }
        this._dropOverlay();
        this._loadStylesheet(null);
    }

    // ------------------------------------------------------------------ D-Bus
    async FreezeAsync([timeout], invocation) {
        try {
            if (!this._overlay) {
                const shooter = new Shell.Screenshot();
                const [content] = await shooter.screenshot_stage_to_content();
                const overlay = new St.Widget({reactive: true});   // swallows clicks while frozen
                overlay.set_content(content);
                overlay.add_constraint(new Clutter.BindConstraint({source: global.stage, coordinate: Clutter.BindCoordinate.ALL}));
                global.stage.add_child(overlay);
                this._overlay = overlay;
                await new Promise(resolve => {
                    const id = global.stage.connect('after-paint', () => {
                        global.stage.disconnect(id);
                        resolve();
                    });
                    global.stage.queue_redraw();
                });
            }
            this._clearSafety();
            this._safety = this._later(Math.min(Math.max(timeout, 300), 6000), () => this._fade(400));
            invocation.return_value(null);
        } catch (e) {
            logError(e, 'bapirlo-studio: freeze');
            this._dropOverlay();
            invocation.return_value(null);   // never block Theme Studio: it just won't fade
        }
    }

    ThawAsync([stylesheet, fadeMs], invocation) {
        invocation.return_value(null);
        this._clearSafety();
        // wait for the new shell theme (user-theme reloads it after the setting changed), max 1.2 s
        const ctx = St.ThemeContext.get_for_stage(global.stage);
        let done = false;
        const go = () => {
            if (done)
                return;
            done = true;
            if (this._themeId) {
                ctx.disconnect(this._themeId);
                this._themeId = 0;
            }
            this._loadStylesheet(stylesheet || null);
            // give the apps a moment to redraw in their new theme too, then fade
            this._later(fadeMs ? 380 : 0, () => this._fade(fadeMs));
        };
        this._themeId = ctx.connect('changed', () => this._later(60, go));
        this._later(1200, go);
    }

    // ------------------------------------------------------------------ helpers
    _fade(ms) {
        const overlay = this._overlay;
        if (!overlay)
            return;
        this._overlay = null;
        if (!ms) {
            overlay.destroy();
            return;
        }
        overlay.ease({
            opacity: 0, duration: ms, mode: Clutter.AnimationMode.EASE_IN_OUT_QUAD,
            onStopped: () => overlay.destroy(),
        });
    }

    _dropOverlay() {
        this._overlay?.destroy();
        this._overlay = null;
    }

    _clearSafety() {
        if (this._safety) {
            GLib.source_remove(this._safety);
            this._timers.delete(this._safety);
            this._safety = 0;
        }
    }

    _later(ms, fn) {
        const id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
            this._timers.delete(id);
            if (this._safety === id)
                this._safety = 0;
            fn();
            return GLib.SOURCE_REMOVE;
        });
        this._timers.add(id);
        return id;
    }

    _activeStylesheet() {
        try {
            const [, bytes] = GLib.file_get_contents(GLib.build_filenamev([STATE, 'active.json']));
            const slot = JSON.parse(new TextDecoder().decode(bytes)).slot;
            const path = GLib.build_filenamev([STATE, `extensions-${slot}.css`]);
            return GLib.file_test(path, GLib.FileTest.EXISTS) ? path : null;
        } catch {
            return null;
        }
    }

    _loadStylesheet(path) {
        const theme = St.ThemeContext.get_for_stage(global.stage).get_theme();
        if (this._sheet) {
            try {
                theme.unload_stylesheet(this._sheet);
            } catch {}
            this._sheet = null;
        }
        if (!path)
            return;
        const file = Gio.File.new_for_path(path);
        try {
            theme.load_stylesheet(file);
            this._sheet = file;
        } catch (e) {
            logError(e, 'bapirlo-studio: stylesheet');
        }
    }

    _spawn(argv) {
        try {
            Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE);
        } catch (e) {
            logError(e, 'bapirlo-studio: spawn');
        }
    }
}
