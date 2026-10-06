#!/usr/bin/env python3
"""Build the Bapirlo OS GRUB theme into ~/bapirlo-os/build/grub/bapirlo (no root needed)."""
import os, subprocess
from PIL import Image, ImageDraw, ImageFilter

HOME = os.path.expanduser("~")
OUT = f"{HOME}/bapirlo-os/build/grub/bapirlo"
LOGO = f"{HOME}/bapirlo-os/assets/bapirlo-logo.png"
BANGERS = f"{HOME}/.local/share/fonts/bapirlo/Bangers-Regular.ttf"
INTER = "/usr/share/fonts/inter/Inter.ttc"
RED, BLUE, PINK, EMERALD = (227, 36, 43), (47, 124, 255), (255, 61, 139), (16, 201, 143)
W, H = 1920, 1200  # designed for GRUB_GFXMODE=1920x1200 (percent layout scales elsewhere)

os.makedirs(f"{OUT}/icons", exist_ok=True)

# --- background (calm variant so the menu stays readable)
subprocess.run(["python3", f"{HOME}/bapirlo-os/tools/make-art.py", str(W), str(H),
                f"{OUT}/background.png", "--calm", "--seed", "11"], check=True)
# darken the centre column behind the menu a little more
bg = Image.open(f"{OUT}/background.png").convert("RGB")
shade = Image.new("L", (W, H), 0)
ImageDraw.Draw(shade).rounded_rectangle([W * .27, H * .27, W * .73, H * .86], 40, fill=150)
shade = shade.filter(ImageFilter.GaussianBlur(60))
bg = Image.composite(Image.new("RGB", (W, H), (6, 6, 8)), bg, shade)
bg.save(f"{OUT}/background.png", optimize=True)

# --- logo
Image.open(LOGO).convert("RGBA").resize((170, 170), Image.LANCZOS).save(f"{OUT}/logo.png")

# --- fonts (.pf2); GRUB names them "<Family> <Style> <size>"
def mkfont(src, size, out, index=None):
    cmd = ["grub-mkfont", "-s", str(size), "-o", f"{OUT}/{out}"]
    if index is not None:
        cmd += ["-i", str(index)]
    subprocess.run(cmd + [src], check=True)

mkfont(BANGERS, 84, "bangers_84.pf2")
mkfont(INTER, 30, "inter_regular_30.pf2", 0)
mkfont(INTER, 30, "inter_bold_30.pf2", 14)
mkfont(INTER, 22, "inter_regular_22.pf2", 0)
mkfont(INTER, 20, "inter_regular_20.pf2", 0)  # terminal / console

# --- selected item: Windows-11 style accent bar on the left + translucent red fill
def save(img, name): img.save(f"{OUT}/{name}")
ih = 72
c = Image.new("RGBA", (8, ih), RED + (54,)); save(c, "select_c.png")
w = Image.new("RGBA", (14, ih), RED + (54,))
wd = ImageDraw.Draw(w)
for y in range(12, ih - 12):  # gradient accent bar pink -> red
    t = (y - 12) / (ih - 24)
    col = tuple(int(PINK[i] + (RED[i] - PINK[i]) * t) for i in range(3))
    wd.line([(0, y), (5, y)], fill=col + (255,))
save(w, "select_w.png")
e = Image.new("RGBA", (8, ih), RED + (54,)); save(e, "select_e.png")
for side, size in (("n", (8, 2)), ("s", (8, 2))):
    save(Image.new("RGBA", size, RED + (110,)), f"select_{side}.png")
for corner in ("nw", "ne", "sw", "se"):
    save(Image.new("RGBA", (2, 2), RED + (110,)), f"select_{corner}.png")

# --- menu box: smoky black glass with thin dark-red border
save(Image.new("RGBA", (8, 8), (11, 11, 13, 175)), "menu_c.png")
for side, size in (("n", (8, 2)), ("s", (8, 2)), ("w", (2, 8)), ("e", (2, 8))):
    save(Image.new("RGBA", size, (120, 20, 26, 200)), f"menu_{side}.png")
for corner in ("nw", "ne", "sw", "se"):
    save(Image.new("RGBA", (2, 2), (120, 20, 26, 200)), f"menu_{corner}.png")

# --- terminal box (console / 'e' editor)
save(Image.new("RGBA", (8, 8), (11, 11, 13, 235)), "terminal_box_c.png")
for side, size in (("n", (8, 2)), ("s", (8, 2)), ("w", (2, 8)), ("e", (2, 8))):
    save(Image.new("RGBA", size, RED + (255,)), f"terminal_box_{side}.png")
