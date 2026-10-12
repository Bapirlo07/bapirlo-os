"""Local data: settings, "My voice" profile, rewrite history (last 20), personal dictionary.

Everything lives in ~/.config/bapirlo/writer (settings, voice, dictionary) and
~/.local/share/bapirlo-writer (history), written 0600 because it is your own writing.
"""
import json
import os
import time

from gi.repository import GLib

CONF = os.path.join(GLib.get_user_config_dir(), "bapirlo", "writer")
DATA = os.path.join(GLib.get_user_data_dir(), "bapirlo-writer")
SETTINGS = os.path.join(CONF, "settings.json")
VOICE = os.path.join(CONF, "voice.json")
DICT = os.path.join(CONF, "dictionary.json")
HISTORY = os.path.join(DATA, "history.json")
HISTORY_MAX = 20

DEFAULTS = {"model": "claude-opus-5-5", "effort": "low", "mode": "rewrite",
            "type": 0, "tone": 0, "lt_port": 8081}


def _load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def _save(path, obj):
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(obj, f, indent=1, ensure_ascii=False)
    os.replace(tmp, path)


def settings():
    return {**DEFAULTS, **_load(SETTINGS, {})}


def save_settings(s):
    _save(SETTINGS, s)


def voice():
    """{"samples": [str], "profile": str, "updated": epoch} or {}"""
    return _load(VOICE, {})


def save_voice(samples, profile):
    _save(VOICE, {"samples": samples, "profile": profile, "updated": int(time.time())})


def clear_voice():
    try:
        os.remove(VOICE)
    except FileNotFoundError:
        pass


def history():
    return _load(HISTORY, [])


def add_history(entry):
    h = [dict(entry, time=int(time.time()))] + history()
    _save(HISTORY, h[:HISTORY_MAX])


def clear_history():
    try:
        os.remove(HISTORY)
    except FileNotFoundError:
        pass


def dictionary():
    return set(_load(DICT, []))


def add_word(word):
    d = dictionary() | {word}
    _save(DICT, sorted(d))
