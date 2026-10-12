"""Rewrite mode: Claude API calls, prompts, cost maths and the local "fact guard"."""
import json
import re

TYPES = ["Email", "Placement application / cover letter", "LinkedIn post", "Casual message"]
TONES = ["Professional", "Friendly", "Confident", "Short and direct"]
MODELS = {  # id: (label, $ per MTok input, $ per MTok output)
    "claude-opus-5-5": ("Claude Opus 5.5 — best", 4.00, 20.00),
    "claude-sonnet-5-5": ("Claude Sonnet 5.5 — cheaper", 2.00, 10.00),
    "claude-haiku-5-5": ("Claude Haiku 5.5 — cheapest", 0.10, 0.50),
}
CACHE_READ = {"claude-opus-5-5": 0.20, "claude-sonnet-5-5": 0.20}  # $ per MTok; others ≈ 0.1 × input
EFFORTS = ["low", "medium", "high"]
REFINE = {
    "shorter": "Make it noticeably shorter. Cut anything that isn't pulling its weight, keep every fact that matters.",
    "formal": "Make it a step more formal. Still plain words and natural, just more polished.",
    "casual": "Make it a step more casual and relaxed, while staying appropriate for who it's going to.",
    "again": "Write a different version. Don't reuse the previous version's sentences or structure.",
}

SYSTEM = """You rewrite text for one person so it sounds like them on a good day: clear, natural, human. \
It must never read like AI wrote it.

How to write:
- UK English spelling and conventions (organise, colour, programme, CV, "Hi" or "Dear" as appropriate).
- Vary sentence length. Mix short sentences with longer ones. Plain, everyday words.
- No filler or stock phrases. Never use: "I hope this email finds you well", "I hope you're doing well", \
"delve", "leverage", "passionate", "thrilled", "excited to", "utilise", "synergy", "spearhead", "robust", \
"dynamic", "fast-paced", "esteemed", "in today's world", "I am writing to express", "game-changer", \
"journey", "at the end of the day", "furthermore", "moreover", "additionally".
- Use dashes rarely: at most one in the whole text, and none if a comma or full stop works. \
No bullet points or lists unless the original already had them.
- No emojis or hashtags unless the original had them (a LinkedIn post may keep the ones it had).
- Keep the person's meaning, intent and level of detail. Fix the flow, not the substance.

Truth rules, these matter most:
- Never invent facts, experience, skills, results, numbers, names, dates, companies or feelings. \
Everything in the rewrite must be supported by the original text.
- Don't upgrade claims ("helped with" must not become "led"; "some" must not become "many").
- If something needed is missing (a name, a role title), leave a clear placeholder like [name] rather than guessing.
- Separately, flag anything in the ORIGINAL that sounds exaggerated, vague or hard to back up, quoting the words \
exactly, with a short plain reason. Only flag real concerns; an empty list is fine.

Text types:
- Email: a fitting greeting and sign-off, gets to the point in the first two lines.
- Placement application / cover letter: specific and grounded, links what they have actually done to the role, \
no grovelling, no clichés about being a "team player".
- LinkedIn post: reads like a person, not a press release; a natural first line, short paragraphs.
- Casual message: like a text or chat message to someone they know.

Return only the JSON asked for. "rewrite" is the finished text and nothing else."""

SCHEMA = {
    "type": "object",
    "properties": {
        "rewrite": {"type": "string"},
        "flags": {"type": "array", "items": {
            "type": "object",
            "properties": {"quote": {"type": "string"}, "concern": {"type": "string"}},
            "required": ["quote", "concern"], "additionalProperties": False}},
        "notes": {"type": "string"},
    },
    "required": ["rewrite", "flags", "notes"],
    "additionalProperties": False,
}

VOICE_PROMPT = """Below are samples of one person's own writing. Describe how they write, as a short style \
profile another writer could follow to sound like them. Cover: sentence length and rhythm, how they open and \
close messages, typical words and phrases, punctuation habits, formality, humour, and anything they never do. \
Describe the style only: do not repeat facts about their life, studies or work. Plain text, 6 to 10 short \
lines starting with "- ", under 150 words.

{samples}"""


class WriterError(Exception):
    pass


def _client(key):
    import anthropic  # imported on first use: it takes over a second, and the window should open instantly
    return anthropic.Anthropic(api_key=key, timeout=120.0, max_retries=2)


def _create(key, model, effort, max_tokens, system, user, schema=None):
    import anthropic
    kw = {}
    oc = {"effort": effort}
    if schema:
        oc["format"] = {"type": "json_schema", "schema": schema}
    if model in ("claude-opus-5-5", "claude-sonnet-5-5"):
        # if a safety classifier declines, the API re-runs the request on Anthropic's recommended model
        kw = {"betas": ["server-side-fallback-2026-07-01"], "fallbacks": "default"}
    try:
        msg = _client(key).beta.messages.create(
            model=model, max_tokens=max_tokens, system=system, output_config=oc,
            messages=[{"role": "user", "content": user}], **kw)
    except anthropic.AuthenticationError:
        raise WriterError("The API key was rejected. Check it in Preferences.")
    except anthropic.PermissionDeniedError:
        raise WriterError("This API key isn't allowed to use that model.")
    except anthropic.RateLimitError:
        raise WriterError("Rate limited by the API. Wait a minute and try again.")
    except anthropic.BadRequestError as e:
        m = getattr(e, "message", str(e))
        if "credit" in m.lower():
            raise WriterError("Your Anthropic account is out of credit.")
        raise WriterError(f"The API refused the request: {m}")
    except anthropic.APIStatusError as e:
        raise WriterError(f"Anthropic API error {e.status_code}. Try again in a moment.")
    except anthropic.APIConnectionError:
        raise WriterError("Couldn't reach the Anthropic API. Are you online?")
    if msg.stop_reason == "refusal":
        raise WriterError("Claude declined to rewrite this text.")
    if msg.stop_reason == "max_tokens":
        raise WriterError("The answer was cut off (text too long). Try a shorter piece.")
    text = "".join(b.text for b in msg.content if b.type == "text")
    return text, msg


