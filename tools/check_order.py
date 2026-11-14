#!/usr/bin/env python3
"""Find local functions that are used before they are defined.

Lua resolves an unknown name to a global at call time, so a local function that
is called before its "local function" line runs hits a nil global instead.  The
engine only shows that as a runtime error in the log, which is easy to miss.

    python3 tools/check_order.py [file.lua ...]
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DEF = re.compile(r"^\s*local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)")
ASSIGN = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function")
LOCALVAR = re.compile(r"^\s*local\s+([A-Za-z_][A-Za-z0-9_, \t]*)\s*(?:=|,|\)|$)")

KEYWORDS = {
    "if", "for", "while", "return", "function", "and", "or", "not", "local", "print",
    "pcall", "xpcall", "tostring", "tonumber", "type", "pairs", "ipairs", "require",
    "setmetatable", "getmetatable", "assert", "error", "select", "unpack", "rawget",
    "rawset", "string", "table", "math", "os", "io", "coroutine", "next", "load",
    "loadstring", "setfenv", "getfenv", "collectgarbage", "print", "in", "do", "end",
}

SKIP_DIRS = {".git", "tmp", "dist", "vb", "__pycache__"}


def strip(line, in_block):
    """Remove comments and string literals so only code is left."""
    if in_block:
        end = line.find("]]")
        if end < 0:
            return "", True
        line = line[end + 2:]
        in_block = False
    out, i, n = [], 0, len(line)
    while i < n:
        c = line[i]
        if c == "-" and line[i:i + 2] == "--":
            if line[i:i + 4] == "--[[":
                return "".join(out), True
            break
        if c == '"' or c == "'":
            quote = c
            i += 1
            while i < n:
                if line[i] == "\\":
                    i += 2
                    continue
                if line[i] == quote:
                    i += 1
                    break
                i += 1
            out.append('""')
            continue
        out.append(c)
        i += 1
    return "".join(out), in_block


def check(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        raw = f.readlines()
    lines, in_block = [], False
    for l in raw:
        code, in_block = strip(l, in_block)
        lines.append(code)
    defined = set()
    problems = []
    for n, line in enumerate(lines, 1):
        m = DEF.match(line) or ASSIGN.match(line)
        if m:
            defined.add(m.group(1))
            continue
        m = LOCALVAR.match(line)
        if m:
            for nm in m.group(1).split(","):
                nm = nm.strip()
                if nm:
                    defined.add(nm)
            continue
        for m in re.finditer(r"(?<![\w.:])([A-Za-z_][A-Za-z0-9_]*)\s*\(", line):
            name = m.group(1)
            if name in KEYWORDS or name in defined:
                continue
            later = any(DEF.match(l) or ASSIGN.match(l) for l in lines[n:])
            if later:
                problems.append((n, name, raw[n - 1].rstrip()))
    return problems


def main():
    files = sys.argv[1:]
    if not files:
        files = []
        for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, "game")):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for fn in filenames:
                if fn.endswith(".lua"):
                    files.append(os.path.join(dirpath, fn))
    bad = 0
    for path in sorted(files):
        rel = os.path.relpath(path, ROOT)
        for n, name, line in check(path):
            bad += 1
            print(f"{rel}:{n}: '{name}' is called before it is defined -> {line.strip()}")
    if not bad:
        print("no forward calls found")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
