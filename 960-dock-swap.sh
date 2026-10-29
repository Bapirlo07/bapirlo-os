#!/usr/bin/env bash
# Replace dash2dock-lite with Dash to Dock (GNOME 51 supported upstream).
# dash2dock-lite v92 crashed gnome-shell 20x (Clutter assert in clutter_actor_destroy_all_children
# from stock dash.js:77 while removing an app icon).
#   bash 960-dock-swap.sh           apply (backs up first)
#   bash 960-dock-swap.sh restore   back to dash2dock-lite
set -euo pipefail
OS=$(cd "$(dirname "$0")" && pwd)
OLD=dash2dock-lite@icedman.github.com
NEW=dash-to-dock@micxgx.gmail.com
list_without() { python3 -c 'import ast,sys; l=ast.literal_eval(sys.argv[1] or "[]"); print([x for x in l if x!=sys.argv[2]])' "$1" "$2"; }
list_with() { python3 -c 'import ast,sys; l=ast.literal_eval(sys.argv[1] or "[]"); print(l+[sys.argv[2]] if sys.argv[2] not in l else l)' "$1" "$2"; }
en() { gsettings get org.gnome.shell enabled-extensions | sed 's/^@as //'; }
dis() { gsettings get org.gnome.shell disabled-extensions | sed 's/^@as //'; }

if [ "${1:-}" = restore ]; then
  B=$(readlink -f ~/theme-backups/LATEST-DOCK-SWAP)
  gsettings set org.gnome.shell enabled-extensions "$(list_with "$(list_without "$(en)" "$NEW")" "$OLD")"
  gsettings set org.gnome.shell disabled-extensions "$(list_with "$(dis)" "$NEW")"
  dconf load /org/gnome/shell/extensions/dash2dock-lite/ < "$B/dash2dock-lite.dconf"
  echo "Restored dash2dock-lite (backup $B)."
  exit 0
fi

[ -d ~/.local/share/gnome-shell/extensions/$NEW ] || { echo "Install $NEW first (gnome-extensions install)"; exit 1; }
B=~/theme-backups/$(date +%Y%m%d-%H%M%S)-dock-swap
mkdir -p "$B"
dconf dump /org/gnome/shell/extensions/dash2dock-lite/ > "$B/dash2dock-lite.dconf"
dconf dump /org/gnome/shell/extensions/dash-to-dock/ > "$B/dash-to-dock.dconf"
gsettings get org.gnome.shell enabled-extensions > "$B/enabled-extensions.txt"
gsettings get org.gnome.shell disabled-extensions > "$B/disabled-extensions.txt"
ln -sfn "$B" ~/theme-backups/LATEST-DOCK-SWAP

dconf load /org/gnome/shell/extensions/dash-to-dock/ < "$OS/config/dash-to-dock-kuro.dconf"
gsettings set org.gnome.shell disabled-extensions "$(list_with "$(list_without "$(dis)" "$NEW")" "$OLD")"
gsettings set org.gnome.shell enabled-extensions "$(list_with "$(list_without "$(en)" "$OLD")" "$NEW")"
echo "Dock swapped (backup $B). Undo: bash $OS/960-dock-swap.sh restore"
