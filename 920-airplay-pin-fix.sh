#!/usr/bin/env bash
# Kuro OS — fix "wrong code" on AirPlay pairing.
# Run as yourself (NOT sudo; it asks for the password once):  bash ~/bapirlo-os/920-airplay-pin-fix.sh
# Why: UxPlay 1.73.7 (the packaged version) rejects every iPhone pairing code with
# "Client Authentication Failure (client_proof_len 20 invalid)" — a security patch made it
# demand a 64-byte proof, but iPhones send 20 bytes. Fixed upstream (commit d29dfab, Sep 2026),
# not released yet. This builds upstream master (+ a bounded memcpy) into tools/uxplay;
# bapirlo-airplay uses that build whenever it exists.
# Undo:  rm -rf ~/bapirlo-os/tools/uxplay   (falls back to the packaged uxplay)
set -euo pipefail
[ "$(id -u)" != 0 ] || { echo "run WITHOUT sudo"; exit 1; }
SRC=$HOME/bapirlo-os/tools/uxplay-src
DEST=$HOME/bapirlo-os/tools/uxplay

echo "==> Build tool (cmake)"
command -v cmake >/dev/null || sudo pacman -S --needed --noconfirm --asdeps cmake

echo "==> Building UxPlay"
rm -rf "$SRC/build"
cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$DEST" >/dev/null
make -C "$SRC/build" -j"$(nproc)" >/dev/null
make -C "$SRC/build" install >/dev/null
"$DEST/bin/uxplay" -v

echo "==> Restarting AirPlay"
BA=$HOME/bapirlo-os/bin/bapirlo-airplay
if "$BA" status >/dev/null 2>&1; then "$BA" off; sleep 1; "$BA" on; fi
echo
echo "Done. iPhone: Screen Mirroring → Kuro OS · code $("$BA" pin)"
