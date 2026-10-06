#!/usr/bin/env python3
"""Recolour the installed WhiteSur-Dark-red (+hdpi/xhdpi, ~/.config/gtk-4.0) from salmon
#ED5F5D to Kuro crimson using build/whitesur-kuro-colormap.json — an exact old->new map of
every derived shade, learned by building WhiteSur twice with identical options. Keeps all
other install options (rounded corners, activities icon, ...) untouched."""
import glob, json, os, re
HOME = os.path.expanduser("~")
mp = json.load(open(f"{HOME}/bapirlo-os/build/whitesur-kuro-colormap.json"))
tok = re.compile(r"#[0-9A-Fa-f]{6}\b|rgba?\([^)]*\)")
files = [f for d in glob.glob(f"{HOME}/.themes/WhiteSur-Dark-red*") for f in glob.glob(f"{d}/**/*.css", recursive=True)]
files += [f for f in glob.glob(f"{HOME}/.config/gtk-4.0/*.css") if not os.path.islink(f)]
n_total = 0
for f in files:
    s = open(f).read(); n = 0
    def sub(m):
        global n_total
        r = mp.get(m.group(0))
        if r: n_total += 1; return r
        return m.group(0)
    t = tok.sub(sub, s)
    if t != s: open(f, "w").write(t); print(f"  recoloured {f.replace(HOME, '~')}")
print(f"  {n_total} colour values replaced")
