"""Grammar mode: a LanguageTool server on 127.0.0.1 (started on demand, stopped on quit) + local clarity checks.

Nothing in this module talks to the internet. LanguageTool's HTTPServer binds to localhost unless given
--public, which we never pass.
"""
import glob
import json
import os
import re
import shutil
import socket
import subprocess
import time
import urllib.parse
import urllib.request

JAR_GLOBS = ["/usr/share/java/languagetool/languagetool-server.jar",
             "/usr/share/languagetool/languagetool-server.jar",
             "/opt/languagetool*/languagetool-server.jar",
             os.path.expanduser("~/.local/share/languagetool*/languagetool-server.jar")]

KIND = {  # LanguageTool category id → our kind
    "TYPOS": "spelling",
    "GRAMMAR": "grammar", "CONFUSED_WORDS": "grammar", "SEMANTICS": "grammar", "MISC": "grammar",
    "CASING": "grammar", "COMPOUNDING": "grammar", "BRITISH_ENGLISH": "spelling", "AMERICAN_ENGLISH": "spelling",
    "PUNCTUATION": "punctuation", "TYPOGRAPHY": "punctuation",
    "REDUNDANCY": "clarity", "PLAIN_ENGLISH": "clarity", "REPETITIONS": "clarity",
}
# typographic nit-picks that would "restyle" text rather than correct it
DISABLED_RULES = ["EN_QUOTES", "DASH_RULE", "ELLIPSIS", "MULTIPLICATION_SIGN", "WORD_REPEAT_BEGINNING_RULE",
                  "PLUS_MINUS", "EN_UNPAIRED_QUOTES", "ARROWS", "APOS_TYP"]
LONG_SENTENCE = 35  # words


class GrammarError(Exception):
    pass


def find_jar():
    for g in JAR_GLOBS:
        hits = sorted(glob.glob(g))
        if hits:
            return hits[-1]
    return None


def classpath(jar):
    """Arch splits the release zip: jars in /usr/share/java/languagetool, rule data in /usr/share/languagetool.
    A plain unzipped release keeps both in one folder."""
    d = os.path.dirname(jar)
    parts = [d] + sorted(glob.glob(os.path.join(d, "*.jar")))
    if d == "/usr/share/java/languagetool" and os.path.isdir("/usr/share/languagetool"):
        parts.insert(0, "/usr/share/languagetool")
    return os.pathsep.join(parts)


def installed():
    return bool(find_jar() and shutil.which("java"))


class Server:
    def __init__(self, port):
        self.port = port
        self.proc = None

    @property
    def url(self):
        return f"http://127.0.0.1:{self.port}/v2/"

    def alive(self):
        try:
            with urllib.request.urlopen(self.url + "languages", timeout=1.5) as r:
                return r.status == 200
        except OSError:
            return False

    def ensure(self, timeout=60):
        """Start LanguageTool if it isn't already answering. Blocking: call from a thread."""
        if self.alive():
            return
        if not installed():
            raise GrammarError("LanguageTool isn't installed. Run: bash ~/bapirlo-os/writer/install.sh languagetool")
        with socket.socket() as s:
            if s.connect_ex(("127.0.0.1", self.port)) == 0:
                raise GrammarError(f"Port {self.port} is used by another program. Change it in Preferences.")
        if self.proc is None or self.proc.poll() is not None:
            self.proc = subprocess.Popen(
                ["java", "-Xms64m", "-Xmx700m", "-XX:+UseSerialGC", "-XX:TieredStopAtLevel=1",
                 "-cp", classpath(find_jar()), "org.languagetool.server.HTTPServer", "--port", str(self.port)],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                start_new_session=True)
        end = time.time() + timeout
        while time.time() < end:
            if self.proc.poll() is not None:
                raise GrammarError("LanguageTool stopped while starting (is Java installed?).")
            if self.alive():
                return
            time.sleep(0.4)
        raise GrammarError("LanguageTool took too long to start.")

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(3)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.proc = None

    def check(self, text, dictionary=(), clarity=True):
        self.ensure()
        body = urllib.parse.urlencode({
            "text": text, "language": "en-GB", "level": "default",
            "disabledRules": ",".join(DISABLED_RULES),
        }).encode()
        try:
            with urllib.request.urlopen(self.url + "check", data=body, timeout=60) as r:
                data = json.load(r)
        except OSError as e:
            raise GrammarError(f"LanguageTool didn't answer: {e}")
        u16 = _utf16_map(text)
        issues = []
        for m in data.get("matches", []):
            cat = m["rule"]["category"]["id"]
            kind = KIND.get(cat)
            if kind is None or (kind == "clarity" and not clarity):
                continue
            start, end = u16(m["offset"]), u16(m["offset"] + m["length"])
            word = text[start:end]
            if kind == "spelling" and word in dictionary:
                continue
            reps = [r["value"] for r in m.get("replacements", [])[:4]]
            issues.append({"start": start, "end": end, "kind": kind, "word": word,
                           "reason": _one_line(m.get("message") or m.get("shortMessage") or "Check this."),
                           "replacements": reps, "rule": m["rule"]["id"]})
        if clarity:
            issues += long_sentences(text)
        issues.sort(key=lambda i: (i["start"], i["end"]))
        return issues


def _one_line(msg):
    msg = re.sub(r"\s+", " ", msg).strip()
    first = re.split(r"(?<=[.!?])\s", msg, maxsplit=1)[0]
    return first if len(first) <= 140 else first[:137] + "…"


def _utf16_map(text):
    """LanguageTool offsets are Java UTF-16 units; Python/GTK use code points."""
    if all(ord(c) < 0x10000 for c in text):
        return lambda i: i
    table, n = [], 0
    for idx, c in enumerate(text):
        table.append(idx)
        if ord(c) >= 0x10000:
            table.append(idx)
    table.append(len(text))
    return lambda i: table[min(i, len(table) - 1)]


def long_sentences(text):
    out = []
    for m in re.finditer(r"[^.!?\n]+(?:[.!?]+|$)", text):
        words = re.findall(r"[\w'’-]+", m.group())
        if len(words) > LONG_SENTENCE:
            s = m.start() + (len(m.group()) - len(m.group().lstrip()))
            out.append({"start": s, "end": m.end(), "kind": "long", "word": "",
                        "reason": f"Long sentence ({len(words)} words). It may read more clearly split in two.",
                        "replacements": [], "rule": "BAPIRLO_LONG_SENTENCE"})
    return out
