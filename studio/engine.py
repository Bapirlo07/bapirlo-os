"""Bapirlo OS Theme Studio — colour engine (no GTK, no root; imported by the app, the CLI and the
root helpers).

  palette_from_image(img, …)  matugen (through bapirlo-autotheme, never called twice) → a full
                              Kuro-shaped palette: same roles, same darkness, new hue, contrast-checked
  Transform(palette)          maps ANY colour of the original Kuro theme to the new palette:
                              every colour is moved like its nearest Kuro "anchor" (crimson, ember,
                              blood, sakura, rose …) in OKLCH — so the 1 300 hard-coded shades in the
                              theme files keep their relationships. Greys keep their lightness and
                              only take on the new tint, so the base stays exactly as dark.
  remap_text(text, kind, T)   rewrites colour literals in CSS / SVG / JSON / INI / dconf / ANSI text
  remap_png(src, dst, T)      the same for theme bitmaps (GTK checkboxes, Plymouth glyphs …)
  contrast(a, b)              WCAG 2 contrast ratio
"""
import colorsys
import functools
import importlib.machinery
import json
import math
import os
import re

HERE = os.path.dirname(os.path.realpath(__file__))
OS_DIR = os.path.dirname(HERE)

# ----------------------------------------------------------------------------- the Kuro original
# Every value the theme files were built from (tools/palette.py + the extra shades the scripts use).
KURO = {
    "ink": "#0E0A0D", "night": "#161015", "surface": "#231A1F", "line": "#523B44",
    "muted": "#8E7680", "mist": "#CAB5BF", "paper": "#F2E9EC",
    "crimson": "#E11D2E", "ember": "#FF4655", "blood": "#7A0F1A",
    "sakura": "#F08AA4", "sakura_bright": "#FFB3C6", "rose": "#AE7788",
    "accent2": "#F08AA4", "accent2_bright": "#FFB3C6", "accent3": "#6FC7C2", "accent3_bright": "#9EE6E1",
    "steel": "#7C9CFF", "jade": "#3FC69A", "amber": "#F2B45A",
}
ACCENT_ANCHORS = ("crimson", "ember", "blood")
ACCENT2_ANCHORS = ("sakura", "sakura_bright", "rose")
# colours that mean something (info / success / warning) and the terminal's red slot keep their hue
FIXED = ("steel", "jade", "amber")
NEUTRAL_C = 0.045        # OKLCH chroma below this = a grey of the base
GREY_C = 0.004           # true greys (white, black, #afafaf …) stay untouched
ANCHOR_REACH = 0.16      # an accent-ish colour further than this from every anchor is left alone

# WCAG AA targets the generated palette must meet (the original Kuro values meet them too)
AA_TEXT, AA_UI = 4.5, 3.0


# ----------------------------------------------------------------------------- colour maths
def hex_rgb(h):
    h = h.lstrip("#")
    if len(h) in (3, 4):
        h = "".join(c * 2 for c in h[:3])
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def rgb_hex(rgb, upper=True):
    s = "#{:02x}{:02x}{:02x}".format(*(round(max(0.0, min(1.0, c)) * 255) for c in rgb))
    return s.upper() if upper else s


