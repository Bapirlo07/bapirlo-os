#!/usr/bin/env python3
"""Bapirlo OS — writes the EasyEffects 8 output presets used by bin/bapirlo-sound-profile.
   Bapirlo Speakers    MSI Pulse 16 laptop speakers: cut the rumble they can't play, lift the
                       upper bass they can, scoop the boxy 350 Hz, clearer voices, softer 6–7 kHz
                       hiss, a little air, then a limiter so it gets louder without crackling.
   Bapirlo Headphones  any headphones / earbuds: gentle warm low shelf, a touch of air, limiter.
   Bapirlo Flat        nothing (HDMI / external speakers / to compare).
Tuned from the speaker class, not measured on this laptop — tweak in EasyEffects and save over it.
usage: make-presets.py <easyeffects data dir>   (e.g. ~/.local/share/easyeffects)"""
import json
import os
import sys


def band(kind, freq, gain=0.0, q=0.71, slope="x1"):
    return {"frequency": freq, "gain": gain, "mode": "RLC (BT)", "mute": False, "q": q,
            "slope": slope, "solo": False, "type": kind, "width": 4.0}


def equalizer(bands, input_gain):
    side = {f"band{i}": b for i, b in enumerate(bands)}
    return {"bypass": False, "input-gain": input_gain, "output-gain": 0.0, "mode": "IIR",
            "num-bands": len(bands), "split-channels": False, "balance": 0.0, "pitch-left": 0.0,
            "pitch-right": 0.0, "left": side, "right": json.loads(json.dumps(side))}


def limiter(boost):
    return {"bypass": False, "input-gain": boost, "output-gain": 0.0, "mode": "Herm Thin",
            "oversampling": "Half x2(2L)", "dithering": "None", "threshold": -1.0, "attack": 5.0,
            "release": 20.0, "lookahead": 5.0, "stereo-link": 100.0, "sidechain-preamp": 0.0,
            "alr": False, "alr-attack": 5.0, "alr-release": 50.0, "alr-knee": 0.0, "gain-boost": True}


def preset(eq_bands, eq_gain, boost):
    if not eq_bands:
        return {"output": {"blocklist": [], "plugins_order": []}}
    return {"output": {"blocklist": [], "plugins_order": ["equalizer#0", "limiter#0"],
                       "equalizer#0": equalizer(eq_bands, eq_gain), "limiter#0": limiter(boost)}}


PRESETS = {
    "Bapirlo Speakers": preset([
        band("Hi-pass", 110.0, q=0.71, slope="x2"),   # tiny drivers: below ~110 Hz only distorts
        band("Bell", 170.0, 3.0, q=1.0),              # the bass they CAN play
        band("Bell", 350.0, -3.0, q=1.2),             # boxy / muddy
        band("Bell", 1000.0, -1.0, q=1.0),
        band("Bell", 3000.0, 2.0, q=1.0),             # voices, presence
        band("Bell", 6500.0, -2.0, q=2.0),            # harsh / hissy
        band("Hi-shelf", 10000.0, 2.5, q=0.71),       # air
    ], eq_gain=-3.5, boost=4.0),
    "Bapirlo Headphones": preset([
        band("Lo-shelf", 105.0, 3.5, q=0.71),
        band("Bell", 3500.0, -1.0, q=1.4),
        band("Hi-shelf", 9000.0, 1.0, q=0.71),
    ], eq_gain=-4.0, boost=1.5),
    "Bapirlo Flat": preset([], 0, 0),
}

if __name__ == "__main__":
    out = os.path.join(sys.argv[1], "output")
    os.makedirs(out, exist_ok=True)
    for name, data in PRESETS.items():
        with open(os.path.join(out, f"{name}.json"), "w") as f:
            json.dump(data, f, indent=4)
        print(f"{out}/{name}.json")
