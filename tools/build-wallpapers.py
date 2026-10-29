#!/usr/bin/env python3
"""Kuro OS — original manga-style wallpapers, drawn entirely in code (no source artwork).

Eight scenes, two per time of day, in the Kuro palette (tools/palette.py):
  dawn-a  rising sun behind three ink ridges, sakura sky          dawn-b  sun-stripes over a misty lake
  day-a   paper sky in screentone, crimson sun + focus lines      day-b   big crimson disc, ink brush slash
  dusk-a  sun sinking into the sea, torii in the water, crows     dusk-b  city skyline + power lines at dusk
  night-a pale moon, sakura branch, falling petals, star tone     night-b blood moon, speed lines, mist ridges

The busy parts sit right of centre: the desktop widgets live bottom-left and the icons top-left.
  build-wallpapers.py [OUT_DIR] [--size 2560x1600] [--only dusk-b,...]
Default OUT_DIR: ~/.local/share/backgrounds/bapirlo/originals
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from palette import PAL  # noqa: E402


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255


C = {k: hexrgb(v) for k, v in PAL.items()}
C["violet"] = hexrgb("#2A1830")
C["peach"] = hexrgb("#FFD9C9")
C["gold"] = hexrgb("#FFB36B")

# tools/build-live-wallpapers.py sets this: scenes then leave out what it animates (drifting petals, crows)
LIVE = False


# ------------------------------------------------------------------ canvas helpers
class Canvas:
    def __init__(self, w, h, seed):
        self.w, self.h = w, h
        self.rng = np.random.default_rng(seed)
        self.img = np.zeros((h, w, 3), np.float32)
        self.y, self.x = np.mgrid[0:h, 0:w].astype(np.float32)
        self.u, self.v = self.x / w, self.y / h          # 0..1

    def put(self, color, mask):
        """Paint colour (rgb array or HxWx3) where mask (HxW, 0..1)."""
        m = np.clip(mask, 0, 1)[..., None]
        self.img = self.img * (1 - m) + np.asarray(color, np.float32) * m

    def gradient(self, stops, t=None):
        """Vertical (or any t-map) gradient through [(pos, colour), …]."""
        t = self.v if t is None else t
        out = np.zeros_like(self.img)
        pos = [p for p, _ in stops]
        for ch in range(3):
            out[..., ch] = np.interp(t, pos, [c[ch] for _, c in stops])
        return out

    def save(self, path, grain=0.018):
        img = self.img + self.rng.normal(0, grain, self.img.shape[:2])[..., None]   # paper grain
        Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(path, quality=92, optimize=True)


def smooth(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


def halftone(cv, amount, spacing=14, angle=45):
    """Screentone: dot coverage follows amount (0..1)."""
    a = math.radians(angle)
    u = cv.x * math.cos(a) + cv.y * math.sin(a)
    v = -cv.x * math.sin(a) + cv.y * math.cos(a)
    du = np.mod(u, spacing) - spacing / 2
    dv = np.mod(v, spacing) - spacing / 2
    d = np.sqrt(du * du + dv * dv)
    r = spacing / 2 * np.sqrt(np.clip(amount, 0, 1)) * 1.12
    return smooth(r + 0.8, r - 0.8, d) * (amount > 0.002)


def fbm1d(rng, n, octaves=6, rough=0.55):
    """1-D fractal noise, n samples, roughly -1..1."""
    out = np.zeros(n, np.float32)
    amp, freq, total = 1.0, 3, 0.0
    for _ in range(octaves):
        pts = rng.uniform(-1, 1, freq + 2)
        xs = np.linspace(0, freq + 1, n)
        out += amp * np.interp(xs, np.arange(freq + 2), pts)
        total += amp
        amp *= rough
        freq *= 2
    return out / total


def ridge(cv, base, height, rough=0.55, sharp=True, octaves=7):
    """Mask under a mountain ridge line (base, height as fractions of the canvas height)."""
    n = fbm1d(cv.rng, cv.w, octaves, rough)
    if sharp:
        n = 1 - np.abs(n) * 2          # ridged peaks
    line = (base - height * n) * cv.h
    return smooth(line - 1.2, line + 1.2, cv.y), line


def disc(cv, cx, cy, r, soft=1.5):
    d = np.hypot(cv.x - cx, cv.y - cy)
    return smooth(r + soft, r - soft, d), d


def speed_lines(cv, cx, cy, n=220, inner=0.22, width=0.35, density=0.7, seed_shift=0):
    """Manga focus lines radiating from (cx, cy); inner = clear radius as a fraction of the diagonal."""
    rng = np.random.default_rng(cv.rng.integers(1 << 30) + seed_shift)
    ang = (np.arctan2(cv.y - cy, cv.x - cx) / (2 * math.pi) + 0.5) * n
    k = np.floor(ang).astype(np.int32) % n
    f = ang - np.floor(ang)
    on = rng.uniform(0, 1, n) < density
    wid = rng.uniform(0.08, width, n)
    start = rng.uniform(inner, inner * 1.9, n) * math.hypot(cv.w, cv.h)
    dist = np.hypot(cv.x - cx, cv.y - cy)
    taper = np.clip((dist - start[k]) / (0.35 * math.hypot(cv.w, cv.h)), 0, 1)
    half = wid[k] * taper / 2
    m = smooth(half + 0.04, half - 0.04, np.abs(f - 0.5)) * on[k]
    return m * smooth(start[k], start[k] + 60, dist)


def stripes(cv, top, bottom, count, phase=0.0, min_gap=0.05, max_gap=0.45):
    """Horizontal cut-out bands that thicken towards `bottom` (classic sunset stripes)."""
    t = np.clip((cv.y - top) / (bottom - top), 0, 1)
    band = np.mod(t * count + phase, 1)
    gap = min_gap + (max_gap - min_gap) * t
    inside = (cv.y > top) & (cv.y < bottom)
    return smooth(gap + 0.03, gap - 0.03, band) * inside


def petal_poly(cx, cy, size, rot):
    """Sakura petal: a teardrop, wide at the outer end, with the little notch in its tip."""
    pts = []
    for i in range(40):
        t = i / 40 * 2 * math.pi
        x = math.cos(t) * size / 2
        y = math.sin(t) * size * 0.34 * (1 + 0.3 * math.cos(t))
        if math.cos(t) > 0.92:
            x -= (math.cos(t) - 0.92) * size * 2.2
        pts.append((cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)))
    return pts


def petals(cv, n, region, size=(18, 44), color=("sakura",), alpha=(0.55, 0.95), blur=0):
    """Drift of sakura petals inside region (x0, y0, x1, y1 as fractions); denser to the right."""
    layer = Image.new("RGBA", (cv.w, cv.h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = region
    for _ in range(n):
        x = (x0 + (x1 - x0) * cv.rng.uniform(0, 1) ** 0.6) * cv.w
        x = cv.w * (x1 + x0) - x if cv.rng.uniform() < 0.35 else x
        y = cv.rng.uniform(y0, y1) * cv.h
        col = C[cv.rng.choice(color)]
        a = cv.rng.uniform(*alpha)
        fill = tuple(int(c * 255) for c in col) + (int(a * 255),)
        d.polygon(petal_poly(x, y, cv.rng.uniform(*size), cv.rng.uniform(0, math.pi)), fill=fill)
    if blur:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
    arr = np.asarray(layer, np.float32) / 255
    cv.put(arr[..., :3], arr[..., 3])


def splatter(cv, cx, cy, spread, n, color, rmax=7):
    layer = Image.new("L", (cv.w, cv.h), 0)
    d = ImageDraw.Draw(layer)
    for _ in range(n):
        r = cv.rng.uniform(1, rmax) * cv.rng.uniform(0.3, 1) ** 2
        x = cx + cv.rng.normal(0, spread)
        y = cy + cv.rng.normal(0, spread * 0.6)
        d.ellipse((x - r, y - r, x + r, y + r), fill=255)
    cv.put(color, np.asarray(layer, np.float32) / 255)


def poly_mask(cv, polys, blur=0):
    layer = Image.new("L", (cv.w, cv.h), 0)
    d = ImageDraw.Draw(layer)
    for p in polys:
        d.polygon(p, fill=255)
    if blur:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(layer, np.float32) / 255


def line_mask(cv, lines, width, blur=0.6):
    layer = Image.new("L", (cv.w, cv.h), 0)
    d = ImageDraw.Draw(layer)
    for pts in lines:
        d.line(pts, fill=255, width=int(width), joint="curve")
    if blur:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(layer, np.float32) / 255


def vignette(cv, strength=0.45, color="ink"):
    d = np.hypot((cv.u - 0.55) * 1.2, cv.v - 0.5)
    cv.put(C[color], smooth(0.35, 0.95, d) * strength)


# ------------------------------------------------------------------ scenes
def dawn_a(cv):
    w, h = cv.w, cv.h
    cv.img = cv.gradient([(0, C["violet"]), (0.38, C["rose"]), (0.62, C["sakura"]), (0.74, C["peach"]), (1, C["peach"])])
    cx, cy, r = 0.68 * w, 0.66 * h, 0.17 * h
    glow = np.exp(-((np.hypot(cv.x - cx, cv.y - cy) / (0.55 * h)) ** 2))
    cv.put(C["peach"], glow * 0.55)
    sun, _ = disc(cv, cx, cy, r)
    cv.put(cv.gradient([(0, C["ember"]), (1, C["crimson"])], np.clip((cv.y - (cy - r)) / (2 * r), 0, 1)), sun)
    cv.put(C["peach"], sun * stripes(cv, cy + 0.15 * r, cy + r, 6, 0.3, 0.06, 0.5) * 0.85)
    cv.put(C["ink"], halftone(cv, smooth(0.42, 0.0, cv.v) * 0.55, 12) * 0.55)       # tone in the high sky
    cv.put(C["paper"], speed_lines(cv, cx, cy, 160, 0.12, 0.22, 0.45) * smooth(0.75, 0.3, cv.v) * 0.18)
    for base, hgt, col, rough in ((0.70, 0.13, "rose", 0.5), (0.78, 0.16, "line", 0.55), (0.90, 0.17, "ink", 0.6)):
        m, _ = ridge(cv, base, hgt, rough)
        cv.put(C[col], m)
        cv.put(C["peach"], m * halftone(cv, smooth(0.04, 0.0, (cv.v - base + hgt * 0.6)) * 0.4, 9) * 0.25)
    petals(cv, 70, (0.45, 0.05, 1.0, 0.8), (18, 40), ("sakura", "paper", "rose"))
    vignette(cv, 0.35, "violet")


def dawn_b(cv):
    w, h = cv.w, cv.h
    horizon = 0.62 * h
    cv.img = cv.gradient([(0, C["violet"]), (0.35, C["rose"]), (0.6, C["peach"]), (0.62, C["peach"]),
                          (0.63, C["sakura"]), (1, C["violet"])])
    cx, cy, r = 0.72 * w, horizon - 0.02 * h, 0.2 * h
    sun, _ = disc(cv, cx, cy, r)
    sun *= cv.y < horizon
    cv.put(cv.gradient([(0, C["ember"]), (1, C["crimson"])], np.clip((cv.y - (cy - r)) / r, 0, 1)), sun)
    cv.put(C["peach"], sun * stripes(cv, cy - 0.45 * r, horizon, 7, 0.2, 0.05, 0.55))
    # the sun's broken reflection on the lake
    rows = (cv.y > horizon) & (cv.y < horizon + 0.3 * h)
    wob = np.sin(cv.y * 0.9) * 18 + np.sin(cv.y * 0.23 + 1) * 30
    refl = smooth(r * 0.9, r * 0.5, np.abs(cv.x - cx + wob)) * rows
    refl *= np.mod(cv.y, 14) < (11 - (cv.y - horizon) / (0.3 * h) * 9)
    cv.put(C["ember"], refl * smooth(horizon + 0.3 * h, horizon, cv.y) * 0.9)
    cv.put(C["ink"], halftone(cv, smooth(horizon + 0.04 * h, h, cv.y) * 0.7, 11, 30) * 0.5)
    mist, _ = ridge(cv, 0.62, 0.07, 0.45, sharp=False)
    cv.put(C["line"], mist * (cv.y < horizon + 2) * 0.85)
    far, _ = ridge(cv, 0.62, 0.04, 0.5)
    cv.put(C["ink"], far * (cv.y < horizon + 2) * 0.6)
    # reeds, right edge
    reeds = []
    for _ in range(46):
        x = cv.rng.uniform(0.82, 1.0) * w
        top = cv.rng.uniform(0.62, 0.8) * h
        bend = cv.rng.uniform(-40, 40)
        reeds.append([(x, h), (x + bend * 0.4, (h + top) / 2), (x + bend, top)])
    cv.put(C["ink"], line_mask(cv, reeds, 4))
    if not LIVE:
        petals(cv, 70, (0.4, 0.05, 1.0, 0.6), (14, 32), ("sakura", "paper"))
    vignette(cv, 0.4, "violet")


def day_a(cv):
    w, h = cv.w, cv.h
    cv.img = np.broadcast_to(C["paper"], cv.img.shape).copy()
    cx, cy, r = 0.74 * w, 0.30 * h, 0.13 * h
    dist = np.hypot(cv.x - cx, cv.y - cy) / math.hypot(w, h)
    cv.put(C["ink"], halftone(cv, smooth(0.08, 0.75, dist) * 0.42 * smooth(0.95, 0.3, cv.v), 13) * 0.8)
    cv.put(C["ink"], speed_lines(cv, cx, cy, 300, 0.14, 0.3, 0.55) * smooth(0.12, 0.45, cv.u) * 0.85)
    ring, _ = disc(cv, cx, cy, r * 1.22)
    cv.put(C["paper"], ring)
    sun, _ = disc(cv, cx, cy, r)
    cv.put(C["crimson"], sun)
    # clouds: stacked rounded bumps with an ink outline, manga style
    for (bx, by, s) in ((0.52, 0.52, 1.0), (0.86, 0.6, 0.8), (0.30, 0.66, 0.7)):
        polys = []
        for i in range(7):
            ex = (bx + (i - 3) * 0.035 * s) * w
            ey = by * h - abs(i - 3) * -6 - (cv.rng.uniform(0, 1) * 30 * s if 1 < i < 5 else 0)
            rr = (0.045 + 0.02 * (3 - abs(i - 3)) / 3) * h * s
            polys.append([(ex + rr * math.cos(t / 20 * 2 * math.pi), ey + rr * math.sin(t / 20 * 2 * math.pi)) for t in range(20)])
        m = poly_mask(cv, polys)
        outline = np.clip(poly_mask(cv, polys, 3) * 1.0 - m, 0, 1) * 3
        cv.put(C["ink"], np.clip(outline, 0, 1))
        cv.put(C["paper"], m)
        cv.put(C["mist"], m * halftone(cv, smooth(by * h - 20, by * h + 0.05 * h, cv.y) * 0.5, 8) * 0.9)
    m, _ = ridge(cv, 0.97, 0.18, 0.6)
    cv.put(C["ink"], m)
    m2, _ = ridge(cv, 1.02, 0.12, 0.6)
    cv.put(C["blood"], m2 * 0.9)
    petals(cv, 60, (0.45, 0.1, 1.0, 0.9), (16, 36), ("crimson", "sakura"))


def day_b(cv):
    w, h = cv.w, cv.h
    cv.img = cv.gradient([(0, C["paper"]), (1, C["mist"])])
    cx, cy, r = 0.66 * w, 0.46 * h, 0.30 * h
    shadow, _ = disc(cv, cx + 22, cy + 26, r, 30)
    cv.put(C["ink"], shadow * 0.25)
    sun, _ = disc(cv, cx, cy, r)
    cv.put(C["crimson"], sun)
    cv.put(C["blood"], sun * halftone(cv, smooth(cy - r * 0.2, cy + r, cv.y) * 0.6, 12) * 0.85)
    # one big diagonal ink brush stroke: pressed hard at the start, ragged edges, dry bristles at the tail
    p0, p1 = np.array([0.34 * w, 0.84 * h]), np.array([0.97 * w, 0.20 * h])
    d = p1 - p0
    length = float(np.hypot(*d))
    tx, ty = d / length
    rel_x, rel_y = cv.x - p0[0], cv.y - p0[1]
    along = (rel_x * tx + rel_y * ty) / length                 # 0 … 1 along the stroke
    across = -rel_x * ty + rel_y * tx                           # px from the centre line
    bend = np.sin(along * 3.2) * 0.012 * h
    edge = fbm1d(cv.rng, 512, 6, 0.6)
    rag = np.interp(np.clip(along, 0, 1) * 511, np.arange(512), edge)
    thick = 0.06 * h * np.clip(along * 9, 0, 1) ** 0.5 * (1 - np.clip(along, 0, 1) ** 2.2) * (1 + 0.18 * rag)
    body = smooth(thick + 2, thick - 2, np.abs(across - bend)) * (along > 0) * (along < 1)
    bristle = np.interp((across - bend) % 2048, np.arange(2048), cv.rng.uniform(0, 1, 2048))
    bristle = np.asarray(Image.fromarray((bristle * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255
    dry = smooth(0.35, 0.95, np.clip(along, 0, 1)) * 0.9
    cv.put(C["ink"], body * (bristle > dry))
    splatter(cv, 0.95 * w, 0.28 * h, 90, 120, C["ink"], 9)
    splatter(cv, 0.40 * w, 0.78 * h, 50, 40, C["crimson"], 6)
    cv.put(C["ink"], halftone(cv, smooth(0.6, 1.0, cv.v) * 0.35, 10) * 0.6)
    if not LIVE:
        petals(cv, 50, (0.5, 0.05, 1.0, 0.9), (20, 44), ("crimson", "sakura", "ink"))
    vignette(cv, 0.25, "line")


def dusk_a(cv):
    w, h = cv.w, cv.h
    horizon = 0.64 * h
    cv.img = cv.gradient([(0, C["ink"]), (0.25, C["blood"]), (0.5, C["crimson"]), (0.63, C["ember"]),
                          (0.64, C["blood"]), (1, C["ink"])])
    cx, cy, r = 0.64 * w, horizon, 0.24 * h
    glow = np.exp(-((np.hypot(cv.x - cx, cv.y - cy) / (0.5 * h)) ** 2)) * (cv.y < horizon)
    cv.put(C["gold"], glow * 0.35)
    sun, _ = disc(cv, cx, cy, r)
    sun *= cv.y < horizon
    cv.put(cv.gradient([(0, C["gold"]), (1, C["ember"])], np.clip((cv.y - (cy - r)) / r, 0, 1)), sun)
    cv.put(C["crimson"], sun * stripes(cv, cy - 0.55 * r, horizon, 8, 0.1, 0.04, 0.6))
    cv.put(C["ink"], halftone(cv, smooth(0.45, 0.0, cv.v) * 0.6, 12) * 0.5)
    # sea: glittering broken bands, the sun's path
    sea = cv.y > horizon
    path = smooth(r * 1.4, r * 0.2, np.abs(cv.x - cx + np.sin(cv.y * 0.5) * 20)) * sea
    bands = np.mod(cv.y + np.sin(cv.x * 0.01) * 4, 10 + np.maximum(cv.y - horizon, 0) * 0.05) < 3
    cv.put(C["gold"], path * bands * smooth(h, horizon, cv.y))
    # torii in the water, right of the sun
    tx, base, tw, th = 0.82 * w, horizon + 0.12 * h, 0.12 * w, 0.26 * h
    post = 0.012 * w
    polys = [
        [(tx - tw * 0.36, base), (tx - tw * 0.36 + post, base), (tx - tw * 0.33 + post, base - th), (tx - tw * 0.33, base - th)],
        [(tx + tw * 0.36, base), (tx + tw * 0.36 - post, base), (tx + tw * 0.33 - post, base - th), (tx + tw * 0.33, base - th)],
        [(tx - tw * 0.48, base - th * 0.98), (tx + tw * 0.48, base - th * 0.98), (tx + tw * 0.56, base - th * 1.1),
         (tx - tw * 0.56, base - th * 1.1)],
        [(tx - tw * 0.42, base - th * 0.8), (tx + tw * 0.42, base - th * 0.8), (tx + tw * 0.42, base - th * 0.74),
         (tx - tw * 0.42, base - th * 0.74)],
        [(tx - post / 2, base - th * 0.98), (tx + post / 2, base - th * 0.98), (tx + post / 2, base - th * 0.8), (tx - post / 2, base - th * 0.8)],
    ]
    torii = poly_mask(cv, polys)
    cv.put(C["ink"], torii)
    refl = np.flipud(torii)
    shift = int(2 * base - h)
    refl = np.roll(refl, shift, axis=0) * (cv.y > base)
    cv.put(C["ink"], refl * (np.mod(cv.y, 7) < 4) * 0.55)
    # crows
    crows = []
    for _ in range(9):
        x, y, s = cv.rng.uniform(0.45, 0.95) * w, cv.rng.uniform(0.12, 0.38) * h, cv.rng.uniform(10, 22)
        crows.append([(x - s, y - s * 0.3), (x - s * 0.4, y - s * 0.05), (x, y + s * 0.15), (x + s * 0.4, y - s * 0.05), (x + s, y - s * 0.35)])
    if not LIVE:
        cv.put(C["ink"], line_mask(cv, crows, 4))
    vignette(cv, 0.45)


def dusk_b(cv):
    w, h = cv.w, cv.h
    cv.img = cv.gradient([(0, C["violet"]), (0.3, C["blood"]), (0.58, C["crimson"]), (0.72, C["ember"]), (0.8, C["gold"]), (1, C["gold"])])
    cx, cy, r = 0.60 * w, 0.72 * h, 0.15 * h
    sun, _ = disc(cv, cx, cy, r)
    cv.put(C["peach"], sun)
    cv.put(C["ember"], sun * stripes(cv, cy - 0.3 * r, cy + r, 6, 0.1, 0.05, 0.5))
    cv.put(C["ink"], halftone(cv, smooth(0.55, 0.0, cv.v) * 0.65, 12) * 0.45)
    # skyline: three depths of blocks; the nearest has lit windows
    for depth, (col, base, hmin, hmax, wmin, wmax) in enumerate((
            ("line", 0.84, 0.10, 0.22, 0.03, 0.07), ("violet", 0.9, 0.12, 0.3, 0.035, 0.08), ("ink", 1.0, 0.14, 0.42, 0.04, 0.1))):
        x = -10.0
        polys, wins = [], []
        while x < w:
            bw = cv.rng.uniform(wmin, wmax) * w
            bh = cv.rng.uniform(hmin, hmax) * h * (1.0 if x > 0.45 * w else 0.55)   # low on the left (widgets)
            top = base * h - bh
            polys.append([(x, h), (x, top), (x + bw, top), (x + bw, h)])
            if cv.rng.uniform() < 0.25:
                ax = x + bw * cv.rng.uniform(0.3, 0.7)
                polys.append([(ax - 2, top), (ax - 2, top - 0.05 * h), (ax + 2, top - 0.05 * h), (ax + 2, top)])
            if depth == 2:
                for wy in np.arange(top + 14, h - 10, 22):
                    for wx in np.arange(x + 10, x + bw - 14, 18):
                        if cv.rng.uniform() < 0.18:
                            wins.append([(wx, wy), (wx + 7, wy), (wx + 7, wy + 10), (wx, wy + 10)])
            x += bw + cv.rng.uniform(-4, 6)
        cv.put(C[col], poly_mask(cv, polys))
        if wins:
            cv.put(C["gold"], poly_mask(cv, wins) * 0.9)
    # utility pole + sagging wires, right side
    px = 0.88 * w
    pole = [[(px - 9, h), (px - 6, 0.18 * h), (px + 6, 0.18 * h), (px + 9, h)],
            [(px - 70, 0.24 * h), (px + 70, 0.24 * h), (px + 70, 0.245 * h + 6), (px - 70, 0.245 * h + 6)],
            [(px - 50, 0.31 * h), (px + 50, 0.31 * h), (px + 50, 0.31 * h + 6), (px - 50, 0.31 * h + 6)]]
    cv.put(C["ink"], poly_mask(cv, pole))
    wires = []
    for k, (y0, sag) in enumerate(((0.245, 0.10), (0.25, 0.14), (0.315, 0.12), (0.32, 0.17))):
        side = px + (-60 if k % 2 == 0 else 60)
        pts = []
        for t in np.linspace(0, 1, 60):
            x = side + (-0.1 * w - side) * t
            pts.append((x, y0 * h + sag * h * 4 * t * (1 - t) * 0.6 + t * 0.06 * h))
        wires.append(pts)
        pts2 = []
        for t in np.linspace(0, 1, 30):
            x = side + (w + 40 - side) * t
            pts2.append((x, y0 * h + sag * h * 4 * t * (1 - t) * 0.25))
        wires.append(pts2)
    cv.put(C["ink"], line_mask(cv, wires, 3))
    vignette(cv, 0.4, "violet")


def night_a(cv):
    w, h = cv.w, cv.h
    cv.img = cv.gradient([(0, C["ink"]), (0.55, C["violet"]), (0.85, C["night"]), (1, C["ink"])])
    cx, cy, r = 0.70 * w, 0.34 * h, 0.16 * h
    halo = np.exp(-((np.hypot(cv.x - cx, cv.y - cy) / (0.42 * h)) ** 2))
    cv.put(C["crimson"], halo * 0.30)
    stars = (cv.rng.uniform(0, 1, (h, w)) > 0.9993).astype(np.float32)
    stars = np.asarray(Image.fromarray((stars * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)), np.float32) / 255
    cv.put(C["paper"], stars * smooth(0.8, 0.2, cv.v) * 0.7)
    cv.put(C["mist"], halftone(cv, smooth(0.9, 0.2, cv.v) * 0.12 * (1 - halo), 14) * 0.22)
    moon, _ = disc(cv, cx, cy, r)
    cv.put(C["paper"], moon)
    crater = np.zeros_like(cv.u)
    for _ in range(14):
        a, rr = cv.rng.uniform(0, 2 * math.pi), cv.rng.uniform(0, 0.8) * r
        m, _ = disc(cv, cx + math.cos(a) * rr, cy + math.sin(a) * rr, cv.rng.uniform(0.04, 0.16) * r, 4)
        crater = np.maximum(crater, m)
    cv.put(C["mist"], crater * moon * halftone(cv, np.full_like(cv.u, 0.5), 7) * 0.8)
    rim, _ = disc(cv, cx, cy, r * 1.04)
    cv.put(C["ember"], np.clip(rim - moon, 0, 1))
    # sakura branch from the top-right corner
    branches = []

    def grow(x, y, ang, length, width, depth):
        if depth == 0 or length < 18:
            return
        pts = [(x, y)]
        for _ in range(6):
            ang += cv.rng.normal(0, 0.18)
            ang = min(ang, math.pi * 1.02) if ang > math.pi * 0.5 else ang   # never droop towards the widgets
            x += math.cos(ang) * length / 6
            y += math.sin(ang) * length / 6
            pts.append((x, y))
        branches.append((pts, width))
        blossoms.extend(pts[2::2] if depth < 4 else [])      # clusters along the thinner twigs too
        for _ in range(2 if depth > 2 else 3):
            grow(x, y, ang + cv.rng.uniform(-0.7, 0.7), length * cv.rng.uniform(0.5, 0.72), max(2, width * 0.62), depth - 1)
        blossoms.append((x, y))

    blossoms = []
    grow(w + 20, 0.04 * h, math.pi * 0.93, 0.34 * w, 34, 7)
    for pts, wd in branches:
        cv.put(C["ink"], line_mask(cv, [pts], wd, 0.8))
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for (x, y) in blossoms:
        if x < 0.2 * w or y > 0.6 * h:
            continue
        for _ in range(int(cv.rng.integers(3, 7))):
            bx, by = x + cv.rng.normal(0, 30), y + cv.rng.normal(0, 20)
            s = cv.rng.uniform(13, 22)
            col = tuple(int(c * 255) for c in C[cv.rng.choice(["sakura", "sakura", "paper", "rose"])]) + (240,)
            rot = cv.rng.uniform(0, 2 * math.pi)
            for k in range(5):
                a = rot + k * 2 * math.pi / 5
                d.polygon(petal_poly(bx + math.cos(a) * s * 0.55, by + math.sin(a) * s * 0.55, s * 0.62, a + math.pi / 2), fill=col)
            d.ellipse((bx - 2.5, by - 2.5, bx + 2.5, by + 2.5), fill=(225, 29, 46, 255))
    arr = np.asarray(layer, np.float32) / 255
    cv.put(arr[..., :3], arr[..., 3])
    m, _ = ridge(cv, 0.96, 0.12, 0.6)
    cv.put(C["ink"], m)
    if not LIVE:
        petals(cv, 80, (0.5, 0.1, 1.0, 0.95), (14, 30), ("sakura", "paper", "rose"), (0.35, 0.9))
    vignette(cv, 0.5)


def night_b(cv):
    w, h = cv.w, cv.h
    cv.img = cv.gradient([(0, C["ink"]), (0.6, C["night"]), (1, C["ink"])])
    cx, cy, r = 0.68 * w, 0.40 * h, 0.21 * h
    cv.put(C["blood"], speed_lines(cv, cx, cy, 260, 0.14, 0.32, 0.6) * 0.75)
    halo = np.exp(-((np.hypot(cv.x - cx, cv.y - cy) / (0.36 * h)) ** 2))
    cv.put(C["crimson"], halo * 0.45)
    moon, _ = disc(cv, cx, cy, r)
    cv.put(cv.gradient([(0, C["ember"]), (1, C["blood"])], np.clip((cv.y - (cy - r)) / (2 * r), 0, 1)), moon)
    cv.put(C["ink"], moon * halftone(cv, smooth(cx - r * 0.2, cx + r, cv.x) * 0.55, 10, 15) * 0.7)
    for base, hgt, col, a in ((0.80, 0.16, "blood", 0.55), (0.88, 0.18, "night", 1.0), (0.97, 0.15, "ink", 1.0)):
        m, line = ridge(cv, base, hgt, 0.6)
        cv.put(C[col], m * a)
        mist = smooth(0.06 * h, 0, np.abs(cv.y - line - 0.04 * h)) * (cv.y > line)
        cv.put(C["rose"], mist * halftone(cv, np.full_like(cv.u, 0.35), 9) * 0.25)
    splatter(cv, 0.86 * w, 0.18 * h, 110, 160, C["crimson"], 6)
    vignette(cv, 0.55)


SCENES = {"dawn-a": dawn_a, "dawn-b": dawn_b, "day-a": day_a, "day-b": day_b,
          "dusk-a": dusk_a, "dusk-b": dusk_b, "night-a": night_a, "night-b": night_b}


def main():
    args = sys.argv[1:]
    size = (2560, 1600)
    only = None
    if "--size" in args:
        i = args.index("--size")
        size = tuple(int(v) for v in args[i + 1].split("x"))
        del args[i:i + 2]
    if "--only" in args:
        i = args.index("--only")
        only = set(args[i + 1].split(","))
        del args[i:i + 2]
    out = os.path.expanduser(args[0] if args else "~/.local/share/backgrounds/bapirlo/originals")
    os.makedirs(out, exist_ok=True)
    for i, (name, fn) in enumerate(SCENES.items()):
        if only and name not in only:
            continue
        cv = Canvas(*size, seed=1000 + i)
        fn(cv)
        path = os.path.join(out, f"{name}.jpg")
        cv.save(path)
        print(path, flush=True)


if __name__ == "__main__":
    main()
