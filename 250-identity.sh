#!/usr/bin/env bash
# Bapirlo OS round 2 — identity (NO sudo; the hostname itself is set by 200-round2-install.sh).
#   bash ~/bapirlo-os/250-identity.sh            # backup + install
#   bash ~/bapirlo-os/250-identity.sh restore    # everything back
#   1. "About This PC" app (Bapirlo branded; in the app grid / ArcMenu, search "About")
#   2. Kuro icon for your own app Lectern (Bapirlo icon theme; the package's icon is untouched)
#   3. fastfetch: device line (MSI model) + live MSI power mode
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")
ICONS=~/.local/share/icons/Bapirlo
DESK=~/.local/share/applications/os.bapirlo.About.desktop
FF=~/.config/fastfetch/config.jsonc
LATEST=~/theme-backups/LATEST-IDENTITY

apply() {
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-identity
  mkdir -p "$BK"
  cp -a "$FF" "$BK/config.jsonc"
  [ -e "$ICONS/scalable/apps/lectern.svg" ] && cp -a "$ICONS/scalable/apps/lectern.svg" "$BK/"
  [ -e "$DESK" ] && cp -a "$DESK" "$BK/"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  # 1. About This PC
  cat > "$DESK" <<DESKTOP
[Desktop Entry]
Type=Application
Name=About This PC
GenericName=System information
Comment=Bapirlo OS — your laptop, specs and MSI modes at a glance
Exec=$HERE/apps/about/bapirlo-about
Icon=bapirlo
Terminal=false
Categories=Settings;System;
Keywords=about;system;info;specs;hardware;bapirlo;
StartupWMClass=os.bapirlo.About
DESKTOP

  # 2. Lectern icon
  install -Dm644 "$HERE/round2/icons/lectern.svg" "$ICONS/scalable/apps/lectern.svg"
  gtk-update-icon-cache -f -t "$ICONS" >/dev/null 2>&1 || true

  # 3. fastfetch
  python3 - "$FF" <<'PY'
import json, re, sys
p = sys.argv[1]; raw = open(p).read()
header = "".join(l + "\n" for l in raw.splitlines() if l.lstrip().startswith("//"))
d = json.loads(re.sub(r"^\s*//.*$", "", raw, flags=re.M))
mods = d["modules"]
if not any(isinstance(m, dict) and m.get("key", "").endswith("device") for m in mods):
    i = next(i for i, m in enumerate(mods) if isinstance(m, dict) and m.get("type") == "os")
    mods.insert(i + 1, {"type": "host", "key": "\U000f0322 device", "format": "MSI {name}"})
if not any(isinstance(m, dict) and m.get("key", "").endswith("power") for m in mods):
    i = next(i for i, m in enumerate(mods) if isinstance(m, dict) and m.get("type") == "disk")
    mods.insert(i + 1, {"type": "command", "key": "\U000f140b power",
                        "text": "m=/sys/devices/platform/msi-ec; [ -r $m/shift_mode ] && echo \"$(cat $m/shift_mode) · fan $(cat $m/fan_mode) · charge limit $(cat /sys/class/power_supply/BAT1/charge_control_end_threshold)%\" || powerprofilesctl get"})
open(p, "w").write(header + json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY
  echo "done. Undo: bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK"
  cp -a "$BK/config.jsonc" "$FF"
  if [ -f "$BK/lectern.svg" ]; then cp -a "$BK/lectern.svg" "$ICONS/scalable/apps/"; else rm -f "$ICONS/scalable/apps/lectern.svg"; fi
  gtk-update-icon-cache -f -t "$ICONS" >/dev/null 2>&1 || true
  if [ -f "$BK/$(basename "$DESK")" ]; then cp -a "$BK/$(basename "$DESK")" "$DESK"; else rm -f "$DESK"; fi
  echo "restored"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
