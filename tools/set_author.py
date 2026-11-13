#!/usr/bin/env python3
"""Set every author attribution in the repo to "goddot info@bitopsy.com".

Handles both kinds of occurrences:
  * Lua/table assignments   author = "..."  /  author  = "..."
  * file header comments    --  author:  Someone

The "Copyright (C) ..." and "Licensed under ..." lines are left untouched.

Run from the repo root:
    python3 tools/set_author.py
"""
import os
import re

NEW = "goddot info@bitopsy.com"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SELF = os.path.abspath(__file__)

RE_ASSIGN = re.compile(r'''(?P<pre>\bauthor(?P<sp>[ \t]*)=[ \t]*)(?P<q>["'])(?P<val>[^"']*)(?P=q)''')
RE_HEADER = re.compile(r'''(?P<pre>--[ \t]*author:[ \t]*)(?P<val>[^\r\n]*)$''', re.M)

SKIP_DIRS = {".git", "tmp", "dist", "vb", "__pycache__"}
EXTS = (".lua", ".txt", ".md", ".py", ".sh", ".html")

changed = []


def fix(path):
    if os.path.abspath(path) == SELF:
        return
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return
    if "author" not in text and "Author" not in text:
        return

    orig = text
    # assignment form
    text = RE_ASSIGN.sub(lambda m: m.group("pre") + m.group("q") + NEW + m.group("q"), text)
    # header comment form
    text = RE_HEADER.sub(lambda m: m.group("pre") + NEW, text)

    if text != orig:
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        changed.append(os.path.relpath(path, ROOT))


for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
    for fn in filenames:
        if fn.endswith(EXTS):
            fix(os.path.join(dirpath, fn))

print("updated %d files" % len(changed))
for c in sorted(changed):
    print("  " + c)
