#!/usr/bin/env python3
"""Bapirlo OS — export your live GNOME settings into the repo, minus anything personal.

  python3 tools/export-settings.py          → config/settings.dconf   (commit this)
  install.sh loads it at the end:  sed "s|@HOME@|$HOME|g" config/settings.dconf | dconf load /

What is exported: every extension's settings, the custom + GNOME keyboard shortcuts, and the
interface / window-manager look. What is DROPPED (never written to the file):
  · GSConnect (paired phone name, IP address, device ids)
  · Smart Auto Move's saved windows (window titles) and the session file
  · the weather location (your city and coordinates live in ~/.config/bapirlo/location.json)
  · "last seen version" / "last shown" bookkeeping keys and clipboard history settings
  · your home directory path → written as @HOME@
"""
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
HERE = os.path.dirname(os.path.realpath(__file__))
OUT = os.path.join(HERE, "..", "config", "settings.dconf")
PATHS = ["/org/gnome/shell/extensions/", "/org/gnome/settings-daemon/plugins/media-keys/",
         "/org/gnome/desktop/wm/keybindings/", "/org/gnome/shell/keybindings/",
         "/org/gnome/mutter/keybindings/", "/org/gnome/desktop/wm/preferences/",
         "/org/gnome/desktop/interface/", "/org/gnome/mutter/"]
DROP_SECTIONS = re.compile(r"^(gsconnect(/.*)?|tiling-assistant)$")   # relative to /org/gnome/shell/extensions/
DROP_KEYS = {
    ("SmartAutoMoveNG", "saved-windows"), ("simple-weather", "locations"),
    ("simple-weather", "main-location-index"), ("bapirlo-desk", "briefing-last"),
}
DROP_KEY_RE = re.compile(r"^(last-|support-notifier-showed|.*-showed-version$|.*history|welcome-dialog)")


def dump(path):
    return subprocess.run(["dconf", "dump", path], capture_output=True, text=True, check=True).stdout


def main():
    out = ["# Bapirlo OS — exported GNOME settings (tools/export-settings.py). Personal data removed;",
           "# @HOME@ = your home folder. Load: sed \"s|@HOME@|$HOME|g\" config/settings.dconf | dconf load /", ""]
    dropped = 0
    for base in PATHS:
        section, skip = None, False
        for line in dump(base).splitlines():
            m = re.match(r"^\[(.*)\]$", line)
            if m:
                section = m.group(1)
                skip = base == "/org/gnome/shell/extensions/" and bool(DROP_SECTIONS.match(section))
                dropped += skip
                if not skip:
                    full = base.rstrip("/") + ("" if section == "/" else "/" + section)
                    out.append(f"[{full.lstrip('/')}]")
                continue
            if skip:
                continue
            if "=" in line and section is not None:
                key = line.split("=", 1)[0]
                if (section, key) in DROP_KEYS or DROP_KEY_RE.match(key):
                    dropped += 1
                    continue
            out.append(line.replace(HOME, "@HOME@"))
        out.append("")
    text = "\n".join(out)
    # belt and braces: no username / home path may survive
    user = os.path.basename(HOME)
    leaks = [l for l in text.splitlines() if user and re.search(rf"\b{re.escape(user)}\b", l, re.I)]
    if leaks:
        print("refusing to write — still personal:", *leaks[:5], sep="\n  ")
        return 1
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w").write(text)
    print(f"wrote {os.path.relpath(OUT)} ({len(text.splitlines())} lines, {dropped} personal entries dropped)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
