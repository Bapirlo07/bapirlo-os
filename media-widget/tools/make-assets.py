#!/usr/bin/env python3
"""Halftone corner for the media card (manga screentone), in the Kuro palette."""
import os, sys
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.expanduser("~/bapirlo-os/tools"))
from palette import rgb

S, STEP, SCALE = 132, 9, 4          # logical size, dot pitch, supersampling
img = Image.new("RGBA", (S * SCALE, S * SCALE), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
r, g, b = rgb("crimson")
for row, y in enumerate(range(0, S + STEP, STEP)):
    off = STEP / 2 if row % 2 else 0                      # staggered screentone grid
    for x in range(0, S + STEP, STEP):
        cx, cy = x + off, y
        # dots fade out from the top-right corner
        t = max(0.0, 1 - ((S - cx) ** 2 + cy ** 2) ** 0.5 / S)
        rad = t * STEP * 0.42
        if rad < 0.35:
            continue
        a = int(70 + 120 * t)
        d.ellipse([(cx - rad) * SCALE, (cy - rad) * SCALE, (cx + rad) * SCALE, (cy + rad) * SCALE],
                  fill=(r, g, b, a))
out = os.path.join(os.path.dirname(__file__), "..", "bapirlo-media@bapirlo-os", "assets", "halftone.png")
img.resize((S * 2, S * 2), Image.LANCZOS).save(out)       # 2x for HiDPI
print("wrote", os.path.normpath(out))