def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _gam(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def rgb_oklab(rgb):
    r, g, b = (_lin(c) for c in rgb)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = (math.copysign(abs(x) ** (1 / 3), x) for x in (l, m, s))
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def oklab_rgb(lab):
    L, a, b = lab
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (_gam(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            _gam(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            _gam(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))


def rgb_lch(rgb):
    L, a, b = rgb_oklab(rgb)
    return L, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360


def lch_rgb(L, C, h):
    """OKLCH → sRGB, reducing chroma until it fits the gamut (hue and lightness are kept)."""
    L = max(0.0, min(1.0, L))
    hr = math.radians(h)

    def at(c):
        return oklab_rgb((L, c * math.cos(hr), c * math.sin(hr)))

    rgb = at(C)
    if all(-1e-4 <= x <= 1 + 1e-4 for x in rgb):
        return tuple(max(0.0, min(1.0, x)) for x in rgb)
    lo, hi = 0.0, C
    for _ in range(22):
        mid = (lo + hi) / 2
        if all(-1e-4 <= x <= 1 + 1e-4 for x in at(mid)):
            lo = mid
        else:
            hi = mid
    return tuple(max(0.0, min(1.0, x)) for x in at(lo))


def luminance(rgb):
    r, g, b = (_lin(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    """WCAG 2 contrast ratio; a / b are hex strings or rgb tuples (0..1)."""
    ya = luminance(hex_rgb(a) if isinstance(a, str) else a)
    yb = luminance(hex_rgb(b) if isinstance(b, str) else b)
    hi, lo = max(ya, yb), min(ya, yb)
    return (hi + 0.05) / (lo + 0.05)


def hue_delta(a, b):
    return (b - a + 180) % 360 - 180


# ----------------------------------------------------------------------------- palette from an image
def _autotheme():
    path = os.path.join(OS_DIR, "bin", "bapirlo-autotheme")
    return importlib.machinery.SourceFileLoader("bapirlo_autotheme", path).load_module()


@functools.lru_cache(maxsize=16)
def scheme(img, mtime=None):
    """matugen's dark scheme for an image (cached per path + mtime)."""
    return _autotheme().matugen_scheme(img)


def candidates(img):
    """A few accent choices the wallpaper suggests (hex), best first, duplicates removed."""
    s = scheme(img, os.path.getmtime(img))
    c, t = s["colors"], s["tones"]
    raw = [c.get("source_color"), t.get("primary", {}).get("50"), t.get("tertiary", {}).get("50"),
           t.get("secondary", {}).get("50"), c.get("tertiary"), c.get("primary")]
    out = []
    for h in raw:
        if not h:
            continue
        L, C, hh = rgb_lch(hex_rgb(h))
        if C < 0.03:
            continue
        if all(abs(hue_delta(hh, rgb_lch(hex_rgb(o))[2])) > 14 for o in out):
            out.append(h.upper())
    return out[:5] or ["#E11D2E"]


def _solve_L(h, C, L0, ok, lo=0.30, hi=0.92):
    """Lightness closest to L0 (in steps of 0.005) at which ok(rgb) holds; None if none does."""
    for step in range(0, 130):
        for L in (L0 - step * 0.005, L0 + step * 0.005):
            if lo <= L <= hi:
                rgb = lch_rgb(L, C, h)
                if ok(rgb):
                    return L, rgb
    return None


def build_palette(accent, accent2=None, accent3=None, vivid=1.0, tint=1.0, neutral_hue=None):
    """Kuro-shaped palette around a main accent colour.

    accent      the colour that plays crimson's role (hex)
    accent2/3   second / third accents (hex) — default: picked from the accent's hue family
    vivid       accent chroma multiplier (0.6 calm … 1.4 loud)
    tint        how much the greys lean towards the accent hue (0 = neutral grey, 1 = like Kuro)
    Returns {"roles": {name: hex}, "checks": [(label, ratio, target, ok)], "params": {...}}.
    """
    k = {n: rgb_lch(hex_rgb(v)) for n, v in KURO.items()}
    aL, aC, ah = rgb_lch(hex_rgb(accent))
    mono = aC < 0.03                     # a grey accent = a monochrome theme (a grey has no real hue)
    # vivid like Kuro's crimson unless the wallpaper is very muted; never neon
    C = 0.0 if mono else max(0.11, min(0.26, max(aC, 0.16) * 1.18 * vivid))
    white, ink, night = (1.0, 1.0, 1.0), hex_rgb(KURO["ink"]), hex_rgb(KURO["night"])

    # crimson role: white labels on it ≥ 4.5, and it stands out from the base ≥ 3
    sol = (_solve_L(ah, C, k["crimson"][0], lambda c: contrast(white, c) >= AA_TEXT and contrast(c, ink) >= AA_UI)
           or _solve_L(ah, C, k["crimson"][0], lambda c: contrast(white, c) >= AA_TEXT))
    cL, crimson = sol
    cC = rgb_lch(crimson)[1]
    # ember role (accent used as TEXT on the dark base): ≥ 4.5 on ink and night
    eL, ember = _solve_L(ah, C, cL + (k["ember"][0] - k["crimson"][0]),
                         lambda c: contrast(c, night) >= AA_TEXT and contrast(c, ink) >= AA_TEXT)
    blood = lch_rgb(k["blood"][0], cC * k["blood"][1] / k["crimson"][1], ah)

    # second accent: matugen's tertiary hue by default, sakura's lightness, readable as text
    if accent2:
        s2h, s2C = rgb_lch(hex_rgb(accent2))[2], max(0.08, rgb_lch(hex_rgb(accent2))[1])
    else:
        s2h, s2C = (ah + 330) % 360, 0.12
    s2C = 0.02 if mono and not accent2 else min(0.16, s2C * vivid)
    _, sakura = _solve_L(s2h, s2C, k["sakura"][0], lambda c: contrast(c, night) >= AA_TEXT)
    sak_b = lch_rgb(k["sakura_bright"][0], s2C * 0.72, s2h)
    rose = lch_rgb(k["rose"][0], s2C * k["rose"][1] / k["sakura"][1], s2h)
    if accent3:
        t3h, t3C = rgb_lch(hex_rgb(accent3))[2], max(0.07, min(0.13, rgb_lch(hex_rgb(accent3))[1]))
    else:
        t3h, t3C = (ah + 150) % 360, 0.10
    _, a3 = _solve_L(t3h, t3C, k["accent3"][0], lambda c: contrast(c, night) >= AA_TEXT)
    a3b = lch_rgb(k["accent3_bright"][0], t3C * 0.8, t3h)

    # greys: Kuro lightness exactly, tinted with the accent hue (or the given neutral hue)
    nh = ah if neutral_hue is None else neutral_hue
    if mono and neutral_hue is None:
        tint = 0.0
    roles = {}
    for n in ("ink", "night", "surface", "line", "muted", "mist", "paper"):
        L, C0, _h = k[n]
        roles[n] = rgb_hex(lch_rgb(L, C0 * tint, nh))
    roles.update(crimson=rgb_hex(crimson), ember=rgb_hex(ember), blood=rgb_hex(blood),
                 sakura=rgb_hex(sakura), sakura_bright=rgb_hex(sak_b), rose=rgb_hex(rose),
                 accent2=rgb_hex(sakura), accent2_bright=rgb_hex(sak_b), accent3=rgb_hex(a3),
                 accent3_bright=rgb_hex(a3b), steel=KURO["steel"], jade=KURO["jade"], amber=KURO["amber"])
    return {"roles": roles, "checks": checks(roles),
            "params": {"accent": accent.upper(), "accent2": accent2, "accent3": accent3,
                       "vivid": vivid, "tint": tint, "neutral_hue": neutral_hue}}


def checks(r):
    """The contrast pairs that matter in Bapirlo OS, with their WCAG AA target."""
    pairs = [("Text on the base", r["paper"], r["ink"], AA_TEXT),
             ("Text on panels", r["paper"], r["night"], AA_TEXT),
             ("Text on raised cards", r["paper"], r["surface"], AA_TEXT),
             ("Secondary text on panels", r["muted"], r["night"], AA_TEXT),
             ("White label on the accent", "#FFFFFF", r["crimson"], AA_TEXT),
             ("Accent text on panels", r["ember"], r["night"], AA_TEXT),
             ("Second accent text on panels", r["sakura"], r["night"], AA_TEXT),
             ("Accent controls on the base", r["crimson"], r["ink"], AA_UI)]
    return [(label, round(contrast(a, b), 2), t, contrast(a, b) >= t) for label, a, b, t in pairs]


def palette_from_image(img, accent=None, **kw):
    """Palette for a wallpaper: its first candidate accent unless one is given."""
    c = candidates(img)
    s = scheme(img, os.path.getmtime(img))["colors"]
    p = build_palette(accent or c[0], accent2=kw.pop("accent2", None) or s.get("tertiary"),
                      accent3=kw.pop("accent3", None) or s.get("secondary"), **kw)
    p["candidates"] = c
    return p


# ----------------------------------------------------------------------------- the transform
class Transform:
    """Kuro colour → new palette colour. Identity when roles == KURO."""

    def __init__(self, roles):
        self.roles = dict(roles)
        self.identity = all(self.roles.get(k, v).upper() == v.upper() for k, v in KURO.items())
        self._src = {n: rgb_lch(hex_rgb(KURO[n])) for n in KURO}
        self._dst = {n: rgb_lch(hex_rgb(self.roles.get(n, KURO[n]))) for n in KURO}
        self._lab = {n: rgb_oklab(hex_rgb(KURO[n])) for n in ACCENT_ANCHORS + ACCENT2_ANCHORS + FIXED}
        # the neutral family: Kuro greys lean ~345°; new greys use the new tint (avg of the roles)
        src_n = [self._src[n] for n in ("night", "surface", "line", "muted", "mist")]
        dst_n = [self._dst[n] for n in ("night", "surface", "line", "muted", "mist")]
        self._n_ratio = (sum(d[1] for d in dst_n) / max(1e-6, sum(s[1] for s in src_n)))
        self._n_hue = math.degrees(math.atan2(sum(math.sin(math.radians(d[2])) * d[1] for d in dst_n),
                                              sum(math.cos(math.radians(d[2])) * d[1] for d in dst_n))) % 360
        self._cache = {}

    def rgb(self, rgb):
        """(r, g, b) floats 0..1 → mapped (r, g, b)."""
        if self.identity:
            return rgb
        key = tuple(round(c * 255) for c in rgb)
        hit = self._cache.get(key)
        if hit is not None:
            return hit
        out = self._map(rgb)
        self._cache[key] = out
        return out

    def _map(self, rgb):
        L, C, h = rgb_lch(rgb)
        if C < GREY_C:
            return rgb
        if C < NEUTRAL_C:                                  # a grey of the base: keep L, new tint
            return lch_rgb(L, C * self._n_ratio, self._n_hue)
        lab = rgb_oklab(rgb)
        best, dist = None, 9.0
        for n, al in self._lab.items():
            d = math.dist(lab, al)
            if d < dist:
                best, dist = n, d
        if best is None or best in FIXED or dist > ANCHOR_REACH:
            return rgb
        s, d = self._src[best], self._dst[best]
        return lch_rgb(L + (d[0] - s[0]), C * d[1] / max(1e-6, s[1]), h + hue_delta(s[2], d[2]))

    def hex(self, h):
        return rgb_hex(self.rgb(hex_rgb(h)), upper=any(c.isupper() for c in h))


# ----------------------------------------------------------------------------- text remapping
_HEX = re.compile(r"(?<![\w&])#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})(?![0-9a-zA-Z_-])")
_RGB = re.compile(r"\brgba?\(\s*(\d{1,3}(?:\.\d+)?%?)\s*[, ]\s*(\d{1,3}(?:\.\d+)?%?)\s*[, ]\s*(\d{1,3}(?:\.\d+)?%?)"
                  r"(\s*[,/]\s*[\d.]+%?)?\s*\)")
_ANSI = re.compile(r"\b([34]8;2;)(\d{1,3});(\d{1,3});(\d{1,3})\b")
_TUPLE = re.compile(r"\((\d(?:\.\d+)?(?:e-?\d+)?), ?(\d(?:\.\d+)?(?:e-?\d+)?), ?(\d(?:\.\d+)?(?:e-?\d+)?)(, ?\d(?:\.\d+)?(?:e-?\d+)?)?\)")
_INI = re.compile(r"^(\s*[\w-]+\s*=\s*)([0-9A-Fa-f]{6})(\s*(?:;.*)?)$", re.M)
_PLY = re.compile(r"(Image\.Text\([^,]+,\s*)([\d.]+),\s*([\d.]+),\s*([\d.]+)")


def _short_ok(m, text):
    """#RGB / #RGBA only count as colours in a value position (never a CSS #id like #face)."""
    if len(m.group(1)) not in (3, 4):
        return True
    before = text[max(0, m.start() - 12):m.start()].rstrip()
    after = text[m.end():m.end() + 1]
    return before.endswith((":", ",", "(", "=", "'", '"')) or after in (";", ",", ")", "'", '"')


def remap_text(text, T, kind="css"):
    """Rewrite colour literals. kind: css (also svg/js/toml/json/kvconfig), ini (bare RRGGBB values),
    dconf (also float tuples), ansi, plymouth."""
    if T.identity:
        return text

    def hexsub(m):
        if not _short_ok(m, text):
            return m.group(0)
        v = m.group(1)
        alpha = v[6:] if len(v) == 8 else (v[3:] * 2 if len(v) == 4 else "")
        rgb = v[:6] if len(v) >= 6 else v[:3]
        out = rgb_hex(T.rgb(hex_rgb(rgb)), upper=any(c.isupper() for c in v))
        return out + alpha

    def rgbsub(m):
        def ch(x):
            return float(x[:-1]) / 100 if x.endswith("%") else float(x) / 255
        r, g, b = T.rgb((ch(m.group(1)), ch(m.group(2)), ch(m.group(3))))
        whole = m.group(0)
        head = whole[:whole.index("(")]
        sep = ", " if ", " in whole else ("," if "," in whole else " ")
        vals = sep.join(str(round(c * 255)) for c in (r, g, b))
        return f"{head}({vals}{m.group(4) or ''})"

    out = _HEX.sub(hexsub, text)
    out = _RGB.sub(rgbsub, out)
    if kind in ("ansi", "css", "dconf"):
        out = _ANSI.sub(lambda m: m.group(1) + ";".join(str(round(c * 255)) for c in
                                                          T.rgb(tuple(int(x) / 255 for x in m.groups()[1:]))), out)
    if kind == "ini":
        out = _INI.sub(lambda m: m.group(1) + rgb_hex(T.rgb(hex_rgb(m.group(2))), upper=m.group(2).isupper()).lstrip("#")
                       + m.group(3), out)
    if kind == "dconf":
        def tup(m):
            vals = [float(x) for x in m.groups()[:3]]
            if not all(0 <= v <= 1 for v in vals):
                return m.group(0)
            r, g, b = T.rgb(tuple(vals))
            return f"({r:.3f}, {g:.3f}, {b:.3f}{m.group(4) or ''})"
        out = _TUPLE.sub(tup, out)
    if kind == "plymouth":
        out = _PLY.sub(lambda m: m.group(1) + ", ".join(f"{c:.3f}" for c in
                                                         T.rgb(tuple(float(x) for x in m.groups()[1:]))), out)
    return out


def remap_png(src, dst, T):
    """Recolour a bitmap pixel by pixel through T (alpha kept). Small theme assets: < 50 ms each."""
    from PIL import Image
    import numpy as np
    im = Image.open(src)
    mode = im.mode
    im = im.convert("RGBA")
    a = np.asarray(im).copy()
    rgb = a[..., :3].reshape(-1, 3)
    uniq, inv = np.unique(rgb, axis=0, return_inverse=True)
    mapped = np.array([[round(c * 255) for c in T.rgb(tuple(int(v) / 255 for v in u))] for u in uniq],
                      dtype=np.uint8)
    a[..., :3] = mapped[inv.reshape(-1)].reshape(a.shape[0], a.shape[1], 3)
    out = Image.fromarray(a, "RGBA")
    if mode in ("RGB", "P", "L"):
        out = out.convert("RGB") if mode != "L" else out
    out.save(dst)


def kind_for(path):
    p = path.lower()
    if p.endswith(".ini"):
        return "ini"
    if p.endswith(".ans"):
        return "ansi"
    if p.endswith(".script"):
        return "plymouth"
    return "css"


# ----------------------------------------------------------------------------- override stylesheets
_COMMENT = re.compile(r"/\*.*?\*/", re.S)


def css_override(text, T, prefix="StWidget"):
    """Only the colour declarations a palette changes, with selectors made one element more
    specific ("StWidget .x" — every shell actor sits inside one), so they win over the original rule
    whatever order St loaded the stylesheets in —
    and never over a more specific rule of the theme."""
    out = []
    body = _COMMENT.sub("", text)
    for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", body):
        sels, decls = m.group(1).strip(), m.group(2)
        if not sels or sels.startswith("@"):
            continue
        changed = []
        for d in decls.split(";"):
            if ":" not in d:
                continue
            new = remap_text(d, T)
            if new != d:
                changed.append(new.strip())
        if not changed:
            continue
        sel = ", ".join(f"{prefix} {x.strip()}" for x in sels.split(",") if x.strip())
        out.append(f"{sel} {{ {'; '.join(changed)}; }}")
    return "\n".join(out)
