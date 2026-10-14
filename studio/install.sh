#!/usr/bin/env bash
# Bapirlo OS Theme Studio — install / remove.
#   bash ~/bapirlo-os/studio/install.sh             # you (no sudo): app, Start menu entry, Super+Alt+T, folder
#                                                   # watcher, shell extension, Control Centre tile
#   sudo bash ~/bapirlo-os/studio/install.sh root   # once: lock/login screen folder + boot splash helper
#   bash ~/bapirlo-os/studio/install.sh restore     # undo the user part (switch to Original first)
#   sudo bash ~/bapirlo-os/studio/install.sh restore-root
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
OS=$(dirname "$HERE")

if [ "${1:-}" = root ] || [ "${1:-}" = restore-root ]; then
  [ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
  U=${SUDO_USER:?run through sudo from your account}
  UH=$(getent passwd "$U" | cut -d: -f6)
  G=/usr/share/web-greeter/themes/bapirlo
  HELPER=/usr/local/lib/bapirlo/bapirlo-studio-boot
  POLICY=/usr/share/polkit-1/actions/os.bapirlo.studio-boot.policy
  if [ "$1" = restore-root ]; then
    BK=$(cat "$UH/theme-backups/LATEST-STUDIO-ROOT")
    cp -a "$BK/index.html" "$G/index.html"
    rm -rf "$G/studio" "$HELPER" "$POLICY"
    echo "Removed. The boot splash stays as it is — apply Original in Theme Studio first to reset it."
    exit 0
  fi
  BK=$UH/theme-backups/$(date +%Y%m%d-%H%M%S)-studio-root
  install -d -o "$U" -g "$(id -gn "$U")" "$BK"
  cp -a "$G/index.html" "$BK/"
  echo "$BK" > "$UH/theme-backups/LATEST-STUDIO-ROOT"; chown "$U:" "$UH/theme-backups/LATEST-STUDIO-ROOT"
  # 1. lock / login screen: one folder you own; its stylesheet loads after the theme's own
  install -d -o "$U" -g "$(id -gn "$U")" -m 755 "$G/studio"
  [ -f "$G/studio/studio.css" ] || install -o "$U" -g "$(id -gn "$U")" -m 644 /dev/null "$G/studio/studio.css"
  grep -q 'href="studio/studio.css"' "$G/index.html" ||
    sed -i 's|<link rel="stylesheet" href="css/style.css">|&\n  <link rel="stylesheet" href="studio/studio.css">|' "$G/index.html"
  grep -q 'href="studio/studio.css"' "$G/index.html" || { cp -a "$BK/index.html" "$G/index.html"; echo "!! couldn't add the stylesheet link"; exit 1; }
  # 2. boot splash helper (root-owned copy; pkexec always asks for your password)
  install -d -m 755 /usr/local/lib/bapirlo
  install -o root -g root -m 755 "$HERE/root/bapirlo-studio-boot" "$HELPER"
  install -o root -g root -m 644 "$HERE/root/os.bapirlo.studio-boot.policy" "$POLICY"
  echo "Done: $G/studio (yours), $HELPER, $POLICY. Backup: $BK"
  exit 0
fi

[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo (sudo only for: install.sh root)."; exit 1; }
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
EXT=$DATA/gnome-shell/extensions
UNITS=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
DESKTOP=$DATA/applications/os.bapirlo.ThemeStudio.desktop
ICONS=$DATA/icons
MK=org.gnome.settings-daemon.plugins.media-keys
KEY=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/bapirlo-studio/
BINDING='<Super><Alt>t'
CCS=org.gnome.shell.extensions.bapirlo-control-centre
CC=bapirlo-control-centre@bapirlo-os
MEDIA=bapirlo-media@bapirlo-os
STUDIO=bapirlo-studio@bapirlo-os

ext_list() {   # add | remove UUID → enabled-extensions
  python3 - "$1" "$2" <<'EOF'
import ast, subprocess, sys
op, uuid = sys.argv[1:]
v = subprocess.run(["gsettings", "get", "org.gnome.shell", "enabled-extensions"], capture_output=True, text=True).stdout.strip()
en = ast.literal_eval(v.replace("@as ", "")) if v not in ("", "@as []") else []
en = [e for e in en if e != uuid] + ([uuid] if op == "add" else [])
subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(en)], check=True)
EOF
}
cc_tiles() {   # add | remove 'studio' in the Control Centre's tile list
  python3 - "$1" "$EXT/$CC/schemas" <<'EOF'
import ast, subprocess, sys
op, sd = sys.argv[1:]
g = ["gsettings", "--schemadir", sd]
v = subprocess.run(g + ["get", "org.gnome.shell.extensions.bapirlo-control-centre", "tiles"], capture_output=True, text=True).stdout.strip()
t = [x for x in ast.literal_eval(v.replace("@as ", "")) if x != "studio"]
if op == "add":
    t.insert(t.index("vault") + 1 if "vault" in t else len(t), "studio")
subprocess.run(g + ["set", "org.gnome.shell.extensions.bapirlo-control-centre", "tiles", str(t)], check=True)
EOF
}

