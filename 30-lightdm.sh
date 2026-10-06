#!/usr/bin/env bash
# Bapirlo OS — step 8: LightDM slick-greeter theme (run with sudo).
# The greeter runs as the 'lightdm' user, so theme/icons/cursor/art are copied system-wide.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
U_HOME=$(getent passwd "${SUDO_USER:?run via sudo}" | cut -d: -f6)
BK="$U_HOME/theme-backups/$(cat "$U_HOME/theme-backups/LATEST")/system"
[ -f "$BK/etc/lightdm/lightdm.conf" ] || { echo "Backup missing — run 00-backup-system.sh first."; exit 1; }
LOG="$BK/installed-system-paths.txt"   # restore.sh removes everything listed here

put() {  # put SRC DEST — copy (replacing) and record DEST for restore
  rm -rf "$2"; cp -a "$1" "$2"; chown -R root:root "$2"; chmod -R a+rX "$2"
  grep -qxF "$2" "$LOG" 2>/dev/null || echo "$2" >> "$LOG"
  echo "  installed $2"
}

echo "== 1. System-wide theme, icons, cursor"
for t in WhiteSur-Dark-red; do
  [ -e "/usr/share/themes/$t" ] && ! grep -qxF "/usr/share/themes/$t" "$LOG" 2>/dev/null \
    && { echo "  /usr/share/themes/$t exists and isn't ours — leaving it"; continue; }
  put "$U_HOME/.themes/$t" "/usr/share/themes/$t"
done
for t in WhiteSur-red WhiteSur-red-dark WhiteSur-cursors Bapirlo; do
  [ -e "/usr/share/icons/$t" ] && ! grep -qxF "/usr/share/icons/$t" "$LOG" 2>/dev/null \
    && { echo "  /usr/share/icons/$t exists and isn't ours — leaving it"; continue; }
  put "$U_HOME/.local/share/icons/$t" "/usr/share/icons/$t"
done
# Bapirlo icon theme's logo files live in the user's assets; make them self-contained copies
find /usr/share/icons/Bapirlo -type l -exec sh -c 'cp --remove-destination "$(readlink -f "$1")" "$1"' _ {} \;
gtk-update-icon-cache -q -f /usr/share/icons/Bapirlo || true

echo "== 2. Login art"
mkdir -p /usr/share/backgrounds/bapirlo
grep -qxF /usr/share/backgrounds/bapirlo "$LOG" 2>/dev/null || echo /usr/share/backgrounds/bapirlo >> "$LOG"
install -m 644 "$U_HOME/bapirlo-os/build/lightdm/login.png" /usr/share/backgrounds/bapirlo/login.png
install -m 644 "$U_HOME/bapirlo-os/build/lightdm/badge.png" /usr/share/backgrounds/bapirlo/badge.png

echo "== 3. /etc/lightdm/slick-greeter.conf"
cat > /etc/lightdm/slick-greeter.conf <<'EOF'
# Bapirlo OS login screen
[Greeter]
background=/usr/share/backgrounds/bapirlo/login.png
background-color=#0b0b0d
draw-user-backgrounds=false
draw-grid=false
content-align=left
logo=/usr/share/backgrounds/bapirlo/badge.png
theme-name=WhiteSur-Dark-red
icon-theme-name=Bapirlo
cursor-theme-name=WhiteSur-cursors
cursor-theme-size=24
font-name=Inter 11
enable-hidpi=auto
show-hostname=false
show-clock=true
clock-format=%H:%M  ·  %a %d %b
show-a11y=true
show-keyboard=true
show-power=true
show-quit=true
EOF
chmod 644 /etc/lightdm/slick-greeter.conf

echo "== 4. Checks"
grep -q '^greeter-session=lightdm-slick-greeter' /etc/lightdm/lightdm.conf && echo "  OK   lightdm still uses slick-greeter"
for f in /usr/share/backgrounds/bapirlo/login.png /usr/share/backgrounds/bapirlo/badge.png \
         /usr/share/themes/WhiteSur-Dark-red/gtk-3.0/gtk.css /usr/share/icons/Bapirlo/index.theme \
         /usr/share/icons/WhiteSur-cursors/index.theme; do
  sudo -u lightdm test -r "$f" && echo "  OK   lightdm can read $f" || echo "  FAIL lightdm cannot read $f"
done
echo "LightDM done. (lightdm.conf itself was not changed.)"
