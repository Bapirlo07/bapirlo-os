#!/usr/bin/env python3
"""Bapirlo OS Plymouth theme v2 "Kuro awakens" -> ~/bapirlo-os/build/plymouth-v2/bapirlo (no root).

Timeline (seconds from plymouthd showing the splash):
  0.0-1.2  artwork fades up from black (GRUB hands over on black, so no flash)
  0.4-1.4  logo lockup rises 28px and fades in; halo starts breathing
  0.9-1.7  the character's eyes ignite, then pulse like a heartbeat (2.2 s period)
  always   crimson / sakura embers drift upward
  >0.9     progress line (eased) with a glowing ember head; status text under it
Password prompt: frosted glass card, crimson bullet dots. Shutdown: "See you soon." Reboot: "Be right back."

Also writes build/plymouth-v2/preview.gif — a frame simulation of the same timeline.
"""
import math, os, random, sys
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont
sys.path.insert(0, os.path.dirname(__file__))
from palette import PAL, rgb

HOME = os.path.expanduser("~")
OUT = f"{HOME}/bapirlo-os/build/plymouth-v2/bapirlo"
ART = f"{HOME}/bapirlo-os/build/art/boot-2560x1600.png"
LOGO = f"{HOME}/bapirlo-os/build/art/logo-kuro.svg"      # made by build-grub-v2.py
BANGERS = f"{HOME}/.local/share/fonts/bapirlo/Bangers-Regular.ttf"
INTER = "/usr/share/fonts/inter/Inter.ttc"
I_MED, I_SEMI, I_BOLD = 10, 12, 14
W, H = 2560, 1600
EYES = [(1970, 794), (2256, 786)]          # eye centres in the 2560x1600 art
CX, CY = 660, 700                          # lockup centre (left third, above middle)
BAR_W, BAR_Y = 560, 900
N_EMBERS = 22
os.makedirs(OUT, exist_ok=True)
def font(p, s, i=0): return ImageFont.truetype(p, s, index=i)


def logo(size):
    import subprocess
    tmp = f"{OUT}/_l.png"
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), LOGO, "-o", tmp], check=True)
    im = Image.open(tmp).convert("RGBA"); os.remove(tmp); return im


def glow_dot(d, color, core=0.0, falloff=2.2):
    im = Image.new("RGBA", (d, d)); px = im.load(); r = d / 2
    for y in range(d):
        for x in range(d):
            t = min(1, math.hypot(x + .5 - r, y + .5 - r) / r)
            a = 1 if t < core else (1 - (t - core) / (1 - core)) ** falloff
            px[x, y] = color + (int(255 * a),)
    return im


def tracked(draw, xy, text, fnt, fill, track):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill); x += draw.textlength(ch, font=fnt) + track
    return x


def tracked_w(draw, text, fnt, track):
    return sum(draw.textlength(c, font=fnt) + track for c in text) - track


# ------------------------------------------------------------------ assets
bg = Image.open(ART).convert("RGB")
bg = ImageEnhance.Brightness(bg).enhance(0.72)
# depth-of-field pool behind the lockup: blur + darken an ellipse so the logo floats
pool = Image.new("L", (W, H), 0)
ImageDraw.Draw(pool).ellipse([CX - 560, CY - 430, CX + 560, BAR_Y + 330], fill=255)
pool = pool.filter(ImageFilter.GaussianBlur(150))
soft = Image.blend(bg.filter(ImageFilter.GaussianBlur(18)), Image.new("RGB", (W, H), rgb("ink")), 0.72)
bg = Image.composite(soft, bg, pool)
bg.save(f"{OUT}/bg.png", optimize=True)

# eye glow: bright core + wide crimson bloom
eye = Image.alpha_composite(glow_dot(260, rgb("crimson"), 0, 2.6), glow_dot(260, rgb("ember"), 0, 9))
eye.save(f"{OUT}/eye.png")

