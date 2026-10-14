#!/usr/bin/env python3
"""Bapirlo OS — build every hero-art variant from the one source image.

  build/art/hero-2560x1600.png   desktop wallpaper (clean, light grade)
  build/art/boot-2560x1600.png   GRUB / Plymouth / login base (darker left side for UI)
  build/art/blur-2560x1600.png   heavily blurred + darkened (password / overview backdrop)

The source is ~736x414, so it is upscaled ~3.9x: Real-ESRGAN anime x4 with TTA (8 flipped /
rotated passes averaged — cleaner line art, ~10 s on the NVIDIA card, falls back to the default
GPU), Lanczos down to 1600 px tall, a light unsharp mask, then fine pixel-sized monochrome grain
(reads as print/manga screentone; the old half-resolution grain looked blotchy and soft). The artist watermark sits in the bottom-right
corner and is cropped off by the centre crop + covered by the vignette.
"""
import os, random, subprocess, sys
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter
sys.path.insert(0, os.path.dirname(__file__))
from palette import HERO, rgb

W, H = 2560, 1600
OUT = os.path.expanduser("~/bapirlo-os/build/art")
os.makedirs(OUT, exist_ok=True)


def upscale():
    """AI 4x upscale (Real-ESRGAN anime model, tools/realesrgan) when available,
    ImageMagick Lanczos as fallback; then fit to 2560x1600 (centre crop)."""
    tmp = f"{OUT}/_up.png"
    esr = os.path.join(os.path.dirname(__file__), "realesrgan")
    src = HERO
    if os.access(f"{esr}/realesrgan-ncnn-vulkan", os.X_OK):
        ai = f"{OUT}/_x4.png"
        cmd = [f"{esr}/realesrgan-ncnn-vulkan", "-i", HERO, "-o", ai, "-n", "realesrgan-x4plus-anime",
               "-m", f"{esr}/models", "-x"]
        gpu = os.environ.get("BAPIRLO_ESR_GPU", "1")          # 1 = the RTX 4060 here; Intel is 0
        if subprocess.run(cmd + ["-g", gpu], capture_output=True).returncode or not os.path.exists(ai):
            subprocess.run(cmd, check=True, capture_output=True)
        subprocess.run(["magick", ai, "-filter", "Lanczos", "-resize", f"x{H}", "-gravity", "center",
                        "-crop", f"{W}x{H}+0+0", "+repage", "-unsharp", "0x1.4+0.45+0.008", tmp], check=True)
        os.remove(ai); print("upscale: Real-ESRGAN x4plus-anime (TTA)")
    else:
        subprocess.run(["magick", src, "-enhance", "-colorspace", "RGB", "-filter", "LanczosSharp",
                        "-distort", "Resize", f"x{H}", "-colorspace", "sRGB",
                        "-adaptive-sharpen", "0x1.6", "-gravity", "center",
                        "-crop", f"{W}x{H}+0+0", "+repage", tmp], check=True)
        print("upscale: ImageMagick fallback")
    im = Image.open(tmp).convert("RGB")
    os.remove(tmp)
    return im


def radial(w, h, inner=0.35, outer=1.0, power=1.6):
    """L mask: 255 at centre fading to 0 at corners."""
    small = Image.new("L", (256, 160))
    px = small.load()
    for y in range(160):
        for x in range(256):
            dx, dy = (x - 128) / 128, (y - 80) / 80
            d = (dx * dx + dy * dy) ** .5 / 1.4142
            t = min(1, max(0, (d - inner) / (outer - inner)))
            px[x, y] = int(255 * (1 - t ** power))
    return small.resize((w, h), Image.BICUBIC)


def hgrad(w, h, stops):
    """L mask from list of (x_fraction, value) stops, left->right."""
    row = Image.new("L", (w, 1))
    for x in range(w):
        f = x / (w - 1)
        for (f0, v0), (f1, v1) in zip(stops, stops[1:]):
            if f0 <= f <= f1:
                v = v0 + (v1 - v0) * (f - f0) / (f1 - f0 or 1)
                row.putpixel((x, 0), int(v)); break
    return row.resize((w, h))


def grain(im, amount=14, seed=7):
    random.seed(seed)
    n = Image.effect_noise((W, H), 64)                          # one grain per pixel: crisp, not blotchy
    n = n.point(lambda v: 128 + (v - 128) * amount // 64).convert("RGB")
    return ImageChops.overlay(im, n)


def tint(im, color, mask):
    return Image.composite(Image.new("RGB", im.size, color), im, mask)


base = upscale()
base = ImageEnhance.Color(base).enhance(1.10)
base = ImageEnhance.Contrast(base).enhance(1.06)

ink = rgb("ink")
vig = radial(W, H, inner=.30, outer=1.05, power=1.8)          # 255 centre
corner = Image.new("L", (W, H), 0)                              # watermark cover
ImageDraw.Draw(corner).ellipse([W - 520, H - 380, W + 320, H + 300], fill=255)
corner = corner.filter(ImageFilter.GaussianBlur(120))

# 1) desktop wallpaper: light vignette only
wall = tint(base, ink, ImageChops.invert(vig).point(lambda v: v * 0.55))
wall = tint(wall, ink, corner.point(lambda v: v * 0.85))
grain(wall, 4).save(f"{OUT}/hero-{W}x{H}.png", optimize=True)

# 2) boot / login base: darker overall, strong left shade so menus/panels read clearly
boot = ImageEnhance.Brightness(base).enhance(0.80)
boot = tint(boot, ink, ImageChops.invert(vig).point(lambda v: v * 0.75))
boot = tint(boot, ink, hgrad(W, H, [(0, 200), (.30, 150), (.52, 40), (1, 0)]))
boot = tint(boot, ink, corner.point(lambda v: v * 0.95))
grain(boot, 7).save(f"{OUT}/boot-{W}x{H}.png", optimize=True)

# 3) blurred backdrop
blur = base.resize((W // 8, H // 8), Image.LANCZOS).filter(ImageFilter.GaussianBlur(6)).resize((W, H), Image.BICUBIC)
blur = ImageEnhance.Brightness(blur).enhance(0.45)
blur = tint(blur, ink, ImageChops.invert(vig).point(lambda v: v * 0.6))
grain(blur, 5).save(f"{OUT}/blur-{W}x{H}.png", optimize=True)

for n in ("hero", "boot", "blur"):
    Image.open(f"{OUT}/{n}-{W}x{H}.png").resize((W // 2, H // 2), Image.LANCZOS).save(f"{OUT}/_prev-{n}.png")
print("art ->", OUT)
