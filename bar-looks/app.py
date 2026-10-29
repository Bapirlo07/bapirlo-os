"""Kuro Bar Looks — the window (GTK4 / libadwaita).

One card per look of the top bar and the dock (classic · manga · glass · islands · flat) with pictures of both;
click a card to switch. It only writes the bapirlo-bar `bar-look` setting — the bar (looks.js)
restyles itself live — and follows the setting, so Super+Alt+L or the bar's right-click menu
moves the highlight here too. Pictures: previews/<look>.png + dock-<look>.png (shot from the headless test shell).
"""
import os
import sys

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402

HERE = os.path.dirname(os.path.realpath(__file__))
OS_DIR = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(OS_DIR, "studio"))

APP_ID = "os.bapirlo.BarLooks"
SCHEMA = "org.gnome.shell.extensions.bapirlo-bar"
SCHEMA_DIRS = [os.path.expanduser("~/.local/share/gnome-shell/extensions/bapirlo-bar@bapirlo-os/schemas"),
               os.path.join(OS_DIR, "bar", "bapirlo-bar@bapirlo-os", "schemas")]
# same order and words as looks.js
LOOKS = [
    ("classic", "Classic", "The original floating bar and dock"),
    ("manga", "Manga", "Ink bar and dock, bold outline, crimson shadow, comic lettering"),
    ("glass", "Glass", "See-through frosted bar and dock — the wallpaper shows through"),
    ("islands", "Islands", "Top: left, centre and right float as separate pills · dock: one rounded pill"),
    ("flat", "Flat", "Edge-to-edge strips: the bar along the top, the dock along the bottom"),
]


def bar_settings():
    for d in SCHEMA_DIRS:
        if os.path.exists(os.path.join(d, "gschemas.compiled")):
            src = Gio.SettingsSchemaSource.new_from_directory(d, Gio.SettingsSchemaSource.get_default(), False)
            schema = src.lookup(SCHEMA, False)
            if schema and schema.has_key("bar-look"):
                return Gio.Settings.new_full(schema, None, None)
    return None


def studio_palette():
    try:
        import studio as S
        return (S.active() or {}).get("palette")
    except Exception:  # noqa: BLE001
        return None


def lbl(text="", css=(), xalign=0.0, **kw):
    return Gtk.Label(label=text, xalign=xalign, css_classes=list(css), **kw)


class Card(Gtk.Button):
    def __init__(self, look, name, hint):
        super().__init__(css_classes=["look-card"])
        self.look = look
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        pic = Gtk.Picture(content_fit=Gtk.ContentFit.CONTAIN, can_shrink=True, height_request=52,
                          css_classes=["shot"])
        path = os.path.join(HERE, "previews", f"{look}.png")
        if os.path.exists(path):
            pic.set_filename(path)
        box.append(pic)
        dock = os.path.join(HERE, "previews", f"dock-{look}.png")
        if os.path.exists(dock):
            box.append(Gtk.Picture(file=Gio.File.new_for_path(dock), content_fit=Gtk.ContentFit.CONTAIN,
                                   can_shrink=True, height_request=46, css_classes=["shot"]))
        row = Gtk.Box(spacing=10)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, hexpand=True)
        text.append(lbl(name, ["name"]))
        text.append(lbl(hint, ["dim"], wrap=True))
        row.append(text)
        self.badge = lbl("IN USE", ["badge"], valign=Gtk.Align.CENTER, visible=False)
        row.append(self.badge)
        box.append(row)
        self.set_child(box)
        self.set_tooltip_text(f"Use the {name} look")

    def set_current(self, on):
        self.badge.set_visible(on)
        (self.add_css_class if on else self.remove_css_class)("picked")


class Window(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Bar Looks", default_width=900, default_height=760,
                         css_classes=["bapirlo-barlooks"])
        self.css = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), self.css,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)
        self.reload_css()
        self.settings = bar_settings()

        self.toasts = Adw.ToastOverlay()
        tv = Adw.ToolbarView()
        hb = Adw.HeaderBar(css_classes=["flat"])
        hb.set_title_widget(lbl("BAR LOOKS", ["brand"], xalign=0.5))
        tv.add_top_bar(hb)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin_start=22, margin_end=22,
                       margin_bottom=20)
        body.append(lbl("Pick how the top bar and the dock look. They change straight away; colours follow your wallpaper.",
                        ["dim"], wrap=True))
        self.cards = []
        for look, name, hint in LOOKS:
            c = Card(look, name, hint)
            c.connect("clicked", lambda b: self.choose(b.look))
            self.cards.append(c)
            body.append(c)
        tips = Gtk.Box(spacing=18, margin_top=4)
        tips.append(lbl("Super+Alt+L  next look", ["faint"]))
        tips.append(lbl("Right-click an empty spot on the bar  pick one", ["faint"]))
        body.append(tips)

        scroll = Gtk.ScrolledWindow(child=body, vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.toasts.set_child(scroll)
        tv.set_content(self.toasts)
        self.set_content(tv)

        if self.settings is None:
            for c in self.cards:
                c.set_sensitive(False)
            GLib.idle_add(lambda: self.toast("The Kuro bar isn't installed — run 1200-bar-looks.sh", 0))
        else:
            self.settings.connect("changed::bar-look", lambda *_: self.sync())
            self.sync()

    def reload_css(self):
        with open(os.path.join(HERE, "style.css")) as f:
            css = f.read()
        roles = studio_palette()
        if roles:
            try:
                import engine as E
                css = E.remap_text(css, E.Transform(roles))
            except Exception:  # noqa: BLE001 — the Kuro colours are fine too
                pass
        self.css.load_from_string(css)

    def current(self):
        return self.settings.get_string("bar-look") if self.settings else "classic"

    def sync(self):
        cur = self.current()
        for c in self.cards:
            c.set_current(c.look == cur)

    def choose(self, look):
        if not self.settings or look == self.current():
            return
        self.settings.set_string("bar-look", look)
        name = next(n for k, n, _ in LOOKS if k == look)
        self.toast(f"Bar look: {name}")

    def toast(self, text, timeout=2):
        self.toasts.add_toast(Adw.Toast(title=text, timeout=timeout))
        return GLib.SOURCE_REMOVE


class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.win = None

    def do_startup(self):
        Adw.Application.do_startup(self)
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK)
        a = Gio.SimpleAction.new("quit", None)
        a.connect("activate", lambda *_: self.quit())
        self.add_action(a)
        self.set_accels_for_action("app.quit", ["<Ctrl>q", "<Ctrl>w"])

    def do_activate(self):
        if not self.win:
            self.win = Window(self)
        self.win.present()


def main():
    return App().run(sys.argv)
