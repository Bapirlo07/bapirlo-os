#!/usr/bin/env bash
# Kuro OS round 5 — animated web login screen (web-greeter 4 + theme greeter/bapirlo).
# Run as YOURSELF (it asks for sudo itself). Each step is separate so nothing switches by surprise:
#
#   bash ~/bapirlo-os/500-round5-greeter.sh snapshot  # only the Timeshift snapshot "Before round 5"
#   bash ~/bapirlo-os/500-round5-greeter.sh install   # snapshot → backup → paru web-greeter → theme + config
#                                                     #   (your current slick-greeter stays ACTIVE)
#   bash ~/bapirlo-os/500-round5-greeter.sh preview   # real web-greeter engine, windowed, in your session
#   bash ~/bapirlo-os/500-round5-greeter.sh switch    # make it the login screen (takes effect on reboot)
#   bash ~/bapirlo-os/500-round5-greeter.sh theme     # re-copy the theme after editing it (no switch)
#   bash ~/bapirlo-os/500-round5-greeter.sh revert    # back to slick-greeter (web-greeter stays installed)
#   bash ~/bapirlo-os/500-round5-greeter.sh restore   # full undo: /etc/lightdm + session as before, theme gone
#
# From a TTY (Ctrl+Alt+F3) if the login screen ever fails:  sudo bapirlo-greeter-revert && sudo reboot
#
# Never touches Limine/GRUB, partitions, fstab or EFI.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as yourself, WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
THEME_SRC=$HERE/greeter/bapirlo
THEME_DST=/usr/share/web-greeter/themes/bapirlo
CONF=/etc/lightdm/lightdm.conf
WG_CONF=/etc/lightdm/web-greeter.toml
REVERT=/usr/local/bin/bapirlo-greeter-revert
LATEST=~/theme-backups/LATEST-ROUND5-GREETER
SNAP="Before round 5"

snapshot() {
  echo "== Timeshift snapshot \"$SNAP\" (incremental — a few minutes)"
  if sudo timeshift --list --scripted 2>/dev/null | grep -q "$SNAP"; then
    echo "already there:"
  else
    sudo timeshift --create --scripted --comments "$SNAP" --tags O
  fi
  sudo timeshift --list --scripted | grep "$SNAP" || { echo "!! snapshot missing — stopping, nothing changed."; exit 1; }
}

backup() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round5-greeter
  mkdir -p "$BK"
  sudo cp -a /etc/lightdm "$BK/etc-lightdm"
  [ -d /etc/xdg/lightdm ] && sudo cp -a /etc/xdg/lightdm "$BK/etc-xdg-lightdm" || true
  sudo cp -a "/var/lib/AccountsService/users/$USER" "$BK/accountsservice-user"
  [ -f ~/.dmrc ] && cp -a ~/.dmrc "$BK/dmrc" || true
  pacman -Q > "$BK/packages-before.txt"
  sudo chown -R "$USER:" "$BK"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"
}

install_theme() {
  bash "$HERE/tools/build-greeter.sh" >/dev/null
  sudo rm -rf "$THEME_DST"
  sudo mkdir -p "$(dirname "$THEME_DST")"
  sudo cp -r "$THEME_SRC" "$THEME_DST"
  sudo chmod -R a+rX "$THEME_DST"
  echo "theme -> $THEME_DST"
}

write_conf() {
  sudo tee "$WG_CONF" >/dev/null <<'EOF'
# Kuro OS — web-greeter config (written by 500-round5-greeter.sh; package default is in the backup)
layouts = ["gb"]

[greeter]
debug-mode = false
detect-theme-errors = true   # broken theme → offers the built-in fallback instead of a dead screen
screensaver-timeout = 120
secure-mode = true           # theme may not touch the network
theme = "bapirlo"
icon-theme = "Bapirlo"
time-language = "en-gb"

[features.battery]
enabled = false

[features.backlight]
enabled = false
value = 10
steps = 0

[branding]
background-images-dir = "/usr/share/backgrounds/bapirlo"
logo-image = "/usr/share/web-greeter/themes/bapirlo/img/logo.svg"
user-image = "/usr/share/web-greeter/themes/bapirlo/img/avatar.png"
EOF
}

