// Test-only (installed into the throwaway headless shell, never into the real session):
// exposes org.bapirlo.Test.Eval and Screenshot on the test bus.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const Iface = `<node><interface name="org.bapirlo.Test">
  <method name="Eval"><arg type="s" direction="in"/><arg type="s" direction="out"/></method>
  <method name="Shot"><arg type="s" direction="in"/></method>
</interface></node>`;

export default class {
    enable() {
        this._impl = Gio.DBusExportedObject.wrapJSObject(Iface, {
            EvalAsync: async ([code], inv) => {
                try {
                    globalThis.Main = Main;
                    const v = await (0, eval)(`(async () => { ${code}\n})()`);
                    inv.return_value(new GLib.Variant('(s)', [String(JSON.stringify(v) ?? '')]));
                } catch (e) {
                    inv.return_value(new GLib.Variant('(s)', [`ERROR: ${e}\n${e.stack}`]));
                }
            },
            ShotAsync: async ([path], inv) => {
                try {
                    const s = new Shell.Screenshot();
                    const out = Gio.File.new_for_path(path).replace(null, false, 0, null);
                    await new Promise((res, rej) => s.screenshot(false, out, (o, r) => {
                        try { s.screenshot_finish(r); res(); } catch (e) { rej(e); }
                    }));
                    out.close(null);
                    inv.return_value(null);
                } catch (e) {
                    inv.return_dbus_error('org.bapirlo.Test.Error', String(e));
                }
            },
        });
        this._impl.export(Gio.DBus.session, '/org/bapirlo/Test');
        this._own = Gio.bus_own_name(Gio.BusType.SESSION, 'org.bapirlo.Test', 0, null, null, null);
    }
    disable() {
        this._impl.unexport();
        Gio.bus_unown_name(this._own);
    }
}
