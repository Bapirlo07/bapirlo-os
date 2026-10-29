#!/usr/bin/env bash
# Kuro OS round 2 — gaming & streaming (NO sudo; needs mangohud + gpu-screen-recorder from 200-round2-install.sh).
#   bash ~/bapirlo-os/230-gaming.sh            # backup + configure + enable
#   bash ~/bapirlo-os/230-gaming.sh restore    # everything back as it was
#   1. MangoHud "Kuro" overlay: FPS, frame-time graph, CPU/GPU load + temps. Toggle Right Shift+F12.
#      Per game: Steam → Properties → Launch options:  mangohud %command%
#   2. Instant replay (GPU Screen Recorder, Intel iGPU encoder, last 30 s in RAM):
#      Super+Alt+G save · Super+Alt+R buffer on/off · clips → ~/Videos/Replays
#   3. bapirlo-game extension: while a fullscreen game runs or OBS records/streams →
#      Do Not Disturb + replay buffer; games also hold the Turbo power profile.
#   4. OBS script for (3): OBS → Tools → Scripts → + → ~/bapirlo-os/game/obs/bapirlo-dnd.lua
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
. "$HERE/lib/ext.sh"
UUID=bapirlo-game@bapirlo-os
MANGO=~/.config/MangoHud/MangoHud.conf
UNITS=~/.config/systemd/user
MK=org.gnome.settings-daemon.plugins.media-keys
CK=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
KEYS=("$MK custom-keybindings")
LATEST=~/theme-backups/LATEST-GAMING

add_key() {   # add_key ID NAME BINDING COMMAND
  local path="$CK/$1/"
  dconf write "${path}name" "'$2'"; dconf write "${path}binding" "'$3'"; dconf write "${path}command" "'$4'"
  python3 - "$path" <<'PY'
import ast, subprocess, sys
k = ["gsettings", "get", "org.gnome.settings-daemon.plugins.media-keys", "custom-keybindings"]
v = subprocess.run(k, capture_output=True, text=True).stdout.strip()
cur = [] if v.startswith("@as") else ast.literal_eval(v)
if sys.argv[1] not in cur:
    cur.append(sys.argv[1])
subprocess.run(["gsettings", "set", *k[2:], str(cur)], check=True)
PY
}

apply() {
  command -v gpu-screen-recorder >/dev/null || { echo "gpu-screen-recorder missing — run 200-round2-install.sh first"; exit 1; }
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-gaming
  mkdir -p "$BK"
  [ -f "$MANGO" ] && cp -a "$MANGO" "$BK/MangoHud.conf"
  backup_keys "$BK" "${KEYS[@]}"
  [ -d "$EXT_DIR/$UUID" ] && cp -a "$EXT_DIR/$UUID" "$BK/ext-before"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  install -Dm644 "$HERE/round2/mangohud/MangoHud.conf" "$MANGO"
  # pick up the current wallpaper accent for the graph / CPU colours
  [ -x "$HERE/bin/bapirlo-autotheme" ] && "$HERE/bin/bapirlo-autotheme" apply >/dev/null 2>&1 || true

  mkdir -p "$UNITS" ~/Videos/Replays
  install -m644 "$HERE/round2/systemd/bapirlo-replay.service" "$UNITS/"
  systemctl --user daemon-reload          # not enabled: bapirlo-game / the hotkey start it on demand
  add_key bapirlo-replay-save   "Save last 30 s (instant replay)" "<Super><Alt>g" "$HERE/bin/bapirlo-replay save"
  add_key bapirlo-replay-toggle "Instant replay on/off"          "<Super><Alt>r" "$HERE/bin/bapirlo-replay toggle"

  rm -rf "${EXT_DIR:?}/$UUID"; cp -r "$HERE/game/$UUID" "$EXT_DIR/$UUID"
  ext_enable "$UUID"
  echo; echo "done. Log out/in once to load bapirlo-game. Undo: bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  ext_unenable "$UUID"
  rm -rf "${EXT_DIR:?}/$UUID"; [ -d "$BK/ext-before" ] && cp -a "$BK/ext-before" "$EXT_DIR/$UUID"
  systemctl --user stop bapirlo-replay.service 2>/dev/null || true
  rm -f "$UNITS/bapirlo-replay.service"; systemctl --user daemon-reload
  dconf reset -f "$CK/bapirlo-replay-save/"; dconf reset -f "$CK/bapirlo-replay-toggle/"
  restore_keys "$BK"
  if [ -f "$BK/MangoHud.conf" ]; then cp -a "$BK/MangoHud.conf" "$MANGO"; else rm -f "$MANGO"; fi
  # if a game was running, banners may be off: bapirlo-game turns them back on when disabled
  echo "restored (clips in ~/Videos/Replays are kept)"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
