"""Kuro OS Theme Studio — presets, the files every theme touches, and Apply / Original.

How a theme is applied without breaking anything
  · themes that GNOME / GTK / Kvantum load by NAME (shell, GTK3, Kvantum, GTK4 folder) are written
    as recoloured COPIES into one of two slots (Bapirlo-Studio-A / -B) and then switched to by name —
    the originals (Bapirlo-Kuro, WhiteSur-Dark-red) are never modified, and switching back is exact
  · our own extensions get ONE extra stylesheet (recoloured copies of their rules, loaded after them
    by bapirlo-studio@bapirlo-os); their installed files are never modified
  · files that can only be changed in place (Alacritty, fastfetch, Spicetify, VS Code + Chrome
    themes) are copied to originals/ the first time; "Original Kuro OS" copies them back
    byte for byte. If something else rewrites one of them later (a Kuro script), the new
    version becomes the original automatically.
  · dconf colours (dock, ArcMenu, Coverflow, ddterm, background) — the values before the first
    preset are kept and written back by Original.
  · the wallpaper's day / night grades + accents go through bapirlo-daycycle and bapirlo-autotheme
    (they read state/active.json), so nothing fights over the wallpaper.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import urllib.parse

import engine as E

HOME = os.path.expanduser("~")
OS_DIR = E.OS_DIR
DATA = os.path.join(os.environ.get("XDG_DATA_HOME", HOME + "/.local/share"), "bapirlo", "theme-studio")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME", HOME + "/.local/state"), "bapirlo", "studio")
CONFIG = os.environ.get("XDG_CONFIG_HOME", HOME + "/.config")
DROP = os.path.join(HOME, "Pictures", "Theme Studio")
PRESETS = os.path.join(DATA, "presets")
ORIG = os.path.join(DATA, "originals")
ACTIVE = os.path.join(STATE, "active.json")
EXT_DIR = os.path.join(HOME, ".local/share/gnome-shell/extensions")
THEMES = os.path.join(HOME, ".themes")
KV = os.path.join(CONFIG, "Kvantum")
GTK4 = os.path.join(CONFIG, "gtk-4.0")

ORIGINAL = {"shell": "Bapirlo-Kuro", "gtk": "WhiteSur-Dark-red", "kvantum": "Bapirlo-Kuro", "accent": "red"}
SHELL_SRC = os.path.join(THEMES, "Bapirlo-Kuro", "gnome-shell")
WHITESUR = os.path.join(THEMES, "WhiteSur-Dark-red")
IMG_EXT = (".jpg", ".jpeg", ".png", ".webp")

# dconf keys holding colours (paths + key filter). Two dock keys are owned by bapirlo-autotheme.
DCONF = {
    "/org/gnome/shell/extensions/dash2dock-lite/": r"color$",
    "/org/gnome/shell/extensions/arcmenu/": r"color$",
    "/org/gnome/shell/extensions/coverflowalttab/": r"color$",
    "/com/github/amezin/ddterm/": r"color$|^palette$",
    "/org/gnome/desktop/background/": r"^primary-color$",
}
DCONF_SKIP = {"/org/gnome/shell/extensions/dash2dock-lite/running-indicator-color",
              "/org/gnome/shell/extensions/dash2dock-lite/drawing-secondary-color"}


def firefox_profile():
    """The profile Firefox opens by default: installs.ini's Default, else profiles.ini's Default=1."""
    import configparser
    for base in (os.path.join(CONFIG, "mozilla/firefox"), os.path.join(HOME, ".mozilla/firefox")):
        inst, prof = configparser.ConfigParser(), configparser.ConfigParser()
        inst.read(os.path.join(base, "installs.ini"))
        prof.read(os.path.join(base, "profiles.ini"))
        paths = [inst[s].get("Default") for s in inst.sections()]
        paths += [prof[s].get("Path") for s in prof.sections() if prof[s].get("Default") == "1"]
        for path in paths:
            if path and os.path.isdir(os.path.join(base, path)):
                return os.path.join(base, path)
    return None


FIREFOX = firefox_profile()
# in-place files: path → kind; Alacritty's / ddterm's red slots stay red (it means "error")
INPLACE = {
    os.path.join(CONFIG, "alacritty/alacritty.toml"): "toml",
    os.path.join(CONFIG, "fastfetch/config.jsonc"): "css",
    os.path.join(CONFIG, "fastfetch/bapirlo-logo.ans"): "ansi",
    os.path.join(CONFIG, "spicetify/Themes/Bapirlo/color.ini"): "ini",
    os.path.join(CONFIG, "spicetify/Themes/Bapirlo/user.css"): "css",
    os.path.join(CONFIG, "vesktop/themes/bapirlo.theme.css"): "css",
    os.path.join(CONFIG, "vesktop/themes/bapirlo-kuro.theme.css"): "css",
    os.path.join(CONFIG, "cava/config"): "css",
    os.path.join(CONFIG, "starship.toml"): "css",
}
if FIREFOX:
    INPLACE[os.path.join(FIREFOX, "chrome/userChrome.css")] = "css"
    INPLACE[os.path.join(FIREFOX, "chrome/userContent.css")] = "css"
VSCODE_EXT = os.path.join(HOME, ".vscode/extensions/bapirlo.bapirlo-kuro-theme-1.0.0")
CHROME = os.path.join(HOME, ".local/share/bapirlo/chrome-theme")
NAMED_ACCENTS = {"blue": "#3584E4", "teal": "#2190A4", "green": "#3A944A", "yellow": "#C88800",
                 "orange": "#ED5B00", "red": "#E62D42", "pink": "#D56199", "purple": "#9141AC", "slate": "#6F8396"}


def log(*a):
    print("theme-studio:", *a, flush=True)


def sh(*cmd, check=False, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, check=check, **kw)


def sha(path):
    try:
        with open(path, "rb") as f:
            return hashlib.sha1(f.read()).hexdigest()
    except OSError:
        return None


def write_atomic(path, data, mode="w"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".studio-")
    with os.fdopen(fd, mode) as f:
        f.write(data)
    os.replace(tmp, path)


def load_json(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def active():
    return load_json(ACTIVE)


# ============================================================================ presets
def slug(name):
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:40] or "theme"
    return f"{s}-{time.strftime('%Y%m%d-%H%M%S')}"


def presets():
    """[preset dict], newest first; the built-in Original first of all."""
    out = []
    if os.path.isdir(PRESETS):
        for d in os.listdir(PRESETS):
            p = load_json(os.path.join(PRESETS, d, "preset.json"))
            if p:
                p["dir"] = os.path.join(PRESETS, d)
                out.append(p)
    out.sort(key=lambda p: p.get("created", 0), reverse=True)
    return [original_preset()] + out


def original_preset():
    return {"id": "original", "name": "Original Kuro OS", "builtin": True,
            "roles": dict(E.KURO), "thumb": os.path.join(DATA, "original-thumb.png")}


def get_preset(pid):
    for p in presets():
        if p["id"] == pid:
            return p
    raise KeyError(f"no preset {pid!r}")


def save_preset(name, image, palette):
    """Store a preset: its own copy of the wallpaper, day / night grades, palette, thumbnail."""
    pid = slug(name)
    d = os.path.join(PRESETS, pid)
    os.makedirs(d, exist_ok=True)
    from PIL import Image
    src = Image.open(image).convert("RGB")
    wall = os.path.join(d, "wallpaper.jpg")
    cover(src, (2560, 1600)).save(wall, quality=93, subsampling=0)
    day, night = os.path.join(d, "day.jpg"), os.path.join(d, "night.jpg")
    grades(wall, day, night, palette["roles"]["ink"])
    p = {"id": pid, "name": name, "created": time.time(), "source": os.path.abspath(image),
         "wallpaper": wall, "day": day, "night": night, "roles": palette["roles"],
         "params": palette.get("params", {}), "checks": palette.get("checks", [])}
    write_atomic(os.path.join(d, "preset.json"), json.dumps(p, indent=1))
    import mockup
    mockup.render_png(p["roles"], wall, os.path.join(d, "thumb.png"), width=320)
    p["dir"] = d
    return p


def delete_preset(pid):
    if pid == "original":
        raise ValueError("the Original preset can't be deleted")
    a = active()
    if a and a.get("preset") == pid:
        raise ValueError("switch to another theme before deleting this one")
    shutil.rmtree(os.path.join(PRESETS, pid))


def cover(img, size):
    from PIL import Image
    w, h = size
    s = max(w / img.width, h / img.height)
    im = img.resize((max(w, round(img.width * s)), max(h, round(img.height * s))), Image.LANCZOS)
    x, y = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))


def grades(wall, day_out, night_out, ink="#0E0A0D"):
    """Day / night grades like tools/make-daynight.py does for Kuro (night fades into the ink)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("daynight", os.path.join(OS_DIR, "tools", "make-daynight.py"))
    dn = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dn)
    from PIL import Image
    src = Image.open(wall).convert("RGB")
    dn.grade_day(src).save(day_out, quality=93, subsampling=0)
    dn.grade_night(src, tuple(round(c * 255) for c in E.hex_rgb(ink))).save(night_out, quality=93, subsampling=0)


