// Kuro Media — artwork: local cache for remote covers, accent colour extraction and the
// "frosted" card background (a pre-blurred slice of the wallpaper, rendered once — no live
// blur shader, so it costs nothing per frame).
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GdkPixbuf from 'gi://GdkPixbuf';
import Soup from 'gi://Soup?version=3.0';

const CACHE_DIR = GLib.build_filenamev([GLib.get_user_cache_dir(), 'bapirlo-media-widget']);
const MAX_CACHED = 80;
export const FALLBACK_ACCENT = [225, 29, 46];   // Kuro crimson

let _session = null;

function cacheDir() {
    GLib.mkdir_with_parents(CACHE_DIR, 0o755);
    return CACHE_DIR;
}

function hashName(s, ext) {
    return `${GLib.compute_checksum_for_string(GLib.ChecksumType.SHA1, s, -1)}${ext}`;
}

function pruneCache() {
    try {
        const dir = Gio.File.new_for_path(CACHE_DIR);
        const en = dir.enumerate_children('standard::name,time::modified', 0, null);
        const files = [];
        let info;
        while ((info = en.next_file(null)))
            files.push([info.get_modification_date_time()?.to_unix() ?? 0, info.get_name()]);
        files.sort((a, b) => b[0] - a[0]);
        for (const [, name] of files.slice(MAX_CACHED))
            dir.get_child(name).delete(null);
    } catch {}
}

// Resolve an MPRIS artUrl to a local path (downloading http(s) covers once).
export async function resolveArt(url, cancellable) {
    if (!url)
        return null;
    if (url.startsWith('file://') || url.startsWith('/')) {
        const f = url.startsWith('/') ? Gio.File.new_for_path(url) : Gio.File.new_for_uri(url);
        return f.query_exists(null) ? f.get_path() : null;
    }
    if (!/^https?:\/\//.test(url))
        return null;
    const path = GLib.build_filenamev([cacheDir(), hashName(url, '.img')]);
    if (GLib.file_test(path, GLib.FileTest.EXISTS))
        return path;
    _session ??= new Soup.Session({timeout: 10, user_agent: 'bapirlo-media-widget'});
    const msg = Soup.Message.new('GET', url);
    if (!msg)
        return null;
    const bytes = await new Promise((resolve, reject) => {
        _session.send_and_read_async(msg, GLib.PRIORITY_LOW, cancellable, (s, r) => {
            try {
                resolve(s.send_and_read_finish(r));
            } catch (e) {
                reject(e);
            }
        });
    });
    if (msg.get_status() !== Soup.Status.OK || !bytes?.get_size())
        return null;
    const tmp = `${path}.part`;
    Gio.File.new_for_path(tmp).replace_contents(bytes.toArray(), null, false,
        Gio.FileCreateFlags.REPLACE_DESTINATION, null);
    GLib.rename(tmp, path);
    pruneCache();
    return path;
}

function loadScaled(path, w, h, cancellable) {
    return new Promise((resolve, reject) => {
        const stream = Gio.File.new_for_path(path).read(cancellable);
        GdkPixbuf.Pixbuf.new_from_stream_at_scale_async(stream, w, h, true, cancellable, (s, r) => {
            try {
                resolve(GdkPixbuf.Pixbuf.new_from_stream_finish(r));
            } catch (e) {
                reject(e);
            } finally {
                stream.close(null);
            }
        });
    });
}

function rgbToHsv(r, g, b) {
    r /= 255; g /= 255; b /= 255;
    const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
    let h = 0;
    if (d) {
        if (max === r)
            h = ((g - b) / d) % 6;
        else if (max === g)
            h = (b - r) / d + 2;
        else
            h = (r - g) / d + 4;
        h *= 60;
        if (h < 0)
            h += 360;
    }
    return [h, max ? d / max : 0, max];
}

function hsvToRgb(h, s, v) {
    const c = v * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = v - c;
    const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x]
        : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
    return [r, g, b].map(t => Math.round((t + m) * 255));
}

