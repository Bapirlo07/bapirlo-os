#!/usr/bin/env python3
"""Kuro folder icons — crimson manga folders for the Kuro icon theme.

  python3 build-folders.py OUT_DIR [--preview PNG]

Every folder: blood-red back panel + tab, crimson front panel with a manga halftone fade in the
corner, 1.6 px ink line art, the same hard blood drop shadow as Bapirlo-Cursors, and the place's
glyph in paper white (taken from Adwaita's symbolic icons, recoloured). Writes 64×64 SVGs straight
into OUT_DIR (= the theme's scalable/places, which outranks WhiteSur-red-dark at every size).
"""
import os
import re
import subprocess
import sys

SYM = "/usr/share/icons/Adwaita/symbolic"
INK, PAPER = "#0E0A0D", "#F2E9EC"
BLOOD, CRIMSON, DEEP, SHADOW = "#7A0F1A", "#E11D2E", "#A8121F", "#3A0A10"

# icon name → Adwaita symbolic glyph ('' = plain folder)
ICONS = {
    "folder": "", "inode-directory": "", "folder-open": "", "folder-visiting": "",
    "folder-drag-accept": "folder-drag-accept",
    "user-home": "user-home", "folder-home": "user-home",
    "user-desktop": "devices/video-display", "folder-desktop": "devices/video-display",
    "folder-documents": "folder-documents",
    "folder-download": "folder-download", "folder-downloads": "folder-download",
    "folder-music": "folder-music",
    "folder-pictures": "folder-pictures", "folder-images": "folder-pictures",
    "folder-videos": "folder-videos", "folder-video": "folder-videos",
    "folder-templates": "folder-templates",
    "folder-publicshare": "folder-publicshare", "folder-public": "folder-publicshare",
    "folder-projects": "folder-projects",
    "folder-remote": "folder-remote", "folder-network": "folder-remote",
    "folder-saved-search": "folder-saved-search",
}
OPEN = {"folder-open", "folder-visiting", "folder-drag-accept"}


def glyph(name):
    """Inner markup of an Adwaita symbolic icon, every paint turned paper white."""
    svg = open(os.path.join(SYM, name if "/" in name else f"places/{name}") + "-symbolic.svg").read()
    body = svg[re.search(r"<svg\b[^>]*>", svg).end():svg.rfind("</svg>")]
    body = re.sub(r"<(metadata|sodipodi:namedview|title)\b.*?</\1>|<(sodipodi:namedview)\b[^>]*/>", "", body, flags=re.S)
    body = re.sub(r'\s(gpa|class)(:[\w-]+)?="[^"]*"', "", body)     # GTK "grappa" symbolic extras
    body = re.sub(r"(fill|stroke|color)\s*[:=]\s*\"?#[0-9a-fA-F]{3,6}", lambda m: re.sub(r"#\w+", PAPER, m.group(0)), body)
    return body


def folder(name, sym):
    is_open = name in OPEN
    # front panel: open folders tilt back like a page being turned
    front = ('<path d="M6 25.5h52a3 3 0 0 1 3 3.2l-1.4 22.8a4 4 0 0 1-4 3.7H8.4a4 4 0 0 1-4-3.7L3 28.7a3 3 0 0 1 3-3.2z"/>'
             if not is_open else
             '<path d="M10.5 27h50a2.6 2.6 0 0 1 2.5 3.3l-5.4 21.4a4 4 0 0 1-3.9 3H8.3a3.6 3.6 0 0 1-3.5-4.4l3.2-21a3 3 0 0 1 2.5-2.3z"/>')
    g = ""
    if sym:
        g = (f'<svg x="22" y="31" width="20" height="20" viewBox="0 0 16 16" overflow="visible">'
             f'<g style="fill:{PAPER}">{glyph(sym)}</g></svg>')
        # ink "stamp" behind the glyph so it reads on crimson at 16 px
        g = (f'<svg x="22.9" y="31.9" width="20" height="20" viewBox="0 0 16 16" opacity=".55">'
             f'<g style="fill:{INK}">{glyph(sym).replace(PAPER, INK)}</g></svg>') + g
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<defs>
  <linearGradient id="f" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{CRIMSON}"/><stop offset="1" stop-color="{DEEP}"/></linearGradient>
  <pattern id="dots" width="3.2" height="3.2" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
    <circle cx="1.6" cy="1.6" r=".75" fill="{INK}"/></pattern>
  <linearGradient id="fade" x1="1" y1="1" x2=".45" y2=".35"><stop offset="0" stop-color="#fff" stop-opacity=".5"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
  <mask id="m"><rect width="64" height="64" fill="url(#fade)"/></mask>
  <clipPath id="c">{front}</clipPath>
</defs>
<g transform="translate(1.8 1.8)" fill="{SHADOW}">
  <path d="M8 10h15.5a3 3 0 0 1 2.3 1.1l2.6 3.2a3 3 0 0 0 2.3 1.1H56a3 3 0 0 1 3 3V50H5V13a3 3 0 0 1 3-3z"/>{front}</g>
<path d="M8 10h15.5a3 3 0 0 1 2.3 1.1l2.6 3.2a3 3 0 0 0 2.3 1.1H56a3 3 0 0 1 3 3V50H5V13a3 3 0 0 1 3-3z"
      fill="{BLOOD}" stroke="{INK}" stroke-width="1.6" stroke-linejoin="round"/>
<rect x="9" y="19" width="46" height="9" rx="1.5" fill="{PAPER}" opacity=".9"/>
<g fill="url(#f)" stroke="{INK}" stroke-width="1.6" stroke-linejoin="round">{front}</g>
<g clip-path="url(#c)"><rect width="64" height="64" fill="url(#dots)" mask="url(#m)"/>
  <path d="M5 27.6h54" stroke="{PAPER}" stroke-opacity=".45" stroke-width="1.2" fill="none"/></g>
{g}
</svg>
'''


def main(out):
    os.makedirs(out, exist_ok=True)
    for name, sym in ICONS.items():
        with open(os.path.join(out, f"{name}.svg"), "w") as f:
            f.write(folder(name, sym))
    return len(ICONS)


def preview(out, png):
    from PIL import Image
    import io
    names = ["folder", "folder-open", "user-home", "user-desktop", "folder-documents", "folder-download",
             "folder-music", "folder-pictures", "folder-videos", "folder-templates", "folder-publicshare",
             "folder-projects", "folder-remote"]
    sizes = (96, 48, 32, 16)
    w = sum(s + 10 for s in sizes)
    sheet = Image.new("RGBA", (w * 2 + 20, len(names) * 106 // 2 + 120), "#161015")
    for i, n in enumerate(names):
        x0 = (i % 2) * (w + 20) + 10
        y0 = (i // 2) * 106 + 10
        x = x0
        for s in sizes:
            data = subprocess.run(["rsvg-convert", "-w", str(s), "-h", str(s), os.path.join(out, f"{n}.svg")],
                                  capture_output=True, check=True).stdout
            sheet.alpha_composite(Image.open(io.BytesIO(data)).convert("RGBA"), (x, y0 + (96 - s) // 2))
            x += s + 10
    sheet.save(png)


if __name__ == "__main__":
    n = main(sys.argv[1])
    print(f"{n} folder icons → {sys.argv[1]}")
    if "--preview" in sys.argv:
        preview(sys.argv[1], sys.argv[sys.argv.index("--preview") + 1])
