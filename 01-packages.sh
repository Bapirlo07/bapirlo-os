#!/usr/bin/env bash
# Kuro OS — step 1: official-repo packages only (run with sudo).
set -euo pipefail
pacman -S --needed --noconfirm \
  paru extension-manager \
  gnome-shell-extensions gnome-shell-extension-dash-to-dock \
  gnome-shell-extension-arc-menu gnome-shell-extension-appindicator \
  clapper gst-plugins-bad gst-libav \
  inter-font ttf-jetbrains-mono-nerd papirus-icon-theme \
  sassc libxml2 python-pillow
echo "Repo packages installed."
