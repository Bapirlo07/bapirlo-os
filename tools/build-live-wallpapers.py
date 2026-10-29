#!/usr/bin/env python3
"""Bapirlo OS — original LIVE wallpapers: four of the code-drawn scenes, animated, as seamless loops.

  night-live  night-a: petals fall from the sakura branch, stars twinkle, the moon halo breathes
  dawn-live   dawn-b:  a breeze carries petals over the lake, the sun's path glitters, the mist breathes
  day-live    day-b:   crimson / sakura / ink petals blow past the big sun, the sun breathes
  dusk-live   dusk-a:  crows cross the sky flapping, the sea glitters under the sun, the glow breathes

The still scene (tools/build-wallpapers.py with LIVE = True, i.e. without its static petals / crows) is
the background; what moves is drawn on top every frame. Every motion is periodic in the loop length
(whole laps, whole sways, whole spins), so the last frame runs straight into the first.

  build-live-wallpapers.py [OUT_DIR] [--size 2560x1600] [--seconds 16] [--fps 30] [--only night,dusk]
Default OUT_DIR: ~/.local/share/backgrounds/bapirlo/originals/live   (H.264 .mp4, Intel decodes it in hardware)
"""
import importlib.util
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("bw", os.path.join(HERE, "build-wallpapers.py"))
bw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bw)
bw.LIVE = True
C = bw.C
TAU = 2 * math.pi


def rgba(name, a=1.0):
    return tuple(int(c * 255) for c in C[name]) + (int(max(0.0, min(1.0, a)) * 255),)


def still(scene, size, seed, tweak=None):
    """The scene as an RGBA image; tweak(cv) runs on the canvas before saving (for the breathing variant)."""
    cv = bw.Canvas(*size, seed=seed)
    bw.SCENES[scene](cv)
    if tweak:
        tweak(cv)
    img = cv.img + cv.rng.normal(0, 0.018, cv.img.shape[:2])[..., None]          # same paper grain as the stills
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).convert("RGBA"), cv


def glow(cv, cx, cy, radius, colour, amount):
    g = np.exp(-((np.hypot(cv.x - cx, cv.y - cy) / radius) ** 2))
    cv.put(C[colour], g * amount)


# ------------------------------------------------------------------ moving things
class Petals:
    """Petals travelling from one edge to another: whole laps per loop, sway, spin and a 3-D flip."""

    def __init__(self, rng, n, w, h, start, end, colours, size, alpha=(0.6, 0.95), laps=(1, 2), spread=0.5):
        self.w, self.h = w, h
        self.items = []
        for _ in range(n):
            self.items.append(dict(
                p0=rng.uniform(0, 1), laps=int(rng.integers(laps[0], laps[1] + 1)),
                sx=rng.uniform(*start[0]) * w, sy=rng.uniform(*start[1]) * h,
                ex=rng.uniform(*end[0]) * w, ey=rng.uniform(*end[1]) * h,
                sway=rng.uniform(20, 70) * spread * 2, sways=int(rng.integers(1, 4)), sph=rng.uniform(0, TAU),
                rot=rng.uniform(0, TAU), spins=int(rng.integers(-3, 4)) or 1,
                flips=int(rng.integers(2, 6)), fph=rng.uniform(0, TAU),
                size=rng.uniform(*size), col=colours[int(rng.integers(len(colours)))], a=rng.uniform(*alpha)))

    def draw(self, d, t):
        for q in self.items:
            p = (q["p0"] + q["laps"] * t) % 1.0
            x = q["sx"] + (q["ex"] - q["sx"]) * p
            y = q["sy"] + (q["ey"] - q["sy"]) * p
            nx, ny = -(q["ey"] - q["sy"]), q["ex"] - q["sx"]                   # sway across the path
            norm = math.hypot(nx, ny) or 1
            s = q["sway"] * math.sin(TAU * q["sways"] * t + q["sph"])
            x, y = x + nx / norm * s, y + ny / norm * s
            rot = q["rot"] + TAU * q["spins"] * t
            flip = 0.25 + 0.75 * abs(math.cos(TAU * q["flips"] * t + q["fph"]))
            pts = []
            for px, py in bw.petal_poly(0, 0, q["size"], 0):
                px *= flip
                pts.append((x + px * math.cos(rot) - py * math.sin(rot), y + px * math.sin(rot) + py * math.cos(rot)))
            d.polygon(pts, fill=rgba(q["col"], q["a"] * (0.75 + 0.25 * flip)))


