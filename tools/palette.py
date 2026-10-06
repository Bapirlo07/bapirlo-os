"""Bapirlo OS "Kuro" palette — single source of truth.

Sampled from the "KURO. SCATTER." wallpaper (fan art colour by eSM1LE — not redistributed here):
ink blacks with a violet undertone, blood-red eye/aura glow, sakura-pink and
paper-white spirit wisps. Every themed surface (GRUB, Plymouth, LightDM, shell,
GTK, dock, terminal, fastfetch) imports these values.
"""
import json, os

# The wallpaper the whole theme is built from. It is third-party fan art, so it is NOT in the repo:
# install.sh links your own picture here (or set BAPIRLO_WALLPAPER=/path/to/image).
HERO = os.path.expanduser(os.environ.get("BAPIRLO_WALLPAPER", "~/.config/bapirlo/hero-wallpaper"))

PAL = {
    "ink":      "#0E0A0D",  # deepest background (image shadows)
    "night":    "#161015",  # panels / cards
    "surface":  "#231A1F",  # raised surfaces (image #2C2025, darkened)
    "line":     "#523B44",  # borders, inactive (image #523B44)
    "muted":    "#8E7680",  # secondary text
    "mist":     "#CAB5BF",  # tertiary light (image #CAB5BF)
    "paper":    "#F2E9EC",  # primary text (spirit-white)
    "crimson":  "#E11D2E",  # MAIN accent (eye/aura glow)
    "ember":    "#FF4655",  # hover / glow highlight
    "blood":    "#7A0F1A",  # pressed / deep accent (image #572426 saturated)
    "sakura":   "#F08AA4",  # minor accent (pink wisps, image #AE7788 lifted)
    "rose":     "#AE7788",  # muted pink
    "steel":    "#7C9CFF",  # minor: info / links (kept from brand, cooled)
    "jade":     "#3FC69A",  # minor: success
    "amber":    "#F2B45A",  # warnings
}

def rgb(name, a=None):
    h = PAL[name].lstrip("#")
    t = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    return t + (a,) if a is not None else t

if __name__ == "__main__":
    out = os.path.expanduser("~/bapirlo-os/build/palette.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(PAL, open(out, "w"), indent=2)
    print(json.dumps(PAL, indent=2))
