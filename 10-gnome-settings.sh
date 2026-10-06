#!/usr/bin/env bash
# Bapirlo OS — step 4/5: GNOME look & behaviour (run as your user, NOT sudo).
# Re-runnable. Undo with: bash ~/bapirlo-os/restore.sh user
set -euo pipefail
E=~/.local/share/gnome-shell/extensions
A=~/bapirlo-os/assets
x() { local ext=$1; shift; gsettings --schemadir "$E/$ext/schemas" "$@"; }

# Palette (also used by the boot/login steps)
#   base #0b0b0d  panel #16161a  red #e3242b  blue #2f7cff  pink #ff3d8b  emerald #10c98f

echo "== Theme, icons, cursor, fonts"
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface accent-color 'red'
gsettings set org.gnome.desktop.interface gtk-theme 'WhiteSur-Dark-red'
gsettings set org.gnome.desktop.interface icon-theme 'Bapirlo'
gsettings set org.gnome.desktop.interface cursor-theme 'WhiteSur-cursors'
gsettings set org.gnome.desktop.interface font-name 'Inter 11'
gsettings set org.gnome.desktop.interface document-font-name 'Inter 11'
gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 11'
gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Inter Semi-Bold 11'
gsettings set org.gnome.desktop.interface enable-animations true
gsettings set org.gnome.desktop.interface enable-hot-corners false
gsettings set org.gnome.shell.extensions.user-theme name 'WhiteSur-Dark-red'

echo "== Windows-style window buttons (right side: minimise, maximise, close)"
gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'

echo "== Windows keyboard shortcuts"
gsettings set org.gnome.settings-daemon.plugins.media-keys home "['<Super>e']"   # Super+E: Files
gsettings set org.gnome.desktop.wm.keybindings show-desktop "['<Super>d']"         # Super+D: desktop
gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Alt>Tab']"      # Alt+Tab: windows
gsettings set org.gnome.desktop.wm.keybindings switch-windows-backward "['<Shift><Alt>Tab']"
gsettings set org.gnome.desktop.wm.keybindings switch-applications "['<Super>Tab']"
gsettings set org.gnome.desktop.wm.keybindings switch-applications-backward "['<Shift><Super>Tab']"

echo "== ArcMenu: Windows 11 layout, top-left, opened by Super, Bapirlo icon"
gsettings set org.gnome.shell.extensions.arcmenu menu-layout '11'
gsettings set org.gnome.shell.extensions.arcmenu position-in-panel 'Left'
gsettings set org.gnome.shell.extensions.arcmenu arcmenu-hotkey "['Super_L']"
gsettings set org.gnome.shell.extensions.arcmenu arcmenu-hotkey-overlay-key-enabled true
gsettings set org.gnome.shell.extensions.arcmenu menu-button-icon "$A/bapirlo-symbolic.svg"
gsettings set org.gnome.shell.extensions.arcmenu menu-button-icon-size 20

echo "== Dock: Dash2Dock Animated, centred bottom, magnify + bounce, blurred"
D=dash2dock-lite@icedman.github.com; S=org.gnome.shell.extensions.dash2dock-lite
x $D set $S animate-icons true
x $D set $S animation-magnify 0.5
x $D set $S animation-spread 0.6
x $D set $S animation-rise 0.25
x $D set $S animation-bounce-height 0.6
x $D set $S open-app-animation true          # bounce on launch
x $D set $S lamp-app-animation false         # Magic Lamp extension handles minimise
x $D set $S blur-background true
x $D set $S background-color '(0.043, 0.043, 0.051, 0.55)'   # #0b0b0d @ 55%
x $D set $S border-color '(0.89, 0.141, 0.169, 0.6)'         # red hairline
x $D set $S border-thickness 1
x $D set $S running-indicator-color '(0.89, 0.141, 0.169, 1.0)'
x $D set $S autohide-dash false
x $D set $S autohide-dodge true              # slide away when a window overlaps

echo "== Blur my Shell: mac top bar + Mica-style app blur"
B=blur-my-shell@aunetx; S=org.gnome.shell.extensions.blur-my-shell
x $B set $S.panel blur true
x $B set $S.panel static-blur true
x $B set $S.panel override-background true
x $B set $S.panel style-panel 0
x $B set $S.panel unblur-in-overview false
x $B set $S.overview blur true
x $B set $S.appfolder blur true
x $B set $S.lockscreen blur true
x $B set $S.applications blur true
x $B set $S.applications enable-all true
x $B set $S.applications opacity 235          # 0-255; slight see-through like Mica
x $B set $S.applications dynamic-opacity true # focused window goes solid
x $B set $S.applications blacklist "['firefox', 'Firefox', 'mpv', 'com.github.rafostar.Clapper', 'steam', 'Steam', 'gamescope', 'obs', 'org.gnome.Loupe']"

echo "== Window effects: magic lamp minimise, wobbly windows"
x compiz-alike-magic-lamp-effect@hermes83.github.com set org.gnome.shell.extensions.com.github.hermes83.compiz-alike-magic-lamp-effect duration 450.0
x compiz-windows-effect@hermes83.github.com set org.gnome.shell.extensions.com.github.hermes83.compiz-windows-effect friction 3.0
x compiz-windows-effect@hermes83.github.com set org.gnome.shell.extensions.com.github.hermes83.compiz-windows-effect resize-effect false

echo "== Burn My Windows: glide in, broken-glass 'slash' out"
P=~/.config/burn-my-windows/profiles; mkdir -p "$P"
rm -f "$P"/1000000000000001.conf "$P"/1000000000000002.conf
cat > "$P/1000000000000001.conf" <<'X'
[burn-my-windows-profile]
profile-animation-type=1
glide-enable-effect=true
glide-animation-time=300
X
cat > "$P/1000000000000002.conf" <<'X'
[burn-my-windows-profile]
profile-animation-type=2
broken-glass-enable-effect=true
broken-glass-animation-time=650
X
x burn-my-windows@schneegans.github.com set org.gnome.shell.extensions.burn-my-windows show-support-dialog false

echo "== Tiling Assistant: Windows 11 snap layouts"
T=tiling-assistant@leleat-on-github; S=org.gnome.shell.extensions.tiling-assistant
x $T set $S enable-tiling-popup true        # "snap assist" after snapping a window
x $T set $S enable-tile-animations true
x $T set $S enable-untile-animations true
x $T set $S enable-layout-picker true 2>/dev/null || true

echo "== Enable extensions (take effect after logging out and back in)"
gsettings set org.gnome.shell disable-user-extensions false
gsettings set org.gnome.shell enabled-extensions "[
 'user-theme@gnome-shell-extensions.gcampax.github.com',
 'appindicatorsupport@rgcjonas.gmail.com',
 'arcmenu@arcmenu.com',
 'dash2dock-lite@icedman.github.com',
 'blur-my-shell@aunetx',
 'burn-my-windows@schneegans.github.com',
 'compiz-alike-magic-lamp-effect@hermes83.github.com',
 'compiz-windows-effect@hermes83.github.com',
 'tiling-assistant@leleat-on-github']"
gsettings set org.gnome.shell disabled-extensions "['dash-to-dock@micxgx.gmail.com']"

echo "Done. Log out and back in to load the extensions."