class Twinkle:
    """Points that fade in and out (stars, glitter on water); whole cycles per loop."""

    def __init__(self, rng, points, colour, cycles=(1, 4), length=(0, 0), width=2, cross=0.0, peak=(0.6, 1.0)):
        self.items = [dict(x=x, y=y, c=int(rng.integers(cycles[0], cycles[1] + 1)), ph=rng.uniform(0, TAU),
                           ln=rng.uniform(*length), cross=rng.uniform() < cross, peak=rng.uniform(*peak)) for x, y in points]
        self.colour, self.width = colour, width

    def draw(self, d, t):
        for q in self.items:
            a = max(0.0, math.sin(TAU * q["c"] * t + q["ph"])) ** 3 * q["peak"]
            if a < 0.03:
                continue
            col = rgba(self.colour, a)
            x, y = q["x"], q["y"]
            if q["ln"]:                                        # a glint: short horizontal dash
                d.line((x - q["ln"] / 2, y, x + q["ln"] / 2, y), fill=col, width=self.width)
            else:
                r = 1.5 + 1.5 * a
                d.ellipse((x - r, y - r, x + r, y + r), fill=col)
                if q["cross"]:
                    k = 4 + 9 * a
                    d.line((x - k, y, x + k, y), fill=col, width=1)
                    d.line((x, y - k, x, y + k), fill=col, width=1)


class Crows:
    """Ink crows crossing right → left, wings beating."""

    def __init__(self, rng, n, w, h):
        self.w, self.h = w, h
        self.items = [dict(p0=rng.uniform(0, 1), laps=int(rng.integers(1, 3)), y=rng.uniform(0.10, 0.36) * h,
                           bob=rng.uniform(6, 22), s=rng.uniform(11, 24), flaps=int(rng.integers(28, 44)),
                           ph=rng.uniform(0, TAU)) for _ in range(n)]

    def draw(self, d, t):
        for q in self.items:
            p = (q["p0"] + q["laps"] * t) % 1.0
            s = q["s"]
            x = self.w + 3 * s - p * (self.w + 6 * s)
            y = q["y"] + q["bob"] * math.sin(TAU * 2 * t + q["ph"])
            wing = math.sin(TAU * q["flaps"] * t + q["ph"])              # -1 down … 1 up
            tip = -s * (0.15 + 0.55 * wing)
            mid = -s * (0.05 + 0.2 * wing)
            pts = [(x - s, y + tip), (x - s * 0.45, y + mid), (x, y + s * 0.15), (x + s * 0.45, y + mid), (x + s, y + tip)]
            d.line(pts, fill=rgba("ink"), width=max(3, int(s / 5)), joint="curve")


# ------------------------------------------------------------------ scenes
def night(size, rng):
    w, h = size
    lo, cv = still("night-a", size, 1006)
    hi, _ = still("night-a", size, 1006, lambda c: glow(c, 0.70 * w, 0.34 * h, 0.5 * h, "crimson", 0.14))
    sky = [(x, y) for x, y in zip(rng.uniform(0.02, 0.98, 260) * w, rng.uniform(0.02, 0.62, 260) * h)
           if math.hypot(x - 0.70 * w, y - 0.34 * h) > 0.22 * h]
    movers = [Twinkle(rng, sky, "paper", (1, 5), cross=0.18, peak=(0.35, 0.95)),
              Petals(rng, 70, w, h, ((0.45, 1.05), (-0.08, 0.45)), ((-0.05, 0.75), (1.05, 1.1)),
                     ("sakura", "sakura", "paper", "rose"), (13, 28), (0.55, 0.95))]
    return lo, hi, movers, 1


