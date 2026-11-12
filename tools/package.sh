#!/bin/sh
set -e
cd /home/claude/vb
rm -rf dist; mkdir -p dist
# map
(cd map && rm -f ../dist/voidborn_rift.sd7 && 7z a -t7z -mx=9 ../dist/voidborn_rift.sd7 mapinfo.lua skybox.dds maps >/dev/null)
# game (zip -> .sdz)
(cd game && rm -f ../dist/voidborn.sdz && zip -q -9 -r ../dist/voidborn.sdz . -x '*.DS_Store')
ls -la dist
