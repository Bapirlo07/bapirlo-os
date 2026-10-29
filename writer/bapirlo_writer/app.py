"""Kuro Writer — GTK4/libadwaita window: Rewrite mode (Claude API) and Grammar mode (local LanguageTool)."""
import datetime
import difflib
import os
import re
import shutil
import subprocess
import sys
import threading

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Graphene", "1.0")
from gi.repository import Adw, Gdk, Gio, GLib, Graphene, Gtk, Pango  # noqa: E402

from . import grammar, keystore, store  # noqa: E402
from .rewrite import (EFFORTS, MODELS, TONES, TYPES, WriterError, build_voice,  # noqa: E402
                      estimate, guard, rewrite)

APP_ID = "os.bapirlo.Writer"
HERE = os.path.dirname(os.path.realpath(__file__))
KIND_LABEL = {"spelling": "SPELLING", "grammar": "GRAMMAR", "punctuation": "PUNCTUATION",
              "clarity": "CLARITY", "long": "CLARITY", "fact": "CHECK FACT", "style": "STYLE",
              "flag": "SOUNDS EXAGGERATED"}
UNDERLINE = {"spelling": "#FF4655", "grammar": "#F2B45A", "punctuation": "#7C9CFF", "clarity": "#F08AA4"}


def bg(fn, done, fail):
    """Run fn() in a thread; deliver the result (or exception) on the GTK main loop."""
    def work():
        try:
            r = fn()
        except Exception as e:  # noqa: BLE001 — shown to the user
            GLib.idle_add(fail, e)
        else:
            GLib.idle_add(done, r)
    threading.Thread(target=work, daemon=True).start()


def lbl(text="", css=(), xalign=0.0, wrap=False, **kw):
    w = Gtk.Label(label=text, xalign=xalign, css_classes=list(css), **kw)
    if wrap:
        w.set_wrap(True)
        w.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
    return w


def btn(text, css=("kuro",), cb=None, icon=None, tip=None):
    b = Gtk.Button(css_classes=list(css))
    if icon:
        b.set_child(Adw.ButtonContent(icon_name=icon, label=text))
    else:
        b.set_label(text)
    if cb:
        b.connect("clicked", lambda *_: cb())
    if tip:
        b.set_tooltip_text(tip)
    return b


def page_view(editable=True):
    tv = Gtk.TextView(css_classes=["page"], wrap_mode=Gtk.WrapMode.WORD_CHAR, editable=editable,
                      left_margin=4, right_margin=4, top_margin=4, bottom_margin=12,
                      pixels_below_lines=2, pixels_inside_wrap=3)
    sw = Gtk.ScrolledWindow(child=tv, vexpand=True, hexpand=True)
    sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    return tv, sw


def text_of(buf):
    return buf.get_text(buf.get_start_iter(), buf.get_end_iter(), False)


def tokens(s):
    return re.findall(r"\s+|[\w'’]+|[^\w\s]", s)


