"""Theme Studio preview: the top bar, dock, Control Centre, a window and a notification drawn in a
palette, over the wallpaper. One SVG (no screenshots, no shell needed), rendered with librsvg.

  render_png(roles, wallpaper, out, width=960)
  render_bytes(roles, wallpaper, width=960) → PNG bytes
"""
import base64
import functools
import io
import os

W, H = 960, 600


def _rgba(h, a):
    h = h.lstrip("#")
    return f"rgba({int(h[0:2], 16)},{int(h[2:4], 16)},{int(h[4:6], 16)},{a})"


@functools.lru_cache(maxsize=8)      # the slider preview re-renders often; the picture stays
def _wall_data(path, _mtime=None):
    from PIL import Image
    im = Image.open(path).convert("RGB")
    s = max(W / im.width, H / im.height)
    im = im.resize((max(W, round(im.width * s)), max(H, round(im.height * s))), Image.LANCZOS)
    x, y = (im.width - W) // 2, (im.height - H) // 2
    im = im.crop((x, y, x + W, y + H))
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=82)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def svg(r, wallpaper=None):
    ink, night, surf, line = r["ink"], r["night"], r["surface"], r["line"]
    paper, muted, mist = r["paper"], r["muted"], r["mist"]
    acc, ember, blood, a2, a3 = r["crimson"], r["ember"], r["blood"], r["accent2"], r["accent3"]
    bg = (f'<image href="{_wall_data(wallpaper, os.path.getmtime(wallpaper))}" x="0" y="0" width="{W}" height="{H}" preserveAspectRatio="xMidYMid slice"/>'
          if wallpaper and os.path.exists(wallpaper) else f'<rect width="{W}" height="{H}" fill="{ink}"/>')
    panel = _rgba(night, 0.94)
    hair = _rgba(acc, 0.28)
    font = 'font-family="Inter, sans-serif"'
    # dock icons: neutral squircles, one "running" dot in the second accent, the focused one crimson
    dock = []
    for i in range(7):
        x = 330 + i * 44
        dock.append(f'<rect x="{x}" y="544" width="34" height="34" rx="9" fill="{surf}" stroke="{_rgba(paper, 0.08)}"/>')
        dock.append(f'<rect x="{x + 9}" y="553" width="16" height="16" rx="4" fill="{[acc, a2, mist, a3, muted, ember, paper][i]}" opacity="0.92"/>')
        if i in (0, 2, 3):
            dock.append(f'<circle cx="{x + 17}" cy="584" r="2" fill="{acc if i == 0 else a2}"/>')
    tiles = []
    for i, (on, label) in enumerate(((True, "Wi-Fi"), (False, "Bluetooth"), (False, "Focus"), (True, "Night Light"))):
        x, y = 712 + (i % 2) * 112, 64 + (i // 2) * 52
        tiles.append(f'<rect x="{x}" y="{y}" width="104" height="44" rx="12" fill="{acc if on and i == 0 else surf}" '
                     f'stroke="{hair if on else _rgba(paper, 0.06)}"/>')
        tiles.append(f'<circle cx="{x + 20}" cy="{y + 22}" r="10" fill="{"#FFFFFF" if on and i == 0 else (acc if on else line)}" opacity="{0.95 if on else 0.8}"/>')
        tiles.append(f'<text x="{x + 36}" y="{y + 26}" {font} font-size="10.5" font-weight="600" fill="{"#FFFFFF" if on and i == 0 else paper}">{label}</text>')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">
  {bg}
  <rect width="{W}" height="{H}" fill="{_rgba(ink, 0.18)}"/>
  <!-- top bar -->
  <rect x="8" y="6" width="{W - 16}" height="30" rx="14" fill="{panel}" stroke="{hair}"/>
  <circle cx="28" cy="21" r="8" fill="none" stroke="{ember}" stroke-width="2.2"/>
  <text x="28" y="24.6" {font} font-size="9.5" font-weight="800" fill="{ember}" text-anchor="middle">B</text>
  <rect x="46" y="12" width="18" height="18" rx="6" fill="{acc}"/><text x="55" y="25" {font} font-size="11" font-weight="700" fill="#FFFFFF" text-anchor="middle">1</text>
  <text x="72" y="25" {font} font-size="11" fill="{muted}">2   3</text>
  <rect x="104" y="11" width="78" height="20" rx="10" fill="{_rgba(paper, 0.06)}"/>
  <rect x="112" y="15" width="12" height="12" rx="3" fill="{a2}"/><rect x="130" y="15" width="12" height="12" rx="3" fill="{a3}"/><rect x="148" y="15" width="12" height="12" rx="3" fill="{ember}"/>
  <text x="194" y="25" {font} font-size="11" font-weight="700" fill="{paper}">Files</text>
  <rect x="{W / 2 - 64}" y="10" width="128" height="22" rx="11" fill="{_rgba(ink, 0.9)}"/>
  <text x="{W / 2}" y="25" {font} font-size="11.5" font-weight="700" fill="{paper}" text-anchor="middle">Mon 12 Oct  17:45</text>
  <rect x="604" y="11" width="92" height="20" rx="10" fill="{_rgba(paper, 0.06)}"/>
  <text x="614" y="25" {font} font-size="10.5" fill="{paper}">♪  16°  7%</text>
  <rect x="704" y="11" width="44" height="20" rx="10" fill="{_rgba(paper, 0.06)}"/>
  <rect x="756" y="11" width="190" height="20" rx="10" fill="{_rgba(paper, 0.08)}" stroke="{_rgba(ember, 0.35)}"/>
  <text x="900" y="25" {font} font-size="10.5" font-weight="700" fill="{paper}">80%</text>
  <!-- Control Centre -->
  <rect x="700" y="52" width="244" height="232" rx="18" fill="{_rgba(night, 0.97)}" stroke="{hair}"/>
  {"".join(tiles)}
  <rect x="712" y="168" width="216" height="40" rx="12" fill="{surf}"/>
  <text x="724" y="184" {font} font-size="10" font-weight="600" fill="{paper}">Sound</text>
  <rect x="724" y="194" width="192" height="4" rx="2" fill="{line}"/><rect x="724" y="194" width="118" height="4" rx="2" fill="{acc}"/>
  <circle cx="842" cy="196" r="6" fill="{paper}"/>
  <rect x="712" y="216" width="216" height="56" rx="12" fill="{surf}"/>
  <rect x="722" y="226" width="36" height="36" rx="8" fill="{blood}"/><path d="M736 236v14a3 3 0 1 0 2 3v-11l8-2v8a3 3 0 1 0 2 3v-13z" fill="{ember}"/>
  <text x="768" y="241" {font} font-size="10.5" font-weight="700" fill="{paper}">Now playing</text>
  <text x="768" y="256" {font} font-size="9.5" fill="{muted}">Kuro — Scatter</text>
  <!-- notification -->
  <rect x="{W / 2 - 150}" y="44" width="300" height="52" rx="16" fill="{_rgba(night, 0.97)}" stroke="{hair}"/>
  <circle cx="{W / 2 - 124}" cy="70" r="12" fill="{acc}"/><text x="{W / 2 - 128}" y="74.5" {font} font-size="11" font-weight="800" fill="#FFFFFF">!</text>
  <text x="{W / 2 - 104}" y="64" {font} font-size="10.5" font-weight="700" fill="{ember}">Theme Studio</text>
  <text x="{W / 2 - 104}" y="81" {font} font-size="10" fill="{paper}">New theme applied — looking sharp.</text>
  <!-- a window -->
  <rect x="64" y="128" width="560" height="372" rx="16" fill="{night}" stroke="{_rgba(paper, 0.07)}"/>
  <path d="M64 144a16 16 0 0 1 16-16h528a16 16 0 0 1 16 16v26H64z" fill="{surf}"/>
  <circle cx="86" cy="150" r="6" fill="{acc}"/><circle cx="104" cy="150" r="6" fill="{line}"/><circle cx="122" cy="150" r="6" fill="{line}"/>
  <text x="344" y="154" {font} font-size="11.5" font-weight="700" fill="{paper}" text-anchor="middle">Lecture notes — Week 4</text>
  <rect x="64" y="170" width="150" height="330" fill="{_rgba(ink, 0.55)}"/>
  <rect x="74" y="184" width="130" height="26" rx="8" fill="{_rgba(acc, 0.20)}"/>
  <text x="86" y="201" {font} font-size="10.5" font-weight="700" fill="{ember}">Algorithms</text>
  <text x="86" y="230" {font} font-size="10.5" fill="{mist}">Databases</text>
  <text x="86" y="256" {font} font-size="10.5" fill="{mist}">Networks</text>
  <text x="86" y="282" {font} font-size="10.5" fill="{muted}">Archive</text>
  <text x="234" y="204" {font} font-size="17" font-weight="800" fill="{paper}">Dynamic programming</text>
  <text x="234" y="228" {font} font-size="10.5" fill="{mist}">Break the problem into overlapping sub-problems and</text>
  <text x="234" y="245" {font} font-size="10.5" fill="{mist}">store each answer once — <tspan fill="{a2}" text-decoration="underline">see the worked example</tspan>.</text>
  <rect x="234" y="262" width="372" height="64" rx="10" fill="{ink}" stroke="{_rgba(paper, 0.06)}"/>
  <text x="248" y="285" font-family="JetBrains Mono, monospace" font-size="10" fill="{ember}">def <tspan fill="{a3}">fib</tspan><tspan fill="{paper}">(n, memo={{}}):</tspan></text>
  <text x="248" y="303" font-family="JetBrains Mono, monospace" font-size="10" fill="{muted}">    # each n solved once</text>
  <text x="248" y="319" font-family="JetBrains Mono, monospace" font-size="10" fill="{paper}">    return memo.setdefault(n, …)</text>
  <rect x="234" y="344" width="248" height="22" rx="4" fill="{_rgba(acc, 0.32)}"/>
  <text x="240" y="359" {font} font-size="10.5" fill="{paper}">highlighted: O(n) time, O(n) memory</text>
  <rect x="234" y="448" width="96" height="30" rx="9" fill="{acc}"/>
  <text x="282" y="467" {font} font-size="11" font-weight="700" fill="#FFFFFF" text-anchor="middle">Save</text>
  <rect x="340" y="448" width="96" height="30" rx="9" fill="{_rgba(paper, 0.07)}"/>
  <text x="388" y="467" {font} font-size="11" font-weight="600" fill="{paper}" text-anchor="middle">Cancel</text>
  <rect x="560" y="454" width="36" height="18" rx="9" fill="{acc}"/><circle cx="587" cy="463" r="7" fill="#FFFFFF"/>
  <!-- dock -->
  <rect x="318" y="536" width="320" height="52" rx="18" fill="{_rgba(night, 0.88)}" stroke="{hair}"/>
  {"".join(dock)}
</svg>'''


def render_bytes(roles, wallpaper=None, width=W):
    import gi
    gi.require_version("Rsvg", "2.0")
    from gi.repository import Rsvg
    import cairo
    h = Rsvg.Handle.new_from_data(svg(roles, wallpaper).encode())
    scale = width / W
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, int(W * scale), int(H * scale))
    cr = cairo.Context(surf)
    vp = Rsvg.Rectangle()
    vp.x, vp.y, vp.width, vp.height = 0, 0, W * scale, H * scale
    h.render_document(cr, vp)
    buf = io.BytesIO()
    surf.write_to_png(buf)
    return buf.getvalue()


def render_png(roles, wallpaper, out, width=W):
    data = render_bytes(roles, wallpaper, width)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as f:
        f.write(data)
    return out
