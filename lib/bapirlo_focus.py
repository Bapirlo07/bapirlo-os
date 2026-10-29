"""Kuro OS — focus timer log + controls, shared by bin/bapirlo-focus and the Welcome app.

The timer itself runs in the top bar (bar/bapirlo-bar@bapirlo-os/focus.js); its state is in the bar's
GSettings keys and it is the only writer of the log ~/.local/state/bapirlo/focus.tsv:
    2026-10-25T14:05:00 <TAB> 25 <TAB> done        (done = ran to the end, stopped = ended early)
Stopped blocks under a minute are never logged. Only stdlib — fast to import.
"""
import datetime
import os
import subprocess
import time

STATE = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
LOG = os.path.join(STATE, "bapirlo", "focus.tsv")
SCHEMA = "org.gnome.shell.extensions.bapirlo-bar"
SCHEMA_DIR = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
                          "gnome-shell", "extensions", "bapirlo-bar@bapirlo-os", "schemas")


def sessions(path=LOG):
    """[(start datetime, minutes, status)] oldest first; bad lines skipped."""
    out = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) != 3:
                    continue
                try:
                    out.append((datetime.datetime.fromisoformat(parts[0]), int(parts[1]), parts[2]))
                except ValueError:
                    continue
    except OSError:
        pass
    return out


def summary(today=None, path=LOG):
    """Minutes and blocks today / this week (Mon-Sun), and the streak of days with a finished block."""
    today = today or datetime.date.today()
    week_start = today - datetime.timedelta(days=today.weekday())
    s = {"today_min": 0, "today_blocks": 0, "week_min": 0, "week_blocks": 0, "streak": 0,
         "days": {}}   # date -> minutes, this week
    done_days = set()
    for start, minutes, status in sessions(path):
        d = start.date()
        if status == "done":
            done_days.add(d)
        if d == today:
            s["today_min"] += minutes
            s["today_blocks"] += 1
        if week_start <= d <= today:
            s["week_min"] += minutes
            s["week_blocks"] += 1
            s["days"][d] = s["days"].get(d, 0) + minutes
    # a streak still counts this morning if yesterday had a block
    d = today if today in done_days else today - datetime.timedelta(days=1)
    while d in done_days:
        s["streak"] += 1
        d -= datetime.timedelta(days=1)
    return s


def hm(minutes):
    h, m = divmod(int(minutes), 60)
    return f"{h} h {m:02d} min" if h else f"{m} min"


# ---------------------------------------------------------------- live state (the bar's keys)
def _gs(*args):
    cmd = ["gsettings"] + (["--schemadir", SCHEMA_DIR] if os.path.isdir(SCHEMA_DIR) else []) + list(args)
    return subprocess.run(cmd, capture_output=True, text=True, timeout=5)


def get(key):
    r = _gs("get", SCHEMA, key)
    if r.returncode:
        return None
    v = r.stdout.strip()
    if v.startswith("'"):
        return v[1:-1]
    for p in ("int64 ", "uint32 "):
        v = v.removeprefix(p)
    try:
        return int(v)
    except ValueError:
        return v == "true" if v in ("true", "false") else v


def state():
    """{'phase': ''|'focus'|'break', 'left': seconds, 'paused': bool} — None if the bar isn't installed."""
    phase = get("focus-phase")
    if phase is None:
        return None
    left_paused = get("focus-left") or 0
    end = get("focus-end") or 0
    left = left_paused if left_paused > 0 else max(0, end - int(time.time()))
    return {"phase": phase, "left": left if phase else 0, "paused": bool(phase) and left_paused > 0}


def request(verb, minutes=None):
    """Ask the shell to start / stop / toggle / pause (it applies the change in one write)."""
    cmd = verb if minutes is None else f"{verb} {int(minutes)}"
    return _gs("set", SCHEMA, "focus-request", f"{cmd} @{time.time_ns()}").returncode == 0
