#!/usr/bin/env python3
"""Minimal MPRIS player for testing the widget (no audio).
   fake-player.py NAME [--art-dir DIR] [--paused]"""
import sys, os, time, argparse
import dbus, dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

ap = argparse.ArgumentParser()
ap.add_argument("name"); ap.add_argument("--art-dir", default=os.path.dirname(__file__) + "/art")
ap.add_argument("--paused", action="store_true"); ap.add_argument("--identity")
a = ap.parse_args()
TRACKS = [
    ("Kuro Scatter", ["Kuro Ensemble"], "red.png", 214_000_000),
    ("Spirit Wisps (Extended Night Mix)", ["Sakura Line", "Ink Choir"], "blue.png", 351_000_000),
    ("Episode 12 — The Long Road Home", ["Some Channel"], "wide.png", 1_502_000_000),
]
PI = "org.mpris.MediaPlayer2.Player"; RI = "org.mpris.MediaPlayer2"

class P(dbus.service.Object):
    def __init__(s, bus):
        super().__init__(bus, "/org/mpris/MediaPlayer2")
        s.i = 0; s.status = "Paused" if a.paused else "Playing"; s.vol = 0.7
        s.pos = 0; s.t0 = time.monotonic()
    def position(s):
        return s.pos + (int((time.monotonic() - s.t0) * 1e6) if s.status == "Playing" else 0)
    def md(s):
        t, ar, art, ln = TRACKS[s.i]
        return dbus.Dictionary({"mpris:trackid": dbus.ObjectPath(f"/fake/track/{s.i}"),
            "xesam:title": t, "xesam:artist": dbus.Array(ar, signature="s"),
            "mpris:artUrl": "file://" + os.path.abspath(os.path.join(a.art_dir, art)),
            "mpris:length": dbus.Int64(ln)}, signature="sv")
    def props(s, iface):
        if iface == RI:
            return {"CanRaise": False, "Identity": a.identity or a.name.capitalize(), "DesktopEntry": "",
                    "CanQuit": False, "HasTrackList": False, "SupportedUriSchemes": dbus.Array([], signature="s"),
                    "SupportedMimeTypes": dbus.Array([], signature="s")}
        return {"PlaybackStatus": s.status, "Rate": 1.0, "Metadata": s.md(), "Volume": s.vol,
                "Position": dbus.Int64(s.position()), "CanGoNext": True, "CanGoPrevious": True,
                "CanPlay": True, "CanPause": True, "CanSeek": True, "CanControl": True,
                "MinimumRate": 1.0, "MaximumRate": 1.0, "LoopStatus": "None", "Shuffle": False}
    def changed(s, **kw):
        s.PropertiesChanged(PI, kw, [])
    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(s, i, p): return s.props(i)[p]
    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(s, i): return s.props(i)
    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ssv")
    def Set(s, i, p, v):
        if p == "Volume":
            s.vol = float(v); print("SET Volume", s.vol, flush=True); s.changed(Volume=s.vol)
    @dbus.service.signal(dbus.PROPERTIES_IFACE, signature="sa{sv}as")
    def PropertiesChanged(s, i, c, inv): pass
    @dbus.service.signal(PI, signature="x")
    def Seeked(s, p): pass
    @dbus.service.method(RI)
    def Raise(s): print("Raise", flush=True)
    def _track(s, d):
        s.i = (s.i + d) % len(TRACKS); s.pos = 0; s.t0 = time.monotonic()
        s.changed(Metadata=s.md())
    @dbus.service.method(PI)
    def Next(s): print("Next", flush=True); s._track(1)
    @dbus.service.method(PI)
    def Previous(s): print("Previous", flush=True); s._track(-1)
    @dbus.service.method(PI)
    def PlayPause(s):
        s.pos = s.position(); s.t0 = time.monotonic()
        s.status = "Paused" if s.status == "Playing" else "Playing"
        print("PlayPause ->", s.status, flush=True); s.changed(PlaybackStatus=s.status)
    @dbus.service.method(PI)
    def Play(s):
        if s.status != "Playing": s.PlayPause()
    @dbus.service.method(PI)
    def Pause(s):
        if s.status == "Playing": s.PlayPause()
    @dbus.service.method(PI, in_signature="ox")
    def SetPosition(s, tid, p):
        s.pos = int(p); s.t0 = time.monotonic(); print("SetPosition", p, flush=True); s.Seeked(dbus.Int64(p))
    @dbus.service.method(PI, in_signature="x")
    def Seek(s, off):
        s.pos = s.position() + int(off); s.t0 = time.monotonic(); s.Seeked(dbus.Int64(s.pos))

DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName(f"org.mpris.MediaPlayer2.{a.name}", bus)
P(bus)
print("fake player up:", a.name, flush=True)
GLib.MainLoop().run()
