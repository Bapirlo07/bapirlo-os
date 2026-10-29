#!/usr/bin/env bash
# Kuro Writer — install / remove (NO sudo, except the `languagetool` step which asks for it).
#   bash ~/bapirlo-os/writer/install.sh               # backup → venv + anthropic SDK → Start menu entry, icon, Super+Shift+H
#   bash ~/bapirlo-os/writer/install.sh languagetool  # sudo pacman: LanguageTool + headless Java 21 (~530 MB, for Grammar mode)
#   bash ~/bapirlo-os/writer/install.sh restore       # undo the install (keeps your settings, voice profile and history)
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
VENV=$DATA/bapirlo-writer/venv
DESKTOP=$DATA/applications/os.bapirlo.Writer.desktop
ICONS=("$DATA/icons/Bapirlo/scalable/apps/bapirlo-writer.svg" "$DATA/icons/hicolor/scalable/apps/bapirlo-writer.svg")
MK=org.gnome.settings-daemon.plugins.media-keys
KEY=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/bapirlo-writer/
BINDING='<Shift><Super>h'
LATEST=~/theme-backups/LATEST-WRITER

backup() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-writer
  mkdir -p "$BK"
  gsettings get $MK custom-keybindings > "$BK/custom-keybindings.txt"
  dconf dump "$KEY" > "$BK/bapirlo-writer-key.ini"
  [ -f "$DESKTOP" ] && cp -a "$DESKTOP" "$BK/"
  for i in "${ICONS[@]}"; do [ -f "$i" ] && cp -a "$i" "$BK/$(basename "$(dirname "$(dirname "$(dirname "$i")")")")-icon.svg"; done
  echo "$BK" > "$LATEST"; echo "backup -> $BK"
}

conflicts() {   # anything else already on Super+Shift+H?
  dconf dump / | grep -n -i -E "'(<Shift><Super>|<Super><Shift>)h'" | grep -v "bapirlo-writer" || true
}

install_app() {
  [ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
  local c; c=$(conflicts)
  if [ -n "$c" ] && ! dconf read "${KEY}binding" | grep -q .; then
    echo "Super+Shift+H is already used:"; echo "$c"; echo "Not installing the hotkey over it."; exit 1
  fi
  backup

  # Python: system PyGObject/GTK/libadwaita/libsecret + the anthropic SDK in a private venv
  if [ ! -x "$VENV/bin/python3" ]; then
    python3 -m venv --system-site-packages "$VENV"
  fi
  "$VENV/bin/python3" -m pip install --quiet --disable-pip-version-check --upgrade "anthropic>=1.12,<2"
  "$VENV/bin/python3" -c 'import anthropic, gi; gi.require_version("Adw","1"); gi.require_version("Secret","1"); from gi.repository import Adw, Secret; print("  anthropic", anthropic.__version__)'
  chmod 755 "$HERE/bapirlo-writer"

  for i in "${ICONS[@]}"; do install -Dm644 "$HERE/bapirlo-writer.svg" "$i"; done
  for t in Kuro hicolor; do gtk-update-icon-cache -q -t "$DATA/icons/$t" 2>/dev/null || true; done
  install -Dm644 /dev/stdin "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Kuro Writer
GenericName=Writing assistant
Comment=Rewrite emails, applications and posts in your own voice; check uni work for spelling and grammar offline
Exec=$HERE/bapirlo-writer
Icon=bapirlo-writer
Terminal=false
Categories=Utility;TextTools;
Keywords=write;rewrite;grammar;spelling;email;cover letter;linkedin;languagetool;bapirlo;
StartupWMClass=os.bapirlo.Writer
DBusActivatable=false
Actions=clipboard;grammar;

[Desktop Action clipboard]
Name=Open with clipboard text
Exec=$HERE/bapirlo-writer --clipboard

[Desktop Action grammar]
Name=Grammar check
Exec=$HERE/bapirlo-writer --grammar
EOF
  update-desktop-database -q "$DATA/applications" 2>/dev/null || true

  # Super+Shift+H → open with the clipboard loaded
  dconf write "${KEY}name" "'Kuro Writer (clipboard)'"
  dconf write "${KEY}binding" "'$BINDING'"
  dconf write "${KEY}command" "'$HERE/bapirlo-writer --clipboard'"
  python3 - "$KEY" <<'PY'
import ast, subprocess, sys
k = ["gsettings", "get", "org.gnome.settings-daemon.plugins.media-keys", "custom-keybindings"]
v = subprocess.run(k, capture_output=True, text=True).stdout.strip()
cur = [] if v.startswith("@as") else ast.literal_eval(v)
if sys.argv[1] not in cur:
    cur.append(sys.argv[1])
subprocess.run(["gsettings", "set", *k[2:], str(cur)], check=True)
PY

  echo
  echo "done. Start menu: Kuro Writer · hotkey: Super+Shift+H (opens with your clipboard)"
  if ! command -v java >/dev/null || [ ! -f /usr/share/java/languagetool/languagetool-server.jar ]; then
    echo "Grammar mode needs LanguageTool: bash $0 languagetool"
  fi
  echo "Undo: bash $0 restore"
}

install_lt() {
  [ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo (it asks for your password itself)."; exit 1; }
  echo "Installs from the official Arch repos (no AUR):"
  echo "  languagetool          ~386 MB  (offline spelling/grammar engine, UK English included)"
  echo "  jre21-openjdk-headless ~148 MB (Java 21 LTS, no GUI parts; skipped if you already have a Java)"
  echo "Nothing runs in the background: the Writer starts it on your first check and stops it on close."
  read -rp "Continue? [y/N] " a; [[ $a == [yY] ]] || exit 1
  local pk=(languagetool)
  command -v java >/dev/null || pk+=(jre21-openjdk-headless)
  sudo pacman -S --needed "${pk[@]}"
  sudo paccache -q -rk0 "${pk[@]}" || true   # drop the ~260 MB of downloaded packages, keep the disk lean
  echo "done. (The languagetool.service system unit is NOT enabled; the Writer runs its own copy on 127.0.0.1.)"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  pkill -f "python3 -m bapirlo_writer" 2>/dev/null || true
  dconf reset -f "$KEY"
  gsettings set $MK custom-keybindings "$(cat "$BK/custom-keybindings.txt")"
  [ -s "$BK/bapirlo-writer-key.ini" ] && dconf load "$KEY" < "$BK/bapirlo-writer-key.ini"
  rm -f "$DESKTOP"; [ -f "$BK/$(basename "$DESKTOP")" ] && cp -a "$BK/$(basename "$DESKTOP")" "$DESKTOP"
  rm -f "${ICONS[@]}"
  for i in "${ICONS[@]}"; do
    b="$BK/$(basename "$(dirname "$(dirname "$(dirname "$i")")")")-icon.svg"; [ -f "$b" ] && cp -a "$b" "$i"
  done
  for t in Kuro hicolor; do gtk-update-icon-cache -q -t "$DATA/icons/$t" 2>/dev/null || true; done
  update-desktop-database -q "$DATA/applications" 2>/dev/null || true
  rm -rf "$VENV"
  echo "restored. Kept: ~/.config/bapirlo/writer (settings, voice, dictionary), $DATA/bapirlo-writer (history),"
  echo "the API key in your keyring (remove it in Preferences first, or in Passwords and Keys)."
  echo "LanguageTool, if installed: sudo pacman -Rns languagetool jre21-openjdk-headless"
}

case "${1:-}" in "") install_app ;; languagetool) install_lt ;; restore) restore ;; *) sed -n 2,5p "$0"; exit 1 ;; esac