# ═══════════════════════════════════════════════ Rewrite ═══════════════════════════════════════════════
class RewritePage(Gtk.Box):
    def __init__(self, win):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                         margin_start=18, margin_end=18, margin_bottom=16, margin_top=4)
        self.win = win
        self.original = None   # text the current result was made from
        self.result = None     # last result dict from the API
        self.programmatic = False
        self.session_cost = 0.0
        s = store.settings()

        # controls row
        row = Gtk.Box(spacing=10)
        self.type_dd = Gtk.DropDown.new_from_strings(TYPES)
        self.type_dd.set_selected(min(s["type"], len(TYPES) - 1))
        self.tone_dd = Gtk.DropDown.new_from_strings(TONES)
        self.tone_dd.set_selected(min(s["tone"], len(TONES) - 1))
        for dd in (self.type_dd, self.tone_dd):
            dd.connect("notify::selected", lambda *_: self._save_choice())
        self.voice_sw = Gtk.Switch(valign=Gtk.Align.CENTER)
        self.voice_sw.set_tooltip_text("Use your saved style profile (My voice)")
        self.voice_sw.connect("notify::active", lambda *_: self._update_estimate())
        self.voice_lbl = lbl("My voice", css=["dim"])
        self.est = lbl("", css=["cost"], ellipsize=Pango.EllipsizeMode.END)
        self.go = btn("Rewrite", css=("kuro", "accent"), cb=self.do_rewrite, icon="document-edit-symbolic",
                      tip="Rewrite (Ctrl+Enter)")
        row.append(lbl("Type", css=["dim"]))
        row.append(self.type_dd)
        row.append(lbl("Tone", css=["dim"], margin_start=6))
        row.append(self.tone_dd)
        row.append(Gtk.Box(hexpand=True))
        row.append(self.voice_lbl)
        row.append(self.voice_sw)
        row.append(self.est)
        row.append(self.go)
        self.append(row)

        # side-by-side panes
        panes = Gtk.Box(spacing=14, homogeneous=True, vexpand=True)
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, css_classes=["card"])
        lh = Gtk.Box(spacing=8)
        lh.append(lbl("YOUR TEXT", css=["heading"], hexpand=True))
        lh.append(btn("Paste", css=("flat-kuro",), cb=self.paste, icon="edit-paste-symbolic"))
        lh.append(btn("Clear", css=("flat-kuro",), cb=self.clear, icon="edit-clear-all-symbolic"))
        left.append(lh)
        self.src, sw = page_view()
        self.src.get_buffer().connect("changed", self._src_changed)
        left.append(sw)
        self.src_hint = lbl("Paste an email, cover letter, LinkedIn post or message here.", css=["faint"])
        left.append(self.src_hint)

        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, css_classes=["card", "result"])
        rh = Gtk.Box(spacing=8)
        rh.append(lbl("REWRITTEN", css=["heading"], hexpand=True))
        self.legend = lbl("red = removed · green = new wording", css=["faint"], visible=False,
                          ellipsize=Pango.EllipsizeMode.END)
        rh.append(self.legend)
        right.append(rh)
        self.out_stack = Gtk.Stack(vexpand=True)
        empty = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER, spacing=6)
        empty.append(lbl("NOTHING YET", css=["empty-title"], xalign=0.5))
        empty.append(lbl("Pick a type and tone, then press Rewrite.\nYour facts stay yours: nothing gets invented.",
                         css=["faint"], xalign=0.5, justify=Gtk.Justification.CENTER))
        self.out_stack.add_named(empty, "empty")
        busy = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER, spacing=10)
        busy.append(Adw.Spinner(width_request=32, height_request=32, halign=Gtk.Align.CENTER))
        self.busy_lbl = lbl("Rewriting…", css=["dim"], xalign=0.5)
        busy.append(self.busy_lbl)
        self.out_stack.add_named(busy, "busy")
        self.out, sw2 = page_view()
        self.out.get_buffer().connect("changed", self._out_changed)
        self.out_stack.add_named(sw2, "result")
        right.append(self.out_stack)

        acts = Adw.WrapBox(child_spacing=6, line_spacing=6)
        self.copy_b = btn("Copy", css=("kuro", "accent"), cb=self.copy, icon="edit-copy-symbolic",
                          tip="Copy the rewrite to the clipboard (Ctrl+Shift+C)")
        self.refine_bs = [
            btn("Shorter", cb=lambda: self.do_rewrite("shorter")),
            btn("More formal", cb=lambda: self.do_rewrite("formal")),
            btn("More casual", cb=lambda: self.do_rewrite("casual")),
            btn("Try again", cb=lambda: self.do_rewrite("again"), icon="view-refresh-symbolic"),
        ]
        acts.append(self.copy_b)
        for b in self.refine_bs:
            acts.append(b)
        right.append(acts)
        self.cost_lbl = lbl("", css=["cost"], ellipsize=Pango.EllipsizeMode.END)
        right.append(self.cost_lbl)
        panes.append(left)
        panes.append(right)
        self.append(panes)

        # flags / checks
        self.flags_box = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=3,
                                     min_children_per_line=1, column_spacing=8, row_spacing=8,
                                     homogeneous=False)
        self.flags_wrap = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, visible=False)
        self.flags_wrap.append(lbl("WORTH A SECOND LOOK", css=["heading"]))
        self.flags_wrap.append(self.flags_box)
        self.append(self.flags_wrap)

        for v in (self.src, self.out):
            b = v.get_buffer()
            b.create_tag("del", strikethrough=True, foreground="#FF9AA3", background="rgba(225,29,46,0.20)")
            b.create_tag("ins", foreground="#D6FFF0", background="rgba(63,198,154,0.22)")
            b.create_tag("flag", underline=Pango.Underline.ERROR, underline_rgba=_rgba("#F2B45A"),
                         background="rgba(242,180,90,0.16)")
        self._set_actions(False)
        self.refresh_voice()
        self._update_estimate()

    # ── helpers ──
    def _save_choice(self):
        s = store.settings()
        s["type"], s["tone"] = self.type_dd.get_selected(), self.tone_dd.get_selected()
        store.save_settings(s)

    def refresh_voice(self):
        v = store.voice()
        has = bool(v.get("profile"))
        self.voice_sw.set_sensitive(has)
        self.voice_sw.set_active(has)
        self.voice_lbl.set_label("My voice" if has else "My voice (not set up)")
        self._update_estimate()

    def _voice(self):
        return store.voice().get("profile", "") if self.voice_sw.get_active() else ""

    def _update_estimate(self):
        t = text_of(self.src.get_buffer())
        m = store.settings()["model"]
        if not t.strip():
            self.est.set_label("")
            return
        e = estimate(t, m, self._voice())
        self.est.set_label(f"≈ ${e:.3f} per rewrite" if e >= 0.001 else "< $0.001 per rewrite")
        self.est.set_tooltip_text(f"Estimate for {MODELS[m][0]}. The real cost is shown after each rewrite.")

    def _src_changed(self, buf):
        if not self.programmatic:
            buf.remove_all_tags(buf.get_start_iter(), buf.get_end_iter())
        self.src_hint.set_visible(not text_of(buf).strip())
        self._update_estimate()

    def _out_changed(self, buf):
        if not self.programmatic:
            buf.remove_tag_by_name("ins", buf.get_start_iter(), buf.get_end_iter())

    def _set_actions(self, on):
        self.copy_b.set_sensitive(on)
        for b in self.refine_bs:
            b.set_sensitive(on)

    def load_text(self, text):
        self.programmatic = True
        self.src.get_buffer().set_text(text)
        self.programmatic = False
        self.src.grab_focus()

    def paste(self):
        self.win.read_clipboard(self.load_text)

    def clear(self):
        self.load_text("")
        self.out.get_buffer().set_text("")
        self.original = self.result = None
        self.out_stack.set_visible_child_name("empty")
        self.legend.set_visible(False)
        self.flags_wrap.set_visible(False)
        self.cost_lbl.set_label("")
        self._set_actions(False)

    def copy(self):
        t = text_of(self.out.get_buffer()).strip()
        if t:
            self.win.copy_out(t)

    # ── API ──
    def do_rewrite(self, refine=None):
        key = keystore.get_key()
        if not key:
            self.win.toast("Add your Anthropic API key first")
            self.win.preferences()
            return
        if refine:
            text, previous = self.original, text_of(self.out.get_buffer())
        else:
            text, previous = text_of(self.src.get_buffer()), None
        if not (text or "").strip():
            self.win.toast("Paste some text first")
            return
        s = store.settings()
        kind, tone = TYPES[self.type_dd.get_selected()], TONES[self.tone_dd.get_selected()]
        voice = self._voice()
        self.busy_lbl.set_label({"shorter": "Making it shorter…", "formal": "Making it more formal…",
                                 "casual": "Making it more casual…", "again": "Trying another version…"}
                                .get(refine, "Rewriting…"))
        self.out_stack.set_visible_child_name("busy")
        self.go.set_sensitive(False)
        self._set_actions(False)

        def done(r):
            self.go.set_sensitive(True)
            self.show_result(text, r)
            self.session_cost += r["cost"]
            self.cost_lbl.set_label(f"This one ${r['cost']:.4f} · session ${self.session_cost:.3f}")
            self.cost_lbl.set_tooltip_text(f"Served by {r['model']}")
            store.add_history({"original": text, "result": r["rewrite"], "type": kind, "tone": tone,
                               "cost": r["cost"], "model": r["model"], "flags": r["flags"], "notes": r["notes"]})

        def fail(e):
            self.go.set_sensitive(True)
            self._set_actions(self.result is not None)
            self.out_stack.set_visible_child_name("result" if self.result else "empty")
            self.win.toast(str(e) if isinstance(e, WriterError) else f"Something went wrong: {e}", 6)

        bg(lambda: rewrite(key, s["model"], s["effort"], text, kind, tone, voice, previous, refine), done, fail)

    def show_result(self, original, r):
        self.original, self.result = original, r
        self.programmatic = True
        sb, ob = self.src.get_buffer(), self.out.get_buffer()
        sb.set_text("")
        ob.set_text("")
        a, b = tokens(original), tokens(r["rewrite"])
        for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
            left, right = "".join(a[i1:i2]), "".join(b[j1:j2])
            if op == "equal":
                sb.insert(sb.get_end_iter(), left)
                ob.insert(ob.get_end_iter(), right)
                continue
            if left:
                if left.strip():
                    sb.insert_with_tags_by_name(sb.get_end_iter(), left, "del")
                else:
                    sb.insert(sb.get_end_iter(), left)
            if right:
                if right.strip():
                    ob.insert_with_tags_by_name(ob.get_end_iter(), right, "ins")
                else:
                    ob.insert(ob.get_end_iter(), right)
        self.programmatic = False
        self.out_stack.set_visible_child_name("result")
        self.legend.set_visible(True)
        self._set_actions(True)
        self._show_flags(original, r)

    def _show_flags(self, original, r):
        while (c := self.flags_box.get_first_child()):
            self.flags_box.remove(c)
        items = [("flag", f["quote"], f["concern"]) for f in r.get("flags", []) if f.get("quote")]
        items += guard(original, r["rewrite"])
        if r.get("notes", "").strip():
            items.append(("style", "", r["notes"].strip()))
        sb = self.src.get_buffer()
        for kind, quote, why in items:
            card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, css_classes=["issue"])
            card.set_size_request(320, -1)
            top = Gtk.Box(spacing=8)
            top.append(lbl("NOTE" if not quote and kind == "style" else KIND_LABEL[kind], css=["kind", kind]))
            if quote and kind == "flag":
                top.append(lbl(f"“{quote}”", css=["dim"], ellipsize=Pango.EllipsizeMode.END, hexpand=True))
                self._tag_quote(sb, quote)
            card.append(top)
            card.append(lbl(why, css=["reason"], wrap=True))
            self.flags_box.append(card)
        self.flags_wrap.set_visible(bool(items))

    def _tag_quote(self, buf, quote):
        it = buf.get_start_iter()
        found = it.forward_search(quote, Gtk.TextSearchFlags.CASE_INSENSITIVE, None)
        if found:
            buf.apply_tag_by_name("flag", found[0], found[1])

    def load_history(self, h):
        for i, t in enumerate(TYPES):
            if t == h.get("type"):
                self.type_dd.set_selected(i)
        for i, t in enumerate(TONES):
            if t == h.get("tone"):
                self.tone_dd.set_selected(i)
        self.show_result(h["original"], {"rewrite": h["result"], "flags": h.get("flags", []),
                                         "notes": h.get("notes", ""), "cost": h.get("cost", 0)})
        self.cost_lbl.set_label(f"From history · cost ${h.get('cost', 0):.4f}")


