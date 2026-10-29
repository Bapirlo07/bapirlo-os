#!/usr/bin/env bash
# Kuro OS — packages for "play videos from any app on the laptop" (bapirlo-play).
# Run once:  sudo bash ~/bapirlo-os/930-play-anything.sh
#   yt-dlp     turns links from YouTube, TikTok, Instagram, X, Reddit, Twitch… into playable video
#   mpv-mpris  lets the phone's "Play / Pause" command (playerctl) control the mpv window
# The rest (GSConnect share hook, phone commands, AirPlay video casting) needs no root and is
# already set up by bapirlo-iphone setup / bapirlo-airplay.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
pacman -S --needed --noconfirm yt-dlp mpv-mpris
echo
echo "Done. iPhone: Share → KDE Connect → Kuro OS on any video link."
