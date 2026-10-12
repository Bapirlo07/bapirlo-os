# Bapirlo Writer

A small GTK4/libadwaita writing app for Bapirlo OS, styled in the Kuro palette. It has two modes.

**Rewrite** (Claude API) is for your own emails, placement applications, cover letters, LinkedIn posts and messages.
Pick a type and a tone, press Rewrite (Ctrl+Enter), and you get a UK-English version that sounds like a person
wrote it. The result sits next to your original, with removed words in red and new wording in green. Then use
Copy, Shorter, More formal, More casual or Try again.

- **Nothing gets invented.** The prompt forbids new facts and upgraded claims ("helped" never becomes "led").
  The model also flags anything in your original that sounds exaggerated. A free local check then looks at the
  result for numbers and names that weren't in your text, AI-sounding words, extra dashes and new bullet lists.
  All of this appears under **Worth a second look**.
- **My voice** (person icon): paste 3–5 samples of your own writing once. Claude turns them into a short style
  profile, which you can read and edit. Only the profile is sent with each rewrite, not the samples. Turn it on
  or off with the switch next to Rewrite.
- **Cost:** an estimate shows next to Rewrite, and the real cost (from the API's token counts) shows under each
  result, plus a running total for the session.
- **History** (clock icon): your last 20 rewrites, stored only on this computer. Clear them from the header.

**Grammar** is for uni work. It checks spelling, grammar and punctuation in UK English, plus clarity (very long
sentences, redundant wording). It never rewrites your content. Each issue is underlined in your text and listed
with a suggested fix and a one-line reason. You accept, ignore or add to your dictionary one issue at a time.
It uses **LanguageTool running locally** on 127.0.0.1, so coursework never leaves the laptop. LanguageTool starts
on your first check and stops when you close the Writer.

## Install

```bash
bash ~/bapirlo-os/writer/install.sh               # app, Start menu entry + icon, Super+Shift+H
bash ~/bapirlo-os/writer/install.sh languagetool  # Grammar mode engine (sudo pacman, ~530 MB)
bash ~/bapirlo-os/writer/install.sh restore       # undo
```

Then open **Preferences** (Ctrl+,) and paste your Anthropic API key (console.anthropic.com → API keys).

## Hotkey: Super+Shift+H

1. Copy some text anywhere (Ctrl+C).
2. Press **Super+Shift+H**. The Writer opens (or comes to the front) with that text loaded, in whichever mode you
   used last. Grammar mode checks it straight away.
3. Press **Copy** (Ctrl+Shift+C), then paste the result back where you were.

Other keys: Ctrl+Enter rewrite or check · Ctrl+Shift+C copy the result · Ctrl+, preferences · Ctrl+Q quit.

## Privacy and where things live

| What | Where |
|---|---|
| API key | GNOME keyring (libsecret, schema `os.bapirlo.Writer`), never in a file or the code. See it in *Passwords and Keys*. |
| Settings, style profile, dictionary | `~/.config/bapirlo/writer/*.json` (mode 0600) |
| History (last 20) | `~/.local/share/bapirlo-writer/history.json` (0600) |
| Python env (anthropic SDK) | `~/.local/share/bapirlo-writer/venv` (uses the system GTK/PyGObject) |
| Sent to Anthropic | Rewrite mode only: your text, the type and tone, and the style profile if it's on |
| Sent anywhere in Grammar mode | Nothing. LanguageTool listens on localhost only (it is started without `--public`) |

## Choices you can change (Preferences)

- **Model:** Claude Opus 5.5 by default (best writing, ≈1–2 p per email). Sonnet 5.5 is half that; Haiku 5.5 is
  a fraction of a penny but writes less naturally.
- **Thinking effort:** low by default, which is plenty for rewriting.
- **Clarity hints** and the **LanguageTool port** (8081).

Opus 5.5 and Sonnet 5.5 requests use the API's server-side fallback (`fallbacks: "default"`). If a safety
classifier wrongly declines a harmless email, the request is retried on Anthropic's recommended fallback model
instead of failing.

## Files

```
bapirlo-writer          launcher (runs the module with the venv's Python)
install.sh              install / languagetool / restore
bapirlo-writer.svg      app icon (Kuro: ink squircle, paper page, crimson nib)
bapirlo_writer/
  app.py                window, both modes, dialogs, clipboard + hotkey handling
  rewrite.py            prompts, Claude API call, cost maths, local fact/style guard
  grammar.py            LanguageTool server lifecycle + clarity checks
  keystore.py           API key in the GNOME keyring
  store.py              settings, voice profile, history, dictionary
  style.css             Kuro styling
```

Backups of anything the installer changes (custom-keybindings list, Start menu entry, icons) go to
`~/theme-backups/<date>-writer`, and `~/theme-backups/LATEST-WRITER` points at the newest one.