def _rgba(hexstr):
    c = Gdk.RGBA()
    c.parse(hexstr)
    return c


# ═══════════════════════════════════════════════ Grammar ═══════════════════════════════════════════════
class GrammarPage(Gtk.Box):
    def __init__(self, win):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                         margin_start=18, margin_end=18, margin_bottom=16, margin_top=4)
        self.win = win
        self.server = grammar.Server(store.settings()["lt_port"])
        self.issues = []          # dicts with GtkTextMarks "m0"/"m1"
        self.ignored = set()      # (rule, word) ignored this session
        self.selected = None
        self.recheck_id = 0
        self.programmatic = False
        self.checking = False

        row = Gtk.Box(spacing=10)
        self.status = lbl("Checks spelling, grammar, punctuation and clarity in UK English. "
                          "Runs on this computer only.", css=["dim"], hexpand=True,
                          ellipsize=Pango.EllipsizeMode.END)
        self.counts = lbl("", css=["count"], ellipsize=Pango.EllipsizeMode.END)
        self.check_b = btn("Check", css=("kuro", "accent"), cb=self.check, icon="tools-check-spelling-symbolic",
                           tip="Check again (Ctrl+Enter)")
        row.append(self.status)
        row.append(self.counts)
        row.append(btn("Copy text", cb=self.copy, icon="edit-copy-symbolic",
                       tip="Copy the corrected text (Ctrl+Shift+C)"))
        row.append(self.check_b)
        self.append(row)

        body = Gtk.Box(spacing=14, vexpand=True)
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, css_classes=["card"], hexpand=True)
        lh = Gtk.Box(spacing=8)
        lh.append(lbl("YOUR WORK", css=["heading"], hexpand=True))
        lh.append(btn("Paste", css=("flat-kuro",), cb=self.paste, icon="edit-paste-symbolic"))
        lh.append(btn("Clear", css=("flat-kuro",), cb=lambda: self.load_text(""), icon="edit-clear-all-symbolic"))
        left.append(lh)
        self.tv, sw = page_view()
        buf = self.tv.get_buffer()
        for k, col in UNDERLINE.items():
            buf.create_tag(k, underline=Pango.Underline.ERROR, underline_rgba=_rgba(col))
        buf.create_tag("long", background="rgba(240,138,164,0.10)")
        buf.create_tag("sel", background="rgba(225,29,46,0.30)")
        buf.connect("changed", self._changed)
        click = Gtk.GestureClick()
        click.connect("released", self._clicked)
        self.tv.add_controller(click)
        left.append(sw)
        body.append(left)

        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, css_classes=["card"])
        right.set_size_request(380, -1)
        right.set_hexpand(False)
        right.append(lbl("SUGGESTIONS", css=["heading"]))
        self.list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.list_sw = Gtk.ScrolledWindow(child=self.list, vexpand=True)
        self.list_sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.empty = lbl("Paste your text and press Check.\nNothing is rewritten: you accept or ignore "
                         "each suggestion yourself.", css=["faint"], wrap=True)
        self.list.append(self.empty)
        right.append(self.list_sw)
        body.append(right)
        self.append(body)

    # ── text ──
    def load_text(self, text, autocheck=False):
        self.tv.get_buffer().set_text(text)
        self.tv.grab_focus()
        if autocheck and text.strip():
            self.check()

    def paste(self):
        self.win.read_clipboard(lambda t: self.load_text(t, autocheck=True))

    def copy(self):
        t = text_of(self.tv.get_buffer())
        if t.strip():
            self.win.copy_out(t)

    def _changed(self, buf):
        if self.programmatic:
            return
        self._paint()
        if self.issues and not self.checking:  # re-check after a pause in typing (free, local)
            if self.recheck_id:
                GLib.source_remove(self.recheck_id)
            self.recheck_id = GLib.timeout_add(1500, self._auto_recheck)

    def _auto_recheck(self):
        self.recheck_id = 0
        self.check(quiet=True)
        return False

    # ── checking ──
    def check(self, quiet=False):
        text = text_of(self.tv.get_buffer())
        if not text.strip():
            if not quiet:
                self.win.toast("Paste some text first")
            return
        if self.checking:
            return
        self.checking = True
        self.check_b.set_sensitive(False)
        if not self.server.alive():
            self.status.set_label("Starting LanguageTool (first check takes a few seconds)…")
        else:
            self.status.set_label("Checking…")
        s = store.settings()
        if self.server.port != s["lt_port"]:
            self.server.stop()
            self.server = grammar.Server(s["lt_port"])
        dictionary = store.dictionary()
        clarity = s.get("clarity", True)

        def done(issues):
            self.checking = False
            self.check_b.set_sensitive(True)
            if text_of(self.tv.get_buffer()) != text:  # edited while checking → go again
                self.check(quiet=True)
                return
            self._set_issues([i for i in issues if (i["rule"], i["word"]) not in self.ignored])
            self.status.set_label("LanguageTool · UK English · offline")
            self.status.set_css_classes(["status-ok"])

        def fail(e):
            self.checking = False
            self.check_b.set_sensitive(True)
            self.status.set_label(str(e))
            self.status.set_css_classes(["status-warn"])

        bg(lambda: self.server.check(text, dictionary, clarity), done, fail)

    def _set_issues(self, issues):
        buf = self.tv.get_buffer()
        for i in self.issues:
            buf.delete_mark(i["m0"])
            buf.delete_mark(i["m1"])
        self.issues, self.selected = [], None
        for i in issues:
            # start mark keeps left gravity, end mark right gravity: a fix accepted at the edge of a
            # span (e.g. the first word of a long sentence) stays inside it instead of pushing it along
            i["m0"] = buf.create_mark(None, buf.get_iter_at_offset(i["start"]), True)
            i["m1"] = buf.create_mark(None, buf.get_iter_at_offset(i["end"]), False)
            self.issues.append(i)
        self._paint()
        self._rebuild_list()

    def _span(self, i):
        buf = self.tv.get_buffer()
        return buf.get_iter_at_mark(i["m0"]), buf.get_iter_at_mark(i["m1"])

    def _paint(self):
        buf = self.tv.get_buffer()
        s, e = buf.get_start_iter(), buf.get_end_iter()
        for t in list(UNDERLINE) + ["long", "sel"]:
            buf.remove_tag_by_name(t, s, e)
        for i in self.issues:
            a, b = self._span(i)
            buf.apply_tag_by_name("long" if i["kind"] == "long" else i["kind"], a, b)
        if self.selected is not None:
            a, b = self._span(self.selected)
            buf.apply_tag_by_name("sel", a, b)
        n = {}
        for i in self.issues:
            k = "clarity" if i["kind"] == "long" else i["kind"]
            n[k] = n.get(k, 0) + 1
        self.counts.set_label("  ·  ".join(f"{v} {k}" for k, v in n.items()) if n else
                              ("No issues found" if self.issues == [] and self.status.get_label().startswith("Language")
                               else ""))

    def _rebuild_list(self):
        while (c := self.list.get_first_child()):
            self.list.remove(c)
        if not self.issues:
            self.list.append(lbl("No issues found. Nice.", css=["faint"]))
            return
        for i in self.issues:
            i["card"] = self._card(i)
            self.list.append(i["card"])

    def _card(self, i):
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, css_classes=["issue"])
        top = Gtk.Box(spacing=8)
        top.append(lbl(KIND_LABEL[i["kind"]], css=["kind", i["kind"]]))
        if i["word"] and i["kind"] != "long":
            top.append(lbl(i["word"], css=["wrong"], ellipsize=Pango.EllipsizeMode.END, hexpand=True))
        card.append(top)
        card.append(lbl(i["reason"], css=["reason"], wrap=True))
        acts = Adw.WrapBox(child_spacing=6, line_spacing=6)
        for r in i["replacements"][:3]:
            shown = r if r.strip() else "(remove)" if r == "" else "(space)"
            b = btn(shown, css=("chip",), cb=lambda r=r: self.accept(i, r),
                    tip="Accept this fix")
            acts.append(b)
        if i["kind"] == "spelling" and i["word"]:
            acts.append(btn("Add to dictionary", css=("flat-kuro",), cb=lambda: self.add_word(i)))
        acts.append(btn("Ignore" if i["kind"] != "long" else "Fine as is", css=("flat-kuro",),
                        cb=lambda: self.ignore(i)))
        card.append(acts)
        click = Gtk.GestureClick()
        click.connect("released", lambda *_: self.select(i, scroll_text=True))
        card.add_controller(click)
        return card

    # ── accept / ignore ──
    def _drop(self, i):
        buf = self.tv.get_buffer()
        if i in self.issues:
            self.issues.remove(i)
        buf.delete_mark(i["m0"])
        buf.delete_mark(i["m1"])
        if i.get("card") and i["card"].get_parent():
            self.list.remove(i["card"])
        if self.selected is i:
            self.selected = None
        if not self.issues:
            self._rebuild_list()

    def accept(self, i, replacement):
        buf = self.tv.get_buffer()
        a, b = self._span(i)
        after = [o for o in self.issues if o is not i and self._span(o)[0].get_offset() >= b.get_offset()]
        self.programmatic = True
        buf.begin_user_action()
        buf.delete(a, b)
        buf.insert(buf.get_iter_at_mark(i["m0"]), replacement)
        buf.end_user_action()
        self.programmatic = False
        end = buf.get_iter_at_mark(i["m0"])
        end.forward_chars(len(replacement))
        for o in after:  # an issue that began right after the fixed words must not swallow the fix
            if self._span(o)[0].compare(end) < 0:
                buf.move_mark(o["m0"], end)
        # anything that overlapped the replaced words is stale now
        for o in [o for o in self.issues if o is not i and o["kind"] != "long"]:
            oa, ob = self._span(o)
            if oa.get_offset() >= ob.get_offset():
                self._drop(o)
        self._drop(i)
        self._paint()

    def ignore(self, i):
        self.ignored.add((i["rule"], i["word"]))
        self._drop(i)
        self._paint()

    def add_word(self, i):
        store.add_word(i["word"])
        for o in [o for o in self.issues if o["kind"] == "spelling" and o["word"] == i["word"]]:
            self._drop(o)
        self._paint()
        self.win.toast(f"“{i['word']}” added to your dictionary")

    def select(self, i, scroll_text=False):
        if self.selected and self.selected.get("card"):
            self.selected["card"].remove_css_class("selected")
        self.selected = i
        if i.get("card"):
            i["card"].add_css_class("selected")
            GLib.idle_add(self._scroll_card, i["card"])
        if scroll_text:
            self.tv.scroll_to_mark(i["m0"], 0.2, False, 0, 0)
        self._paint()

    def _scroll_card(self, card):
        ok, pt = card.compute_point(self.list, Graphene.Point())
        if ok:
            adj = self.list_sw.get_vadjustment()
            adj.set_value(max(0, pt.y - 20))
        return False

    def _clicked(self, gesture, n, x, y):
        bx, by = self.tv.window_to_buffer_coords(Gtk.TextWindowType.WIDGET, int(x), int(y))
        ok, it = self.tv.get_iter_at_location(bx, by)
        if not ok:
            return
        off = it.get_offset()
        hits = [i for i in self.issues if self._span(i)[0].get_offset() <= off <= self._span(i)[1].get_offset()]
        if hits:  # prefer a word-level issue over a whole long sentence
            hits.sort(key=lambda i: (i["kind"] == "long", self._span(i)[1].get_offset() - self._span(i)[0].get_offset()))
            self.select(hits[0])