if [ "${1:-}" = restore ]; then
  BK=$(cat ~/theme-backups/LATEST-STUDIO)
  [ -f ~/.local/state/bapirlo/studio/active.json ] && { echo "Switch to Original Bapirlo OS in Theme Studio first."; exit 1; }
  systemctl --user disable --now bapirlo-studio-watch.path 2>/dev/null || true
  rm -f "$UNITS/bapirlo-studio-watch.path" "$UNITS/bapirlo-studio-watch.service" "$DESKTOP"
  systemctl --user daemon-reload
  ext_list remove "$STUDIO"; rm -rf "${EXT:?}/$STUDIO"
  for e in $CC $MEDIA; do [ -d "$BK/$e" ] && { rm -rf "${EXT:?}/$e"; cp -a "$BK/$e" "$EXT/$e"; }; done
  dconf load / < "$BK/dconf.ini"
  gsettings set $MK custom-keybindings "$(cat "$BK/custom-keybindings.txt")"
  dconf reset -f "$KEY"
  echo "Removed (your saved themes stay in $DATA/bapirlo/theme-studio). Log out and back in."
  exit 0
fi

# ------------------------------------------------------------------ install (you)
conflict=$(gsettings list-recursively 2>/dev/null | grep -i -E "'(<Super><Alt>|<Alt><Super>)t'" | grep -v bapirlo-studio || true)
if [ -n "$conflict" ]; then echo "Super+Alt+T is already used:"; echo "$conflict"; exit 1; fi

BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-studio
mkdir -p "$BK"
for e in $CC $MEDIA $STUDIO; do [ -d "$EXT/$e" ] && cp -a "$EXT/$e" "$BK/"; done
gsettings get $MK custom-keybindings > "$BK/custom-keybindings.txt"
{ echo "[org/gnome/shell]"; echo "enabled-extensions=$(gsettings get org.gnome.shell enabled-extensions)"
  echo "[org/gnome/shell/extensions/bapirlo-control-centre]"
  echo "tiles=$(gsettings --schemadir "$EXT/$CC/schemas" get $CCS tiles)"; } > "$BK/dconf.ini"
echo "$BK" > ~/theme-backups/LATEST-STUDIO
echo "backup -> $BK"