# ============================================================================ originals (in-place)
def _orig_path(path):
    return os.path.join(ORIG, path.lstrip("/").replace("/", "%"))


def capture_original(path, written=None):
    """Keep the pre-Studio version of an in-place file. If the file changed since Studio last wrote
    it (another script rewrote it), that new version becomes the original."""
    if not os.path.exists(path):
        return None
    o = _orig_path(path)
    cur = sha(path)
    if not os.path.exists(o) or (cur != written and cur != sha(o)):
        os.makedirs(ORIG, exist_ok=True)
        shutil.copy2(path, o)
    return o


# ============================================================================ building one slot
def other_slot():
    a = active()
    return "B" if a and a.get("slot") == "A" else "A"


def _copy_remap_tree(src, dst, T, skip=()):
    """Recoloured copy of a theme folder: css / svg / text through remap_text, pngs pixel-mapped."""
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    for root, dirs, files in os.walk(src, followlinks=True):
        rel = os.path.relpath(root, src)
        if any(rel == s or rel.startswith(s + os.sep) for s in skip):
            continue
        os.makedirs(os.path.join(dst, rel), exist_ok=True)
        for f in files:
            s, d = os.path.join(root, f), os.path.join(dst, rel, f)
            low = f.lower()
            try:
                if low.endswith((".css", ".svg", ".kvconfig", ".rc", ".json", ".xml", ".theme")):
                    with open(s, encoding="utf-8", errors="surrogateescape") as fh:
                        txt = fh.read()
                    with open(d, "w", encoding="utf-8", errors="surrogateescape") as fh:
                        fh.write(E.remap_text(txt, T))
                elif low.endswith(".png"):
                    E.remap_png(s, d, T)
                else:
                    shutil.copy2(s, d)
            except Exception as e:          # one odd asset must not stop the theme
                log(f"copied {os.path.relpath(s, src)} unchanged ({e})")
                shutil.copy2(s, d)