// {aspect, accent:[r,g,b]} — accent is the dominant *vibrant* hue of the cover,
// lifted so it reads as a glow on the dark card. Greyscale covers fall back to crimson.
export async function analyseArt(path, cancellable) {
    const pb = await loadScaled(path, 32, 32, cancellable);
    const info = GdkPixbuf.Pixbuf.get_file_info(path);
    const aspect = info?.[1] > 0 && info?.[2] > 0 ? info[1] / info[2] : pb.get_width() / pb.get_height();
    const px = pb.get_pixels(), n = pb.get_n_channels(), stride = pb.get_rowstride();
    const buckets = Array.from({length: 12}, () => ({w: 0, r: 0, g: 0, b: 0}));
    for (let y = 0; y < pb.get_height(); y++) {
        for (let x = 0; x < pb.get_width(); x++) {
            const o = y * stride + x * n;
            const [r, g, b] = [px[o], px[o + 1], px[o + 2]];
            if (n === 4 && px[o + 3] < 128)
                continue;
            const [h, s, v] = rgbToHsv(r, g, b);
            if (s < 0.25 || v < 0.2)
                continue;
            const w = s * s * v;
            const bk = buckets[Math.floor(h / 30) % 12];
            bk.w += w; bk.r += r * w; bk.g += g * w; bk.b += b * w;
        }
    }
    const best = buckets.reduce((a, b) => (b.w > a.w ? b : a));
    const total = pb.get_width() * pb.get_height();
    if (best.w < total * 0.02)
        return {aspect, accent: FALLBACK_ACCENT};
    const [h, s, v] = rgbToHsv(best.r / best.w, best.g / best.w, best.b / best.w);
    return {aspect, accent: hsvToRgb(h, Math.max(s, 0.6), Math.max(v, 0.9))};
}

// Heavily blurred copy of a cover for the dropdown backdrop: decode tiny, grow back in two bilinear
// steps (same trick as the frost). Cached per cover + size; a few KB.
export async function blurredArt(path, w, h, cancellable) {
    const out = GLib.build_filenamev([cacheDir(), hashName(`${path}|${w}x${h}|blur1`, '.blur.png')]);
    if (GLib.file_test(out, GLib.FileTest.EXISTS))
        return out;
    const tiny = await loadScaled(path, 10, 10, cancellable);
    const mid = tiny.scale_simple(Math.max(2, Math.round(w / 8)), Math.max(2, Math.round(h / 8)), GdkPixbuf.InterpType.BILINEAR);
    const full = mid.scale_simple(w, h, GdkPixbuf.InterpType.BILINEAR);
    full.savev(`${out}.part.png`, 'png', [], []);
    GLib.rename(`${out}.part.png`, out);
    pruneCache();
    return out;
}

