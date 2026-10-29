#!/usr/bin/env python3
"""Build the Kuro OS Plymouth theme into ~/bapirlo-os/build/plymouth/bapirlo (no root)."""
import math, os, subprocess
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HOME = os.path.expanduser("~")
OUT = f"{HOME}/bapirlo-os/build/plymouth/bapirlo"
LOGO = f"{HOME}/bapirlo-os/assets/bapirlo-logo.png"
BANGERS = f"{HOME}/.local/share/fonts/bapirlo/Bangers-Regular.ttf"
RED, BLUE, PINK, EMERALD = (227, 36, 43), (47, 124, 255), (255, 61, 139), (16, 201, 143)
os.makedirs(OUT, exist_ok=True)

# background: very dim speed lines (splash should feel dark/premium)
subprocess.run(["python3", f"{HOME}/bapirlo-os/tools/make-art.py", "1920", "1200",
                f"{OUT}/bg.png", "--calm", "--seed", "5"], check=True)
bg = Image.open(f"{OUT}/bg.png").convert("RGB")
bg = Image.blend(Image.new("RGB", bg.size, (6, 6, 8)), bg, 0.45)
bg.save(f"{OUT}/bg.png", optimize=True)

# logo 512
Image.open(LOGO).convert("RGBA").resize((512, 512), Image.LANCZOS).save(f"{OUT}/logo.png")

# title
f = ImageFont.truetype(BANGERS, 110)
tmp = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
tw = int(tmp.textlength("KURO OS", font=f)) + 40
t = Image.new("RGBA", (tw, 150), (0, 0, 0, 0))
d = ImageDraw.Draw(t)
d.text((26, 18), "KURO OS", font=f, fill=(245, 245, 245), stroke_width=5, stroke_fill=(11, 11, 13))
d.text((20, 12), "KURO OS", font=f, fill=RED, stroke_width=5, stroke_fill=(11, 11, 13))
t.save(f"{OUT}/title.png")

# slash: full-screen diagonal streak (1920x1200), gradient glow + white core
W, H = 1920, 1200
x0, y0, x1, y1 = -100, 1060, 2020, 140
def streak(width, colorfn, alpha):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); dd = ImageDraw.Draw(im)
    n = 80
    for i in range(n):
        a, b = i / n, (i + 1) / n
        p = (x0 + (x1 - x0) * a, y0 + (y1 - y0) * a); q = (x0 + (x1 - x0) * b, y0 + (y1 - y0) * b)
        taper = math.sin(math.pi * (a + b) / 2)
        dd.line([p, q], fill=colorfn(a) + (alpha,), width=max(1, int(width * taper)))
    return im
def grad(tt):
    lerp = lambda c1, c2, k: tuple(int(c1[j] + (c2[j] - c1[j]) * k) for j in range(3))
    return lerp(BLUE, PINK, tt * 2) if tt < .5 else lerp(PINK, EMERALD, (tt - .5) * 2)
glow = streak(40, grad, 255).filter(ImageFilter.GaussianBlur(22))
slash = Image.alpha_composite(glow, streak(26, grad, 200))
slash = Image.alpha_composite(slash, streak(9, lambda _: (255, 255, 255), 255))
slash.save(f"{OUT}/slash.png")

# loader dots
for name, col in (("red", RED), ("blue", BLUE), ("pink", PINK), ("emerald", EMERALD)):
    im = Image.new("RGBA", (48, 48), (0, 0, 0, 0)); dd = ImageDraw.Draw(im)
    dd.ellipse([8, 8, 40, 40], fill=col + (255,))
    im = Image.alpha_composite(im.filter(ImageFilter.GaussianBlur(5)), im)
    im.save(f"{OUT}/dot-{name}.png")

# password entry box + bullet + lock
e = Image.new("RGBA", (520, 64), (0, 0, 0, 0)); dd = ImageDraw.Draw(e)
dd.rounded_rectangle([1, 1, 518, 62], 14, fill=(22, 22, 26, 235), outline=RED + (255,), width=3)
e.save(f"{OUT}/entry.png")
b = Image.new("RGBA", (22, 22), (0, 0, 0, 0)); ImageDraw.Draw(b).ellipse([3, 3, 19, 19], fill=PINK + (255,))
b.save(f"{OUT}/bullet.png")

open(f"{OUT}/bapirlo.plymouth", "w").write("""[Plymouth Theme]
Name=Kuro OS
Description=Kuro OS: katana slash, pulsing logo, RGB loader
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/bapirlo
ScriptFile=/usr/share/plymouth/themes/bapirlo/bapirlo.script
""")
print("Plymouth theme assets built in", OUT)