# ═══════════════════════════════════════════════ Dialogs ═══════════════════════════════════════════════
class VoiceDialog(Adw.Dialog):
    def __init__(self, win):
        super().__init__(title="My voice", content_width=760, content_height=720)
        self.win = win
        v = store.voice()
        tb = Adw.ToolbarView()
        tb.add_top_bar(Adw.HeaderBar())
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin_start=20, margin_end=20,
                      margin_bottom=20)
        box.append(lbl("Paste 3 to 5 things you wrote yourself (emails, messages, posts). They're used once to "
                       "build a short style profile, and saved only on this computer. Rewrites then follow the "
                       "profile so they sound like you.", css=["dim"], wrap=True))
        self.samples = []
        old = v.get("samples", [])
        for n in range(5):
            box.append(lbl(f"Sample {n + 1}" + ("" if n < 3 else " (optional)"), css=["heading"]))
            tv = Gtk.TextView(css_classes=["page"], wrap_mode=Gtk.WrapMode.WORD_CHAR,
                              top_margin=6, bottom_margin=6, left_margin=6, right_margin=6)
            if n < len(old):
                tv.get_buffer().set_text(old[n])
            sw = Gtk.ScrolledWindow(child=tv, min_content_height=90, css_classes=["card"])
            sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            box.append(sw)
            self.samples.append(tv)
        row = Gtk.Box(spacing=8)
        self.build_b = btn("Build my style profile", css=("kuro", "accent"), cb=self.build,
                           icon="avatar-default-symbolic")
        self.spin = Adw.Spinner(visible=False)
        row.append(self.build_b)
        row.append(self.spin)
        row.append(Gtk.Box(hexpand=True))
        row.append(btn("Delete profile", css=("flat-kuro",), cb=self.delete))
        box.append(row)
        box.append(lbl("STYLE PROFILE", css=["heading"]))
        box.append(lbl("You can edit this directly. It's what gets sent with each rewrite.", css=["faint"]))
        self.profile = Gtk.TextView(css_classes=["page"], wrap_mode=Gtk.WrapMode.WORD_CHAR,
                                    top_margin=6, bottom_margin=6, left_margin=6, right_margin=6)
        self.profile.get_buffer().set_text(v.get("profile", ""))
        sw = Gtk.ScrolledWindow(child=self.profile, min_content_height=170, css_classes=["card"])
        box.append(sw)
        save = btn("Save", css=("kuro", "accent"), cb=self.save, icon="document-save-symbolic")
        save.set_halign(Gtk.Align.END)
        box.append(save)
        outer = Gtk.ScrolledWindow(child=box)
        outer.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        tb.set_content(outer)
        self.set_child(tb)

    def _samples(self):
        return [t for t in (text_of(tv.get_buffer()).strip() for tv in self.samples) if t]

    def build(self):
        samples = self._samples()
        if len(samples) < 3:
            self.win.toast("Paste at least 3 samples")
            return
        key = keystore.get_key()
        if not key:
            self.win.toast("Add your Anthropic API key in Preferences first")
            return
        self.build_b.set_sensitive(False)
        self.spin.set_visible(True)

        def done(r):
            profile, cost = r
            self.profile.get_buffer().set_text(profile)
            self.build_b.set_sensitive(True)
            self.spin.set_visible(False)
            self.win.toast(f"Profile built (cost ${cost:.4f}). Check it, then Save.")

        def fail(e):
            self.build_b.set_sensitive(True)
            self.spin.set_visible(False)
            self.win.toast(str(e), 6)

        bg(lambda: build_voice(key, store.settings()["model"], samples), done, fail)

    def save(self):
        profile = text_of(self.profile.get_buffer()).strip()
        if not profile:
            self.win.toast("Build or write a profile first")
            return
        store.save_voice(self._samples(), profile)
        self.win.rewrite.refresh_voice()
        self.win.toast("My voice saved")
        self.close()

    def delete(self):
        store.clear_voice()
        self.win.rewrite.refresh_voice()
        self.win.toast("Style profile deleted")
        self.close()