def build_shell_gtk3(slot, T):
    """~/.themes/Bapirlo-Studio-<slot>: gnome-shell (Bapirlo-Kuro + recoloured WhiteSur base) + gtk-3.0."""
    name = f"Bapirlo-Studio-{slot}"
    root = os.path.join(THEMES, name)
    os.makedirs(root, exist_ok=True)
    base = os.path.join(root, "gnome-shell", "whitesur")
    _copy_remap_tree(os.path.join(WHITESUR, "gnome-shell"), base, T)
    with open(os.path.join(SHELL_SRC, "gnome-shell.css")) as f:
        css = f.read()
    css = re.sub(r'@import url\("[^"]*WhiteSur[^"]*/gnome-shell/gnome-shell\.css"\);',
                 f'@import url("{base}/gnome-shell.css");', css)
    write_atomic(os.path.join(root, "gnome-shell", "gnome-shell.css"), E.remap_text(css, T))
    _copy_remap_tree(os.path.join(WHITESUR, "gtk-3.0"), os.path.join(root, "gtk-3.0"), T)
    with open(os.path.join(WHITESUR, "index.theme")) as f:
        idx = f.read().replace("WhiteSur-Dark-red", name)
    write_atomic(os.path.join(root, "index.theme"), idx)
    return name


def build_gtk4(slot, T):
    """~/.config/gtk-4.0/studio-<slot>/: recoloured WhiteSur GTK4 + Kuro surfaces."""
    d = os.path.join(GTK4, f"studio-{slot}")
    if os.path.isdir(d):
        shutil.rmtree(d)
    os.makedirs(d)
    for sub in ("assets", "windows-assets"):
        if os.path.isdir(os.path.join(GTK4, sub)):
            _copy_remap_tree(os.path.join(GTK4, sub), os.path.join(d, sub), T)
    for f in ("gtk-Dark.css", "bapirlo-surfaces.css"):
        src = os.path.join(GTK4, f)
        if os.path.exists(src):
            with open(os.path.realpath(src)) as fh:
                write_atomic(os.path.join(d, f), E.remap_text(fh.read(), T))
    return d


