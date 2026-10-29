#!/usr/bin/env python3
"""Kuro OS round 7 icons — Kuro app icons (ink squircle, crimson glow, paper glyph) and
symbolic versions (single colour, even-odd paths, no masks: St recolours symbolic SVGs).
Writes into the given output dir: scalable/apps/<name>.svg and symbolic/apps/<name>-symbolic.svg"""
import os, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "build/round7-icons"

# glyphs drawn on a 0..16 grid; filled with fill-rule evenodd
G = {
 # screen + triangle
 "airplay": "M2 2h12a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-2.2l-1-1.2H13V3.5H3v7.3h2.2l-1 1.2H2a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1z M8 9l4.5 5.5h-9z",
 # monitor + stand + pointer arrow
 "remote": "M1.5 2h13a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H9.5v1.5H12V15H4v-1.5h2.5V12h-5a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1z M2 3.5v7h12v-7z M6 4.5l5 2.6-2.1.6 1.4 2.2-1 .6-1.4-2.2-1.6 1.4z",
 # padlock
 "vault": "M8 1a4 4 0 0 1 4 4v2h.5a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1H4V5a4 4 0 0 1 4-4z M8 2.6A2.4 2.4 0 0 0 5.6 5v2h4.8V5A2.4 2.4 0 0 0 8 2.6z M8 9a1.3 1.3 0 0 0-.7 2.4V13h1.4v-1.6A1.3 1.3 0 0 0 8 9z",
 # caption box with two text lines
 "captions": "M2 3h12a1.5 1.5 0 0 1 1.5 1.5v7A1.5 1.5 0 0 1 14 13H2a1.5 1.5 0 0 1-1.5-1.5v-7A1.5 1.5 0 0 1 2 3z M2 4.5v7h12v-7z M3.5 7.5h5v1.4h-5z M9.5 7.5h3v1.4h-3z M3.5 9.6h3v1.4h-3z M7.5 9.6h5v1.4h-5z",
 # paper plane
 "localsend": "M1 7.5L15 1.5 11.5 14.5 8 10.5 13 3.5 6.5 9.5z M6.5 10.5L8 12 6.5 14.5z",
 # cloud
 "icloud": "M4.5 13a3.5 3.5 0 0 1-.6-6.95A4.5 4.5 0 0 1 12.5 5.5 3.75 3.75 0 0 1 12 13z",
 # 3x3 grid
 "launchpad": " ".join(f"M{x} {y}h3.2a.8.8 0 0 1 .8.8v3.2H{x}z".replace(f"M{x} {y}h3.2a.8.8 0 0 1 .8.8v3.2H{x}z",
     f"M{x+.8} {y}h2.4a.8.8 0 0 1 .8.8v2.4a.8.8 0 0 1-.8.8h-2.4a.8.8 0 0 1-.8-.8v-2.4a.8.8 0 0 1 .8-.8z")
     for y in (1, 6, 11) for x in (1, 6, 11)),
}

APP = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <!-- {name} — Kuro OS "Kuro" app icon -->
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2A1F25"/><stop offset="1" stop-color="#0E0A0D"/></linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.42" r="0.5"><stop offset="0" stop-color="#FF4655" stop-opacity="0.55"/><stop offset="0.6" stop-color="#E11D2E" stop-opacity="0.14"/><stop offset="1" stop-color="#E11D2E" stop-opacity="0"/></radialGradient>
    <linearGradient id="ink" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E4D6DB"/></linearGradient>
  </defs>
  <rect x="24" y="24" width="464" height="464" rx="104" fill="url(#bg)"/>
  <rect x="24" y="24" width="464" height="464" rx="104" fill="url(#glow)"/>
  <rect x="25.5" y="25.5" width="461" height="461" rx="102.5" fill="none" stroke="#E11D2E" stroke-opacity="0.45" stroke-width="3"/>
  <g transform="translate(112 112) scale(18)"><path fill="url(#ink)" fill-rule="evenodd" d="{d}"/></g>
  <circle cx="392" cy="120" r="14" fill="#E11D2E"/>
</svg>
"""
SYM = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16"><path fill="#2e3436" fill-rule="evenodd" d="{d}"/></svg>
"""
os.makedirs(f"{OUT}/scalable/apps", exist_ok=True)
os.makedirs(f"{OUT}/symbolic/apps", exist_ok=True)
for name, d in G.items():
    open(f"{OUT}/scalable/apps/bapirlo-{name}.svg", "w").write(APP.format(name=name, d=d))
    open(f"{OUT}/symbolic/apps/bapirlo-{name}-symbolic.svg", "w").write(SYM.format(d=d))
print("icons ->", OUT)
