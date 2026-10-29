#!/usr/bin/env bash
# Kuro OS round 7 — everything that does NOT need your password (run after 800-round7-install.sh).
#   bash ~/bapirlo-os/810-round7.sh             # backup + apply (then log out / in once)
#   bash ~/bapirlo-os/810-round7.sh captions    # + Live Captions (Flatpak, ~1.5 GB incl. GNOME runtime)
#   bash ~/bapirlo-os/810-round7.sh restore     # undo all of it
#
#  1. bapirlo-desk@bapirlo-os (desk/): Launchpad (Super+G + dock icon), desktop widgets, login briefing
#     (Super+Alt+B), PiP + Live Captions always on top, privacy dots, AirPods battery chip
#  2. Control Centre: AirPlay · Remote · Captions · Vault tiles; top bar: slots for the new chips
#  3. icons (Kuro theme) + Start-menu entries: Launchpad, iCloud (web app), Vault, AirPlay Receiver,
#     LocalSend (opens its port only while running, received → ~/Downloads/iPhone)
#  4. GSConnect for the KDE Connect iOS app (bin/bapirlo-iphone setup)
#  5. Vault: hotkey Super+Alt+V, locks with the screen (bapirlo-lockd) and at logout, not indexed
#  6. Downloads auto-tidy: daily user timer (first run 10 min after login, idle priority)
#  7. LibrePods starts hidden 20 s after login (only if installed); Live Captions hotkey Super+Alt+C
# iCloud Photos stays OFF until you run `bapirlo-icloud setup` yourself.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/ext.sh"
BIN=$HERE/bin
EXT=~/.local/share/gnome-shell/extensions
APPS=~/.local/share/applications
ICONS=~/.local/share/icons/Bapirlo
UNITS=~/.config/systemd/user
AUTO=~/.config/autostart
LATEST=~/theme-backups/LATEST-ROUND7
DESK=bapirlo-desk@bapirlo-os
CC=bapirlo-control-centre@bapirlo-os
BAR=bapirlo-bar@bapirlo-os
KB=/org/gnome/settings-daemon/plugins/media-keys
DCONF_PATHS=(/org/gnome/shell/extensions/bapirlo-desk/ /org/gnome/shell/extensions/bapirlo-control-centre/
             /org/gnome/shell/extensions/gsconnect/ $KB/)
NEW_APPS=(os.bapirlo.Launchpad.desktop os.bapirlo.iCloud.desktop os.bapirlo.Vault.desktop
          os.bapirlo.AirPlay.desktop localsend.desktop uxplay.desktop rustdesk.desktop)
NEW_UNITS=(bapirlo-tidy.service bapirlo-tidy.timer bapirlo-icloud.service bapirlo-icloud.timer bapirlo-vault-guard.service)
CAPTIONS=net.sapples.LiveCaptions

