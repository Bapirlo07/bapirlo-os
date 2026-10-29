#!/usr/bin/env python3
# Kuro OS — battery "plugged in, holding at the charge limit" icons.
# WhiteSur links battery-level-N-plugged-in to the charging bolt, so with the 80 % limit the bar
# claimed "charging" forever. These draw WhiteSur's battery with a small plug instead of a bolt.
#   python3 make-plugged-icons.py OUT_DIR
import os, sys

OUTLINE = ('m2 3c-1.108 0-2 0.892-2 2v6c0 1.108 0.892 2 2 2h9c1.108 0 2-0.892 2-2v-6c0-1.108-0.892-2-2-2z'
           'm0 1h9c0.554 0 1 0.446 1 1v6c0 0.554-0.446 1-1 1h-9c-0.554 0-1-0.446-1-1v-6c0-0.554 0.446-1 1-1z')
NUB = 'm14 6v4a2 2 0 0 0 2-2 2 2 0 0 0-2-2z'
# plug: two prongs, body, cable — inside the 9×6 fill area (x 2–11, y 5–11)
PLUG = [(5, 5, 1, 1.5), (7, 5, 1, 1.5), (4.5, 6.5, 4, 2.5), (6, 9, 1, 2)]
PLUG_D = ''.join(f'M{x} {y}h{w}v{h}h-{w}z' for x, y, w, h in PLUG)


def icon(level):
    # GNOME recolours every shape of a symbolic icon, so no masks: the plug is an even-odd hole
    # in the charge fill, and solid where the battery is empty (both clipped at the fill's end)
    end = 2 + round(9 * level / 100, 2)
    return f'''<svg width="16" height="16" version="1.1" xmlns="http://www.w3.org/2000/svg">
 <defs>
  <clipPath id="full"><rect x="2" y="0" width="{end - 2}" height="16"/></clipPath>
  <clipPath id="empty"><rect x="{end}" y="0" width="16" height="16"/></clipPath>
 </defs>
 <g fill="#dedede">
  <path d="{OUTLINE}"/>
  <path d="M2 5h9v6h-9z{PLUG_D}" fill-rule="evenodd" clip-path="url(#full)"/>
  <path d="{PLUG_D}" clip-path="url(#empty)"/>
  <path d="{NUB}"/>
 </g>
</svg>
'''

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
for level in range(0, 101, 10):
    with open(os.path.join(out, f'battery-level-{level}-plugged-in-symbolic.svg'), 'w') as f:
        f.write(icon(level))