echo "== app, icons, Start menu"
chmod 755 "$HERE/bapirlo-studio" "$HERE/bapirlo-theme-studio"
mkdir -p "$HOME/Pictures/Theme Studio"
install -Dm644 "$HERE/icons/bapirlo-studio.svg" "$ICONS/Bapirlo/scalable/apps/bapirlo-studio.svg"
install -Dm644 "$HERE/icons/bapirlo-studio.svg" "$ICONS/hicolor/scalable/apps/bapirlo-studio.svg"
install -Dm644 "$HERE/icons/bapirlo-studio-symbolic.svg" "$ICONS/Bapirlo/symbolic/apps/bapirlo-studio-symbolic.svg"
install -Dm644 "$HERE/icons/bapirlo-studio-symbolic.svg" "$ICONS/hicolor/symbolic/apps/bapirlo-studio-symbolic.svg"
for t in Bapirlo hicolor; do gtk-update-icon-cache -q -t "$ICONS/$t" 2>/dev/null || true; done
install -Dm644 /dev/stdin "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Theme Studio
GenericName=Wallpaper theming
Comment=Re-theme Bapirlo OS from a wallpaper: preview, apply, and switch between saved themes
Exec=$HERE/bapirlo-theme-studio %f
Icon=bapirlo-studio
Terminal=false
Categories=Settings;DesktopSettings;GTK;
MimeType=image/jpeg;image/png;image/webp;
Keywords=theme;colour;color;accent;wallpaper;palette;matugen;bapirlo;
StartupWMClass=os.bapirlo.ThemeStudio
StartupNotify=true
EOF
update-desktop-database -q "$DATA/applications" 2>/dev/null || true

echo "== shortcut: Super+Alt+T"
dconf write "${KEY}name" "'Theme Studio'"
dconf write "${KEY}command" "'$HERE/bapirlo-theme-studio'"
dconf write "${KEY}binding" "'$BINDING'"
python3 - "$KEY" <<'EOF'
import ast, subprocess, sys
mk = "org.gnome.settings-daemon.plugins.media-keys"
v = subprocess.run(["gsettings", "get", mk, "custom-keybindings"], capture_output=True, text=True).stdout.strip()
l = ast.literal_eval(v.replace("@as ", "")) if v not in ("", "@as []") else []
if sys.argv[1] not in l:
    subprocess.run(["gsettings", "set", mk, "custom-keybindings", str(l + [sys.argv[1]])], check=True)
EOF

echo "== folder watcher: a new picture in ~/Pictures/Theme Studio → \"Preview theme\" notification"
mkdir -p "$UNITS"
cat > "$UNITS/bapirlo-studio-watch.path" <<'EOF'
[Unit]
Description=Bapirlo Theme Studio: watch ~/Pictures/Theme Studio

[Path]
PathChanged=%h/Pictures/Theme Studio
Unit=bapirlo-studio-watch.service

[Install]
WantedBy=default.target
EOF
cat > "$UNITS/bapirlo-studio-watch.service" <<EOF
[Unit]
Description=Bapirlo Theme Studio: offer a preview of a new wallpaper

[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 2
ExecStart=$HERE/bapirlo-studio notify-new
TimeoutStartSec=15min
Nice=10
EOF
systemctl --user daemon-reload
systemctl --user enable --now bapirlo-studio-watch.path
# the accent watcher was started before it learnt about Theme Studio palettes
systemctl --user try-restart bapirlo-autotheme.service 2>/dev/null || true

echo "== shell extensions: Theme Studio (fade), Control Centre tile, media frost tint"
rm -rf "${EXT:?}/$STUDIO"; cp -rL "$HERE/$STUDIO" "$EXT/$STUDIO"
for d in "$OS/control-centre/$CC" "$OS/media-widget/$MEDIA"; do rm -rf "${EXT:?}/$(basename "$d")"; cp -rL "$d" "$EXT/"; done
rm -rf "$EXT/$CC/test" "$EXT/$MEDIA/test"
glib-compile-schemas "$EXT/$CC/schemas"
ext_list add "$STUDIO"
cc_tiles add
echo
echo "Installed. Log out and back in once (GNOME loads new extension code at login)."
echo "Then: Super+Alt+T, Start menu → Theme Studio, or the Control Centre tile."
echo "For the lock/login screen and the boot splash, once:  sudo bash $HERE/install.sh root"
