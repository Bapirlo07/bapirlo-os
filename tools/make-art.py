#!/usr/bin/env python3
"""Bapirlo OS manga-style background generator.

usage: make-art.py WIDTH HEIGHT OUT.png [--logo] [--title] [--calm] [--right] [--seed N]
  --logo   draw the Bapirlo logo
  --title  draw "BAPIRLO OS" in Bangers
  --calm   fewer/dimmer speed lines (for screens with text on top, e.g. GRUB menu)
"""
import math, os, random, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

BASE, PANEL = (11, 11, 13), (22, 22, 26)
RED, BLUE, PINK, EMERALD = (227, 36, 43), (47, 124, 255), (255, 61, 139), (16, 201, 143)
HOME = os.path.expanduser("~")
LOGO = f"{HOME}/bapirlo-os/assets/bapirlo-logo.png"
FONT = f"{HOME}/.local/share/fonts/bapirlo/Bangers-Regular.ttf"


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient_color(t):
    """blue -> pink -> emerald along the slash."""
    return lerp(BLUE, PINK, t * 2) if t < 0.5 else lerp(PINK, EMERALD, (t - 0.5) * 2)


def main():
    args = sys.argv[1:]
    W, H, out = int(args[0]), int(args[1]), args[2]
    calm = "--calm" in args
    seed = int(args[args.index("--seed") + 1]) if "--seed" in args else 7
    rnd = random.Random(seed)
    s = min(W, H) / 1080  # scale factor

    # 1. base: vertical gradient black -> charcoal
    img = Image.new("RGB", (W, H), BASE)
    d = ImageDraw.Draw(img)
    for y in range(H):
        d.line([(0, y), (W, y)], fill=lerp(BASE, PANEL, y / H))

    # 2. halftone screen-tone, denser toward bottom-right
    tone = Image.new("L", (W, H), 0)
    td = ImageDraw.Draw(tone)
    step = max(6, int(14 * s))
    for y in range(0, H, step):
        for x in range((y // step % 2) * step // 2, W, step):
            t = max(0.0, (x / W + y / H) / 2 - 0.35) / 0.65
            r = step * 0.42 * t
            if r > 0.6:
                td.ellipse([x - r, y - r, x + r, y + r], fill=255)
    img.paste(Image.new("RGB", (W, H), (70, 12, 16)), mask=tone)

    # 3. radial speed lines from a focal point
    fx, fy = W * 0.60, H * 0.46
    lines = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lines)
    n = 70 if calm else 150
    R = math.hypot(W, H)
    for _ in range(n):
        a = rnd.uniform(0, 2 * math.pi)
        width = rnd.uniform(0.002, 0.012 if calm else 0.02)
        inner = rnd.uniform(0.18, 0.42) * min(W, H)
        col = RED if rnd.random() < 0.7 else (235, 235, 235)
        alpha = rnd.randint(25, 70) if calm else rnd.randint(50, 150)
        p1 = (fx + math.cos(a) * inner, fy + math.sin(a) * inner)
        p2 = (fx + math.cos(a - width) * R, fy + math.sin(a - width) * R)
        p3 = (fx + math.cos(a + width) * R, fy + math.sin(a + width) * R)
        ld.polygon([p1, p2, p3], fill=col + (alpha,))
    img.paste(lines, mask=lines)

    # 4. the katana slash: gradient glow + white core
    x0, y0, x1, y1 = W * -0.05, H * 0.86, W * 1.05, H * 0.14
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    segs = 60
    for i in range(segs):
        t0, t1 = i / segs, (i + 1) / segs
        a = (x0 + (x1 - x0) * t0, y0 + (y1 - y0) * t0)
        b = (x0 + (x1 - x0) * t1, y0 + (y1 - y0) * t1)
        taper = math.sin(math.pi * (t0 + t1) / 2)  # thick in middle
        gd.line([a, b], fill=gradient_color(t0) + (255,), width=max(2, int(26 * s * taper)))
    blurred = glow.filter(ImageFilter.GaussianBlur(18 * s))
    img.paste(blurred, mask=blurred)
    img.paste(glow, mask=glow.getchannel("A").point(lambda v: v // 2))
    core = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(core)
    for i in range(segs):
        t0, t1 = i / segs, (i + 1) / segs
        a = (x0 + (x1 - x0) * t0, y0 + (y1 - y0) * t0)
        b = (x0 + (x1 - x0) * t1, y0 + (y1 - y0) * t1)
        taper = math.sin(math.pi * (t0 + t1) / 2)
        cd.line([a, b], fill=(255, 255, 255, 255), width=max(1, int(7 * s * taper)))
    img.paste(core, mask=core)

    # 5. ink splatter dots along the slash
    sd = ImageDraw.Draw(img)
    for _ in range(40 if not calm else 15):
        t = rnd.random()
        px = x0 + (x1 - x0) * t + rnd.gauss(0, 60 * s)
        py = y0 + (y1 - y0) * t + rnd.gauss(0, 60 * s)
        r = rnd.uniform(1.5, 7) * s
        sd.ellipse([px - r, py - r, px + r, py + r], fill=rnd.choice([RED, RED, PINK, (240, 240, 240)]))

    # 6. vignette
    vig = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vig).ellipse([-W * 0.25, -H * 0.3, W * 1.25, H * 1.3], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(min(W, H) * 0.12))
    img = Image.composite(img, Image.new("RGB", (W, H), (0, 0, 0)), vig)

    # 7. logo + title
    cx, cy = (int(W * 0.70) if "--right" in args else W // 2), H // 2
    if "--logo" in args and os.path.exists(LOGO):
        size = int(min(W, H) * 0.30)
        logo = Image.open(LOGO).convert("RGBA").resize((size, size), Image.LANCZOS)
        ly = cy - size // 2 - (int(size * 0.18) if "--title" in args else 0)
        img.paste(logo, (cx - size // 2, ly), logo)
        cy = ly + size + int(size * 0.02)
    if "--title" in args and os.path.exists(FONT):
        fs = int(min(W, H) * 0.085)
        font = ImageFont.truetype(FONT, fs)
        text = "BAPIRLO OS"
        dd = ImageDraw.Draw(img)
        tw = dd.textlength(text, font=font)
        tx = cx - tw / 2
        ty = cy if "--logo" in args else cy - fs / 2
        off = max(2, int(fs * 0.06))
        dd.text((tx + off, ty + off), text, font=font, fill=(245, 245, 245),
                stroke_width=max(2, fs // 18), stroke_fill=BASE)
        dd.text((tx, ty), text, font=font, fill=RED,
                stroke_width=max(2, fs // 18), stroke_fill=BASE)

    img.save(out, optimize=True)
    print(out, img.size)


if __name__ == "__main__":
    main()