// Readable text colour on top of an accent: white unless the accent is light (WCAG contrast < 3).
export function textOn([r, g, b]) {
    const lin = c => ((c /= 255) <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
    const L = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
    return 1.05 / (L + 0.05) >= 3 ? '#ffffff' : '#0e0a0d';
}

function wallpaperFile() {
    try {
        const bg = new Gio.Settings({schema_id: 'org.gnome.desktop.background'});
        const iface = new Gio.Settings({schema_id: 'org.gnome.desktop.interface'});
        const dark = iface.get_string('color-scheme') === 'prefer-dark';
        const uri = (dark && bg.get_string('picture-uri-dark')) || bg.get_string('picture-uri');
        const opts = bg.get_string('picture-options');
        const f = Gio.File.new_for_uri(uri);
        const path = f.get_path();
        if (!path || !f.query_exists(null) || /\.xml$/i.test(path) || opts === 'none')
            return null;
        return {path, opts, mtime: f.query_info('time::modified', 0, null).get_modification_date_time()?.to_unix() ?? 0};
    } catch {
        return null;
    }
}

// The frost tint: Kuro "night", or the active Theme Studio preset's night (studio/engine.py)
const STUDIO_ACTIVE = GLib.build_filenamev([GLib.get_user_state_dir(), 'bapirlo', 'studio', 'active.json']);
function frostTint() {
    try {
        const [, bytes] = GLib.file_get_contents(STUDIO_ACTIVE);
        const night = JSON.parse(new TextDecoder().decode(bytes)).palette?.night ?? '';
        if (/^#[0-9a-fA-F]{6}$/.test(night))
            return parseInt(night.slice(1), 16);
    } catch {}
    return 0x161015;
}

// Pre-blurred, tinted strip of the wallpaper covering [x, x+w) × the monitor's full height,
// in monitor-logical coordinates. Returns a PNG path, or null (card then uses a plain tint).
export async function frostStrip(monitor, x, w, cancellable) {
    const wp = wallpaperFile();
    if (!wp)
        return null;
    const tintRGB = frostTint();
    const out = GLib.build_filenamev([cacheDir(), hashName(
        `${wp.path}|${wp.mtime}|${wp.opts}|${monitor.width}x${monitor.height}|${x}|${w}|v2|${tintRGB}`, '.frost.png')]);
    if (GLib.file_test(out, GLib.FileTest.EXISTS))
        return out;

    const info = GdkPixbuf.Pixbuf.get_file_info(wp.path);
    if (!info?.[1])
        return null;
    const [iw, ih] = [info[1], info[2]];
    // decode at ~1/10 size — that small copy *is* the blur
    const small = await loadScaled(wp.path, Math.max(64, Math.round(iw / 10)), -1, cancellable);
    const k = small.get_width() / iw;
    // map monitor → image for zoom (cover); everything else approximated as stretched
    let s, ox, oy;
    if (wp.opts === 'zoom' || wp.opts === 'spanned') {
        s = Math.max(monitor.width / iw, monitor.height / ih);
        ox = (monitor.width - iw * s) / 2;
        oy = (monitor.height - ih * s) / 2;
    } else {
        s = monitor.width / iw;
        ox = 0;
        oy = 0;
    }
    const clampX = v => Math.max(0, Math.min(small.get_width() - 1, v));
    const clampY = v => Math.max(0, Math.min(small.get_height() - 1, v));
    const sx = clampX(Math.floor(((x - ox) / s) * k));
    const sy = clampY(Math.floor((-oy / s) * k));
    const sw = Math.max(1, clampX(Math.ceil(((x + w - ox) / s) * k)) - sx);
    const sh = Math.max(1, clampY(Math.ceil(((monitor.height - oy) / s) * k)) - sy);
    const crop = small.new_subpixbuf(sx, sy, sw, sh);
    // shrink further then grow in two bilinear steps → soft gaussian-ish blur without banding
    const tiny = crop.scale_simple(Math.max(2, Math.round(sw / 3)), Math.max(2, Math.round(sh / 3)),
        GdkPixbuf.InterpType.BILINEAR);
    const mid = tiny.scale_simple(Math.round(w / 3), Math.round(monitor.height / 3), GdkPixbuf.InterpType.BILINEAR);
    const full = mid.scale_simple(Math.round(w), Math.round(monitor.height), GdkPixbuf.InterpType.BILINEAR);
    // tint: Kuro "night" #161015 (or the Theme Studio night) at 80% → matches the shell's surfaces while
    // letting a hint of the wallpaper through
    const tint = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, false, 8, full.get_width(), full.get_height());
    tint.fill(((tintRGB << 8) | 0xff) >>> 0);
    tint.composite(full, 0, 0, full.get_width(), full.get_height(), 0, 0, 1, 1,
        GdkPixbuf.InterpType.NEAREST, 204);
    full.savev(`${out}.part.png`, 'png', [], []);
    GLib.rename(`${out}.part.png`, out);
    pruneCache();
    return out;
}
