#!/bin/sh
# Run from anywhere: builds dist/voidborn.sdz (game) and dist/voidborn_rift.sd7 (map) from this repo.
set -e
cd "$(dirname "$0")/.."
rm -rf dist; mkdir -p dist
python3 build_sdz.py --no-install --no-engine-check   # checked build of dist/voidborn.sdz
if command -v 7z >/dev/null 2>&1 && [ -d map ]; then (cd map && 7z a -t7z -mx=9 ../dist/voidborn_rift.sd7 mapinfo.lua skybox.dds maps >/dev/null); fi
ls -la dist