class HistoryDialog(Adw.Dialog):
    def __init__(self, win):
        super().__init__(title="History", content_width=640, content_height=620)
        self.win = win
        tb = Adw.ToolbarView()
        hb = Adw.HeaderBar()
        clear = btn("Clear", css=("flat-kuro",), cb=self.confirm_clear, icon="user-trash-symbolic")
        hb.pack_start(clear)
        tb.add_top_bar(hb)
        h = store.history()
        clear.set_sensitive(bool(h))
        if not h:
            tb.set_content(Adw.StatusPage(title="No rewrites yet", icon_name="document-open-recent-symbolic",
                                          description="Your last 20 rewrites are kept here, on this computer only."))
        else:
            lb = Gtk.ListBox(css_classes=["boxed-list"], selection_mode=Gtk.SelectionMode.NONE,
                             margin_start=16, margin_end=16, margin_bottom=16)
            for e in h:
                first = re.sub(r"\s+", " ", e["result"]).strip()
                when = datetime.datetime.fromtimestamp(e.get("time", 0)).strftime("%d %b %H:%M")
                row = Adw.ActionRow(title=GLib.markup_escape_text(first[:90] + ("…" if len(first) > 90 else "")),
                                    subtitle=f"{e.get('type', '')} · {e.get('tone', '')} · {when} · "
                                             f"${e.get('cost', 0):.4f}", activatable=True)
                row.add_suffix(Gtk.Image(icon_name="go-next-symbolic"))
                row.connect("activated", lambda _r, e=e: self.open(e))
                lb.append(row)
            sw = Gtk.ScrolledWindow(child=lb)
            tb.set_content(sw)
        self.set_child(tb)

    def open(self, e):
        self.win.stack.set_visible_child_name("rewrite")
        self.win.rewrite.load_history(e)
        self.close()

    def confirm_clear(self):
        d = Adw.AlertDialog(heading="Clear history?", body="Deletes all saved rewrites from this computer.")
        d.add_response("cancel", "Cancel")
        d.add_response("clear", "Clear")
        d.set_response_appearance("clear", Adw.ResponseAppearance.DESTRUCTIVE)
        d.connect("response", lambda _d, r: (store.clear_history(), self.win.toast("History cleared"),
                                             self.close()) if r == "clear" else None)
        d.present(self)