def build_kvantum(slot, T):
    name = f"Bapirlo-Studio-{slot}"
    src, dst = os.path.join(KV, "Bapirlo-Kuro"), os.path.join(KV, name)
    if not os.path.isdir(src):
        return None
    _copy_remap_tree(src, dst, T)
    for ext in (".kvconfig", ".svg"):
        a, b = os.path.join(dst, "Bapirlo-Kuro" + ext), os.path.join(dst, name + ext)
        if os.path.exists(a):
            os.replace(a, b)
    return name


def bapirlo_stylesheets():
    """Installed stylesheets of our own extensions (in load order)."""
    out = []
    for d in sorted(os.listdir(EXT_DIR)) if os.path.isdir(EXT_DIR) else []:
        if d.startswith("bapirlo-") and d != "bapirlo-studio@bapirlo-os":
            p = os.path.join(EXT_DIR, d, "stylesheet.css")
            if os.path.exists(p):
                out.append(p)
    return out


def build_ext_css(slot, T):
    parts = ["/* Theme Studio — recoloured rules of the Kuro extensions (generated; do not edit) */"]
    for p in bapirlo_stylesheets():
        with open(p) as f:
            parts.append(f"/* {os.path.basename(os.path.dirname(p))} */\n" + E.css_override(f.read(), T))
    path = os.path.join(STATE, f"extensions-{slot}.css")
    write_atomic(path, "\n".join(parts))
    return path


def source_hashes():
    """Fingerprint of everything a slot is built from — a change means "rebuild" (refresh)."""
    h = hashlib.sha1()
    for p in [os.path.join(SHELL_SRC, "gnome-shell.css"), os.path.join(WHITESUR, "gnome-shell", "gnome-shell.css"),
              os.path.join(WHITESUR, "gtk-3.0", "gtk-dark.css"), os.path.join(GTK4, "gtk-Dark.css"),
              os.path.join(GTK4, "bapirlo-surfaces.css")] + bapirlo_stylesheets():
        h.update((p + str(sha(p))).encode())
    return h.hexdigest()


# ============================================================================ dconf
def _dconf_items():
    for path, keyre in DCONF.items():
        out = sh("dconf", "dump", path).stdout
        section = None
        for line in out.splitlines():
            m = re.match(r"^\[(.*)\]$", line)
            if m:
                section = m.group(1)
                continue
            if section == "/" and "=" in line:
                k, v = line.split("=", 1)
                full = path + k
                if re.search(keyre, k) and full not in DCONF_SKIP:
                    yield full, v


def dconf_baseline(refresh=False):
    path = os.path.join(DATA, "dconf-original.json")
    base = load_json(path)
    if base is None or refresh:
        base = dict(_dconf_items())
        write_atomic(path, json.dumps(base, indent=1))
    return base


def dconf_apply(T, base):
    for key, val in base.items():
        if key.endswith("/palette") and "ddterm" in key:
            pal = re.findall(r"'(#[0-9A-Fa-f]{6})'", val)
            if len(pal) == 16:          # slots 1 / 9 = red (errors) stay red
                new = [c if i in (1, 9) else T.hex(c) for i, c in enumerate(pal)]
                val = "[" + ", ".join(f"'{c}'" for c in new) + "]"
            sh("dconf", "write", key, val)
            continue
        sh("dconf", "write", key, E.remap_text(val, T, "dconf"))


def dconf_restore(base):
    for key, val in base.items():
        sh("dconf", "write", key, val)


# ============================================================================ in-place files
def inplace_apply(T, written):
    out = {}
    for path, kind in INPLACE.items():
        o = capture_original(path, written.get(path))
        if not o:
            continue
        with open(o, encoding="utf-8", errors="surrogateescape") as f:
            txt = f.read()
        if path.endswith("alacritty.toml"):
            # keep the ANSI red slots red: they mean "error" in every program
            keep = {}
            def stash(m):
                keep[len(keep)] = m.group(0)
                return f"@@KEEP{len(keep) - 1}@@"
            txt = re.sub(r'(?m)^red\s*=\s*"#[0-9A-Fa-f]{6}"', stash, txt)
            txt = E.remap_text(txt, T, "css")
            for i, v in keep.items():
                txt = txt.replace(f"@@KEEP{i}@@", v)
        else:
            txt = E.remap_text(txt, T, "ini" if kind == "ini" else ("ansi" if kind == "ansi" else "css"))
        write_atomic(path, txt)
        out[path] = sha(path)
    return out


