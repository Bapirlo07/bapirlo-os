"""Bapirlo OS — wallpaper media jobs (ffmpeg + a little numpy). Used by lib/bapirlo_wallpaper.py,
bin/bapirlo-wallpaper and the Wallpapers app.

    make_loop()     a seamless loop cut from any video: the last `fade` seconds cross-fade into the
                    first, so the end meets the start with no jump. Screen-sized, no audio → the library.
    lite()          the battery copy of a live wallpaper: 1280x800, 24 fps (~1/8 of the pixels of a
                    2560x1600 / 60 fps file). Played instead of the original while on battery.
    lock_anim()     the lock screen's live copy: an animated AVIF (the lock screen is web-greeter =
                    Chromium 134, which plays it as a CSS background — no <video>, no root).
    subject()       where the main subject of a wallpaper is (a box in screen fractions), so the desk
                    widgets can step out of its way.

Encoding uses the Intel iGPU (VA-API, /dev/dri of the i915 card) so the NVIDIA card stays asleep;
libx264 on the CPU if that fails. Every job runs at nice 15 and writes to a .part file first.
"""
import hashlib
import json
import os
import re
import subprocess

from gi.repository import GLib

CACHE = os.path.join(GLib.get_user_cache_dir(), "bapirlo", "wallpaper")
LITE_DIR = os.path.join(CACHE, "lite")
LOCK_DIR = os.path.join(CACHE, "lock")
LITE_SIZE, LITE_FPS = (1280, 800), 24
LOCK_SIZE, LOCK_FPS, LOCK_MAX_S = (1600, 1000), 20, 12
NICE = ["nice", "-n", "15", "ionice", "-c", "3"]


def log(*a):
    print("wallmedia:", *a, flush=True)


def _key(path):
    st = os.stat(path)
    return hashlib.sha1(f"{path}\0{st.st_mtime_ns}\0{st.st_size}".encode()).hexdigest()[:16]


def probe(path):
    """{duration, width, height, fps} of a video."""
    r = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                        "stream=width,height,avg_frame_rate,r_frame_rate:format=duration", "-of", "json", path],
                       capture_output=True, text=True, timeout=30)
    d = json.loads(r.stdout or "{}")
    s = (d.get("streams") or [{}])[0]

    def rate(v):
        try:
            n, m = (v or "0/1").split("/")
            return float(n) / float(m) if float(m) else 0.0
        except ValueError:
            return 0.0
    fps = rate(s.get("avg_frame_rate")) or rate(s.get("r_frame_rate")) or 30.0
    return {"duration": float((d.get("format") or {}).get("duration") or 0), "width": int(s.get("width") or 0),
            "height": int(s.get("height") or 0), "fps": fps}


def screen_size():
    """The primary monitor in logical pixels (2560x1600 when there is no display to ask)."""
    try:
        import gi
        gi.require_version("Gdk", "4.0")
        from gi.repository import Gdk
        disp = Gdk.Display.get_default()
        mons = disp.get_monitors() if disp else None
        if mons and mons.get_n_items():
            g = mons.get_item(0).get_geometry()
            sc = mons.get_item(0).get_scale_factor()
            return g.width * sc, g.height * sc
    except Exception:  # noqa: BLE001
        pass
    return 2560, 1600


def _intel_node():
    for n in sorted(os.listdir("/dev/dri")) if os.path.isdir("/dev/dri") else []:
        if n.startswith("renderD"):
            try:
                drv = os.path.basename(os.readlink(f"/sys/class/drm/{n}/device/driver"))
            except OSError:
                continue
            if drv in ("i915", "xe"):
                return f"/dev/dri/{n}"
    return None


def _run(cmd, total_s=None, progress=None):
    """Run ffmpeg; progress(fraction) from its -progress output. Raises with the tail of stderr."""
    p = subprocess.Popen(NICE + cmd + ["-progress", "pipe:1", "-nostats"], stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True)
    for line in p.stdout:
        if progress and total_s and line.startswith("out_time_us="):
            try:
                progress(min(1.0, int(line.split("=")[1]) / 1e6 / total_s))
            except ValueError:
                pass
    err = p.stderr.read()
    if p.wait() != 0:
        raise RuntimeError(err.strip().splitlines()[-1] if err.strip() else f"ffmpeg exit {p.returncode}")