class Prefs(Adw.PreferencesDialog):
    def __init__(self, win):
        super().__init__(title="Preferences")
        self.win = win
        s = store.settings()
        page = Adw.PreferencesPage(title="Writer", icon_name="preferences-system-symbolic")

        g = Adw.PreferencesGroup(title="Anthropic API key",
                                 description="Stored in your GNOME keyring (Passwords and Keys), never in a file. "
                                             "Get one at console.anthropic.com.")
        self.key_row = Adw.PasswordEntryRow(title="Paste a new key to replace the saved one")
        self.key_row.set_show_apply_button(True)
        self.key_row.connect("apply", self.save_key)
        g.add(self.key_row)
        self.key_state = Adw.ActionRow(title="")
        self.rm_key = btn("Remove", css=("flat-kuro",), cb=self.remove_key)
        self.rm_key.set_valign(Gtk.Align.CENTER)
        self.key_state.add_suffix(self.rm_key)
        g.add(self.key_state)
        self._key_status()
        page.add(g)

        g2 = Adw.PreferencesGroup(title="Rewrite mode")
        ids = list(MODELS)
        self.model_row = Adw.ComboRow(title="Model", subtitle="Price per rewrite shown next to the Rewrite button",
                                      model=Gtk.StringList.new([MODELS[m][0] for m in ids]))
        self.model_row.set_selected(ids.index(s["model"]) if s["model"] in ids else 0)
        self.model_row.connect("notify::selected", lambda r, _p: self._set("model", ids[r.get_selected()]))
        g2.add(self.model_row)
        self.eff_row = Adw.ComboRow(title="Thinking effort", subtitle="Low is quick and cheap; fine for rewriting",
                                    model=Gtk.StringList.new([e.capitalize() for e in EFFORTS]))
        self.eff_row.set_selected(EFFORTS.index(s["effort"]) if s["effort"] in EFFORTS else 0)
        self.eff_row.connect("notify::selected", lambda r, _p: self._set("effort", EFFORTS[r.get_selected()]))
        g2.add(self.eff_row)
        page.add(g2)

        g3 = Adw.PreferencesGroup(title="Grammar mode",
                                  description="LanguageTool runs on this computer only (127.0.0.1). It starts on "
                                              "the first check and stops when you close the Writer.")
        cl = Adw.SwitchRow(title="Clarity hints", subtitle="Long sentences, redundant or unclear wording",
                           active=s.get("clarity", True))
        cl.connect("notify::active", lambda r, _p: self._set("clarity", r.get_active()))
        g3.add(cl)
        port = Adw.SpinRow.new_with_range(1025, 65535, 1)
        port.set_title("LanguageTool port")
        port.set_value(s["lt_port"])
        port.connect("notify::value", lambda r, _p: self._set("lt_port", int(r.get_value())))
        g3.add(port)
        g3.add(Adw.ActionRow(title="LanguageTool",
                             subtitle="Installed" if grammar.installed() else
                             "Not installed: bash ~/bapirlo-os/writer/install.sh languagetool"))
        page.add(g3)
        self.add(page)

    def _set(self, k, v):
        s = store.settings()
        s[k] = v
        store.save_settings(s)
        self.win.rewrite._update_estimate()

    def _key_status(self):
        k = keystore.get_key()
        self.key_state.set_title(f"Saved key: {k[:7]}…{k[-4:]}" if k else "No key saved")
        self.rm_key.set_sensitive(bool(k))

    def save_key(self, row):
        k = row.get_text().strip()
        if not k.startswith("sk-ant-"):
            self.add_toast(Adw.Toast(title="That doesn't look like an Anthropic key (sk-ant-…)"))
            return
        keystore.set_key(k)
        row.set_text("")
        self._key_status()
        self.add_toast(Adw.Toast(title="Key saved to the GNOME keyring"))

    def remove_key(self):
        keystore.clear_key()
        self._key_status()
        self.add_toast(Adw.Toast(title="Key removed"))


