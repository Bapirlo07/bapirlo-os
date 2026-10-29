#!/usr/bin/env python3
"""Bapirlo-Cursors — the WhiteSur cursor shapes redrawn in the Kuro palette, with a manga touch.

  python3 build-cursors.py OUT_DIR [--preview PNG]

Source: ~/.local/share/icons/WhiteSur-cursors/cursors_scalable (one folder per cursor: SVG frames +
metadata.json with hotspot / delay, in 32-unit SVG space for nominal size 24).
Recolour: black body → ink, white rim → paper, grey → line, every rainbow colour of the busy spinner →
crimson/ember/blood/sakura by hue order. Manga touch: a hard blood-red drop shadow (no blur, offset
down-right, like the Bangers clock's text-shadow) under every cursor.
Writes OUT_DIR/{index.theme, cursors/<name> (Xcursor), cursors_scalable/<name>/ (recoloured SVGs)}.
Xcursor files are written here directly (no xcursorgen needed). Symlinked names in WhiteSur
(aliases + hash names) become symlinks here too.
"""
import colorsys
import io
import json
import os
import re
import shutil
import struct
import subprocess
import sys

from PIL import Image

SRC = os.path.expanduser("~/.local/share/icons/WhiteSur-cursors/cursors_scalable")
SIZES = (24, 32, 36, 48, 64, 72, 96)
INK, PAPER, LINE = "#0E0A0D", "#F2E9EC", "#523B44"
BLOOD, CRIMSON, EMBER, SAKURA = "#7A0F1A", "#E11D2E", "#FF4655", "#F08AA4"
SHADOW = 1.6          # svg units (32-unit canvas) — ≈1.6 px at size 24
SPIN = [BLOOD, CRIMSON, EMBER, SAKURA, "#FFFFFF", SAKURA, EMBER, CRIMSON]


def remap(svg):
    def col(m):
        c = m.group(0).lower()
        if len(c) == 4:
            c = "#" + "".join(ch * 2 for ch in c[1:])
        if c == "#000000":
            return INK
        if c == "#ffffff":
            return PAPER
        r, g, b = (int(c[i:i + 2], 16) / 255 for i in (1, 3, 5))
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        if s < 0.12:                                    # greys
            return LINE if l < 0.6 else "#CAB5BF"
        return SPIN[int(h * len(SPIN)) % len(SPIN)]      # spinner / colour accents by hue
    return re.sub(r"#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b", col, svg)


def manga(svg):
    """Wrap the drawing: blood-red hard shadow underneath. The shadow is the drawing's alpha, flooded."""
    m = re.search(r"<svg\b[^>]*>", svg)
    head, body = svg[:m.end()], svg[m.end():]
    body = body[:body.rfind("</svg>")]
    defs = (f'<defs><filter id="bapirlo-shadow" x="-20%" y="-20%" width="140%" height="140%">'
            f'<feOffset in="SourceAlpha" dx="{SHADOW}" dy="{SHADOW}" result="o"/>'
            f'<feFlood flood-color="{BLOOD}" flood-opacity="0.95"/>'
            f'<feComposite in2="o" operator="in" result="s"/>'
            f'<feMerge><feMergeNode in="s"/><feMergeNode in="SourceGraphic"/></feMerge>'
            f'</filter></defs>')
    return f'{head}{defs}<g filter="url(#bapirlo-shadow)">{body}</g></svg>'


def render(svg_text, px):
    png = subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px)], input=svg_text.encode(),
                         capture_output=True, check=True).stdout
    return Image.open(io.BytesIO(png)).convert("RGBA")


def xcursor(frames):
    """frames: [(nominal, Image, xhot, yhot, delay)] → bytes (Xcursor format, premultiplied ARGB)."""
    chunks = []
    for nominal, im, xh, yh, delay in frames:
        w, h = im.size
        raw, px = im.tobytes(), bytearray(w * h * 4)
        for i in range(0, len(raw), 4):        # RGBA → premultiplied BGRA (= little-endian ARGB)
            r, g, b, a = raw[i:i + 4]
            px[i:i + 4] = bytes((b * a // 255, g * a // 255, r * a // 255, a))
        chunks.append((nominal, struct.pack("<9I", 36, 0xFFFD0002, nominal, 1, w, h, xh, yh, delay) + bytes(px)))
    out = bytearray(struct.pack("<4sIII", b"Xcur", 16, 0x10000, len(chunks)))
    pos = 16 + 12 * len(chunks)
    for nominal, c in chunks:
        out += struct.pack("<III", 0xFFFD0002, nominal, pos)
        pos += len(c)
    for _, c in chunks:
        out += c
    return bytes(out)


def build(out):
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(os.path.join(out, "cursors"))
    os.makedirs(os.path.join(out, "cursors_scalable"))
    with open(os.path.join(out, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=Kuro Cursors\nComment=Kuro ink + crimson, manga drop shadow\n"
                "Inherits=WhiteSur-cursors,Adwaita\n")
    links = []
    for name in sorted(os.listdir(SRC)):
        p = os.path.join(SRC, name)
        if os.path.islink(p):
            links.append((name, os.readlink(p)))
            continue
        meta = json.load(open(os.path.join(p, "metadata.json")))
        sdir = os.path.join(out, "cursors_scalable", name)
        os.makedirs(sdir)
        frames = []
        for fr in meta:
            svg = manga(remap(open(os.path.join(p, fr["filename"])).read()))
            open(os.path.join(sdir, fr["filename"]), "w").write(svg)
            for nominal in SIZES:
                k = nominal / 24
                frames.append((nominal, render(svg, round(32 * k)), round(fr["hotspot_x"] * k),
                               round(fr["hotspot_y"] * k), fr.get("delay", 50)))
        json.dump(meta, open(os.path.join(sdir, "metadata.json"), "w"), indent=4)
        frames.sort(key=lambda f: f[0])          # all frames of a size together, in order
        open(os.path.join(out, "cursors", name), "wb").write(xcursor(frames))
    for name, target in links:
        os.symlink(target, os.path.join(out, "cursors", name))
        os.symlink(target, os.path.join(out, "cursors_scalable", name))
    return len(os.listdir(os.path.join(out, "cursors"))) - len(links), len(links)


def preview(out, png):
    names = ["default", "pointer", "text", "help", "progress", "wait", "crosshair", "move", "grabbing",
             "not-allowed", "nwse-resize", "col-resize", "zoom-in", "copy"]
    cell = 76
    sheet = Image.new("RGBA", (cell * len(names), cell * 2), "#2a2a2a")
    light = Image.new("RGBA", (cell * len(names), cell), "#e8e2e4")
    sheet.paste(light, (0, cell))
    for i, n in enumerate(names):
        d = os.path.join(out, "cursors_scalable", n)
        d = os.path.realpath(d)
        meta = json.load(open(os.path.join(d, "metadata.json")))
        im = render(open(os.path.join(d, meta[0]["filename"])).read(), 64)
        for row in (0, 1):
            sheet.alpha_composite(im, (i * cell + 6, row * cell + 6))
    sheet.save(png)


if __name__ == "__main__":
    out = sys.argv[1]
    real, aliases = build(out)
    print(f"Bapirlo-Cursors: {real} cursors + {aliases} aliases × sizes {SIZES} → {out}")
    if "--preview" in sys.argv:
        preview(out, sys.argv[sys.argv.index("--preview") + 1])
