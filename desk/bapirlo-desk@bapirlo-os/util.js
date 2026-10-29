// Kuro Desk — small shared helpers.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Pango from 'gi://Pango';
import St from 'gi://St';

export const HOME = GLib.get_home_dir();
export const BIN = GLib.build_filenamev([HOME, 'bapirlo-os', 'bin']);
export const EASE = Clutter.AnimationMode.EASE_OUT_QUAD;
export const STATE_DIR = GLib.build_filenamev([GLib.get_user_state_dir(), 'bapirlo']);

// run argv, resolve with stdout (rejects on spawn error / non-zero exit / timeout)
export function run(argv, {timeoutS = 30, cancellable = null} = {}) {
    return new Promise((resolve, reject) => {
        let proc;
        try {
            proc = Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
        } catch (e) {
            reject(e);
            return;
        }
        const timer = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, timeoutS, () => {
            proc.force_exit();
            return GLib.SOURCE_REMOVE;
        });
        proc.communicate_utf8_async(null, cancellable, (p, res) => {
            GLib.source_remove(timer);
            try {
                const [, out] = p.communicate_utf8_finish(res);
                if (p.get_successful())
                    resolve(out ?? '');
                else
                    reject(new Error(`${argv[0]} exited ${p.get_exit_status()}`));
            } catch (e) {
                reject(e);
            }
        });
    });
}

export function spawn(argv) {
    try {
        Gio.Subprocess.new(argv, Gio.SubprocessFlags.NONE);
    } catch (e) {
        logError(e, `bapirlo-desk: ${argv[0]} failed`);
    }
}

// GTK4 apps enumerate Vulkan ICDs on start; the NVIDIA one wakes the sleeping dGPU (~1.7 s
// whole-screen stall, see the Control Centre fix). Launch them on the Intel ICD only.
export const IGPU_VK = '/usr/share/vulkan/icd.d/intel_icd.json';

export function label(text, style, ellipsize = true) {
    const l = new St.Label({text, style_class: style, y_align: Clutter.ActorAlign.CENTER});
    l.clutter_text.ellipsize = ellipsize ? Pango.EllipsizeMode.END : Pango.EllipsizeMode.NONE;
    return l;
}

export function readJson(path, fallback) {
    try {
        const [ok, bytes] = GLib.file_get_contents(path);
        return ok ? JSON.parse(new TextDecoder().decode(bytes)) : fallback;
    } catch {
        return fallback;
    }
}

export function writeJson(path, data) {
    try {
        GLib.mkdir_with_parents(GLib.path_get_dirname(path), 0o755);
        GLib.file_set_contents(path, JSON.stringify(data));
    } catch (e) {
        logError(e, `bapirlo-desk: writing ${path}`);
    }
}

const DAY = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
export const startOfDay = d => new Date(d.getFullYear(), d.getMonth(), d.getDate());
export const hhmm = d => `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;

// "Today" / "Tomorrow" / "Wed" / "Wed 21"
export function dayName(d, now = new Date()) {
    const days = Math.round((startOfDay(d) - startOfDay(now)) / 86400000);
    if (days === 0)
        return 'Today';
    if (days === 1)
        return 'Tomorrow';
    if (days < 0)
        return 'Overdue';
    return days < 7 ? DAY[d.getDay()] : `${DAY[d.getDay()]} ${d.getDate()}`;
}