apply() {
  if [ -z "${BAPIRLO_INSTALLER:-}" ] && ! grep -qs '"Before round 7"' /timeshift/snapshots/*/info.json; then
    echo "No Timeshift snapshot \"Before round 7\" yet — run first:  bash $HERE/800-round7-install.sh"; exit 1
  fi
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round7
  mkdir -p "$BK"/{ext,apps,units,autostart}
  for e in $DESK $CC $BAR; do [ -d "$EXT/$e" ] && cp -a "$EXT/$e" "$BK/ext/"; done
  backup_dconf "$BK" "${DCONF_PATHS[@]}"
  backup_keys "$BK" "org.gnome.shell enabled-extensions" "org.gnome.shell favorite-apps" \
              "org.freedesktop.Tracker3.Miner.Files ignored-directories"
  for a in "${NEW_APPS[@]}"; do [ -e "$APPS/$a" ] && cp -a "$APPS/$a" "$BK/apps/"; done; ls "$BK/apps" > "$BK/apps.list"
  for u in "${NEW_UNITS[@]}"; do [ -e "$UNITS/$u" ] && cp -a "$UNITS/$u" "$BK/units/"; done
  [ -e "$AUTO/bapirlo-librepods.desktop" ] && cp -a "$AUTO/bapirlo-librepods.desktop" "$BK/autostart/"
  [ -d "$ICONS" ] && cp -a "$ICONS" "$BK/icons-Bapirlo"
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo "== 1/7 extensions"
  chmod +x "$BIN"/bapirlo-{airplay,localsend,remote,captions,vault,tidy,icloud,iphone,agenda,launchpad}
  for d in "desk/$DESK" "control-centre/$CC" "bar/$BAR"; do
    glib-compile-schemas "$HERE/$d/schemas"
    rm -rf "${EXT:?}/$(basename "$d")"; cp -rL "$HERE/$d" "$EXT/"
  done
  ext_enable "$DESK"

  echo "== 2/7 icons + Start menu"
  python3 "$HERE/round7/icons/make-icons.py" "$HERE/build/round7-icons" >/dev/null
  mkdir -p "$ICONS"; cp -r "$HERE/build/round7-icons/scalable" "$HERE/build/round7-icons/symbolic" "$ICONS/"
  gtk-update-icon-cache -f -t "$ICONS" >/dev/null 2>&1 || true
  gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor >/dev/null 2>&1 || true
  mkdir -p "$APPS"
  for f in os.bapirlo.Launchpad.desktop os.bapirlo.iCloud.desktop os.bapirlo.Vault.desktop os.bapirlo.AirPlay.desktop localsend.desktop; do
    sed "s|@BIN@|$BIN|g" "$HERE/round7/apps/$f" > "$APPS/$f"
  done
  # UxPlay's own entry opens a bare terminal — hidden; "AirPlay Receiver" replaces it
  [ -f /usr/share/applications/uxplay.desktop ] && { cp /usr/share/applications/uxplay.desktop "$APPS/uxplay.desktop"; echo "NoDisplay=true" >> "$APPS/uxplay.desktop"; }
  # RustDesk keeps its app (shows your ID), with the Kuro icon
  [ -f /usr/share/applications/rustdesk.desktop ] && sed 's/^Icon=.*/Icon=bapirlo-remote/' /usr/share/applications/rustdesk.desktop > "$APPS/rustdesk.desktop"
  update-desktop-database "$APPS" 2>/dev/null || true
  python3 - <<'PY'
import ast, subprocess
v = subprocess.run(["gsettings", "get", "org.gnome.shell", "favorite-apps"], capture_output=True, text=True).stdout
fav = [] if v.startswith("@as") else ast.literal_eval(v)
if "os.bapirlo.Launchpad.desktop" not in fav:
    subprocess.run(["gsettings", "set", "org.gnome.shell", "favorite-apps", str(["os.bapirlo.Launchpad.desktop"] + fav)], check=True)
PY

  echo "== 3/7 GSConnect (KDE Connect iOS)"
  "$BIN/bapirlo-iphone" setup

  echo "== 4/7 Vault + hotkeys"
  python3 - "$BIN" <<'PY'
import ast, subprocess, sys
b = sys.argv[1]
KB = "org.gnome.settings-daemon.plugins.media-keys"
def get(*a): return subprocess.run(["gsettings", "get", *a], capture_output=True, text=True).stdout.strip()
paths = [] if get(KB, "custom-keybindings").startswith("@as") else ast.literal_eval(get(KB, "custom-keybindings"))
for name, binding, cmd in (("bapirlo-captions", "<Super><Alt>c", f"{b}/bapirlo-captions toggle"),
                           ("bapirlo-vault", "<Super><Alt>v", f"{b}/bapirlo-vault toggle")):
    p = f"/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/{name}/"
    if p not in paths: paths.append(p)
    for k, v in (("name", name), ("binding", binding), ("command", cmd)):
        subprocess.run(["gsettings", "set", f"{KB}.custom-keybinding:{p}", k, v], check=True)
subprocess.run(["gsettings", "set", KB, "custom-keybindings", str(paths)], check=True)
# never index the Vault's unlocked files
T = "org.freedesktop.Tracker3.Miner.Files"
ig = ast.literal_eval(get(T, "ignored-directories"))
if "Vault" not in ig:
    subprocess.run(["gsettings", "set", T, "ignored-directories", str(ig + ["Vault"])], check=True)
PY
  mkdir -p ~/Downloads/iPhone ~/Pictures/iCloud "$UNITS"
  for u in "${NEW_UNITS[@]}"; do sed "s|@BIN@|$BIN|g" "$HERE/round7/systemd/$u" > "$UNITS/$u"; done
  systemctl --user daemon-reload
  systemctl --user enable --now bapirlo-vault-guard.service >/dev/null 2>&1
  systemctl --user restart bapirlo-lockd.service   # picks up "lock the Vault with the screen"

  echo "== 5/7 Downloads auto-tidy (daily)"
  systemctl --user enable --now bapirlo-tidy.timer
  systemctl --user list-timers bapirlo-tidy.timer --no-pager | head -2

  echo "== 6/7 LibrePods (AirPods)"
  if command -v librepods >/dev/null; then
    mkdir -p "$AUTO"; cp "$HERE/round7/apps/bapirlo-librepods-autostart.desktop" "$AUTO/bapirlo-librepods.desktop"
    pgrep -x librepods >/dev/null || (setsid -f nice -n 5 librepods --hide >/dev/null 2>&1)
    echo "   started; autostarts hidden 20 s after login"
  else echo "   librepods not installed — skipped (AirPods chip stays hidden)"; fi

  echo "== 7/7 Live Captions"
  if flatpak info --user $CAPTIONS >/dev/null 2>&1; then echo "   installed"
  else echo "   not installed — run: bash $0 captions   (~1.5 GB, $(df -h --output=avail / | tail -1 | tr -d ' ') free now)"; fi

  echo; echo "Done. Log out and back in once (Wayland loads extension code at login)."
  echo "Undo: bash $0 restore"
}

