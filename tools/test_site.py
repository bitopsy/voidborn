#!/usr/bin/env python3
"""Check the website: every local file a page refers to must exist, every page
must be reachable from every other one, and no page may load anything from the
network.

    python3 tools/test_site.py

It runs as part of build_sdz.py (the smoke tests), so a broken link in the
website is caught by the build.
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SITE = os.path.join(ROOT, "vb")
PAGES = ["index.html", "play.html", "maps.html", "forge.html"]

fails = 0


def check(name, ok, info=""):
    global fails
    print(("ok    " if ok else "FAIL  ") + name + (("  (" + str(info) + ")") if info else ""))
    if not ok:
        fails += 1


# ---------------------------------------------------------------- the local files
for page in PAGES:
    path = os.path.join(SITE, page)
    if not os.path.isfile(path):
        check(f"{page} exists", False)
        continue
    src = open(path, encoding="utf-8").read()
    refs = set(re.findall(r'(?:src|href)="(\.?/?[^"#:]+)"', src))
    for ref in sorted(refs):
        if ref.startswith(("http", "mailto", "#")):
            continue
        target = os.path.normpath(os.path.join(SITE, ref.lstrip("./")))
        check(f"{page} -> {ref}", os.path.isfile(target), "missing" if not os.path.isfile(target) else "")

# ------------------------------------------------------- the pages reach each other
for page in PAGES:
    src = open(os.path.join(SITE, page), encoding="utf-8").read()
    for other in PAGES:
        if other == page:
            continue
        check(f"{page} links to {other}", re.search(r'href="[^"]*' + other + '"', src) is not None)

# --------------------------------------------------------- nothing from the network
for page in PAGES:
    src = open(os.path.join(SITE, page), encoding="utf-8").read()
    head = src[:src.lower().find("</head>") + 7] if "</head>" in src.lower() else src
    for m in re.finditer(r'(?:src|href)="(https?://[^"]+)"', head):
        check(f"{page} loads nothing from the network: {m.group(1)}", False)
    for m in re.finditer(r"url\((https?://[^)]+)\)", head):
        check(f"{page} loads nothing from the network: {m.group(1)}", False)

# ------------------------------------------------------------- the data file
src = open(os.path.join(SITE, "maps-data.js"), encoding="utf-8").read()
check("maps-data.js has the map list", "VOIDBORN_MAPS" in src)
import json
data = json.loads(src[src.index("["):src.rindex(";")])
check("maps-data.js parses", isinstance(data, list), f"{len(data)} maps")
check("the official map is first", data and data[0].get("id") == "voidborn_rift")
for m in data:
    p = os.path.join(SITE, m["preview"])
    check(f"preview of {m['id']}", os.path.isfile(p))

# ------------------------------------------------------------------ the sizes
total = 0
for root, _, files in os.walk(SITE):
    for f in files:
        total += os.path.getsize(os.path.join(root, f))
print(f"\nthe whole site is {total/1024:.0f} KB")
for page in PAGES:
    print(f"  {page:14} {os.path.getsize(os.path.join(SITE, page))/1024:.1f} KB")

print("\nALL PASSED" if fails == 0 else f"\n{fails} FAILED")
sys.exit(1 if fails else 0)
