#!/usr/bin/env python3
"""Give GTK app surfaces the same ink undertone as the shell (one look everywhere).

GTK3 (WhiteSur hardcodes its colours): every dark NEUTRAL grey (r=g=b, 0x08..0x60) in
~/.themes/WhiteSur-Dark-red/gtk-3.0/*.css is replaced by the same HSL lightness at the shell's
surface hue — contrast and readability stay exactly as they were. Pure black shadows are kept.
Already-tinted values are no longer neutral, so a second run changes nothing.

GTK4/libadwaita (colours come from libadwaita variables): writes ~/.config/gtk-4.0/bapirlo-surfaces.css
with tinted versions of libadwaita's dark defaults; ~/.config/gtk-4.0/gtk.css @imports it.
Qt: `tint-surfaces.py --kvantum SRC_DIR DST_DIR NAME` copies a Kvantum theme, applies the same grey
tint to its .kvconfig/.svg and swaps its highlight colour for crimson.
Usage: tint-surfaces.py [--dry-run] | --kvantum SRC DST NAME"""
import colorsys, glob, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from palette import rgb

HOME = os.path.expanduser("~")
DRY = "--dry-run" in sys.argv

# hue + saturation of the shell surface "night" #161015 (≈312°, 16%)
_r, _g, _b = (c / 255 for c in rgb("night"))
HUE, _l, SAT = colorsys.rgb_to_hls(_r, _g, _b)

def tint(r, g, b):
    _, l, _ = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    return tuple(round(c * 255) for c in colorsys.hls_to_rgb(HUE, l, SAT))

def hexc(t): return "#%02x%02x%02x" % t

tok = re.compile(r"#[0-9A-Fa-f]{6}\b|rgba?\([^)]*\)")

def sub(m):
    s = m.group(0)
    if s.startswith("#"):
        r, g, b = (int(s[i:i + 2], 16) for i in (1, 3, 5))
        return hexc(tint(r, g, b)) if r == g == b and 0x08 <= r <= 0x60 else s
    parts = [p.strip() for p in s[s.index("(") + 1:-1].split(",")]
    try: r, g, b = (int(float(p)) for p in parts[:3])
    except ValueError: return s
    if not (r == g == b and 0x08 <= r <= 0x60): return s
    t = tint(r, g, b)
    return f"rgba({t[0]}, {t[1]}, {t[2]}, {parts[3]})" if len(parts) == 4 else f"rgb({t[0]}, {t[1]}, {t[2]})"

if "--kvantum" in sys.argv:
    import shutil
    src, dst, name = sys.argv[sys.argv.index("--kvantum") + 1:][:3]
    old = os.path.basename(src.rstrip("/"))
    shutil.rmtree(dst, ignore_errors=True); os.makedirs(dst)
    conf = open(f"{src}/{old}.kvconfig").read()
    hl = re.search(r"^highlight\.color=(#[0-9A-Fa-f]{6})", conf, re.M).group(1)
    acc = "#%02x%02x%02x" % rgb("crimson")
    for ext in ("kvconfig", "svg"):
        s = open(f"{src}/{old}.{ext}").read()
        s = re.sub(re.escape(hl), acc, s, flags=re.I)
        s = tok.sub(sub, s)
        if ext == "kvconfig":
            for k, v in {"highlight.color": acc, "inactive.highlight.color": "#7a0f1a",
                         "highlight.text.color": "#ffffff", "link.color": "#ff4655",
                         "link.visited.color": "#f08aa4", "progress.indicator.text.color": "#ffffff"}.items():
                s = re.sub(rf"^{re.escape(k)}=.*$", f"{k}={v}", s, flags=re.M)
        open(f"{dst}/{name}.{ext}", "w").write(s)
    print(f"  kvantum {old} -> {name}: highlight {hl} -> {acc}, greys tinted")
    sys.exit()

total = 0
for f in sorted(glob.glob(f"{HOME}/.themes/WhiteSur-Dark-red/gtk-3.0/*.css")):
    if os.path.islink(f): continue
    s = open(f).read()
    t, n = tok.subn(lambda m: sub(m), s)
    changed = sum(1 for a, b in zip(tok.findall(s), tok.findall(t)) if a != b)
    if changed:
        total += changed
        print(f"  gtk3 {f.replace(HOME, '~')}: {changed} greys tinted")
        if not DRY: open(f, "w").write(t)
print(f"  gtk3 total {total}")

# libadwaita dark defaults (1.6+) -> tinted
ADW = {"window_bg_color": "#222226", "view_bg_color": "#1d1d20", "headerbar_bg_color": "#2e2e32",
       "sidebar_bg_color": "#2e2e32", "secondary_sidebar_bg_color": "#28282c",
       "popover_bg_color": "#36363a", "dialog_bg_color": "#36363a", "thumbnail_bg_color": "#39393d",
       "headerbar_backdrop_color": "#222226", "sidebar_backdrop_color": "#28282c"}
def tint_hex(h): return hexc(tint(*(int(h[i:i + 2], 16) for i in (1, 3, 5))))
lines = ["/* Kuro OS — libadwaita surfaces with the shell's ink undertone (tools/tint-surfaces.py) */"]
lines += [f"@define-color {k} {tint_hex(v)};" for k, v in ADW.items()]
lines += [":root {"] + [f"  --{k.replace('_color', '').replace('_', '-')}-color: {tint_hex(v)};" for k, v in ADW.items()] + ["}"]
out = f"{HOME}/.config/gtk-4.0/bapirlo-surfaces.css"
print(f"  gtk4 -> {out.replace(HOME, '~')}: " + ", ".join(f"{k.split('_')[0]} {tint_hex(v)}" for k, v in list(ADW.items())[:4]))
if not DRY: open(out, "w").write("\n".join(lines) + "\n")
