#!/bin/sh
# Run from anywhere: builds dist/voidborn.sdz (game) and dist/voidborn_rift.sd7 (map) from this repo.
#
# The map archive needs the generated height map (map/maps), so the map is built
# first when the generator and its python packages are available.  Without them
# the existing map files are packed as they are.
set -e
cd "$(dirname "$0")/.."
rm -rf dist; mkdir -p dist
python3 build_sdz.py --no-install --no-engine-check   # checked build of dist/voidborn.sdz

# the map: generate the height map if we can, then pack it
# -ms=off keeps every file in its own stream instead of one solid block, so the
# components of the archive can be read one by one (the cost is 0.2% in size).
if [ ! -f map/maps/voidrift.smf ] && python3 -c "import numpy" 2>/dev/null; then
  python3 tools/build_map.py   # the height map and the skybox
fi
if command -v 7z >/dev/null 2>&1 && [ -d map/maps ]; then
  (cd map && 7z a -t7z -mx=9 -ms=off ../dist/voidborn_rift.sd7 mapinfo.lua maps >/dev/null)
elif command -v 7z >/dev/null 2>&1; then
  (cd map && 7z a -t7z -mx=9 -ms=off ../dist/voidborn_rift.sd7 mapinfo.lua >/dev/null)
fi
ls -la dist
