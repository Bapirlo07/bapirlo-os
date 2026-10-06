#!/usr/bin/env bash
# Bapirlo OS — sound theme + working, themed lock (NO sudo).
#   bash ~/bapirlo-os/120-sound-lock.sh            # backup + install + enable
#   bash ~/bapirlo-os/120-sound-lock.sh restore    # everything back as it was
#
# Sounds (Kenney.nl CC0, see ~/.local/share/sounds/bapirlo/SOURCES.txt):
#   notification "shing" (bapirlo-sounds extension: not in Do Not Disturb / fullscreen, max 1 per 2 s),
#   soft tick on volume change, blade-draw on login.
# Lock: GNOME's lock screen needs GDM; you use LightDM, so nothing ever locked. Now:
#   Super+L, suspend, idle (Settings → Privacy → Screen Lock) and `loginctl lock-session` all lock via
#   LightDM = your themed login screen, with the session kept running behind it.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
. "$HERE/lib/ext.sh"
SOUNDS_DST=${XDG_DATA_HOME:-$HOME/.local/share}/sounds/bapirlo
SOUNDS_EXT=bapirlo-sounds@bapirlo-os
UNIT=~/.config/systemd/user/bapirlo-lockd.service
MK=org.gnome.settings-daemon.plugins.media-keys
LATEST=~/theme-backups/LATEST-SOUND-LOCK

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-sound-lock
  mkdir -p "$BK"
  backup_dconf "$BK" /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/bapirlo-lock/
  backup_keys "$BK" "org.gnome.desktop.sound theme-name" "org.gnome.desktop.sound event-sounds" \
    "$MK screensaver" "$MK custom-keybindings"
  [ -d "$SOUNDS_DST" ] && cp -a "$SOUNDS_DST" "$BK/sounds-bapirlo"
  [ -d "$EXT_DIR/$SOUNDS_EXT" ] && cp -a "$EXT_DIR/$SOUNDS_EXT" "$BK/ext-previous"
  [ -f "$UNIT" ] && cp -a "$UNIT" "$BK/"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  # ---- sound theme + extension
  rm -rf "$SOUNDS_DST"; mkdir -p "$(dirname "$SOUNDS_DST")"
  cp -a "$HERE/sounds/theme/bapirlo" "$SOUNDS_DST"
  gsettings set org.gnome.desktop.sound theme-name bapirlo
  gsettings set org.gnome.desktop.sound event-sounds true
  rm -rf "${EXT_DIR:?}/$SOUNDS_EXT"; cp -a "$HERE/sounds/$SOUNDS_EXT" "$EXT_DIR/"
  ext_enable "$SOUNDS_EXT"

  # ---- lock daemon (user service) — only needed with LightDM; on GDM GNOME's own lock screen works
  if ! readlink -f /etc/systemd/system/display-manager.service 2>/dev/null | grep -q lightdm; then
    echo; echo "display manager is not LightDM → GNOME's own lock screen works; lock daemon not installed."
    echo "Undo: bash $0 restore"
    return 0
  fi
  mkdir -p "$(dirname "$UNIT")"
  cat > "$UNIT" <<EOF
[Unit]
Description=Bapirlo OS lock (Super+L / suspend / idle via LightDM)
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=$HERE/bin/bapirlo-lockd
Restart=on-failure
RestartSec=3
Nice=5

[Install]
WantedBy=graphical-session.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now bapirlo-lockd.service

  # ---- Super+L → bapirlo-lockd --lock-now (GNOME's own binding pointed at the missing lock screen)
  gsettings set $MK screensaver "[]"
  python3 - "$HERE/bin/bapirlo-lockd" <<'PY'
import ast, subprocess, sys
k = "org.gnome.settings-daemon.plugins.media-keys"
p = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/bapirlo-lock/"
cur = subprocess.run(["gsettings", "get", k, "custom-keybindings"], capture_output=True, text=True).stdout.strip()
cur = [] if cur.startswith("@as") else ast.literal_eval(cur)
if p not in cur: cur.append(p)
subprocess.run(["gsettings", "set", k, "custom-keybindings", str(cur)], check=True)
s = f"{k}.custom-keybinding:{p}"
for key, val in (("name", "Lock screen (Bapirlo)"), ("command", f"{sys.argv[1]} --lock-now"), ("binding", "<Super>l")):
    subprocess.run(["gsettings", "set", s, key, val], check=True)
PY
  echo; echo "done. Sounds + Super+L work now; the notification sound extension loads at next login."
  echo "Preview sounds:  pw-play $SOUNDS_DST/stereo/message-new-instant.oga   (also desktop-login, audio-volume-change)"
  echo "Undo: bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  ext_unenable "$SOUNDS_EXT"
  rm -rf "${EXT_DIR:?}/$SOUNDS_EXT"
  [ -d "$BK/ext-previous" ] && cp -a "$BK/ext-previous" "$EXT_DIR/$SOUNDS_EXT"
  rm -rf "$SOUNDS_DST"
  [ -d "$BK/sounds-bapirlo" ] && cp -a "$BK/sounds-bapirlo" "$SOUNDS_DST"
  systemctl --user disable --now bapirlo-lockd.service 2>/dev/null || true
  rm -f "$UNIT"
  [ -f "$BK/$(basename "$UNIT")" ] && cp -a "$BK/$(basename "$UNIT")" "$UNIT"
  systemctl --user daemon-reload
  restore_dconf "$BK" /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/bapirlo-lock/
  restore_keys "$BK"
  echo "restored"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
