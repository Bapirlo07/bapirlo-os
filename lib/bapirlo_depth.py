#!/usr/bin/env python3
"""Kuro OS — depth maps for the 3D wallpaper (bapirlo-live "depth" setting).
Depth Anything V2 Small (ONNX, CPU, ~1-2 s per picture) guesses how far away each pixel of the wallpaper
is; the live extension's shader then moves near things more than far things as the pointer moves.
  python3 bapirlo_depth.py IMAGE OUT.png     (run with the depth venv's python — see DEPTH_PY)
  python3 bapirlo_depth.py --setup           make the venv + download the model (~100 MB, once)
Output: 8-bit grey PNG, 1024 px on the long side, white = near. Lightly blurred, and near areas are
grown a few pixels so a foreground edge drags its own colour rather than tearing the background.
From the library side use depth_for(still) — cached per picture, returns the PNG path.
"""
import hashlib
import os
import subprocess
import sys

DATA = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "bapirlo")
VENV = os.path.join(DATA, "depth-venv")
DEPTH_PY = os.path.join(VENV, "bin", "python")
MODEL = os.path.join(DATA, "models", "depth-anything-v2-small.onnx")
MODEL_URL = "https://huggingface.co/onnx-community/depth-anything-v2-small/resolve/main/onnx/model.onnx"
MODEL_SHA256 = "afb6a5c28f3b6bf1618c6e43f02073ef9dfdc70e937502d51603e57b0a1df10c"
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "bapirlo", "wallpaper", "depth")
NET = 518           # the model's training size (short side), a multiple of its 14 px patches
OUT_LONG = 1024


def ready():
    return os.path.exists(DEPTH_PY) and os.path.exists(MODEL)


def setup():
    if not os.path.exists(DEPTH_PY):
        subprocess.run([sys.executable, "-m", "venv", "--system-site-packages", VENV], check=True)
    subprocess.run([DEPTH_PY, "-m", "pip", "install", "-q", "onnxruntime", "numpy", "pillow"], check=True)
    if not os.path.exists(MODEL):
        os.makedirs(os.path.dirname(MODEL), exist_ok=True)
        tmp = MODEL + ".part"
        subprocess.run(["curl", "-sSLf", "-o", tmp, MODEL_URL], check=True)
        h = hashlib.sha256()
        with open(tmp, "rb") as f:
            for b in iter(lambda: f.read(1 << 20), b""):
                h.update(b)
        if h.hexdigest() != MODEL_SHA256:
            os.remove(tmp)
            raise SystemExit("depth model download is corrupt (sha256 mismatch)")
        os.replace(tmp, MODEL)


def key(path):
    st = os.stat(path)
    return hashlib.sha1(f"{path}\0{st.st_mtime_ns}\0{st.st_size}".encode()).hexdigest()[:16]


def depth_for(still):
    """Cached depth PNG for a picture (runs the model in the venv if needed). None if not set up."""
    out = os.path.join(CACHE, key(still) + ".png")
    if os.path.exists(out):
        return out
    if not ready():
        return None
    os.makedirs(CACHE, exist_ok=True)
    subprocess.run([DEPTH_PY, "-I", os.path.realpath(__file__), still, out], check=True, timeout=300,
                   stdin=subprocess.DEVNULL)
    return out


def prune(keep):
    if not os.path.isdir(CACHE):
        return
    for f in os.listdir(CACHE):
        if os.path.join(CACHE, f) not in keep:
            os.remove(os.path.join(CACHE, f))


def estimate(src, out):
    import numpy as np
    import onnxruntime as ort
    from PIL import Image, ImageFilter

    img = Image.open(src).convert("RGB")
    s = NET / min(img.size)
    w, h = (max(14, round(d * s / 14) * 14) for d in img.size)
    x = np.asarray(img.resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0
    x = (x - [0.485, 0.456, 0.406]) / [0.229, 0.224, 0.225]
    x = x.transpose(2, 0, 1)[None].astype(np.float32)

    opts = ort.SessionOptions()
    opts.log_severity_level = 3
    sess = ort.InferenceSession(MODEL, opts, providers=["CPUExecutionProvider"])
    d = sess.run(None, {sess.get_inputs()[0].name: x})[0][0]      # relative inverse depth: big = near

    lo, hi = np.percentile(d, [2, 98])
    d = np.clip((d - lo) / max(hi - lo, 1e-6), 0, 1)
    s = OUT_LONG / max(img.size)
    size = (round(img.width * s), round(img.height * s))
    g = Image.fromarray((d * 255).astype(np.uint8)).resize(size, Image.BICUBIC)
    g = g.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(2))
    tmp = out + ".part.png"
    g.save(tmp, optimize=True)
    os.replace(tmp, out)


if __name__ == "__main__":
    if sys.argv[1:] == ["--setup"]:
        setup()
    elif len(sys.argv) == 3:
        estimate(sys.argv[1], sys.argv[2])
    else:
        print(__doc__.strip())
        sys.exit(2)
