"""Kuro OS — battery / SSD / disk health readings, shared by the Welcome app and bapirlo-doctor.

No root needed: the battery comes from sysfs, the drives' SMART data from UDisks2 on the system bus
(NVMe health log or ATA SMART). Nothing here writes anything or wakes the NVIDIA GPU.
"""
import os
import shutil

MIN_FREE_GB = 15            # below this, updates skip their safety snapshot (bapirlo-presnap)
BATTERY_WORN = 60           # % of design capacity below which the battery counts as worn out


def _read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def battery():
    """dict for the first battery, or None."""
    base = "/sys/class/power_supply"
    try:
        names = sorted(n for n in os.listdir(base) if _read(f"{base}/{n}/type") == "Battery")
    except OSError:
        return None
    if not names:
        return None
    b = f"{base}/{names[0]}"
    full = _read(f"{b}/charge_full") or _read(f"{b}/energy_full")
    design = _read(f"{b}/charge_full_design") or _read(f"{b}/energy_full_design")
    unit = "Ah" if _read(f"{b}/charge_full") else "Wh"
    cycles = _read(f"{b}/cycle_count")
    out = {
        "name": names[0],
        "model": " ".join(x for x in (_read(f"{b}/manufacturer"), _read(f"{b}/model_name")) if x),
        "capacity": int(_read(f"{b}/capacity") or 0),
        "status": _read(f"{b}/status") or "",
        "limit": _read(f"{b}/charge_control_end_threshold"),
        "cycles": int(cycles) if cycles and cycles.isdigit() and int(cycles) > 0 else None,
        "health": None, "full": None, "design": None, "unit": unit,
    }
    if full and design and int(design) > 0:
        out["health"] = round(100 * int(full) / int(design), 1)
        out["full"], out["design"] = int(full) / 1e6, int(design) / 1e6
    return out


def disk():
    st = shutil.disk_usage("/")
    return {"free_gb": st.free / 1024 ** 3, "total_gb": st.total / 1024 ** 3, "used_gb": st.used / 1024 ** 3,
            "low": st.free / 1024 ** 3 < MIN_FREE_GB}


def drives():
    """SMART summary for every physical drive UDisks knows (NVMe or ATA). [] if UDisks is unavailable."""
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    objs = bus.call_sync("org.freedesktop.UDisks2", "/org/freedesktop/UDisks2",
                         "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", None, None,
                         Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]
    out = []
    for path, ifaces in sorted(objs.items()):
        drv = ifaces.get("org.freedesktop.UDisks2.Drive")
        if not drv or drv.get("Removable") or drv.get("Size", 0) == 0:
            continue
        d = {"model": drv.get("Model", "").strip() or "Drive", "size_gb": drv.get("Size", 0) / 1e9,
             "kind": None, "warnings": [], "hours": None, "temp_c": None, "used_pct": None,
             "spare_pct": None, "written_tb": None, "media_errors": None, "unsafe_shutdowns": None}
        nvme = ifaces.get("org.freedesktop.UDisks2.NVMe.Controller")
        ata = ifaces.get("org.freedesktop.UDisks2.Drive.Ata")
        if nvme and nvme.get("SmartUpdated"):
            d["kind"] = "NVMe"
            d["warnings"] = list(nvme.get("SmartCriticalWarning", []))
            d["hours"] = nvme.get("SmartPowerOnHours")
            if nvme.get("SmartTemperature"):
                d["temp_c"] = nvme["SmartTemperature"] - 273
            try:
                a = bus.call_sync("org.freedesktop.UDisks2", path, "org.freedesktop.UDisks2.NVMe.Controller",
                                  "SmartGetAttributes", GLib.Variant("(a{sv})", ({},)), None,
                                  Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]
                d["used_pct"] = a.get("percent_used")
                if a.get("avail_spare") is not None:
                    d["spare_pct"], d["spare_min"] = a["avail_spare"], a.get("spare_thresh")
                if a.get("total_data_written") is not None:
                    d["written_tb"] = a["total_data_written"] / 1e12
                d["media_errors"] = a.get("media_errors")
                d["unsafe_shutdowns"] = a.get("unsafe_shutdowns")
            except GLib.Error:
                pass
        elif ata and ata.get("SmartEnabled") and ata.get("SmartUpdated"):
            d["kind"] = "SATA"
            if ata.get("SmartFailing"):
                d["warnings"] = ["failing"]
            if ata.get("SmartPowerOnSeconds"):
                d["hours"] = ata["SmartPowerOnSeconds"] // 3600
            if ata.get("SmartTemperature"):
                d["temp_c"] = round(ata["SmartTemperature"] - 273.15)
            d["media_errors"] = ata.get("SmartNumBadSectors")
        out.append(d)
    return out


def drive_problems(d):
    """Human-readable reasons this drive needs attention ([] = healthy)."""
    p = []
    if d["warnings"]:
        p.append("drive reports: " + ", ".join(d["warnings"]))
    if d.get("media_errors"):
        p.append(f"{d['media_errors']} media errors")
    if d.get("used_pct") is not None and d["used_pct"] >= 90:
        p.append(f"{d['used_pct']}% of its rated write life used")
    if d.get("spare_pct") is not None and d.get("spare_min") is not None and d["spare_pct"] <= d["spare_min"]:
        p.append(f"spare blocks down to {d['spare_pct']}%")
    return p