def inplace_restore(written):
    for path in INPLACE:
        o = _orig_path(path)
        if os.path.exists(o) and os.path.exists(path):
            cur = sha(path)
            if cur == written.get(path) or written.get(path) is None:
                shutil.copy2(o, path)


def vscode_theme(T):
    """The Kuro VS Code colour theme (installed as a local extension), recoloured."""
    src = os.path.join(OS_DIR, "apps", "vscode-theme")
    if not shutil.which("code") or not os.path.isdir(src):
        return False
    if os.path.isdir(VSCODE_EXT):
        shutil.rmtree(VSCODE_EXT)
    _copy_remap_tree(src, VSCODE_EXT, T)
    return True


def chrome_theme(T):
    """Chrome theme folder (Load unpacked once at chrome://extensions): colours + tints follow T."""
    src = os.path.join(OS_DIR, "apps", "chrome-theme")
    if not os.path.isdir(src):
        return False
    os.makedirs(CHROME, exist_ok=True)
    m = load_json(os.path.join(src, "manifest.json"), {})
    theme = m.get("theme", {})
    for k, v in list(theme.get("colors", {}).items()):
        if isinstance(v, list) and len(v) >= 3:
            r, g, b = T.rgb(tuple(c / 255 for c in v[:3]))
            theme["colors"][k] = [round(r * 255), round(g * 255), round(b * 255)] + v[3:]
    write_atomic(os.path.join(CHROME, "manifest.json"), json.dumps(m, indent=2))
    imgs = os.path.join(src, "images")
    if os.path.isdir(imgs):
        dst = os.path.join(CHROME, "images")
        os.makedirs(dst, exist_ok=True)
        for f in os.listdir(imgs):
            shutil.copy2(os.path.join(imgs, f), os.path.join(dst, f))
    return True


# ============================================================================ per-wallpaper look
# Each preset remembers the bar look (the dock follows it), which desk cards are shown, their corner
# and where they were dragged. Switching theme saves the outgoing preset's look and brings back the
# incoming one's; a preset with nothing saved yet keeps whatever is on screen.
LOOK_KEYS = (("bapirlo-bar", "bar-look"), ("bapirlo-desk", "widgets-cards"), ("bapirlo-desk", "widgets-corner"))
DESK_LAYOUT = os.path.join(os.path.dirname(STATE), "desk", "widgets.json")


def _look_file(pid):
    return os.path.join(DATA, "original-look.json") if pid == "original" else os.path.join(PRESETS, pid, "look.json")


def _ext_schemas(ext):
    return os.path.join(EXT_DIR, f"{ext}@bapirlo-os", "schemas")


def look_save(pid):
    if pid != "original" and not os.path.isdir(os.path.join(PRESETS, pid or "")):
        return
    keys = {}
    for ext, key in LOOK_KEYS:
        r = sh("gsettings", "--schemadir", _ext_schemas(ext), "get", f"org.gnome.shell.extensions.{ext}", key)
        if r.returncode == 0:
            keys[f"{ext}/{key}"] = r.stdout.strip()
    write_atomic(_look_file(pid), json.dumps({"keys": keys, "layout": load_json(DESK_LAYOUT, {})}, indent=1))


def look_restore(pid):
    """Before the palette is written: the desk extension re-reads its layout when active.json changes."""
    lk = load_json(_look_file(pid))
    if not lk:
        return False
    for k, v in lk.get("keys", {}).items():
        ext, key = k.split("/", 1)
        _gs(f"org.gnome.shell.extensions.{ext}", key, v, _ext_schemas(ext))
    if lk.get("layout") is not None:
        write_atomic(DESK_LAYOUT, json.dumps(lk["layout"]))
    return True


# ============================================================================ the switch
def _gs(schema, key, val, schemadir=None):
    cmd = ["gsettings"] + (["--schemadir", schemadir] if schemadir else []) + ["set", schema, key, val]
    sh(*cmd)


def _gv(a):
    """Python value → GVariant text for gdbus."""
    if isinstance(a, str):
        return "'" + a.replace("\\", "\\\\").replace("'", "\\'") + "'"
    return f"uint32 {int(a)}"