for corner in ("nw", "ne", "sw", "se"):
    save(Image.new("RGBA", (2, 2), RED + (255,)), f"terminal_box_{corner}.png")

# --- entry icons (64px, original glyphs; no vendor logos)
S = 64
def canvas(): return Image.new("RGBA", (S * 4, S * 4), (0, 0, 0, 0))
def finish(img, names):
    img = img.resize((S, S), Image.LANCZOS)
    for n in names: img.save(f"{OUT}/icons/{n}.png")

logo = Image.open(LOGO).convert("RGBA").resize((S, S), Image.LANCZOS)
for n in ("bapirlo", "gnu-linux", "arch", "linux"):
    logo.save(f"{OUT}/icons/{n}.png")

# Windows: a plain app-window outline in blue (deliberately NOT the Microsoft logo)
img = canvas(); d = ImageDraw.Draw(img)
d.rounded_rectangle([20, 40, 236, 216], 22, outline=BLUE + (255,), width=16)
d.line([(20, 86), (236, 86)], fill=BLUE + (255,), width=14)
for i, col in enumerate((EMERALD, PINK, RED)):
    d.ellipse([170 - 40 * i, 54, 188 - 40 * i, 72], fill=col + (255,))
finish(img, ["windows"])

# CachyOS BootNext / other EFI OS: emerald power glyph
img = canvas(); d = ImageDraw.Draw(img)
d.arc([36, 44, 220, 228], 300, 240, fill=EMERALD + (255,), width=20)
d.line([(128, 24), (128, 128)], fill=EMERALD + (255,), width=22)
finish(img, ["cachyos", "efi", "os", "uefi_", "submenu"])

# Firmware settings: gear
img = canvas(); d = ImageDraw.Draw(img)
import math
for k in range(8):
    a = k * math.pi / 4
    d.line([(128 + math.cos(a) * 60, 128 + math.sin(a) * 60),
            (128 + math.cos(a) * 104, 128 + math.sin(a) * 104)], fill=(200, 200, 210, 255), width=34)
d.ellipse([52, 52, 204, 204], fill=(200, 200, 210, 255))
d.ellipse([96, 96, 160, 160], fill=(0, 0, 0, 0))
finish(img, ["firmware", "setup", "uefi"])

# --- theme.txt
theme = f"""# Bapirlo OS GRUB theme
title-text: ""
desktop-image: "background.png"
desktop-image-scale-method: "crop"
desktop-color: "#0b0b0d"
terminal-font: "Inter Regular 20"
terminal-box: "terminal_box_*.png"
terminal-left: "10%"
terminal-top: "10%"
terminal-width: "80%"
terminal-height: "80%"

+ image {{
  top = 6%
  left = 50%-85
  width = 170
  height = 170
  file = "logo.png"
}}

+ label {{
  top = 6%+178
  left = 0
  width = 100%
  align = "center"
  text = "BAPIRLO OS"
  font = "Bangers Regular 84"
  color = "#e3242b"
}}

+ boot_menu {{
  left = 29%
  top = 36%
  width = 42%
  height = 44%
  item_font = "Inter Regular 30"
  item_color = "#c9c9d1"
  selected_item_font = "Inter Bold 30"
  selected_item_color = "#ffffff"
  icon_width = 44
  icon_height = 44
  item_icon_space = 22
  item_height = 72
  item_padding = 18
  item_spacing = 10
  selected_item_pixmap_style = "select_*.png"
  menu_pixmap_style = "menu_*.png"
  scrollbar = false
}}

+ progress_bar {{
  id = "__timeout__"
  left = 29%
  top = 82%
  width = 42%
  height = 6
  show_text = false
  fg_color = "#e3242b"
  bg_color = "#16161a"
  border_color = "#16161a"
}}

+ label {{
  id = "__timeout__"
  left = 0
  top = 82%+18
  width = 100%
  align = "center"
  color = "#ff3d8b"
  font = "Inter Regular 22"
  text = "Booting in %d s"
}}

+ label {{
  left = 0
  top = 95%
  width = 100%
  align = "center"
  color = "#7a7a86"
  font = "Inter Regular 22"
  text = "↑ ↓  select     Enter  boot     E  edit     C  console"
}}
"""
open(f"{OUT}/theme.txt", "w").write(theme)
print("GRUB theme built in", OUT)
