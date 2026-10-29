#!/usr/bin/env python3
"""Kuro OS — day / night grades of the Kuro wallpaper (no root, deterministic).

  day    brighter: shadows lifted, paper-white highlights, a touch warmer — reads like a printed page
  night  darker: deeper ink, crimson kept glowing, soft vignette — easy on the eyes after sunset

Input:  ~/.local/share/backgrounds/bapirlo/kuro-2560x1600.png (the approved upscaled art)
Output: build/art/kuro-day-2560x1600.jpg, build/art/kuro-night-2560x1600.jpg
        (JPEG q95: ~5x smaller than PNG, loads faster on every switch)
Want different art for day or night? Put images in ~/Pictures/wallpapers/bapirlo/day or …/night —
bapirlo-daycycle uses those folders first (one image per day, rotating).
"""
import os
from PIL import Image, ImageChops, ImageEnhance, ImageFilter

HOME = os.path.expanduser("~")
SRC = f"{HOME}/.local/share/backgrounds/bapirlo/kuro-2560x1600.png"
OUT = f"{HOME}/bapirlo-os/build/art"


def curve(img, lift, gamma, gain):
    """per-channel tone curve: out = lift + (1-lift) * in^gamma * gain"""
    lut = []
    for ch in range(3):
        for i in range(256):
            v = i / 255
            v = lift[ch] + (1 - lift[ch]) * (v ** gamma) * gain[ch]
            lut.append(max(0, min(255, round(v * 255))))
    return img.point(lut)


def vignette(size, strength):
    w, h = size
    m = Image.radial_gradient("L").resize((w, h), Image.BICUBIC)       # 0 centre → 255 edge
    m = m.point(lambda v: round(255 - strength * 255 * (v / 255) ** 1.6))
    return m.filter(ImageFilter.GaussianBlur(40))


def grade_day(src):
    day = curve(src, lift=(0.075, 0.065, 0.07), gamma=0.80, gain=(1.03, 1.0, 0.99))
    day = ImageEnhance.Contrast(day).enhance(0.94)
    day = ImageEnhance.Color(day).enhance(1.06)
    glow = day.filter(ImageFilter.GaussianBlur(28))
    return Image.blend(day, ImageChops.screen(day, glow), 0.18)            # soft bloom on the whites


def grade_night(src, ink=(14, 10, 13)):
    """Darker, cooler, edges fading into the base colour (Theme Studio passes its own ink)."""
    night = curve(src, lift=(0.0, 0.0, 0.0), gamma=1.25, gain=(0.80, 0.75, 0.78))
    night = ImageEnhance.Color(night).enhance(1.10)
    return Image.composite(night, Image.new("RGB", src.size, ink), vignette(src.size, 0.55))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    src = Image.open(SRC).convert("RGB")
    day = grade_day(src)
    day.save(f"{OUT}/kuro-day-2560x1600.jpg", quality=95, subsampling=0)
    night = grade_night(src)
    night.save(f"{OUT}/kuro-night-2560x1600.jpg", quality=95, subsampling=0)
    # contact sheet for review
    sheet = Image.new("RGB", (1920, 400), (20, 20, 20))
    for i, im in enumerate((day, src, night)):
        sheet.paste(im.resize((640, 400), Image.LANCZOS), (i * 640, 0))
    sheet.save(f"{OUT}/_prev-daynight.png")
    print("ok", OUT)