# Plain GNOME as the default session (LightDM remembers the last one per user in AccountsService).
default_gnome() {
  local f=/var/lib/AccountsService/users/$USER
  sudo sed -i -E 's/^(X?Session)=.*/\1=gnome/' "$f"
  sudo grep -q '^Session=' "$f" || sudo sed -i '/^\[User\]/a Session=gnome' "$f"
  sudo grep -q '^XSession=' "$f" || sudo sed -i '/^\[User\]/a XSession=gnome' "$f"
  printf '[Desktop]\nSession=gnome\n' > ~/.dmrc
  grep -q '^user-session=gnome$' "$CONF" || sudo sed -i 's/^user-session=.*/user-session=gnome/' "$CONF"
  echo "default session -> gnome"
}

install_revert_tool() {
  sudo tee "$REVERT" >/dev/null <<'EOF'
#!/bin/sh
# Kuro OS — put the old slick-greeter login screen back (safe to run from a TTY).
#   sudo bapirlo-greeter-revert && sudo reboot
set -e
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
sed -i 's/^greeter-session=.*/greeter-session=lightdm-slick-greeter/' /etc/lightdm/lightdm.conf
grep -n '^greeter-session' /etc/lightdm/lightdm.conf
echo "slick-greeter restored. Reboot (sudo reboot) or: sudo systemctl restart lightdm"
EOF
  sudo chmod 755 "$REVERT"
  echo "TTY rescue -> $REVERT"
}

case "${1:-}" in
  snapshot)
    sudo -v
    snapshot
    ;;
  install)
    sudo -v
    snapshot
    backup
    echo
    echo "== AUR package (built from source, about 10-20 min; downloads PySide6/Qt WebEngine from PyPI):"
    paru -Si --aur web-greeter | grep -E '^(Name|Version|URL|Depends On|Make Deps|Maintainer|Last Modified)'
    read -rp "Install web-greeter now? [y/N] " ok
    [ "$ok" = y ] || [ "$ok" = Y ] || { echo "stopped before installing (snapshot + backup kept)."; exit 0; }
    sudo pacman -S --needed --noconfirm xorg-xsetroot   # used by web-greeter's greeter wrapper
    paru -S --needed --removemake web-greeter
    install_theme
    write_conf
    default_gnome
    install_revert_tool
    echo
    grep -n '^greeter-session' "$CONF"
    echo "Done. slick-greeter is STILL the login screen. Next: bash $0 preview"
    ;;
  preview)
    command -v web-greeter >/dev/null || { echo "web-greeter not installed — run: bash $0 install"; exit 1; }
    echo "Opening the real web-greeter window (cannot log in from here — LightDM isn't driving it). Close it with Alt+F4."
    web-greeter --mode debug --theme bapirlo
    ;;
  switch)
    [ -f "$THEME_DST/index.html" ] && command -v web-greeter >/dev/null || { echo "run install first"; exit 1; }
    [ -x "$REVERT" ] || { echo "rescue tool missing — run install first"; exit 1; }
    sudo sed -i 's/^greeter-session=.*/greeter-session=web-greeter/' "$CONF"
    grep -n '^greeter-session' "$CONF"
    echo "Switched. It shows on the next boot (reboot when ready)."
    echo "If it ever fails: Ctrl+Alt+F3 → log in → sudo bapirlo-greeter-revert && sudo reboot"
    ;;
  theme)
    install_theme
    ;;
  revert)
    sudo "$REVERT"
    ;;
  restore)
    BK=$(cat "$LATEST")
    echo "restoring from $BK"
    # copy the old files back over (not rm -rf: the web-greeter package's Xgreeter wrapper must stay
    # while the package is installed — its /etc/xdg drop-in points every greeter at it)
    sudo cp -a "$BK/etc-lightdm/." /etc/lightdm/
    sudo cp "$BK/accountsservice-user" "/var/lib/AccountsService/users/$USER"
    sudo chown root:root "/var/lib/AccountsService/users/$USER"; sudo chmod 600 "/var/lib/AccountsService/users/$USER"
    [ -f "$BK/dmrc" ] && cp "$BK/dmrc" ~/.dmrc
    sudo rm -rf "$THEME_DST" "$REVERT"
    grep -n '^greeter-session' "$CONF"
    echo "Restored. web-greeter package left installed — remove with: paru -Rns web-greeter"
    ;;
  *)
    sed -n '2,15p' "$0"; exit 1 ;;
esac