# ═══════════════════════════════════════════════ Window / app ═══════════════════════════════════════════
class Window(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Kuro Writer", default_width=1280, default_height=820,
                         css_classes=["bapirlo-writer"])
        self.set_icon_name("bapirlo-writer")
        self.toasts = Adw.ToastOverlay()
        tb = Adw.ToolbarView()
        hb = Adw.HeaderBar()
        hb.pack_start(lbl("KURO WRITER", css=["brand"], margin_start=6))
        self.stack = Adw.ViewStack()
        self.rewrite = RewritePage(self)
        self.grammar = GrammarPage(self)
        self.stack.add_titled_with_icon(self.rewrite, "rewrite", "Rewrite", "document-edit-symbolic")
        self.stack.add_titled_with_icon(self.grammar, "grammar", "Grammar", "tools-check-spelling-symbolic")
        hb.set_title_widget(Adw.ViewSwitcher(stack=self.stack, policy=Adw.ViewSwitcherPolicy.WIDE))
        for icon, tip, cb in (("open-menu-symbolic", "Preferences (Ctrl+,)", self.preferences),
                              ("document-open-recent-symbolic", "History", self.history),
                              ("avatar-default-symbolic", "My voice", self.voice)):
            b = Gtk.Button(icon_name=icon, tooltip_text=tip)
            b.connect("clicked", lambda *_, cb=cb: cb())
            hb.pack_end(b)
        tb.add_top_bar(hb)
        tb.set_content(self.stack)
        self.toasts.set_child(tb)
        self.set_content(self.toasts)
        self.stack.set_visible_child_name(store.settings()["mode"])
        self.stack.connect("notify::visible-child-name", self._mode_changed)
        self.last_copied = None

    def _mode_changed(self, *_):
        s = store.settings()
        s["mode"] = self.stack.get_visible_child_name()
        store.save_settings(s)

    def page(self):
        return self.grammar if self.stack.get_visible_child_name() == "grammar" else self.rewrite

    def toast(self, text, timeout=3):
        self.toasts.add_toast(Adw.Toast(title=GLib.markup_escape_text(text), timeout=timeout))

    # clipboard
    def read_clipboard(self, cb):
        clip = self.get_display().get_clipboard()

        def got(c, res):
            try:
                t = c.read_text_finish(res)
            except GLib.Error:
                t = None
            if not t and shutil.which("wl-paste"):  # Wayland focus race at launch: ask wl-paste
                try:
                    t = subprocess.run(["wl-paste", "-n", "-t", "text"], capture_output=True, text=True,
                                       timeout=2).stdout
                except (OSError, subprocess.TimeoutExpired):
                    t = None
            if t and t.strip():
                cb(t)
            else:
                self.toast("The clipboard has no text")
        clip.read_text_async(None, got)

    def copy_out(self, text):
        self.get_display().get_clipboard().set_content(Gdk.ContentProvider.new_for_value(text))
        self.last_copied = text
        self.toast("Copied. Paste it back where you were.")

    def preferences(self):
        Prefs(self).present(self)

    def history(self):
        HistoryDialog(self).present(self)

    def voice(self):
        VoiceDialog(self).present(self)


