"""Kuro Theme Studio — the "Theme" tab of the Wallpapers window (wallpaper/app.py, GTK4 / libadwaita).

Left: pictures in ~/Pictures/Theme Studio and your saved themes. Right: a preview of the top bar,
dock, Control Centre, a window and a notification in the new colours, the palette, the colour
controls, the readability check, and Apply. All the work happens in studio.py / engine.py — the
same code the command line (bapirlo-studio) and the Control Centre tile use.
"""
import hashlib
import io
import os
import re
import shutil
import sys
import threading

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
import engine as E  # noqa: E402
import mockup  # noqa: E402
import studio as S  # noqa: E402

KURO_WALL = os.path.expanduser("~/.local/share/backgrounds/bapirlo/kuro-2560x1600.png")
THUMBS = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "bapirlo", "studio-thumbs")
SWATCHES = [("crimson", "Accent"), ("ember", "Accent text"), ("accent2", "Second"), ("accent3", "Third"),
            ("surface", "Cards"), ("night", "Panels"), ("paper", "Text")]


def bg(fn, done, fail=None):
    """Run fn() in a thread; hand the result (or the exception) back on the GTK main loop."""
    def work():
        try:
            r = fn()
        except Exception as e:  # noqa: BLE001 — shown to the user
            GLib.idle_add(fail or (lambda e: print("theme-studio:", e, file=sys.stderr)), e)
        else:
            GLib.idle_add(done, r)
    threading.Thread(target=work, daemon=True).start()


def lbl(text="", css=(), xalign=0.0, wrap=False, **kw):
    w = Gtk.Label(label=text, xalign=xalign, css_classes=list(css), **kw)
    if wrap:
        w.set_wrap(True)
        w.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
    return w


def btn(text=None, css=("kuro",), cb=None, icon=None, tip=None):
    b = Gtk.Button(css_classes=list(css))
    if icon and text:
        b.set_child(Adw.ButtonContent(icon_name=icon, label=text))
    elif icon:
        b.set_icon_name(icon)
    else:
        b.set_label(text)
    if cb:
        b.connect("clicked", lambda *_: cb())
    if tip:
        b.set_tooltip_text(tip)
    return b


def texture(data):
    return Gdk.Texture.new_from_bytes(GLib.Bytes.new(data))


def thumb_bytes(path, w=260, h=162):
    """Small JPEG of a picture (cached by path + mtime)."""
    key = hashlib.sha1(f"{path}{os.path.getmtime(path)}{w}".encode()).hexdigest()
    cache = os.path.join(THUMBS, key + ".jpg")
    if os.path.exists(cache):
        with open(cache, "rb") as f:
            return f.read()
    from PIL import Image
    im = S.cover(Image.open(path).convert("RGB"), (w, h))
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=85)
    os.makedirs(THUMBS, exist_ok=True)
    with open(cache, "wb") as f:
        f.write(buf.getvalue())
    return buf.getvalue()