captions() {
  echo "Live Captions (Flathub, offline speech recognition). Needs the GNOME 50 Flatpak runtime."
  echo "Download ~750 MB, on disk ~1.5 GB. Free now: $(df -h --output=avail / | tail -1 | tr -d ' ')"
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --user -y --noninteractive flathub $CAPTIONS
  # GTK4 theme (same overrides as the other Flatpaks)
  flatpak override --user --filesystem=xdg-config/gtk-4.0:ro $CAPTIONS
  echo "installed. Toggle: Super+Alt+C or the Control Centre \"Captions\" tile."
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "undoing round 7 (backup $BK)"
  ext_unenable "$DESK"
  rm -rf "${EXT:?}/$DESK"
  for e in $CC $BAR; do [ -d "$BK/ext/$e" ] && { rm -rf "${EXT:?}/$e"; cp -a "$BK/ext/$e" "$EXT/"; }; done
  restore_dconf "$BK" "${DCONF_PATHS[@]}"
  while IFS=$'\t' read -r schema key value; do gsettings set "$schema" "$key" "$value"; done < "$BK/keys.tsv"
  systemctl --user disable --now bapirlo-tidy.timer bapirlo-icloud.timer bapirlo-vault-guard.service 2>/dev/null || true
  for u in "${NEW_UNITS[@]}"; do rm -f "$UNITS/$u"; [ -e "$BK/units/$u" ] && cp -a "$BK/units/$u" "$UNITS/"; done
  systemctl --user daemon-reload
  for a in "${NEW_APPS[@]}"; do rm -f "$APPS/$a"; [ -e "$BK/apps/$a" ] && cp -a "$BK/apps/$a" "$APPS/"; done
  update-desktop-database "$APPS" 2>/dev/null || true
  rm -f "$AUTO/bapirlo-librepods.desktop"; [ -e "$BK/autostart/bapirlo-librepods.desktop" ] && cp -a "$BK/autostart/bapirlo-librepods.desktop" "$AUTO/"
  if [ -d "$BK/icons-Bapirlo" ]; then rm -rf "$ICONS"; cp -a "$BK/icons-Bapirlo" "$ICONS"; gtk-update-icon-cache -f -t "$ICONS" >/dev/null 2>&1 || true; fi
  cp -a ~/theme-backups/round7-src-pre/bapirlo-lockd "$BIN/bapirlo-lockd" 2>/dev/null && systemctl --user restart bapirlo-lockd.service || true
  flatpak info --user $CAPTIONS >/dev/null 2>&1 && echo "Live Captions is still installed — remove with: flatpak uninstall --user $CAPTIONS"
  echo "done. Your files are untouched (Vault, Downloads/iPhone, Pictures/iCloud). Log out / in once."
  echo "Root parts: bash $HERE/800-round7-install.sh restore"
}

case "${1:-apply}" in
  apply) apply ;;
  captions) captions ;;
  restore) restore ;;
  *) sed -n 2,16p "$0"; exit 1 ;;
esac
