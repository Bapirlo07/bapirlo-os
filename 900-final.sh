#!/usr/bin/env bash
# Bapirlo OS final round — everything that does NOT need your password (after 900-final-install.sh).
#   bash ~/bapirlo-os/900-final.sh            backup → apply (then log out / in once)
#   bash ~/bapirlo-os/900-final.sh restore    undo all of it
#
#  1. fixes: Control Centre (150 log warnings per login, deprecated button masks, Restart-to-Windows
#     button, "Classic" moved to Shift+Super+S — Super+Alt+S is the screen reader), top bar slots +
#     Places icon + logo colour for the new extensions
#  2. new extensions from extensions.gnome.org (GNOME 51 builds only): Logo Menu (on the Bapirlo logo;
#     ArcMenu's own button hidden, ArcMenu stays on Super), Lock Keys (Caps Lock icon only while on),
#     Just Perfection (faster animations = Impatience, banners top-right when the Island steps aside),
#     Bluetooth Battery Meter, Alphabetical App Grid, Wiggly (shake to find the cursor), plus GNOME's
#     own Removable Drive Menu and Places Status Indicator (with the Windows drive)
#  3. Start menu: Bapirlo OS Guide (the manual), Bapirlo Doctor, Restart to Windows (+ icons)
#  4. update-proofing: bapirlo-doctor after every system update + after login (notifies only on
#     problems); Spotify theme re-applied after every Spotify update (bapirlo-spicetify.path)
#  5. ~/bapirlo-os/bin on your PATH (fish), so `bapirlo-doctor`, `bapirlo-mode`… work everywhere
#  6. Spicetify: Bapirlo theme applied (only if Spicetify is installed)
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/ext.sh"
BIN=$HERE/bin
EXT=~/.local/share/gnome-shell/extensions
APPS=~/.local/share/applications
ICONS=~/.local/share/icons/Bapirlo
UNITS=~/.config/systemd/user
FISH=~/.config/fish/conf.d/bapirlo-path.fish
LATEST=~/theme-backups/LATEST-FINAL
CC=bapirlo-control-centre@bapirlo-os
BAR=bapirlo-bar@bapirlo-os
NEW_EXTS=(logomenu@aryan_k lockkeys@vaina.lt just-perfection-desktop@just-perfection
          Bluetooth-Battery-Meter@maniacx.github.com AlphabeticalAppGrid@stuarthayhurst wiggly@mojarch)
SYS_EXTS=(drive-menu@gnome-shell-extensions.gcampax.github.com places-menu@gnome-shell-extensions.gcampax.github.com)
DCONF_PATHS=(/org/gnome/shell/extensions/Logo-menu/ /org/gnome/shell/extensions/lockkeys/
             /org/gnome/shell/extensions/just-perfection/ /org/gnome/shell/extensions/Bluetooth-Battery-Meter/
             /org/gnome/shell/extensions/alphabetical-app-grid/ /org/gnome/shell/extensions/wiggly/
             /org/gnome/shell/extensions/bapirlo-control-centre/)
NEW_APPS=(os.bapirlo.Guide.desktop os.bapirlo.Doctor.desktop os.bapirlo.RestartWindows.desktop)
NEW_UNITS=(bapirlo-doctor.service bapirlo-doctor.path bapirlo-doctor.timer bapirlo-spicetify.service bapirlo-spicetify.path)

