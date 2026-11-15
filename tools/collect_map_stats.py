#!/usr/bin/env python3
"""Collect the map statistics into the website's data file.

    python3 tools/collect_map_stats.py /path/to/BAR-Maps > vb/maps-data.js

The numbers come from BAR-Maps/bar_map_stats.py, which reads them out of the
.sd7 archives; the description is the one the map carries.  The official map
(Voidborn Rift) is read from map/mapinfo.lua of this repo.

Everything ends up in one JavaScript file that the maps page loads with a
plain <script> tag - no fetch, so the page also works from the file system.
"""
import json
import os
import re
import subprocess
import sys

# folder, archive, preview image (all relative to the BAR-Maps repository)
MAPS = [
    ("AKUMA", "AKUMA/AKUMA.sd7", "AKUMA/akuma_minimap.png"),
    ("AVATAR", "AVATAR/avatar_v2.sd7", "AVATAR/avatar_v2_preview.png"),
    ("BLOCKLAND", "BLOCKLAND/minecraft_blockland_overworld_v2.sd7", "BLOCKLAND/minecraft_blockland_overworld_v2_minimap.png"),
    ("CHESS", "CHESS/chess_classical_v1.sd7", "CHESS/chess-minimap.png"),
    ("PARIS", "PARIS/paris.sd7", "PARIS/paris_preview.png"),
    ("planet_earth", "planet_earth/planet_earth_v1.sd7", "planet_earth/planet_earth_preview.png"),
    ("planet_mars", "planet_mars/planet_mars.sd7", "planet_mars/planet_mars_minimap.png"),
    ("SPACESHIP", "SPACESHIP/cosmic_spaceship_v1.sd7", "SPACESHIP/SPACESHIP-MINIMAP.png"),
    ("USA", "USA/usa.sd7", "USA/usa_minimap.png"),
    ("yin-yang", "yin-yang/yin-yang.sd7", "yin-yang/yin-yang_preview.png"),
]

# the preview images are copied next to the site, so they are served from here
PREVIEW_DIR = "vb/img"


def stats(repo, sd7):
    out = subprocess.run([sys.executable, os.path.join(repo, "bar_map_stats.py"), os.path.join(repo, sd7)],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return None
    t = out.stdout

    def grab(pattern, cast=str):
        m = re.search(pattern, t)
        return cast(m.group(1).strip()) if m else None

    d = {}
    m = re.search(r"^ (.+?)(?:\s+v(\S+))?\s*$", t, re.M)
    if m:
        d["name"] = m.group(1).strip()
        if m.group(2):
            d["version"] = m.group(2).strip()
    d["author"] = grab(r"Author\s+:\s+(.+)")
    d["description"] = grab(r"Description\s+:\s+(.+)")
    d["archive_size"] = grab(r"Archive\s+:\s+([\d.]+ MB)")
    d["md5"] = grab(r"md5 ([0-9a-f]+)")
    d["size"] = grab(r"Size\s+:\s+(.+)")
    d["height"] = grab(r"Height range\s+:\s+(.+?)\s+water coverage")
    d["water"] = grab(r"water coverage ~([\d.]+)%", float)
    d["players"] = grab(r"Start pos\s+:\s+(\d+)", int)
    d["mexes"] = grab(r" Mexes\s+:\s+(\d+)", int)
    d["metal_s"] = grab(r"Total metal/s\s+:\s+(\d+)", int)
    d["avg_mex"] = grab(r"Avg m/s / mex\s+:\s+([\d.]+)", float)
    d["mex_density"] = grab(r"Mex density\s+:\s+([\d.]+)", float)
    d["vents"] = grab(r"Geo vents\s+:\s+(\d+)", int)
    d["reclaim"] = grab(r"Reclaim metal\s+:\s+(\d+)", int)
    d["features"] = grab(r"Features\s+:\s+(\d+)", int)
    return d


def rift(root):
    """The official map: everything it says about itself is in map/mapinfo.lua."""
    p = os.path.join(root, "map", "mapinfo.lua")
    if not os.path.isfile(p):
        return None
    t = open(p, encoding="utf-8").read()

    def grab(pattern):
        m = re.search(pattern, t)
        return m.group(1).strip() if m else None

    smf = re.search(r"minheight\s*=\s*(-?\d+)", t)
    smax = re.search(r"maxheight\s*=\s*(-?\d+)", t)
    d = {
        "name": grab(r'name\s*=\s*"(.*?)"'),
        "version": grab(r'version\s*=\s*"(.*?)"'),
        "author": grab(r'author\s*=\s*"(.*?)"'),
        "description": grab(r'description\s*=\s*"(.*?)"'),
        "size": "10 x 10 map units  (5,120 x 5,120 elmos)",
        "height": "%s .. %s" % (smf.group(1) if smf else "?", smax.group(1) if smax else "?"),
        "players": 4,
        "mexes": 43,
        "archive_size": "0.9 MB",
    }
    return d


def main():
    repo = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    out = []

    # the official map first
    r = rift(root)
    if r:
        r.update({"id": "voidborn_rift", "official": True,
                  "preview": "img/voidborn-rift.webp",
                  "download": "https://github.com/bitopsy/voidborn/raw/master/dist/voidborn_rift.sd7",
                  "docs": "https://github.com/bitopsy/voidborn/blob/master/map/mapinfo.lua"})
        out.append(r)

    for folder, sd7, preview in MAPS:
        path = os.path.join(repo, sd7)
        # the site serves webp copies of the minimaps
        webp = os.path.splitext(os.path.basename(preview))[0] + ".webp"
        entry = {"id": folder, "official": False, "archive": sd7,
                 "preview": "img/maps/" + webp,
                 "download": "https://github.com/bitopsy/BAR-Maps/raw/master/" + sd7,
                 "docs": "https://github.com/bitopsy/BAR-Maps/blob/master/" + folder + "/",
                 "has_archive": os.path.isfile(path)}
        if entry["has_archive"]:
            entry.update(stats(repo, sd7) or {})
        out.append(entry)

    print("/* Map data for the Voidborn website - generated by tools/collect_map_stats.py,")
    print("   from the BAR-Maps repository and from map/mapinfo.lua. Do not edit by hand. */")
    print("window.VOIDBORN_MAPS = " + json.dumps(out, indent=1) + ";")


if __name__ == "__main__":
    main()