def _encode_h264(inputs, graph, out, total_s, quality, progress=None):
    """graph ends in [v]; tries VA-API on the Intel card, then libx264."""
    # hidden while it's being written: the library scan (and the app's thumbnails) skip dot-files
    tmp = os.path.join(os.path.dirname(out), "." + os.path.basename(out) + ".part.mp4")
    node = _intel_node()
    tries = []
    if node:
        tries.append(["ffmpeg", "-hide_banner", "-y", "-vaapi_device", node] + inputs +
                     ["-filter_complex", graph + ";[v]format=nv12,hwupload[o]", "-map", "[o]", "-an",
                      "-c:v", "h264_vaapi", "-rc_mode", "CQP", "-qp", str(quality), "-profile:v", "high",
                      "-movflags", "+faststart", tmp])
    tries.append(["ffmpeg", "-hide_banner", "-y"] + inputs +
                 ["-filter_complex", graph + ";[v]format=yuv420p[o]", "-map", "[o]", "-an",
                  "-c:v", "libx264", "-preset", "medium", "-crf", str(quality - 2),
                  "-movflags", "+faststart", tmp])
    last = None
    for cmd in tries:
        try:
            _run(cmd, total_s, progress)
            os.replace(tmp, out)
            return out
        except RuntimeError as e:
            last = e
            log(f"{cmd[cmd.index('-c:v') + 1]} failed: {e}")
    if os.path.exists(tmp):
        os.remove(tmp)
    raise last


def _fit(w, h, fps):
    return f"fps={fps:g},scale={w}:{h}:force_original_aspect_ratio=increase:flags=lanczos,crop={w}:{h},setsar=1"


# ------------------------------------------------------------------ 1. loop maker
def loop_name(src, folder):
    stem = re.sub(r"[\s_\-]*loop(-\d+)?$", "", os.path.splitext(os.path.basename(src))[0])
    out = os.path.join(folder, f"{stem} loop.mp4")
    n = 2
    while os.path.exists(out):
        out = os.path.join(folder, f"{stem} loop-{n}.mp4")
        n += 1
    return out


def make_loop(src, start, length, fade, out, size=None, fps=None, progress=None):
    """Cut [start, start+length+fade) and fold the extra `fade` seconds back over the beginning:
       out = clip[fade:length]  +  crossfade(clip[length:length+fade] → clip[0:fade])
    so its last frame flows into its first. Length of the result = `length`."""
    info = probe(src)
    fade = max(0.0, min(fade, length / 2))
    need = length + fade
    if info["duration"] and start + need > info["duration"] + 0.05:
        start = max(0.0, info["duration"] - need)
        if start + need > info["duration"] + 0.05:
            raise ValueError(f"the video is only {info['duration']:.1f} s — pick a shorter loop")
    w, h = size or screen_size()
    fps = fps or min(60, round(info["fps"]) or 30)
    inputs = ["-ss", f"{start:.3f}", "-t", f"{need + 0.5:.3f}", "-i", src]
    fit = _fit(w, h, fps)
    if fade > 0:
        graph = (f"[0:v]{fit},split=3[s1][s2][s3];"
                 f"[s1]trim=start={fade:.3f}:end={length:.3f},setpts=PTS-STARTPTS[body];"
                 f"[s2]trim=start={length:.3f}:end={need:.3f},setpts=PTS-STARTPTS[tail];"
                 f"[s3]trim=start=0:end={fade:.3f},setpts=PTS-STARTPTS[head];"
                 f"[tail][head]xfade=transition=fade:duration={fade:.3f}:offset=0[seam];"
                 f"[body][seam]concat=n=2:v=1:a=0[v]")
    else:
        graph = f"[0:v]{fit},trim=start=0:end={length:.3f},setpts=PTS-STARTPTS[v]"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    _encode_h264(inputs, graph, out, length, 20, progress)
    return out


# ------------------------------------------------------------------ 2. battery copy
def lite_path(src):
    return os.path.join(LITE_DIR, _key(src) + ".mp4")


def lite(src, progress=None):
    """The battery copy (made once per file, kept in the cache). Returns its path."""
    out = lite_path(src)
    if os.path.exists(out):
        return out
    os.makedirs(LITE_DIR, exist_ok=True)
    info = probe(src)
    w, h = LITE_SIZE
    _encode_h264(["-i", src], f"[0:v]{_fit(w, h, LITE_FPS)}[v]", out, info["duration"] or None, 27, progress)
    log(f"battery copy ready: {os.path.basename(src)} → {out} ({os.path.getsize(out) >> 20} MB)")
    return out


def prune(folder, keep):
    """Drop cached copies of files that are no longer in `keep` (a set of paths)."""
    want = set()
    for p in keep:
        try:
            want.add(_key(p))
        except OSError:
            pass
    if not os.path.isdir(folder):
        return
    for f in os.listdir(folder):
        if f.split(".")[0] not in want:
            try:
                os.remove(os.path.join(folder, f))
            except OSError:
                pass