apply() {
  if [ -z "${BAPIRLO_INSTALLER:-}" ] && ! grep -qs '"Before final"' /timeshift/snapshots/*/info.json; then
    echo "No Timeshift snapshot \"Before final\" yet — run first:  sudo bash $HERE/900-final-install.sh"; exit 1
  fi
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-final
  mkdir -p "$BK"/{ext,apps,units}
  for e in $CC $BAR "${NEW_EXTS[@]}"; do [ -d "$EXT/$e" ] && cp -a "$EXT/$e" "$BK/ext/"; done
  ls "$BK/ext" > "$BK/ext.list"
  backup_dconf "$BK" "${DCONF_PATHS[@]}"
  backup_keys "$BK" "org.gnome.shell enabled-extensions" "org.gnome.shell disabled-extensions" \
              "org.gnome.shell app-picker-layout" "org.gnome.shell.extensions.arcmenu menu-button-appearance"
  for a in "${NEW_APPS[@]}"; do [ -e "$APPS/$a" ] && cp -a "$APPS/$a" "$BK/apps/"; done
  for u in "${NEW_UNITS[@]}"; do [ -e "$UNITS/$u" ] && cp -a "$UNITS/$u" "$BK/units/"; done
  [ -e "$FISH" ] && cp -a "$FISH" "$BK/"
  cp -a ~/.config/gtk-3.0/bookmarks "$BK/bookmarks" 2>/dev/null || true
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo "== 1/6 Control Centre + top bar"
  chmod +x "$BIN"/bapirlo-{doctor,spicetify,restart-windows} "$HERE/apps/guide/bapirlo-guide"
  for d in "control-centre/$CC" "bar/$BAR"; do
    glib-compile-schemas "$HERE/$d/schemas"
    rm -rf "${EXT:?}/$(basename "$d")"; cp -rL "$HERE/$d" "$EXT/"
  done

  echo "== 2/6 new extensions (GNOME $SHELL_MAJOR builds)"
  for u in "${NEW_EXTS[@]}"; do
    ext_install "$u"
    # some zips ship the schema XML only
    [ -d "$EXT/$u/schemas" ] && [ ! -f "$EXT/$u/schemas/gschemas.compiled" ] && glib-compile-schemas "$EXT/$u/schemas"
  done
  sed "s|@HOME@|$HOME|g" "$HERE/final/new-extensions.dconf" | dconf load /org/gnome/shell/extensions/
  ext_enable "${NEW_EXTS[@]}" "${SYS_EXTS[@]}"

  echo "== 3/6 Guide, Doctor, Restart to Windows"
  python3 "$HERE/final/icons/make-icons.py" "$HERE/build/final-icons" >/dev/null
  mkdir -p "$ICONS"; cp -r "$HERE/build/final-icons/scalable" "$HERE/build/final-icons/symbolic" "$ICONS/"
  gtk-update-icon-cache -f -t "$ICONS" >/dev/null 2>&1 || true
  mkdir -p "$APPS"
  for a in "${NEW_APPS[@]}"; do sed "s|@OS@|$HERE|g" "$HERE/final/apps/$a" > "$APPS/$a"; done
  update-desktop-database "$APPS" 2>/dev/null || true

  echo "== 4/6 update-proofing"
  mkdir -p "$UNITS"
  for u in "${NEW_UNITS[@]}"; do sed "s|@BIN@|$BIN|g" "$HERE/final/systemd/$u" > "$UNITS/$u"; done
  systemctl --user daemon-reload
  systemctl --user enable --now bapirlo-doctor.path bapirlo-doctor.timer
  if [ -d ~/.local/share/spotify-launcher ]; then systemctl --user enable --now bapirlo-spicetify.path
  else echo "spotify-launcher not found — Spotify watcher not enabled"; fi

  echo "== 5/6 PATH"
  mkdir -p "$(dirname "$FISH")"
  printf '# Bapirlo OS: the bapirlo-* commands (bapirlo-doctor, bapirlo-mode, bapirlo-vault …)\nfish_add_path -g %s\n' "$BIN" > "$FISH"

  echo "== 6/6 Spotify theme"
  if command -v spicetify >/dev/null; then "$BIN/bapirlo-spicetify" apply || echo "spicetify: open Spotify once, then: bapirlo-spicetify apply"
  else echo "Spicetify not installed — skipped (sudo bash $HERE/900-final-install.sh installs it)"; fi

  echo
  echo "Done. LOG OUT and back in once: the new extensions and the fixed Control Centre load then."
  echo "Then run:  bapirlo-doctor"
}

restore() {
  local BK; BK=$(cat "$LATEST" 2>/dev/null) || { echo "nothing to restore"; exit 1; }
  echo "restoring from $BK"
  ext_unenable "${NEW_EXTS[@]}" "${SYS_EXTS[@]}"
  for u in "${NEW_EXTS[@]}"; do grep -qx "$u" "$BK/ext.list" || rm -rf "${EXT:?}/$u"; done
  for e in $CC $BAR "${NEW_EXTS[@]}"; do [ -d "$BK/ext/$e" ] && { rm -rf "${EXT:?}/$e"; cp -a "$BK/ext/$e" "$EXT/"; }; done
  restore_dconf "$BK" "${DCONF_PATHS[@]}"
  restore_keys "$BK"
  systemctl --user disable --now bapirlo-doctor.path bapirlo-doctor.timer bapirlo-spicetify.path 2>/dev/null || true
  for u in "${NEW_UNITS[@]}"; do rm -f "$UNITS/$u"; [ -e "$BK/units/$u" ] && cp -a "$BK/units/$u" "$UNITS/"; done
  systemctl --user daemon-reload
  for a in "${NEW_APPS[@]}"; do rm -f "$APPS/$a"; [ -e "$BK/apps/$a" ] && cp -a "$BK/apps/$a" "$APPS/"; done
  update-desktop-database "$APPS" 2>/dev/null || true
  rm -f "$FISH"; [ -e "$BK/bapirlo-path.fish" ] && cp -a "$BK/bapirlo-path.fish" "$FISH"
  echo "Done — log out and in. (Spotify keeps its theme: bapirlo-spicetify off removes it.)"
}

case "${1:-apply}" in
  apply) apply ;;
  restore) restore ;;
  *) sed -n '2,20p' "$0"; exit 64 ;;
esac
