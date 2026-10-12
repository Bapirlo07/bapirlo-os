#!/usr/bin/env python3
"""Neutral Bapirlo wallpaper + avatar (no third-party art) — used for the public README screenshots.
   python3 make-neutral-wallpaper.py OUTDIR   → OUTDIR/neutral.jpg (2560x1600), neutral-right.jpg (wordmark on
   the right, for the login screen whose card sits on the left), neutral-avatar.png"""
import os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
FONT = os.path.expanduser("~/.local/share/fonts/bapirlo/Bangers-Regular.ttf")
W, H = 2560, 1600
img = Image.new("RGB", (W, H), (14, 10, 13))
glow = Image.new("RGB", (W, H), (0, 0, 0))
g = ImageDraw.Draw(glow)
g.ellipse((1500, -700, 3300, 1100), fill=(150, 18, 32))
g.ellipse((-700, 900, 1100, 2400), fill=(90, 12, 22))
img = Image.blend(img, glow.filter(ImageFilter.GaussianBlur(260)), 0.55)
d = ImageDraw.Draw(img)
for i in range(-H, W, 46):   # faint manga speed lines
    d.line([(i, 0), (i + H * 0.55, H)], fill=(26, 18, 23), width=2)
big, small = ImageFont.truetype(FONT, 300), ImageFont.truetype(FONT, 80)
base = img.copy()
for name, cx in (("neutral.jpg", W / 2), ("neutral-right.jpg", W * 0.66)):
    im = base.copy()
    d = ImageDraw.Draw(im)
    tw = d.textlength("BAPIRLO", font=big)
    d.text((cx - tw / 2 + 12, 572), "BAPIRLO", font=big, fill=(60, 8, 16))
    d.text((cx - tw / 2, 560), "BAPIRLO", font=big, fill=(225, 29, 46))
    sw = d.textlength("OS  ·  KURO", font=small)
    d.text((cx - sw / 2, 900), "OS  ·  KURO", font=small, fill=(242, 233, 236))
    im.save(os.path.join(OUT, name), quality=92)
a = Image.new("RGB", (512, 512), (22, 16, 21))
ad = ImageDraw.Draw(a)
ad.ellipse((40, 40, 472, 472), fill=(225, 29, 46))
fb = ImageFont.truetype(FONT, 330)
ad.text(((512 - ad.textlength("B", font=fb)) / 2, 70), "B", font=fb, fill=(255, 255, 255))
a.save(os.path.join(OUT, "neutral-avatar.png"))
print("->", OUT)
