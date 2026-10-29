#!/usr/bin/env bash
# Kuro OS — build a GNOME wallpaper slideshow from ~/Pictures/wallpapers.
# Runs automatically (systemd path unit) whenever that folder changes.
#   BAPIRLO_SLIDE_SECONDS  time per image (default 600 = 10 min)
set -euo pipefail
SRC=~/Pictures/wallpapers
OUT=~/.local/share/backgrounds/bapirlo
DEFAULT=$OUT/bapirlo-default.png
SLIDE=${BAPIRLO_SLIDE_SECONDS:-600}
FADE=2
mkdir -p "$OUT"

mapfile -d '' imgs < <(find "$SRC" -maxdepth 2 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
  -print0 2>/dev/null | shuf -z)

if [ ${#imgs[@]} -eq 0 ]; then
  imgs=("$DEFAULT")
fi

# New filename each run: GNOME caches slideshow XML by path.
xml=$OUT/slideshow-$(date +%s).xml
{
  echo '<background>'
  echo '  <starttime><year>2026</year><month>1</month><day>1</day><hour>0</hour><minute>0</minute><second>0</second></starttime>'
  n=${#imgs[@]}
  for ((i = 0; i < n; i++)); do
    cur=${imgs[$i]}; next=${imgs[$(((i + 1) % n))]}
    echo "  <static><duration>$SLIDE</duration><file>$cur</file></static>"
    [ "$n" -gt 1 ] && echo "  <transition type=\"overlay\"><duration>$FADE</duration><from>$cur</from><to>$next</to></transition>"
  done
  echo '</background>'
} > "$xml"

gsettings set org.gnome.desktop.background picture-uri "file://$xml"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$xml"
gsettings set org.gnome.desktop.background picture-options 'zoom'
gsettings set org.gnome.desktop.screensaver picture-uri "file://${imgs[0]}"
find "$OUT" -name 'slideshow-*.xml' ! -path "$xml" -delete
echo "Slideshow: ${#imgs[@]} image(s), ${SLIDE}s each -> $xml"
