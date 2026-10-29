#!/usr/bin/env bash
# Kuro OS round 9 — everything that does NOT need your password (run after 970-round9-install.sh).
#   bash ~/bapirlo-os/980-round9.sh             # backup + apply (then log out / in once)
#   bash ~/bapirlo-os/980-round9.sh restore     # undo all of it
#
#  1. Focus timer in the top bar, next to the clock (new bapirlo-bar): Super+Alt+F starts a 25 min
#     block (banners off while it runs) + 5 min break; click = pause, right-click = stop.
#     `bapirlo-focus` command, "Focus Timer" in the Start menu, FOCUS card in the Welcome app
#     (today / this week / streak, from ~/.local/state/bapirlo/focus.tsv)
#  2. Tiling Shell back on (v77 supports GNOME 51; tested headless): your saved layouts and gaps,
#     Super+←/→/↑/↓ move between tiles, drag a window to the top for the snap assistant
#  3. fish: Starship prompt in Kuro colours (new terminals) · cava with the crimson gradient
#     (both only if 970-round9-install.sh installed them)
#  4. old updates: deletes old Claude Code versions now (keeps the running one + one fallback) —
#     bin/bapirlo-update now does that after every update too
# 1 loads at your next log in (GNOME only reloads an extension's code at login); 2-4 are live.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo."; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/ext.sh"
R9=$HERE/round9
LATEST=~/theme-backups/LATEST-ROUND9
BAR=bapirlo-bar@bapirlo-os
TILING=tilingshell@ferrarodomenico.com
APPS_DIR=~/.local/share/applications
FOCUS_DESKTOP=os.bapirlo.Focus.desktop
FISH_CONF=~/.config/fish/config.fish
STARSHIP=~/.config/starship.toml
CAVA=~/.config/cava/config
MARK="# bapirlo: starship prompt"
DCONF_PATHS=(/org/gnome/shell/extensions/tilingshell/ /org/gnome/shell/extensions/bapirlo-bar/)
TILING_KEYS=("org.gnome.mutter.keybindings toggle-tiled-left" "org.gnome.mutter.keybindings toggle-tiled-right"
             "org.gnome.desktop.wm.keybindings maximize" "org.gnome.desktop.wm.keybindings unmaximize"
             "org.gnome.mutter edge-tiling")

apply() {
  if ! grep -qs '"Before round 9"' /timeshift/snapshots/*/info.json; then
    echo "No Timeshift snapshot \"Before round 9\" yet — run first:  bash $HERE/970-round9-install.sh"; exit 1
  fi
  local BK=~/theme-backups/$(date +%Y%m%d-%H%M%S)-round9
  mkdir -p "$BK/files"
  cp -a "$EXT_DIR/$BAR" "$BK/bar"
  gsettings get org.gnome.shell enabled-extensions > "$BK/enabled-extensions.txt"
  gsettings get org.gnome.shell disabled-extensions > "$BK/disabled-extensions.txt"
  backup_dconf "$BK" "${DCONF_PATHS[@]}"
  backup_keys "$BK" "${TILING_KEYS[@]}"
  for f in "$FISH_CONF" "$STARSHIP" "$CAVA" "$APPS_DIR/$FOCUS_DESKTOP"; do
    if [ -e "$f" ]; then mkdir -p "$BK/files$(dirname "$f")"; cp -a "$f" "$BK/files$f"; else echo "$f" >> "$BK/new-files.txt"; fi
  done
  echo "$BK" > "$LATEST"; echo "backup -> $BK"

  echo "== 1/4 focus timer (top bar · bapirlo-focus · Start menu · Welcome app)"
  glib-compile-schemas "$HERE/bar/$BAR/schemas"
  rm -rf "${EXT_DIR:?}/$BAR"; cp -rL "$HERE/bar/$BAR" "$EXT_DIR/"
  sed "s|@HOME@|$HOME|g" "$R9/apps/$FOCUS_DESKTOP" > "$APPS_DIR/$FOCUS_DESKTOP"
  update-desktop-database -q "$APPS_DIR" 2>/dev/null || true

  echo "== 2/4 Tiling Shell on"
  ext_enable "$TILING"
  gnome-extensions enable "$TILING" 2>/dev/null || true   # live, no login needed (already installed)

  echo "== 3/4 Starship + cava"
  if command -v starship >/dev/null; then
    install -Dm644 "$HERE/apps/starship/starship.toml" "$STARSHIP"
    grep -qF "$MARK" "$FISH_CONF" ||
      printf '\n%s\nif status is-interactive; and command -q starship\n    starship init fish | source\nend\n' "$MARK" >> "$FISH_CONF"
    echo "   starship: on in new terminals"
  else echo "   starship not installed — skipped (run 970-round9-install.sh, then this again)"; fi
  if command -v cava >/dev/null; then
    install -Dm644 "$HERE/apps/cava/config" "$CAVA"; echo "   cava: Kuro colours (run \`cava\` while music plays)"
  else echo "   cava not installed — skipped"; fi

  echo "== 4/4 old Claude Code versions"
  "$HERE/bin/bapirlo-update" --cleanup

  echo
  echo "Done (backup $BK). Log out and back in once for the focus timer (Super+Alt+F)."
  echo "Undo: bash $HERE/980-round9.sh restore"
}

restore() {
  local BK; BK=$(cat "$LATEST" 2>/dev/null) || { echo "nothing to restore ($LATEST missing)"; exit 1; }
  gnome-extensions disable "$TILING" 2>/dev/null || true   # it puts GNOME's Super+arrow keys back itself
  gsettings set org.gnome.shell enabled-extensions "$(cat "$BK/enabled-extensions.txt")"
  gsettings set org.gnome.shell disabled-extensions "$(cat "$BK/disabled-extensions.txt")"
  restore_keys "$BK"
  # a focus block still holding banners off must not outlive the timer
  [ "$(gsettings --schemadir "$EXT_DIR/$BAR/schemas" get org.gnome.shell.extensions.bapirlo-bar focus-owns-dnd 2>/dev/null)" = true ] &&
    gsettings set org.gnome.desktop.notifications show-banners true
  rm -rf "${EXT_DIR:?}/$BAR"; cp -a "$BK/bar" "$EXT_DIR/$BAR"
  restore_dconf "$BK" "${DCONF_PATHS[@]}"
  (cd "$BK/files" && find . -type f) | while read -r f; do cp -a "$BK/files/$f" "/${f#./}"; done
  [ -f "$BK/new-files.txt" ] && while read -r f; do rm -f "$f"; done < "$BK/new-files.txt"
  update-desktop-database -q "$APPS_DIR" 2>/dev/null || true
  echo "Restored from $BK (deleted Claude Code versions stay deleted; the focus log is kept)."
  echo "Log out and back in to load the previous top bar."
}

case "${1:-}" in
  restore) restore ;;
  "") apply ;;
  *) sed -n '2,16p' "$0"; exit 64 ;;
esac