# lockup: logo on top, wordmark, tagline — centred on its own canvas
LW, LH = 760, 420
lock = Image.new("RGBA", (LW, LH)); d = ImageDraw.Draw(lock)
lg = logo(190); lock.alpha_composite(lg, ((LW - 190) // 2, 0))
bf = font(BANGERS, 128)
d.text((LW // 2, 206), "BAPIRLO", font=bf, fill=rgb("paper", 255), anchor="mt")
tf_b, tf_m = font(INTER, 26, I_BOLD), font(INTER, 26, I_MED)
w1 = tracked_w(d, "OS", tf_b, 7); w2 = tracked_w(d, "·  KURO EDITION", tf_m, 7)
x = (LW - (w1 + 12 + w2)) // 2
x = tracked(d, (x, 360), "OS", tf_b, rgb("crimson", 255), 7)
tracked(d, (x + 12, 360), "·  KURO EDITION", tf_m, rgb("mist", 230), 7)
lock.save(f"{OUT}/lockup.png")
halo = glow_dot(420, rgb("crimson"), 0, 2.0)
halo.putalpha(halo.split()[3].point(lambda v: int(v * .55)))
halo.save(f"{OUT}/halo.png")

# progress bar pieces
Image.new("RGBA", (BAR_W, 4), rgb("surface", 255)).save(f"{OUT}/track.png")
row = Image.new("RGBA", (BAR_W, 1))
row.putdata([tuple(int(rgb("blood")[i] + (rgb("crimson")[i] - rgb("blood")[i]) * min(1, x / (BAR_W * .7)))
                   for i in range(3)) + (255,) for x in range(BAR_W)])
row.resize((BAR_W, 4)).save(f"{OUT}/fill.png")
head = Image.alpha_composite(glow_dot(56, rgb("crimson"), 0, 2.4), glow_dot(56, (255, 220, 225), 0, 12))
head.save(f"{OUT}/head.png")

# embers
for name, col, size in (("ember-a", rgb("crimson"), 22), ("ember-b", rgb("sakura"), 16), ("ember-c", rgb("paper"), 12)):
    glow_dot(size, col, .15, 1.6).save(f"{OUT}/{name}.png")

# password card (frosted glass sampled from the art behind it)
PW_W, PW_H = 640, 200
px0, py0 = CX - PW_W // 2, 1040
card = bg.crop((px0, py0, px0 + PW_W, py0 + PW_H)).filter(ImageFilter.GaussianBlur(26))
card = Image.blend(card, Image.new("RGB", card.size, rgb("ink")), .6).convert("RGBA")
m = Image.new("L", (PW_W * 2, PW_H * 2), 0)
ImageDraw.Draw(m).rounded_rectangle([0, 0, PW_W * 2 - 1, PW_H * 2 - 1], 56, fill=255)
card.putalpha(m.resize((PW_W, PW_H), Image.LANCZOS))
ol = Image.new("RGBA", (PW_W * 2, PW_H * 2)); ImageDraw.Draw(ol).rounded_rectangle(
    [1, 1, PW_W * 2 - 2, PW_H * 2 - 2], 56, outline=rgb("crimson", 170), width=3)
card.alpha_composite(ol.resize((PW_W, PW_H), Image.LANCZOS))
d = ImageDraw.Draw(card)
# lock glyph
d.rounded_rectangle([40, 44, 84, 82], 8, fill=rgb("crimson", 255))
d.arc([46, 20, 78, 62], 180, 360, fill=rgb("crimson", 255), width=6)
d.ellipse([58, 56, 66, 64], fill=rgb("ink", 255))
d.text((104, 40), "Unlock to continue", font=font(INTER, 28, I_SEMI), fill=rgb("paper", 255))
# entry field
d.rounded_rectangle([40, 112, PW_W - 40, 164], 26, fill=rgb("ink", 230), outline=rgb("line", 255), width=2)
card.save(f"{OUT}/password.png")
glow_dot(22, rgb("crimson"), .55, 1.2).save(f"{OUT}/bullet.png")

# shutdown text
sd = Image.new("RGBA", (760, 60)); d = ImageDraw.Draw(sd)
tw = tracked_w(d, "SEE YOU SOON", font(INTER, 30, I_SEMI), 10)
tracked(d, ((760 - tw) // 2, 10), "SEE YOU SOON", font(INTER, 30, I_SEMI), rgb("mist", 255), 10)
sd.save(f"{OUT}/bye.png")
sd = Image.new("RGBA", (760, 60)); d = ImageDraw.Draw(sd)          # reboot: "be right back"
tw = tracked_w(d, "BE RIGHT BACK", font(INTER, 30, I_SEMI), 10)
tracked(d, ((760 - tw) // 2, 10), "BE RIGHT BACK", font(INTER, 30, I_SEMI), rgb("mist", 255), 10)
sd.save(f"{OUT}/bye-reboot.png")

# ------------------------------------------------------------------ script
P = {k: tuple(round(c / 255, 3) for c in rgb(k)) for k in PAL}
script = f"""# Bapirlo OS — Plymouth "Kuro awakens" (generated by tools/build-plymouth-v2.py)
#
# Multi-monitor: Plymouth draws every sprite on every screen in ONE shared coordinate space
# centred on the largest screen, so a smaller monitor would only show the middle of the scene.
# Instead each screen d is parked at x = d * SPAN and gets its own copy of the scene, laid out
# for its own size. sync_displays() runs every frame: Plymouth re-centres all screens whenever
# one appears (simpledrm -> i915 -> nvidia during boot), and a new or resized screen is rebuilt.

# ---------- helpers
fun clamp(v, lo, hi) {{ if (v < lo) return lo; if (v > hi) return hi; return v; }}
fun ease_out(t) {{ t = clamp(t, 0, 1); return 1 - (1 - t) * (1 - t) * (1 - t); }}
fun ramp(t, a, b) {{ return clamp((t - a) / (b - a), 0, 1); }}
fun scaled(img, f) {{ return img.Scale(Math.Int(img.GetWidth() * f + 0.5), Math.Int(img.GetHeight() * f + 0.5)); }}

Window.SetBackgroundTopColor(0, 0, 0);
Window.SetBackgroundBottomColor(0, 0, 0);
SPAN = 16384;
NEMB = {N_EMBERS};
mode = Plymouth.GetMode();
booting = (mode == "boot" || mode == "resume");

# ---------- source images (assets are authored for {W}x{H})
bg_src = Image("bg.png");
eye_src = Image("eye.png");
lock_src = Image("lockup.png");
halo_src = Image("halo.png");
track_src = Image("track.png");
fill_src = Image("fill.png");
head_src = Image("head.png");
emb_src[0] = Image("ember-a.png");
emb_src[1] = Image("ember-b.png");
emb_src[2] = Image("ember-c.png");
pw_src = Image("password.png");
bullet_src = Image("bullet.png");
if (!booting) {{ if (mode == "reboot") bye_src = Image("bye-reboot.png"); else bye_src = Image("bye.png"); }}

ndisp = 0;
msg_text = "";
pw_count = -1;

# ---------- one screen's scene; every array below is indexed by screen d
fun hide_scene(d) {{
  global.S_bg[d].SetOpacity(0); global.S_eye0[d].SetOpacity(0); global.S_eye1[d].SetOpacity(0);
  global.S_lock[d].SetOpacity(0); global.S_halo[d].SetOpacity(0); global.S_track[d].SetOpacity(0);
  global.S_fill[d].SetOpacity(0); global.S_head[d].SetOpacity(0); global.S_msg[d].SetOpacity(0);
  global.S_pw[d].SetOpacity(0);
  if (!global.booting) global.S_bye[d].SetOpacity(0);
  for (i = 0; i < global.NEMB; i++) global.E_spr[d * global.NEMB + i].SetOpacity(0);
  for (i = 0; i < 24; i++) if (global.B_spr[d * 24 + i]) global.B_spr[d * 24 + i].SetOpacity(0);
}}

fun build_scene(d) {{
  sw = Window.GetWidth(d);
  sh = Window.GetHeight(d);
  x0 = d * global.SPAN;
  k = Math.Min(sw / {W}, sh / {H});
  kc = Math.Max(sw / {W}, sh / {H});
  ox = x0 + (sw - {W} * kc) / 2;
  oy = (sh - {H} * kc) / 2;
  global.S_sw[d] = sw; global.S_sh[d] = sh; global.S_x0[d] = x0; global.S_k[d] = k;

  # background: cover-scaled so the eyes stay aligned with the glow sprites
  global.S_bg[d] = Sprite(scaled(global.bg_src, kc));
  global.S_bg[d].SetPosition(ox, oy, 0);
  global.S_bg[d].SetOpacity(0);

  eye = scaled(global.eye_src, kc);
  global.S_eye0[d] = Sprite(eye);
  global.S_eye0[d].SetPosition(ox + {EYES[0][0]} * kc - eye.GetWidth() / 2, oy + {EYES[0][1]} * kc - eye.GetHeight() / 2, 5);
  global.S_eye0[d].SetOpacity(0);
  global.S_eye1[d] = Sprite(eye);
  global.S_eye1[d].SetPosition(ox + {EYES[1][0]} * kc - eye.GetWidth() / 2, oy + {EYES[1][1]} * kc - eye.GetHeight() / 2, 5);
  global.S_eye1[d].SetOpacity(0);

  # lockup + halo: contain-scaled, anchored to the left third, always fully on screen
  lock = scaled(global.lock_src, k);
  halo = scaled(global.halo_src, k);
  lcx = x0 + sw * {CX / W:.4f};
  lcy = sh * {CY / H:.4f};
  global.S_lcx[d] = lcx;
  global.S_lock_y[d] = lcy - lock.GetHeight() / 2;
  global.S_lock[d] = Sprite(lock);
  global.S_lock[d].SetPosition(lcx - lock.GetWidth() / 2, global.S_lock_y[d], 20);
  global.S_lock[d].SetOpacity(0);
  global.S_halo[d] = Sprite(halo);
  global.S_halo[d].SetPosition(lcx - halo.GetWidth() / 2, global.S_lock_y[d] + 95 * k - halo.GetHeight() / 2, 19);
  global.S_halo[d].SetOpacity(0);

  # progress
  global.S_bar_w[d] = {BAR_W} * k;
  global.S_bar_x[d] = lcx - global.S_bar_w[d] / 2;
  global.S_bar_y[d] = sh * {BAR_Y / H:.4f};
  global.S_track[d] = Sprite(global.track_src.Scale(Math.Int(global.S_bar_w[d]), Math.Int(4 * k + 0.5)));
  global.S_track[d].SetPosition(global.S_bar_x[d], global.S_bar_y[d], 20);
  global.S_track[d].SetOpacity(0);
  global.S_fill[d] = Sprite();
  global.S_fill[d].SetPosition(global.S_bar_x[d], global.S_bar_y[d], 21);
  global.S_head_img[d] = scaled(global.head_src, k);
  global.S_head[d] = Sprite(global.S_head_img[d]);
  global.S_head[d].SetOpacity(0);

  # status message
  global.S_msg[d] = Sprite();
  global.S_msg[d].SetPosition(lcx, global.S_bar_y[d] + 34 * k, 22);

  # embers
  for (i = 0; i < 3; i++) emb[i] = scaled(global.emb_src[i], k);
  for (i = 0; i < global.NEMB; i++) {{
    j = d * global.NEMB + i;
    r = Math.Random();
    if (r < 0.5) e = emb[0]; else if (r < 0.8) e = emb[1]; else e = emb[2];
    global.E_spr[j] = Sprite(e);
    global.E_spr[j].SetZ(10);
    global.E_spr[j].SetOpacity(0);
    global.E_x[j] = Math.Random() * sw;
    global.E_y[j] = sh * (0.35 + Math.Random() * 0.75);
    global.E_speed[j] = (0.35 + Math.Random() * 0.9) * k;
    global.E_phase[j] = Math.Random() * 6.283;
    global.E_peak[j] = 0.35 + Math.Random() * 0.55;
  }}

  # shutdown / reboot caption
  if (!global.booting) {{
    bye = scaled(global.bye_src, k);
    global.S_bye[d] = Sprite(bye);
    global.S_bye[d].SetPosition(lcx - bye.GetWidth() / 2, global.S_bar_y[d] - 10 * k, 20);
    global.S_bye[d].SetOpacity(0);
  }}

  # password card
  pw = scaled(global.pw_src, k);
  global.S_pw_x[d] = lcx - pw.GetWidth() / 2;
  global.S_pw_y[d] = sh * 0.6500;
  global.S_pw[d] = Sprite(pw);
  global.S_pw[d].SetPosition(global.S_pw_x[d], global.S_pw_y[d], 40);
  global.S_pw[d].SetOpacity(0);
  global.S_bullet_img[d] = scaled(global.bullet_src, k);
}}

fun sync_displays() {{
  n = 0;
  while (n < 8 && Window.GetWidth(n)) n++;
  if (n < 1) return;
  for (d = 0; d < n; d++)
    if (Window.GetX(d) != d * global.SPAN || Window.GetY(d) != 0) {{
      Window.SetX(d, d * global.SPAN);
      Window.SetY(d, 0);
    }}
  changed = (n != global.ndisp);
  for (d = 0; d < n; d++)
    if (d < global.ndisp)
      if (Window.GetWidth(d) != global.S_sw[d] || Window.GetHeight(d) != global.S_sh[d]) changed = 1;
  if (!changed) return;
  for (d = 0; d < global.ndisp; d++) hide_scene(d);
  for (d = 0; d < n; d++) build_scene(d);
  global.ndisp = n;
  if (global.msg_text != "") message_cb(global.msg_text);
  if (global.pw_count >= 0) password_cb("", global.pw_count);
}}

fun message_cb(text) {{
  global.msg_text = text;
  img = Image.Text(text, {P['mist'][0]}, {P['mist'][1]}, {P['mist'][2]}, 1, "Inter 13");
  for (d = 0; d < global.ndisp; d++) {{
    global.S_msg[d].SetImage(img);
    global.S_msg[d].SetX(global.S_lcx[d] - img.GetWidth() / 2);
    global.S_msg[d].SetOpacity(1);
  }}
}}
Plymouth.SetMessageFunction(message_cb);

sync_displays();

# ---------- frame loop (50 Hz)
frame = 0;
progress = 0;
target_progress = 0;
fun refresh_cb() {{
  sync_displays();
  global.frame++;
  t = global.frame / 50;
  bg_a = ease_out(t / 1.2);
  a = ease_out(ramp(t, 0.4, 1.4));
  halo_a = a * (0.55 + 0.30 * Math.Sin(t * 2.0));
  # heartbeat: two quick beats then rest, 2.2 s period
  beat = Math.Sin(t * 6.283 / 2.2);
  if (beat < 0) beat = 0;
  eye_a = ramp(t, 0.9, 1.7) * (0.55 + 0.45 * beat * beat);
  emb_a = ramp(t, 0.6, 1.6);
  b = ramp(t, 0.9, 1.5);
  global.progress += (global.target_progress - global.progress) * 0.06;

  for (d = 0; d < global.ndisp; d++) {{
    k = global.S_k[d];
    sw = global.S_sw[d];
    sh = global.S_sh[d];
    x0 = global.S_x0[d];
    global.S_bg[d].SetOpacity(bg_a);
    global.S_lock[d].SetOpacity(a);
    global.S_lock[d].SetY(global.S_lock_y[d] + (1 - a) * 28 * k);
    global.S_halo[d].SetOpacity(halo_a);
    global.S_eye0[d].SetOpacity(eye_a);
    global.S_eye1[d].SetOpacity(eye_a);

    for (i = 0; i < global.NEMB; i++) {{
      j = d * global.NEMB + i;
      global.E_y[j] -= global.E_speed[j];
      if (global.E_y[j] < sh * 0.15) {{ global.E_y[j] = sh * (1.0 + Math.Random() * 0.1); global.E_x[j] = Math.Random() * sw; }}
      y = global.E_y[j];
      life = clamp((sh - y) / (sh * 0.5), 0, 1) * clamp((y - sh * 0.15) / (sh * 0.25), 0, 1);
      global.E_spr[j].SetX(x0 + global.E_x[j] + Math.Sin(t * 0.9 + global.E_phase[j]) * 18 * k);
      global.E_spr[j].SetY(y);
      global.E_spr[j].SetOpacity(life * global.E_peak[j] * emb_a);
    }}

    if (global.booting) {{
      global.S_track[d].SetOpacity(b * 0.9);
      w = Math.Int(global.S_bar_w[d] * global.progress);
      if (w >= 1) {{
        global.S_fill[d].SetImage(global.fill_src.Scale(w, Math.Int(4 * k + 0.5)));
        global.S_fill[d].SetOpacity(b);
        hi = global.S_head_img[d];
        global.S_head[d].SetPosition(global.S_bar_x[d] + w - hi.GetWidth() / 2,
                                     global.S_bar_y[d] + 2 * k - hi.GetHeight() / 2, 23);
        global.S_head[d].SetOpacity(b * (0.75 + 0.25 * Math.Sin(t * 5)));
      }}
    }} else {{
      global.S_bye[d].SetOpacity(ramp(t, 0.6, 1.4));
    }}
  }}
}}
Plymouth.SetRefreshFunction(refresh_cb);

fun progress_cb(duration, progress) {{
  if (progress > global.target_progress) global.target_progress = progress;
}}
Plymouth.SetBootProgressFunction(progress_cb);

# ---------- password prompt
fun password_cb(prompt, count) {{
  if (count > 24) count = 24;
  global.pw_count = count;
  for (d = 0; d < global.ndisp; d++) {{
    k = global.S_k[d];
    bi = global.S_bullet_img[d];
    global.S_pw[d].SetOpacity(1);
    for (i = 0; i < 24; i++) {{
      j = d * 24 + i;
      if (i < count) {{
        if (!global.B_spr[j]) global.B_spr[j] = Sprite(bi);
        global.B_spr[j].SetImage(bi);
        global.B_spr[j].SetPosition(global.S_pw_x[d] + (64 + i * 22) * k,
                                    global.S_pw_y[d] + 138 * k - bi.GetHeight() / 2, 41);
        global.B_spr[j].SetOpacity(1);
      }} else if (global.B_spr[j]) global.B_spr[j].SetOpacity(0);
    }}
  }}
}}
fun normal_cb() {{
  global.pw_count = -1;
  for (d = 0; d < global.ndisp; d++) {{
    global.S_pw[d].SetOpacity(0);
    for (i = 0; i < 24; i++) if (global.B_spr[d * 24 + i]) global.B_spr[d * 24 + i].SetOpacity(0);
  }}
}}
Plymouth.SetDisplayPasswordFunction(password_cb);
Plymouth.SetDisplayNormalFunction(normal_cb);
"""
open(f"{OUT}/bapirlo.script", "w").write(script)
open(f"{OUT}/bapirlo.plymouth", "w").write("""[Plymouth Theme]
Name=Bapirlo OS
Description=Bapirlo OS "Kuro awakens": fade-up artwork, igniting eyes, rising embers, glowing progress
ModuleName=script
Font=Inter Medium 13
MonospaceFont=JetBrainsMono Nerd Font Mono 12

[script]
ImageDir=/usr/share/plymouth/themes/bapirlo
ScriptFile=/usr/share/plymouth/themes/bapirlo/bapirlo.script
""")

# ------------------------------------------------------------------ GIF preview (same timeline)
PS = 0.3                                         # preview scale -> 768x480
pw_, ph_ = int(W * PS), int(H * PS)
bgp = bg.resize((pw_, ph_), Image.LANCZOS).convert("RGBA")
def sc(im): return im.resize((max(1, int(im.width * PS)), max(1, int(im.height * PS))), Image.LANCZOS)
eyep, lockp, halop, headp = sc(eye), sc(lock), sc(halo), sc(head)
emb = [sc(Image.open(f"{OUT}/ember-{c}.png")) for c in "abc"]
fillp = sc(Image.open(f"{OUT}/fill.png"))
def with_alpha(im, a):
    im = im.copy(); im.putalpha(im.split()[3].point(lambda v: int(v * max(0, min(1, a))))); return im
def ramp(t, a, b): return max(0, min(1, (t - a) / (b - a)))
def ease(t): t = max(0, min(1, t)); return 1 - (1 - t) ** 3
random.seed(3)
ems = [dict(x=random.random() * pw_, y=ph_ * (.35 + random.random() * .75), s=(.35 + random.random() * .9) * PS * 2.5,
            ph=random.random() * 6.28, pk=.35 + random.random() * .55, im=random.choice(emb)) for _ in range(N_EMBERS)]
frames, target, shown, FPS = [], 0.0, 0.0, 15
for f in range(int(4.4 * FPS)):
    t = f / FPS
    fr = Image.new("RGBA", (pw_, ph_), (0, 0, 0, 255))
    fr.alpha_composite(with_alpha(bgp, ease(t / 1.2)))
    for e in ems:
        e["y"] -= e["s"]
        if e["y"] < ph_ * .15: e["y"] = ph_ * (1 + random.random() * .1); e["x"] = random.random() * pw_
        life = max(0, min(1, (ph_ - e["y"]) / (ph_ * .5))) * max(0, min(1, (e["y"] - ph_ * .15) / (ph_ * .25)))
        fr.alpha_composite(with_alpha(e["im"], life * e["pk"] * ramp(t, .6, 1.6)),
                           (int(e["x"] + math.sin(t * .9 + e["ph"]) * 9), int(e["y"])))
    beat = max(0, math.sin(t * 6.283 / 2.2))
    ea = ramp(t, .9, 1.7) * (.55 + .45 * beat * beat)
    for ex, ey in EYES:
        fr.alpha_composite(with_alpha(eyep, ea), (int(ex * PS - eyep.width / 2), int(ey * PS - eyep.height / 2)))
    a = ease(ramp(t, .4, 1.4))
    lx, ly = int(CX * PS - lockp.width / 2), int(CY * PS - lockp.height / 2 + (1 - a) * 28 * PS)
    fr.alpha_composite(with_alpha(halop, a * (.55 + .3 * math.sin(t * 2))),
                       (int(CX * PS - halop.width / 2), int(CY * PS - lockp.height / 2 + 95 * PS - halop.height / 2)))
    fr.alpha_composite(with_alpha(lockp, a), (lx, ly))
    target = min(1, t / 4.0) ** .8
    for _ in range(50 // FPS): shown += (target - shown) * .06
    b = ramp(t, .9, 1.5)
    bx, by = int((CX - BAR_W / 2) * PS), int(BAR_Y * PS)
    dr = ImageDraw.Draw(fr)
    dr.rectangle([bx, by, bx + int(BAR_W * PS), by + 1], fill=rgb("surface") + (int(230 * b),))
    w = int(BAR_W * PS * shown)
    if w > 1:
        fr.alpha_composite(with_alpha(fillp.resize((w, 2)), b), (bx, by))
        fr.alpha_composite(with_alpha(headp, b), (bx + w - headp.width // 2, by + 1 - headp.height // 2))
    frames.append(fr.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
pdir = f"{HOME}/bapirlo-os/build/plymouth-v2"
frames[0].save(f"{pdir}/preview.gif", save_all=True, append_images=frames[1:], duration=1000 // FPS, loop=0, optimize=False)
for i in (6, 22, 60):
    frames[i].convert("RGB").save(f"{pdir}/frame-{i:02d}.png")
# password state still
st = frames[-1].convert("RGBA")
pwp = sc(Image.open(f"{OUT}/password.png")); st.alpha_composite(pwp, (int(CX * PS - pwp.width / 2), int(1040 * PS)))
bp = sc(Image.open(f"{OUT}/bullet.png"))
for i in range(9): st.alpha_composite(bp, (int(CX * PS - pwp.width / 2 + (64 + i * 22) * PS), int((1040 + 138) * PS - bp.height / 2)))
st.convert("RGB").save(f"{pdir}/frame-password.png")
print("Plymouth v2 built in", OUT)