def _dbus(method, *args):
    """Call bapirlo-studio@bapirlo-os (the crossfade). False if it isn't running (yet)."""
    try:
        r = sh("gdbus", "call", "--session", "--dest", "org.gnome.Shell", "--object-path", "/org/bapirlo/Studio",
               "--method", f"org.bapirlo.Studio.{method}", *[_gv(a) for a in args], timeout=8)
    except subprocess.TimeoutExpired:
        return False
    return r.returncode == 0


def nearest_accent(hexc):
    L, C, h = E.rgb_lch(E.hex_rgb(hexc))
    if C < 0.03:
        return "slate"
    return min(NAMED_ACCENTS, key=lambda n: abs(E.hue_delta(h, E.rgb_lch(E.hex_rgb(NAMED_ACCENTS[n]))[2])))


def _user_theme_schemadir():
    for d in (os.path.join(EXT_DIR, "user-theme@gnome-shell-extensions.gcampax.github.com", "schemas"),
              "/usr/share/gnome-shell/extensions/user-theme@gnome-shell-extensions.gcampax.github.com/schemas"):
        if os.path.isdir(d):
            return d
    return None


def _switch(names, ext_css, fade=True):
    """Freeze the screen, flip every name / setting, then fade the new look in."""
    froze = fade and _dbus("Freeze", 900)
    ut = _user_theme_schemadir()
    _gs("org.gnome.shell.extensions.user-theme", "name", names["shell"], ut)
    _gs("org.gnome.desktop.interface", "gtk-theme", names["gtk"])
    _gs("org.gnome.desktop.interface", "accent-color", names["accent"])
    kvconf = os.path.join(KV, "kvantum.kvconfig")
    if os.path.exists(kvconf) and names.get("kvantum"):
        with open(kvconf) as f:
            txt = f.read()
        write_atomic(kvconf, re.sub(r"(?m)^theme=.*$", f"theme={names['kvantum']}", txt))
    if froze:
        _dbus("Thaw", ext_css or "", 700)
    else:
        _dbus("Thaw", ext_css or "", 0)       # no fade, but still (re)load the stylesheet


def apply_preset(pid, fade=True, quiet=False):
    """Apply a saved preset (or "original") to everything that doesn't need a password."""
    if pid == "original":
        return apply_original(fade=fade)
    p = get_preset(pid)
    T = E.Transform(p["roles"])
    a = active() or {}
    written = a.get("written", {})
    if not a:                                   # first preset: remember the original dconf values
        dconf_baseline(refresh=True)
    look_save(a.get("preset", "original"))
    look_restore(pid)
    base = dconf_baseline()
    slot = other_slot()
    t0 = time.time()
    names = {"shell": build_shell_gtk3(slot, T), "gtk": f"Bapirlo-Studio-{slot}",
             "kvantum": build_kvantum(slot, T) or ORIGINAL["kvantum"], "accent": nearest_accent(p["roles"]["crimson"])}
    gtk4dir = build_gtk4(slot, T)
    ext_css = build_ext_css(slot, T)
    log(f"built slot {slot} in {time.time() - t0:.1f} s")

    # everything that reads the active palette (autotheme, daycycle, media frost, lock screen)
    state = {"preset": pid, "name": p["name"], "slot": slot, "palette": p["roles"],
             "day": p["day"], "night": p["night"], "wallpaper": p["wallpaper"], "applied": time.time(),
             "sources": source_hashes(), "written": written}
    os.makedirs(STATE, exist_ok=True)
    write_atomic(ACTIVE, json.dumps(state, indent=1))

    g = os.path.join(GTK4, "gtk.css")
    capture_original(g, written.get(g))          # before the first overwrite
    _switch(names, ext_css, fade=fade)
    write_atomic(g,
                 f'/* Kuro OS Theme Studio: {p["name"]} (Original: Theme Studio → Original Kuro OS) */\n'
                 f'@import url("{gtk4dir}/gtk-Dark.css");\n@import url("{gtk4dir}/bapirlo-surfaces.css");\n')
    dconf_apply(T, base)
    state["written"] = {**written, **inplace_apply(T, written), g: sha(g)}
    vscode_theme(T)
    chrome_theme(T)
    write_atomic(ACTIVE, json.dumps(state, indent=1))
    _after(p["roles"], p)
    _cleanup_slot("B" if slot == "A" else "A", keep_original=True)
    log(f'"{p["name"]}" applied in {time.time() - t0:.1f} s')
    return state