def cost_of(msg, requested):
    u = msg.usage
    served = msg.model if msg.model in MODELS else requested
    _, pin, pout = MODELS.get(served, MODELS["claude-opus-5-5"])
    pcr = CACHE_READ.get(served, pin * 0.1)
    cw = getattr(u, "cache_creation_input_tokens", 0) or 0
    cr = getattr(u, "cache_read_input_tokens", 0) or 0
    return (u.input_tokens * pin + cw * pin * 1.25 + cr * pcr + u.output_tokens * pout) / 1e6


def estimate(text, model, voice_profile=""):
    """Rough pre-send estimate in dollars (≈4 characters per token; low effort thinks little)."""
    _, pin, pout = MODELS[model]
    tin = 1000 + len(voice_profile) / 4 + len(text) / 4 * 2  # system + voice + text (+ previous version)
    tout = len(text) / 4 * 1.2 + 350
    return (tin * pin + tout * pout) / 1e6


def _system(voice_profile):
    blocks = [{"type": "text", "text": SYSTEM}]
    if voice_profile.strip():
        blocks.append({"type": "text", "text": "This person's own writing style (match it closely, it beats "
                       "the generic advice above where they conflict, except the truth rules):\n" + voice_profile})
    blocks[-1]["cache_control"] = {"type": "ephemeral"}
    return blocks


def rewrite(key, model, effort, text, kind, tone, voice_profile="", previous=None, refine=None):
    """Returns dict(rewrite, flags, notes, cost, model)."""
    parts = [f"Text type: {kind}", f"Tone: {tone}", "", "<original>", text.strip(), "</original>"]
    if previous and refine:
        parts += ["", "<previous_version>", previous.strip(), "</previous_version>", "",
                  "Change the previous version: " + REFINE[refine],
                  "Base everything on the original; the truth rules still apply."]
    else:
        parts += ["", "Rewrite the original."]
    raw, msg = _create(key, model, effort, 16000, _system(voice_profile), "\n".join(parts), SCHEMA)
    try:
        data = json.loads(raw)
    except ValueError:
        raise WriterError("Got an unreadable answer from the API. Try again.")
    data["cost"] = cost_of(msg, model)
    data["model"] = msg.model
    return data


def build_voice(key, model, samples):
    joined = "\n\n".join(f"<sample {i + 1}>\n{s.strip()}\n</sample {i + 1}>" for i, s in enumerate(samples))
    text, msg = _create(key, model, "low", 4000, "You analyse writing style.",
                        VOICE_PROMPT.format(samples=joined))
    return text.strip(), cost_of(msg, model)


# ── local checks on the result (free, instant) ─────────────────────────────────────────────────
BANNED = ["hope this email finds you", "hope you're doing well", "hope you are doing well", "delve",
          "leverage", "passionate", "thrilled", "utilise", "synergy", "spearhead", "esteemed",
          "in today's", "i am writing to express", "game-changer", "game changer", "furthermore",
          "moreover", "fast-paced", "robust"]
COMMON_CAPS = {"I", "I'm", "I've", "I'd", "I'll", "Hi", "Hello", "Dear", "Thanks", "Thank", "Best", "Kind",
               "Regards", "Cheers", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
               "Sunday", "January", "February", "March", "April", "May", "June", "July", "August",
               "September", "October", "November", "December", "UK", "CV", "LinkedIn", "Mr", "Ms", "Mrs", "Dr"}


def guard(original, result):
    """Things in the rewrite worth a second look: new numbers/names (possible invented facts) and AI tells."""
    out = []
    o_low = original.lower()
    o_nums = set(re.findall(r"\d+(?:[.,]\d+)?", original))
    for n in sorted(set(re.findall(r"\d+(?:[.,]\d+)?", result)) - o_nums):
        out.append(("fact", n, f"The number “{n}” isn't in your original. Check it's true."))
    o_words = {w.lower() for w in re.findall(r"[A-Za-z][\w'’-]*", original)}
    seen = set()
    for m in re.finditer(r"\b([A-Z][a-zA-Z'’-]+)", result):
        w = m.group(1)
        if w in COMMON_CAPS or w.lower() in o_words or w in seen or w.startswith("["):
            continue
        before = result[:m.start()].rstrip()
        if not before or before[-1] in ".!?:\n\"“":
            continue
        seen.add(w)
        out.append(("fact", w, f"“{w}” wasn't in your original. Make sure it's not an invented name or detail."))
    r_low = result.lower()
    for b in BANNED:
        if b in r_low and b not in o_low:
            out.append(("style", b, f"Contains “{b}”, which reads as AI-written."))
    dashes = len(re.findall(r"—|–| - ", result))
    if dashes > 1:
        out.append(("style", "—", f"{dashes} dashes. Consider swapping some for commas or full stops."))
    if re.search(r"^\s*(?:[-•*]|\d+[.)])\s", result, re.M) and not re.search(r"^\s*(?:[-•*]|\d+[.)])\s", original, re.M):
        out.append(("style", "list", "Added a list your original didn't have."))
    return out