def pretty(path):
    s = os.path.splitext(os.path.basename(path))[0]
    s = re.sub(r"[_\-]+", " ", s)
    s = re.sub(r"https?\S+|[^\w\s']", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return (s[:28].rsplit(" ", 1)[0] if len(s) > 28 else s).title() or "My theme"


class StudioPage(Gtk.Box):
    def __init__(self, win):
        super().__init__(css_classes=["page-studio"])
        self.win = win
        self.css = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), self.css,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)
        self.reload_css()

        self.src = None            # {"kind": "wall", "path"} | {"kind": "preset", "preset"}
        self.palette = None
        self.accent = None         # chosen main colour (None = the wallpaper's first suggestion)
        self.busy = False
        self._render_gen = 0
        self._render_timer = 0
        self._wall_timer = 0

        # header buttons — the window shows them while this tab is open
        self.head_start = Gtk.Box(spacing=6)
        self.head_start.append(btn("Add picture", ("flat-kuro",), self.pick_file, icon="list-add-symbolic",
                                   tip="Copy a picture into Pictures → Theme Studio"))
        self.head_start.append(btn(None, ("flat-kuro",), self.open_folder, icon="folder-pictures-symbolic",
                                   tip="Open the Theme Studio folder — drop wallpapers in here"))
        self.head_end = Gtk.Box()
        self.toasts = win.toasts

        self.append(self.build_sidebar())
        self.append(self.build_main())
        self.seen_active = (S.active() or {}).get("preset", "original")

        self.monitor = Gio.File.new_for_path(S.DROP).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
        self.monitor.connect("changed", lambda *_: self.queue_walls())
        self.load_walls()
        self.load_presets(select=self.seen_active)

    def refresh(self):
        """The theme changed elsewhere (Wallpapers tab, timer, Control Centre): show the new active one."""
        act = (S.active() or {}).get("preset", "original")
        if act != self.seen_active and not self.busy:
            self.seen_active = act
            self.mark_wall(None)
            self.load_presets(select=act)
        self.update_buttons()

    # ------------------------------------------------------------------ styling
    def reload_css(self):
        with open(os.path.join(HERE, "style.css")) as f:
            css = f.read()
        roles = (S.active() or {}).get("palette")
        if roles:
            css = E.remap_text(css, E.Transform(roles))
        self.css.load_from_string(css)

    # ------------------------------------------------------------------ left column
    def build_sidebar(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, css_classes=["sidebar"],
                      margin_top=4, width_request=330)
        sc = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin_start=14, margin_end=14,
                        margin_top=8, margin_bottom=14)
        sc.set_child(inner)
        box.append(sc)

        inner.append(lbl("WALLPAPERS", ("heading",)))
        self.walls = Gtk.FlowBox(max_children_per_line=2, min_children_per_line=2, homogeneous=True,
                                 selection_mode=Gtk.SelectionMode.NONE, row_spacing=6, column_spacing=6,
                                 activate_on_single_click=True)
        self.walls.connect("child-activated", self.on_wall)
        inner.append(self.walls)
        self.walls_empty = lbl("Drop pictures into Pictures → Theme Studio, or press Add picture.",
                               ("faint",), wrap=True)
        inner.append(self.walls_empty)

        inner.append(lbl("SAVED THEMES", ("heading",), margin_top=8))
        self.plist = Gtk.ListBox(css_classes=["presets"], selection_mode=Gtk.SelectionMode.SINGLE)
        self.plist.connect("row-activated", self.on_preset)
        inner.append(self.plist)
        return box

    def queue_walls(self):
        if self._wall_timer:
            GLib.source_remove(self._wall_timer)
        self._wall_timer = GLib.timeout_add(600, self._walls_due)

    def _walls_due(self):
        self._wall_timer = 0
        self.load_walls()
        return GLib.SOURCE_REMOVE

    def load_walls(self, select=None):
        cur = self.src["path"] if self.src and self.src["kind"] == "wall" else None
        self.walls.remove_all()
        paths = S.wallpapers()
        self.walls_empty.set_visible(not paths)
        for p in paths:
            pic = Gtk.Picture(content_fit=Gtk.ContentFit.COVER, can_shrink=True, width_request=140,
                              height_request=88, css_classes=["thumb"], tooltip_text=os.path.basename(p))
            child = Gtk.FlowBoxChild(child=pic)
            child.path = p
            self.walls.append(child)
            bg(lambda p=p: thumb_bytes(p), lambda data, pic=pic: pic.set_paintable(texture(data)))
            if p == (select or cur):
                pic.add_css_class("picked")
        if select and select in paths:
            self.show_wall(select)

    def load_presets(self, select=None):
        act = (S.active() or {}).get("preset", "original")
        self.plist.remove_all()
        for p in S.presets():
            row = Gtk.ListBoxRow(css_classes=["tile"])
            row.preset = p
            hb = Gtk.Box(spacing=10)
            pic = Gtk.Picture(content_fit=Gtk.ContentFit.COVER, can_shrink=True, width_request=96,
                              height_request=60, css_classes=["thumb"])
            hb.append(pic)
            vb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER, hexpand=True, spacing=3)
            name = lbl(p["name"], ())
            name.set_ellipsize(Pango.EllipsizeMode.END)
            vb.append(name)
            if p["id"] == act:
                vb.append(lbl("ACTIVE", ("active-badge",), halign=Gtk.Align.START))
            hb.append(vb)
            if not p.get("builtin") and p["id"] != act:
                trash = btn(None, ("flat-kuro",), lambda p=p: self.delete(p), icon="user-trash-symbolic",
                            tip="Delete this theme")
                trash.set_valign(Gtk.Align.CENTER)
                hb.append(trash)
            row.set_child(hb)
            self.plist.append(row)
            self._preset_thumb(p, pic)
            if p["id"] == select:
                self.plist.select_row(row)
                self.show_preset(p)

    def _preset_thumb(self, p, pic):
        path = p.get("thumb") or os.path.join(p.get("dir", ""), "thumb.png")

        def make():
            if not os.path.exists(path) and p["id"] == "original":
                mockup.render_png(E.KURO, KURO_WALL if os.path.exists(KURO_WALL) else None, path, width=320)
            with open(path, "rb") as f:
                return f.read()
        bg(make, lambda data: pic.set_paintable(texture(data)))

    # ------------------------------------------------------------------ right column
    def build_main(self):
        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, hexpand=True,
                       margin_start=18, margin_end=18, margin_top=8, margin_bottom=16)
        head = Gtk.Box(spacing=10)
        self.title = lbl("", ("heading",), hexpand=True)
        self.title.set_ellipsize(Pango.EllipsizeMode.END)
        head.append(self.title)
        self.spinner = Adw.Spinner(visible=False)
        head.append(self.spinner)
        self.status = lbl("", ("status",))
        head.append(self.status)
        main.append(head)

        self.preview = Gtk.Picture(content_fit=Gtk.ContentFit.CONTAIN, can_shrink=True, vexpand=True,
                                   css_classes=["preview"], height_request=360,
                                   alternative_text="Preview of the top bar, dock, Control Centre and a window")
        main.append(self.preview)

        pal = Gtk.Box(spacing=8, homogeneous=True, css_classes=["card"])
        self.sw = {}
        for role, name in SWATCHES:
            col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
            chip = Gtk.Box(css_classes=["swatch"])
            col.append(chip)
            col.append(lbl(name, ("faint",), xalign=0.5))
            hexl = lbl("", ("hex",), xalign=0.5, selectable=True)
            col.append(hexl)
            pal.append(col)
            self.sw[role] = (chip, hexl)
        self.sw_css = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), self.sw_css,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_USER + 2)
        main.append(pal)

        # colour controls — only for a new wallpaper (a saved theme is applied as it was saved)
        self.controls = Gtk.Box(spacing=18, css_classes=["card"])
        cbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        cbox.append(lbl("Main colour", ("dim",)))
        self.choices = Gtk.Box(spacing=6)
        cbox.append(self.choices)
        self.controls.append(cbox)
        self.vivid = self._slider("Vivid", 0.6, 1.4, 1.0, "Calm", "Loud")
        self.tint = self._slider("Tint", 0.0, 1.5, 1.0, "Neutral grey", "Strong tint")
        self.controls.append(self.vivid[0])
        self.controls.append(self.tint[0])
        main.append(self.controls)

        self.checks = Gtk.Expander(css_classes=["dim"])
        self.checks_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, margin_top=6)
        self.checks.set_child(self.checks_box)
        main.append(self.checks)

        bar = Gtk.Box(spacing=10)
        self.name = Gtk.Entry(placeholder_text="Theme name", css_classes=["kuro"], hexpand=True, max_length=40)
        bar.append(self.name)
        self.boot_btn = btn("Also apply to login & boot…", ("kuro",), self.boot,
                            icon="system-reboot-symbolic",
                            tip="Boot splash too (asks for your password and shows what changes first)")
        bar.append(self.boot_btn)
        self.apply_btn = btn("Apply", ("kuro", "accent"), self.apply)
        bar.append(self.apply_btn)
        main.append(bar)
        return main

    def _slider(self, title, lo, hi, val, left, right):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, hexpand=True)
        box.append(lbl(title, ("dim",)))
        sc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, lo, hi, 0.05)
        sc.set_value(val)
        sc.set_draw_value(False)
        sc.connect("value-changed", lambda *_: self.recompute())
        box.append(sc)
        ends = Gtk.Box()
        ends.append(lbl(left, ("faint",), hexpand=True))
        ends.append(lbl(right, ("faint",)))
        box.append(ends)
        return box, sc

    # ------------------------------------------------------------------ selecting things
    def mark_wall(self, path=None):
        """Highlight one wallpaper (own class: a FlowBox's selection follows keyboard focus)."""
        c = self.walls.get_first_child()
        while c:
            if getattr(c, "path", None) == path:
                c.get_child().add_css_class("picked")
            else:
                c.get_child().remove_css_class("picked")
            c = c.get_next_sibling()

    def on_wall(self, _fb, child):
        self.plist.unselect_all()
        self.mark_wall(child.path)
        self.show_wall(child.path)

    def on_preset(self, _lb, row):
        self.mark_wall(None)
        self.show_preset(row.preset)

    def show_wall(self, path):
        self.src = {"kind": "wall", "path": path}
        self.accent = None
        self.vivid[1].set_value(1.0)
        self.tint[1].set_value(1.0)
        self.title.set_label(os.path.basename(path))
        self.name.set_text(pretty(path))
        self.name.set_sensitive(True)
        self.controls.set_visible(True)
        self.set_status("Reading the colours…", busy=True)

        def done(p):
            if self.src.get("path") != path:
                return
            self.set_status("")
            self.fill_choices(p["candidates"])
            self.show_palette(p)
        bg(lambda: E.palette_from_image(path), done, self.fail)

    def show_preset(self, p):
        self.src = {"kind": "preset", "preset": p}
        self.title.set_label(p["name"])
        self.name.set_text(p["name"])
        self.name.set_sensitive(False)
        self.controls.set_visible(False)
        self.set_status("")
        self.show_palette({"roles": p["roles"], "checks": E.checks(p["roles"])})

    def fill_choices(self, cands):
        while (c := self.choices.get_first_child()):
            self.choices.remove(c)
        css = []
        group = None
        for i, h in enumerate(cands):
            b = Gtk.ToggleButton(css_classes=["choice", f"choice-{i}"], tooltip_text=h,
                                 width_request=30, height_request=30, valign=Gtk.Align.CENTER)
            if group:
                b.set_group(group)
            group = group or b
            b.set_active(i == 0)
            b.connect("toggled", lambda b, h=h: b.get_active() and self.choose(h))
            self.choices.append(b)
            css.append(f"button.choice.choice-{i} {{ background-color: {h}; background-image: none; }}")
        own = Gtk.ColorDialogButton(dialog=Gtk.ColorDialog(title="Main colour", with_alpha=False),
                                    tooltip_text="Pick your own colour", valign=Gtk.Align.CENTER)
        own.connect("notify::rgba", lambda b, _p: self.choose(
            "#{:02X}{:02X}{:02X}".format(*(round(c * 255) for c in (b.get_rgba().red, b.get_rgba().green, b.get_rgba().blue)))))
        self._own = own
        self.choices.append(own)
        if not getattr(self, "_choice_css", None):
            self._choice_css = Gtk.CssProvider()
            Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), self._choice_css,
                                                      Gtk.STYLE_PROVIDER_PRIORITY_USER + 2)
        self._choice_css.load_from_string("\n".join(css))

    def choose(self, h):
        self.accent = h
        self.recompute()

    def recompute(self):
        if not self.src or self.src["kind"] != "wall":
            return
        path = self.src["path"]
        try:
            p = E.palette_from_image(path, accent=self.accent, vivid=self.vivid[1].get_value(),
                                     tint=self.tint[1].get_value())
        except Exception as e:  # noqa: BLE001
            return self.fail(e)
        self.show_palette(p)

    def show_palette(self, p):
        self.palette = p
        r = p["roles"]
        self.sw_css.load_from_string("\n".join(
            f".sw-{role} {{ background-color: {r[role]}; }}" for role, _n in SWATCHES))
        for role, (chip, hexl) in self.sw.items():
            for c in list(chip.get_css_classes()):
                if c.startswith("sw-"):
                    chip.remove_css_class(c)
            chip.add_css_class(f"sw-{role}")
            hexl.set_label(r[role])
        ok = sum(1 for c in p["checks"] if c[3])
        self.checks.set_label(f"Readability: {ok} of {len(p['checks'])} pass WCAG AA"
                              + ("" if ok == len(p["checks"]) else " — adjusted where possible"))
        while (c := self.checks_box.get_first_child()):
            self.checks_box.remove(c)
        for label, ratio, target, good in p["checks"]:
            row = Gtk.Box(spacing=8)
            row.append(lbl("✓" if good else "!", ("pass" if good else "fail",)))
            row.append(lbl(label, ("dim",), hexpand=True))
            row.append(lbl(f"{ratio:.1f} : 1  (needs {target:g})", ("faint",)))
            self.checks_box.append(row)
        self.queue_render()
        self.update_buttons()

    def queue_render(self):
        if self._render_timer:
            GLib.source_remove(self._render_timer)
        self._render_timer = GLib.timeout_add(120, self._render_due)

    def _render_due(self):
        self._render_timer = 0
        self._render_gen += 1
        gen, roles = self._render_gen, dict(self.palette["roles"])
        if self.src["kind"] == "wall":
            wall = self.src["path"]
        else:
            wall = self.src["preset"].get("wallpaper") or (KURO_WALL if os.path.exists(KURO_WALL) else None)
        bg(lambda: mockup.render_bytes(roles, wall, width=1440),
           lambda data: gen == self._render_gen and self.preview.set_paintable(texture(data)), self.fail)
        return GLib.SOURCE_REMOVE

    def update_buttons(self):
        act = (S.active() or {}).get("preset", "original")
        is_active = self.src and self.src["kind"] == "preset" and self.src["preset"]["id"] == act
        self.apply_btn.set_sensitive(bool(self.palette) and not self.busy and not is_active)
        self.apply_btn.set_label("Applied" if is_active else "Apply")
        self.boot_btn.set_sensitive(not self.busy and bool(is_active))
        self.boot_btn.set_tooltip_text(
            "Boot splash too (asks for your password and shows what changes first)" if is_active
            else "Apply this theme first — then it can go on the boot splash too")

    def set_status(self, text, busy=False):
        self.status.set_label(text)
        self.spinner.set_visible(busy)

    def fail(self, e):
        self.busy = False
        self.set_status("")
        self.update_buttons()
        self.toasts.add_toast(Adw.Toast(title=f"Something went wrong: {e}", timeout=8))

    # ------------------------------------------------------------------ actions
    def apply(self):
        if not self.palette or self.busy:
            return
        self.busy = True
        self.update_buttons()
        self.set_status("Applying…", busy=True)
        src, pal = dict(self.src), self.palette
        name = self.name.get_text().strip() or "My theme"

        def work():
            if src["kind"] == "preset":
                pid = src["preset"]["id"]
            else:
                same = [p for p in S.presets() if not p.get("builtin") and p.get("source") == os.path.abspath(src["path"])
                        and p.get("roles") == pal["roles"]]
                pid = same[0]["id"] if same else S.save_preset(name, src["path"], pal)["id"]
            S.apply_preset(pid)
            return pid

        def done(pid):
            self.busy = False
            self.seen_active = pid
            self.mark_wall(None)
            self.load_presets(select=pid)
            self.win.theme_changed()
            self.set_status("")
            nm = "Original Kuro OS" if pid == "original" else S.get_preset(pid)["name"]
            self.toasts.add_toast(Adw.Toast(title=f"“{nm}” applied", timeout=4))
        bg(work, done, self.fail)

    def boot(self):
        act = (S.active() or {}).get("preset", "original")
        import subprocess
        plan = subprocess.run([os.path.join(HERE, "bapirlo-studio"), "boot-plan", act],
                              capture_output=True, text=True).stdout.strip()
        d = Adw.AlertDialog(heading="Also apply to login & boot?", body=plan, body_use_markup=False)
        d.add_response("cancel", "Cancel")
        d.add_response("go", "Continue — ask for my password")
        d.set_response_appearance("go", Adw.ResponseAppearance.SUGGESTED)
        d.set_default_response("cancel")
        d.set_close_response("cancel")

        def resp(_d, r):
            if r != "go":
                return
            self.busy = True
            self.update_buttons()
            self.set_status("Updating the boot splash (about a minute)…", busy=True)
            bg(lambda: S.apply_boot(act), self.boot_done, self.fail)
        d.connect("response", resp)
        d.present(self)

    def boot_done(self, res):
        ok, out = res
        self.busy = False
        self.set_status("")
        self.update_buttons()
        if not ok and ("dismissed" in out.lower() or "not authorized" in out.lower() or out.strip() == ""):
            self.toasts.add_toast(Adw.Toast(title="Boot splash not changed (password cancelled)", timeout=5))
            return
        d = Adw.AlertDialog(heading="Boot splash updated" if ok else "Boot splash NOT changed",
                            body=out[-1800:] or ("Done." if ok else "Unknown error"))
        d.add_response("ok", "OK")
        d.present(self)

    def delete(self, p):
        d = Adw.AlertDialog(heading=f"Delete “{p['name']}”?",
                            body="The saved theme and its copy of the wallpaper are removed. "
                                 "The picture in Theme Studio stays.")
        d.add_response("cancel", "Cancel")
        d.add_response("del", "Delete")
        d.set_response_appearance("del", Adw.ResponseAppearance.DESTRUCTIVE)

        def resp(_d, r):
            if r == "del":
                try:
                    S.delete_preset(p["id"])
                except Exception as e:  # noqa: BLE001
                    return self.fail(e)
                self.load_presets()
        d.connect("response", resp)
        d.present(self)

    def pick_file(self):
        f = Gtk.FileFilter(name="Pictures")
        for m in ("image/jpeg", "image/png", "image/webp"):
            f.add_mime_type(m)
        filters = Gio.ListStore.new(Gtk.FileFilter)
        filters.append(f)
        dlg = Gtk.FileDialog(title="Choose a wallpaper", filters=filters,
                             initial_folder=Gio.File.new_for_path(os.path.expanduser("~/Pictures")))

        def done(d, res):
            try:
                gf = d.open_finish(res)
            except GLib.Error:
                return
            self.add_picture(gf.get_path())
        dlg.open(self.win, None, done)

    def add_picture(self, path):
        """Pictures from elsewhere are copied into the Theme Studio folder, so they stay available."""
        if not path:
            return
        os.makedirs(S.DROP, exist_ok=True)
        if os.path.dirname(os.path.abspath(path)) != S.DROP:
            dst = os.path.join(S.DROP, os.path.basename(path))
            if not os.path.exists(dst):
                shutil.copy2(path, dst)
                os.utime(dst)
            path = dst
        self.plist.unselect_all()
        self.load_walls(select=path)

    def open_folder(self):
        os.makedirs(S.DROP, exist_ok=True)
        Gtk.FileLauncher(file=Gio.File.new_for_path(S.DROP)).launch(self.win, None, None)