def apply_original(fade=True):
    """Everything back exactly as Kuro OS was before Theme Studio."""
    a = active() or {}
    written = a.get("written", {})
    look_save(a.get("preset", "original"))
    look_restore("original")
    if os.path.exists(ACTIVE):
        os.remove(ACTIVE)
    _switch(dict(ORIGINAL), "", fade=fade)
    g = os.path.join(GTK4, "gtk.css")
    capture_original(g, written.get(g))
    if os.path.exists(_orig_path(g)):
        shutil.copy2(_orig_path(g), g)
    base = load_json(os.path.join(DATA, "dconf-original.json"))
    if base:
        dconf_restore(base)
    inplace_restore(written)
    T = E.Transform(E.KURO)
    vscode_theme(T)
    chrome_theme(T)
    _after(E.KURO)
    for s in ("A", "B"):
        _cleanup_slot(s)
    log("Original Kuro OS restored")
    return None


def _after(roles, preset=None):
    """Accents (autotheme), wallpaper (daycycle), Spotify, lock screen."""
    b = os.path.join(OS_DIR, "bin")
    sh(os.path.join(b, "bapirlo-daycycle"), "--no-theme", timeout=30)   # wallpaper first …
    sh(os.path.join(b, "bapirlo-autotheme"), "apply", timeout=90)  # … then the accents read it
    if shutil.which("spicetify"):
        sh("spicetify", "-q", "refresh", timeout=60)
    sh("pkill", "-USR2", "-x", "cava")                             # running cava re-reads its colours
    sh(os.path.join(OS_DIR, "sounds", "mood", "bapirlo-sound-mood"), timeout=30)   # login / unlock sounds
    sh(os.path.join(OS_DIR, "tools", "hypr-theme.py"), timeout=20)              # Hyprland session colours
    greeter_apply(roles, preset)


def _cleanup_slot(slot, keep_original=False):
    """Remove the unused slot's copies (frees ~4 MB); never touches the originals."""
    a = active()
    if a and a.get("slot") == slot:
        return
    for p in (os.path.join(THEMES, f"Bapirlo-Studio-{slot}"), os.path.join(KV, f"Bapirlo-Studio-{slot}"),
              os.path.join(GTK4, f"studio-{slot}")):
        if os.path.isdir(p):
            shutil.rmtree(p, ignore_errors=True)
    css = os.path.join(STATE, f"extensions-{slot}.css")
    if os.path.exists(css):
        os.remove(css)


def refresh_if_stale():
    """At login: rebuild the active preset if any source theme changed (a Kuro script ran)."""
    a = active()
    if not a:
        return False
    if a.get("sources") == source_hashes() and os.path.isdir(os.path.join(THEMES, f"Bapirlo-Studio-{a['slot']}")):
        return False
    log("theme sources changed — rebuilding the active preset")
    apply_preset(a["preset"], fade=False)
    return True


def wallpapers():
    """Pictures in ~/Pictures/Theme Studio, newest first."""
    os.makedirs(DROP, exist_ok=True)
    out = [os.path.join(DROP, f) for f in os.listdir(DROP) if f.lower().endswith(IMG_EXT) and not f.startswith(".")]
    return sorted(out, key=os.path.getmtime, reverse=True)


def current_wallpaper():
    uri = sh("gsettings", "get", "org.gnome.desktop.background", "picture-uri-dark").stdout.strip().strip("'")
    return urllib.parse.unquote(uri[7:]) if uri.startswith("file://") else None


# ============================================================================ lock / login screen
# The lock screen on this system IS the LightDM web-greeter (bin/bapirlo-lockd). Its theme lives in
# /usr/share, but studio/install.sh gives it one folder you own — studio/ — and links studio.css
# after the theme's own stylesheet. Empty studio.css = the original look. Nothing else is writable.
GREETER = "/usr/share/web-greeter/themes/bapirlo"
GREETER_STUDIO = os.path.join(GREETER, "studio")
# live.css = the live wallpaper's lock-screen animation, written by lib/bapirlo_wallpaper.py (@import must come first)
LIVE_IMPORT = '@import url("live.css");'


def greeter_ready():
    return os.path.isdir(GREETER_STUDIO) and os.access(GREETER_STUDIO, os.W_OK)