class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.win = None
        self.connect("shutdown", self._shutdown)

    def do_startup(self):
        Adw.Application.do_startup(self)
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK)
        css = Gtk.CssProvider()
        css.load_from_path(os.path.join(HERE, "style.css"))
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        for name, accels, cb in (
                ("run", ["<Control>Return"], lambda: self.win.page().check() if self.win.page() is self.win.grammar
                 else self.win.rewrite.do_rewrite()),
                ("copy-result", ["<Control><Shift>c"], lambda: self.win.page().copy()),
                ("prefs", ["<Control>comma"], lambda: self.win.preferences()),
                ("quit", ["<Control>q"], self.quit)):
            a = Gio.SimpleAction.new(name, None)
            a.connect("activate", lambda *_, cb=cb: cb())
            self.add_action(a)
            self.set_accels_for_action("app." + name, accels)

    def do_command_line(self, cmd):
        args = cmd.get_arguments()[1:]
        first = self.win is None
        if first:
            self.win = Window(self)
        if "--grammar" in args:
            self.win.stack.set_visible_child_name("grammar")
        elif "--rewrite" in args:
            self.win.stack.set_visible_child_name("rewrite")
        self.win.present()
        if "--clipboard" in args:
            self._load_clipboard_when_focused()
        return 0

    def _load_clipboard_when_focused(self):
        """Wayland only hands the clipboard to a focused window, so wait for focus before reading it."""
        w = self.win

        def load(text):
            p = w.page()
            if p is w.grammar:
                p.load_text(text, autocheck=True)
            else:
                p.clear()
                p.load_text(text)
            w.toast("Loaded from clipboard")

        if w.is_active():
            GLib.timeout_add(120, lambda: (w.read_clipboard(load), False)[1])
            return
        handler = None

        def on_active(*_):
            nonlocal handler
            if w.is_active():
                w.disconnect(handler)
                GLib.timeout_add(120, lambda: (w.read_clipboard(load), False)[1])
        handler = w.connect("notify::is-active", on_active)

    def _shutdown(self, *_):
        if self.win:
            self.win.grammar.server.stop()
            # Wayland drops our clipboard when we exit: hand the last copy to wl-copy so it survives
            t = self.win.last_copied
            clip = self.win.get_display().get_clipboard()
            if t and clip.is_local() and shutil.which("wl-copy"):
                try:
                    subprocess.Popen(["wl-copy", "--", t], start_new_session=True,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except OSError:
                    pass


def main():
    return App().run(sys.argv)
