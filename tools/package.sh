#!/bin/sh
# Run from anywhere: builds dist/voidborn.sdz (game) and dist/voidborn_rift.sd7 (map) from this repo.
set -e
cd "$(dirname "$0")/.."
rm -rf dist; mkdir -p dist
(cd game && zip -q -9 -r ../dist/voidborn.sdz . -x '*.DS_Store')
if command -v 7z >/dev/null 2>&1 && [ -d map ]; then (cd map && 7z a -t7z -mx=9 ../dist/voidborn_rift.sd7 mapinfo.lua skybox.dds maps >/dev/null); fi
ls -la dist
