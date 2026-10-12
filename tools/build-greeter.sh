#!/usr/bin/env bash
# Builds the web-greeter theme's images from the hero art (never committed: third-party fan art).
#   img/bg.jpg      2560x1600 hero (Real-ESRGAN upscale from 60-desktop-v2), q90
#   img/avatar.png  fallback avatar = your AccountsService picture, else the logo on ink
set -euo pipefail
cd "$(dirname "$0")/.."
T=greeter/bapirlo/img
src=build/art/hero-2560x1600.png
[ -f "$src" ] || src=$(readlink -f ~/.config/bapirlo/hero-wallpaper)
magick "$src" -resize 2560x1600^ -gravity center -extent 2560x1600 -strip -quality 90 "$T/bg.jpg"
face=/var/lib/AccountsService/icons/$USER
if [ -r "$face" ]; then
  magick "$face" -resize 512x512^ -gravity center -extent 512x512 "$T/avatar.png"
else
  magick -size 512x512 xc:'#0E0A0D' \( "$T/logo.svg" -resize 300x300 \) -gravity center -composite "$T/avatar.png"
fi
ls -la "$T"
