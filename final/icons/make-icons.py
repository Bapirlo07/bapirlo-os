#!/usr/bin/env python3
"""Kuro OS final-round icons (Guide, Doctor, Restart to Windows) in the round-7 style.
Reuses the templates of round7/icons/make-icons.py; writes scalable/apps + symbolic/apps into OUT."""
import os, re, sys

HERE = os.path.dirname(os.path.realpath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else "build/final-icons"
src = open(os.path.join(HERE, "..", "..", "round7", "icons", "make-icons.py")).read()
APP = re.search(r'APP = """(.*?)"""', src, re.S).group(1)
SYM = re.search(r'SYM = """(.*?)"""', src, re.S).group(1)

G = {
    # open book
    "guide": "M1 3.2C2.9 2.3 5.6 2.3 7.4 3.6V14C5.6 12.9 2.9 12.9 1 13.6z M2.4 4.2v7.6c1.3-.4 2.9-.4 3.6 0V4.4c-1.1-.6-2.5-.6-3.6-.2z"
             " M15 3.2C13.1 2.3 10.4 2.3 8.6 3.6V14c1.8-1.1 4.5-1.1 6.4-.4z M13.6 4.2v7.6c-1.3-.4-2.9-.4-3.6 0V4.4c1.1-.6 2.5-.6 3.6-.2z",
    # heart with a pulse line cut through it
    "doctor": "M8 14.5C3.2 11.2 1 8.6 1 5.8 1 3.6 2.7 2 4.7 2 6.1 2 7.3 2.8 8 4c.7-1.2 1.9-2 3.3-2C13.3 2 15 3.6 15 5.8c0 2.8-2.2 5.4-7 8.7z"
              " M2.6 7.6h2.6l1.1-2.2 1.6 4.4 1.3-2.9h4.2v1.2h-3.5L8 11.6 6.3 7.2l-.4.8H2.6z",
    # four window panes
    "windows": "M1.5 2.6L7 1.9V7.4H1.5z M8 1.8l6.5-.9v6.5H8z M1.5 8.4H7v5.5l-5.5-.7z M8 8.4h6.5v6.6L8 14.1z",
}
os.makedirs(f"{OUT}/scalable/apps", exist_ok=True)
os.makedirs(f"{OUT}/symbolic/apps", exist_ok=True)
for name, d in G.items():
    open(f"{OUT}/scalable/apps/bapirlo-{name}.svg", "w").write(APP.format(name=name, d=d))
    open(f"{OUT}/symbolic/apps/bapirlo-{name}-symbolic.svg", "w").write(SYM.format(d=d))
print("icons ->", OUT)