def greeter_apply(roles, preset=None):
    """Recolour the lock / login screen (no password). False if studio/install.sh hasn't set it up."""
    if not greeter_ready():
        return False
    css, bg = os.path.join(GREETER_STUDIO, "studio.css"), os.path.join(GREETER_STUDIO, "bg.jpg")
    logo = os.path.join(GREETER_STUDIO, "logo.svg")
    if not preset:
        write_atomic(css, LIVE_IMPORT + "\n/* Theme Studio: Original Kuro OS */\n")
        for f in (bg, logo):
            if os.path.exists(f):
                os.remove(f)
        return True
    T = E.Transform(roles)
    with open(os.path.join(GREETER, "css", "style.css")) as f:
        src = f.read()
    src = re.sub(r"@font-face[^}]*}", "", src)                        # already loaded by style.css
    src = src.replace('url("../img/bg.jpg")', 'url("bg.jpg")')
    from PIL import Image
    im = cover(Image.open(preset["day"]).convert("RGB"), (2560, 1600))
    tmp = bg + ".new"
    im.save(tmp, "JPEG", quality=88)
    os.replace(tmp, bg)
    with open(os.path.join(GREETER, "img", "logo.svg")) as f:
        write_atomic(logo, E.remap_text(f.read(), T))
    # the logo is an <img>: Chromium lets CSS swap a replaced element's picture with content: url()
    write_atomic(css, LIVE_IMPORT + f'\n/* Theme Studio: {preset["name"]} (generated) */\n' + E.remap_text(src, T)
                 + '\n#logo { content: url("logo.svg"); }\n')
    for f in (css, bg, logo):
        os.chmod(f, 0o644)
    return True


# ============================================================================ boot splash (staging)
# "Also apply to login & boot": everything is prepared HERE, as you, in boot-stage/; the root helper
# (/usr/local/lib/bapirlo/bapirlo-studio-boot, run through pkexec = your password) only checks and
# copies these files, rebuilds the initramfs and verifies it — or puts everything back.
PLYMOUTH = "/usr/share/plymouth/themes/bapirlo-kuro"
BOOT_STAGE = os.path.join(STATE, "boot-stage")
BOOT_HELPER = "/usr/local/lib/bapirlo/bapirlo-studio-boot"


def plymouth_originals():
    """Copy of the Kuro splash as it was before Theme Studio ever touched it."""
    d = os.path.join(ORIG, "plymouth")
    if not os.path.isdir(d):
        os.makedirs(d)
        for f in os.listdir(PLYMOUTH):
            if f.endswith((".png", ".script")):
                shutil.copy2(os.path.join(PLYMOUTH, f), d)
    return d


def _script_floats(text, T):
    """Plymouth colours are written as three 0…1 floats: Image.Text(t, r, g, b, a, font)."""
    def sub(m):
        rgb = tuple(float(m.group(i)) for i in (1, 2, 3))
        r, g, b = T.rgb(rgb)
        return f"{r:.3f}, {g:.3f}, {b:.3f}"
    return re.sub(r"(?<![\d.])(0?\.\d+|1(?:\.0+)?|0), (0?\.\d+|1(?:\.0+)?|0), (0?\.\d+|1(?:\.0+)?|0)(?=, ?(?:0?\.\d+|1(?:\.0+)?|0)\b)",
                  sub, text)


def stage_boot(pid):
    """Prepare the splash files for preset pid (or "original") in BOOT_STAGE; returns the dir."""
    orig = plymouth_originals()
    if os.path.isdir(BOOT_STAGE):
        shutil.rmtree(BOOT_STAGE)
    os.makedirs(BOOT_STAGE)
    T = None if pid == "original" else E.Transform(get_preset(pid)["roles"])
    for f in sorted(os.listdir(orig)):
        s, d = os.path.join(orig, f), os.path.join(BOOT_STAGE, f)
        if T is None:
            shutil.copy2(s, d)
        elif f.endswith(".png"):
            E.remap_png(s, d, T)
        else:
            with open(s) as fh:
                write_atomic(d, _script_floats(fh.read(), T))
    write_atomic(os.path.join(BOOT_STAGE, "preset.txt"), pid + "\n")
    return BOOT_STAGE


def apply_boot(pid):
    """Stage, then run the root helper through pkexec (asks for your password). Returns (ok, log)."""
    if not os.path.exists(BOOT_HELPER):
        return False, "The boot helper isn't installed yet: run  sudo bash ~/bapirlo-os/studio/install.sh root"
    stage_boot(pid)
    r = sh("pkexec", BOOT_HELPER, "apply", BOOT_STAGE, timeout=900)
    return r.returncode == 0, (r.stdout + r.stderr).strip()