def dawn(size, rng):
    w, h = size
    lo, _ = still("dawn-b", size, 1001)
    hi, _ = still("dawn-b", size, 1001, lambda c: glow(c, 0.72 * w, 0.60 * h, 0.45 * h, "peach", 0.16))
    horizon, cx = 0.62 * h, 0.72 * w
    water = []
    for _ in range(170):
        y = horizon + rng.uniform(0.01, 0.3) ** 1.3 * h
        spread = 0.2 * h * (0.5 + (y - horizon) / (0.3 * h))
        water.append((cx + rng.normal(0, spread * 0.55), y))
    movers = [Twinkle(rng, water, "peach", (2, 6), length=(10, 46), width=3, peak=(0.5, 1.0)),
              Petals(rng, 55, w, h, ((1.02, 1.1), (0.0, 0.5)), ((-0.1, -0.02), (0.15, 0.85)),
                     ("sakura", "paper", "rose"), (14, 30), (0.55, 0.95))]
    return lo, hi, movers, 1


def day(size, rng):
    w, h = size
    lo, _ = still("day-b", size, 1003)
    hi, _ = still("day-b", size, 1003, lambda c: glow(c, 0.66 * w, 0.46 * h, 0.42 * h, "ember", 0.12))
    movers = [Petals(rng, 60, w, h, ((1.02, 1.12), (-0.1, 0.7)), ((-0.12, 0.3), (0.5, 1.1)),
                     ("crimson", "crimson", "sakura", "ink"), (18, 40), (0.7, 1.0), spread=0.7)]
    return lo, hi, movers, 1


def dusk(size, rng):
    w, h = size
    lo, _ = still("dusk-a", size, 1004)
    hi, _ = still("dusk-a", size, 1004, lambda c: glow(c, 0.64 * w, 0.64 * h, 0.5 * h, "gold", 0.14))
    horizon, cx = 0.64 * h, 0.64 * w
    water = []
    for _ in range(230):
        y = horizon + 4 + rng.uniform(0, 1) ** 1.6 * 0.34 * h
        water.append((cx + rng.normal(0, 0.24 * h * (0.4 + (y - horizon) / (0.34 * h))), y))
    movers = [Twinkle(rng, water, "gold", (2, 6), length=(12, 60), width=3, peak=(0.55, 1.0)),
              Crows(rng, 9, w, h)]
    return lo, hi, movers, 1


SCENES = {"night": night, "dawn": dawn, "day": day, "dusk": dusk}


def render(name, out, size, seconds, fps):
    rng = np.random.default_rng(5000 + list(SCENES).index(name))
    lo, hi, movers, breaths = SCENES[name](size, rng)
    frames = int(round(seconds * fps))
    path = os.path.join(out, f"{name}-live.mp4")
    tmp = path + ".part.mp4"
    enc = subprocess.Popen(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", f"{size[0]}x{size[1]}", "-r", str(fps), "-i", "-",
         "-c:v", "libx264", "-preset", "slow", "-crf", "19", "-tune", "animation", "-pix_fmt", "yuv420p",
         "-g", str(fps * 2), "-movflags", "+faststart", "-an", tmp], stdin=subprocess.PIPE)
    for i in range(frames):
        t = i / frames                                               # 0 … 1, never reaching 1: seamless
        k = 0.5 - 0.5 * math.cos(TAU * breaths * t)
        frame = Image.blend(lo, hi, k)
        layer = Image.new("RGBA", size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        for m in movers:
            m.draw(d, t)
        frame.alpha_composite(layer)
        enc.stdin.write(frame.convert("RGB").tobytes())
    enc.stdin.close()
    if enc.wait() != 0:
        raise SystemExit(f"ffmpeg failed for {name}")
    os.replace(tmp, path)
    return path


def main():
    args = sys.argv[1:]
    size, seconds, fps, only = (2560, 1600), 16.0, 30, None
    for flag in ("--size", "--seconds", "--fps", "--only"):
        if flag in args:
            i = args.index(flag)
            v = args[i + 1]
            del args[i:i + 2]
            if flag == "--size":
                size = tuple(int(x) for x in v.split("x"))
            elif flag == "--seconds":
                seconds = float(v)
            elif flag == "--fps":
                fps = int(v)
            else:
                only = set(v.split(","))
    out = os.path.expanduser(args[0] if args else "~/.local/share/backgrounds/bapirlo/originals/live")
    os.makedirs(out, exist_ok=True)
    for name in SCENES:
        if only and name not in only:
            continue
        print(render(name, out, size, seconds, fps), flush=True)


if __name__ == "__main__":
    main()
