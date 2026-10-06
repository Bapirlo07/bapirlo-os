<p align="center">
  <img src="docs/screenshots/welcome-icon.png" width="96" alt="Bapirlo Welcome icon">
</p>

<h1 align="center">BAPIRLO OS · <i>Kuro</i></h1>

<p align="center">
  A manga-styled, ink-black and crimson GNOME 50 desktop on top of CachyOS:<br>
  themed from the first GRUB frame to the shutdown splash, built to stay out of the way while gaming and streaming.
</p>

---

## Features

**One look, everywhere.** A single palette (`tools/palette.py`: ink `#0E0A0D`, crimson `#E11D2E`,
ember `#FF4655`, sakura `#F08AA4`, paper `#F2E9EC`) feeds every themed surface.

| Area | What you get |
|---|---|
| **Boot** | GRUB theme, a Plymouth splash with an animated "awakening" scene (per-monitor layout, password card, *See you soon* / *Be right back* on shutdown and reboot), a themed LightDM greeter |
| **Shell** | One 44 px floating top bar with a mini player, workspace dots, quick-launch, power-mode chip, replay dot, weather and an update count. Dock with intellihide, ArcMenu on Super, Coverflow Alt-Tab, rounded corners, Tiling Shell snap layouts, desktop cube |
| **Living colours** | `bapirlo-autotheme` (matugen) derives the second accent from the wallpaper. The wallpaper switches between a bright day grade and a dark night grade at local sunrise and sunset, and Night Light follows the same times |
| **Bapirlo Welcome** | A GTK4/libadwaita control centre that opens on the first login of the day. It shows the clock, weather, today's calendar events, battery, CPU temperature, power mode, storage and updates, plus quick launchers and **Gaming / Quiet / Do Not Disturb** switches |
| **AI on a key** | Super+A summons a floating Claude Code terminal from anywhere; press again to hide it |
| **Gaming** | Fullscreen game detection triggers DND, a held Turbo profile and a 30 s instant-replay buffer on the iGPU's encoder. Also MangoHud, and an OBS hook |
| **Laptop (MSI)** | `msi-ec` + `bapirlo-perfd`: Turbo on AC, Eco + silent fans on battery, 80 % charge limit |
| **Maintenance** | A Timeshift snapshot before every system update, one-click update from the top bar, and a monthly cleanup that tells you what it removed |
| **Security** | ufw that denies incoming traffic, with only GSConnect, Steam LAN, mDNS and Samba allowed, and only from home networks. Auto-lock after 10 minutes, Bitwarden |
| **Capture** | Print opens an area/window/screen screenshot in **Satty** for annotation. Super+Shift+C copies a colour's hex to the clipboard |
| **Little things** | Sound theme (Kenney, CC0), media widget you can drag anywhere, session restore, emoji picker, clipboard history, fastfetch + starship + Alacritty + cava + Vesktop + Spotify + Chrome themes |

Everything is a plain script. Each one **backs up before it changes anything** (into
`~/theme-backups`), and each one has a `restore` that puts things back.

## Screenshots

<p align="center"><img src="docs/screenshots/welcome.png" width="720" alt="Bapirlo Welcome"></p>

<!-- Add more: press Print, pick an area, save in Satty, then copy from ~/Pictures/Screenshots to docs/screenshots/.
     Suggested: desktop.png (bar + dock), lock.png (greeter), boot.gif (Plymouth), alt-tab.png -->

## Install

> Built and tested on **CachyOS + GNOME 50** (Wayland), on an MSI laptop with Intel + NVIDIA graphics.
> The installer replays the same scripts that built the original machine. Each script was tested
> there, but the whole run has **not** yet been tested on a fresh install, so read what each
> phase does before you confirm it.

1. A fresh CachyOS **GNOME** install, with Timeshift on a disk that has space for a snapshot.
2. Clone to exactly `~/bapirlo-os`, because the builders expect that path:
   ```bash
   git clone https://github.com/Bapirlo07/bapirlo-os ~/bapirlo-os
   cd ~/bapirlo-os
   ```
3. Run the installer as your normal user (it asks for sudo when it needs it). **Bring your own
   wallpaper**: the original art is third-party fan art and isn't redistributed.
   ```bash
   ./install.sh --dry-run --wallpaper ~/Pictures/my-art.jpg                       # see the plan
   ./install.sh --wallpaper ~/Pictures/my-art.jpg --city London --lat 51.507 --lon -0.128
   ./install.sh --wallpaper … --boot                                              # + GRUB / Plymouth / LightDM
   ```
   Phases: checks → a Timeshift snapshot "Before Bapirlo OS" → packages (pacman, then the AUR
   through **paru**, which shows every PKGBUILD) → WhiteSur at pinned commits + the Kuro patch →
   generated art → extensions (GNOME 50 builds only) → desktop scripts → optional boot theme.
4. Log out and back in.

**Undo:** `bash ~/bapirlo-os/<script>.sh restore` for any single part, or roll back to the
"Before Bapirlo OS" snapshot with `sudo timeshift --restore`.

## Shortcuts

| Keys | Action |
|---|---|
| Super | ArcMenu |
| Super+Space | Run / search |
| **Super+A** | Claude Code floating terminal (show / hide) |
| Super+Return | Drop-down terminal (ddterm) |
| Super+V | Clipboard history |
| Super+. | Emoji picker |
| Super+L | Lock |
| **Print** | Screenshot, then annotate in Satty |
| Shift+Print / Ctrl+Print / Alt+Print | GNOME screenshot & recording UI / full screen / window |
| **Super+Shift+C** | Colour picker (hex to clipboard) |
| Super+Alt+G / Super+Alt+R | Save the last 30 s / start-stop the replay buffer |
| Right Shift+F12 | MangoHud on/off |
| Ctrl+Super+←/→ · Ctrl+Super+D · Ctrl+Super+F4 | Switch / add / remove workspace |

## Repo layout

```
install.sh              fresh-install orchestrator
NN-*.sh                 one script per feature, run in number order; each has `restore`
bin/                    small daemons & tools (autotheme, daycycle, lockd, replay, mode, capture, update…)
welcome-app/            Bapirlo Welcome (Python, GTK4 + libadwaita)
ai/ bar/ game/ media-widget/ session/ sounds/   GNOME Shell extensions written for Bapirlo OS
round2/ round3/         config files, units and root helpers those rounds install
tools/                  generators: palette, art, GRUB / Plymouth / LightDM / shell theme builders
build/                  hand-tuned theme sources (CSS, configs); generated images are not committed
apps/                   app themes (Alacritty, starship, cava, Vesktop, Spicetify, Chrome, VS Code)
patches/                the one-line WhiteSur colour patch
```

## Credits

- [WhiteSur GTK / icon / cursor themes](https://github.com/vinceliuice) by vinceliuice, used as the base.
- [Bangers](https://github.com/googlefonts/bangers) font (SIL OFL 1.1, included in `assets/fonts`), and Inter.
- Sounds: [Kenney](https://kenney.nl), CC0.
- The GNOME extensions it configures, by their authors: ArcMenu, Blur my Shell, Dash2Dock Lite,
  Burn My Windows, Vitals, SimpleWeather, Clipboard Indicator, Caffeine, Rounded Window Corners
  Reborn, Desktop Cube, GSConnect, Coverflow Alt-Tab, ddterm, Tiling Shell, Emoji Copy, Smart Auto
  Move NG, Arch Update, Gtk4 Desktop Icons NG.
- The "KURO. SCATTER." wallpaper on the original machine is fan art colored by eSM1LE. It isn't
  included in this repo; use your own picture.