# ------------------------------------------------------------------ 3. lock screen
def lock_anim_path(src):
    return os.path.join(LOCK_DIR, _key(src) + ".avif")


def lock_anim(src, progress=None):
    """Animated AVIF for the lock screen: up to 12 s, 1600x1000, 20 fps, AV1 (SVT-AV1, CPU, nice 15)."""
    out = lock_anim_path(src)
    if os.path.exists(out):
        return out
    os.makedirs(LOCK_DIR, exist_ok=True)
    info = probe(src)
    dur = min(info["duration"] or LOCK_MAX_S, LOCK_MAX_S)
    w, h = LOCK_SIZE
    tmp = out + ".part.avif"
    _run(["ffmpeg", "-hide_banner", "-y", "-t", f"{dur:.3f}", "-i", src, "-vf", _fit(w, h, LOCK_FPS) + ",format=yuv420p",
          "-an", "-c:v", "libsvtav1", "-preset", "8", "-crf", "40", "-g", str(LOCK_FPS * 4),
          "-svtav1-params", "tune=0", "-loop", "0", "-f", "avif", tmp], dur, progress)
    os.replace(tmp, out)
    log(f"lock-screen animation ready: {os.path.basename(src)} ({os.path.getsize(out) >> 20} MB)")
    return out


# ------------------------------------------------------------------ 4. where's the subject
def subject(image, aspect):
    """Box [x0, y0, x1, y1] (fractions of the screen) around the wallpaper's main subject.

    The picture is first cropped the way GNOME shows it ("zoom" = cover at the screen's aspect).
    Saliency = colour distinctness (distance from the picture's mean colour, frequency-tuned
    style) × local detail (blurred gradient energy) × a soft centre prior; the box holds the
    middle ~70 % of that mass, padded a little. Good for the usual anime / portrait wallpaper
    (one character); for scenery it comes back wide, and wide boxes are ignored by the widgets."""
    import numpy as np
    from PIL import Image, ImageFilter
    im = Image.open(image).convert("RGB")
    W, H = im.size
    if W / H > aspect:
        cw = round(H * aspect)
        im = im.crop(((W - cw) // 2, 0, (W - cw) // 2 + cw, H))
    else:
        ch = round(W / aspect)
        im = im.crop((0, (H - ch) // 2, W, (H - ch) // 2 + ch))
    sw, sh = 192, max(1, round(192 / aspect))
    im = im.resize((sw, sh), Image.LANCZOS)
    a = np.asarray(im.filter(ImageFilter.GaussianBlur(1.2)).convert("YCbCr"), dtype=np.float32)
    a[..., 1:] *= 1.6                                   # colour counts more than brightness
    distinct = np.sqrt(((a - a.reshape(-1, 3).mean(0)) ** 2).sum(-1))
    y = a[..., 0]
    gx, gy = np.zeros_like(y), np.zeros_like(y)
    gx[:, 1:-1] = y[:, 2:] - y[:, :-2]
    gy[1:-1, :] = y[2:, :] - y[:-2, :]
    g = np.hypot(gx, gy)
    detail = np.asarray(Image.fromarray(np.uint8(255 * g / (g.max() + 1e-6))).filter(ImageFilter.GaussianBlur(6)),
                        dtype=np.float32)
    yy, xx = np.mgrid[0:sh, 0:sw]
    centre = np.exp(-(((xx / sw - 0.5) / 0.32) ** 2 + ((yy / sh - 0.52) / 0.40) ** 2) / 2)
    norm = lambda m: (m - m.min()) / (np.ptp(m) + 1e-6)  # noqa: E731
    s = norm(distinct) * 0.55 + norm(detail) * 0.45
    s = (s ** 2) * (0.35 + 0.65 * centre)
    s[s < np.quantile(s, 0.70)] = 0                     # only the strongest 30 % counts
    tot = s.sum() or 1.0

    def span(mass):
        c = np.cumsum(mass) / tot
        return float(np.searchsorted(c, 0.15)), float(np.searchsorted(c, 0.85))
    x0, x1 = span(s.sum(0))
    y0, y1 = span(s.sum(1))
    pad = 0.04            # + extra above: the head of a character sits over the strongest colour mass
    box = [max(0.0, x0 / sw - pad), max(0.0, y0 / sh - 2 * pad), min(1.0, x1 / sw + pad), min(1.0, y1 / sh + pad)]
    return [round(v, 4) for v in box]
