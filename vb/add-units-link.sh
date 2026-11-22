#!/bin/sh
# Adds the "Units" link to the top navigation and the footer of every page in a folder.
# Safe to run twice (skips pages that already have it) and keeps a .bak of every page it changes.
# usage: sh add-units-link.sh /path/to/vb
dir="${1:-.}"
for f in "$dir"/*.html; do
  case "$f" in */units.html) continue;; esac
  grep -q 'href="./units.html"' "$f" && { echo "skip   $f (already linked)"; continue; }
  cp "$f" "$f.bak"
  perl -0pi -e 's{(<a class="navlink" href="\./forge\.html")}{<a class="navlink" href="./units.html">Units</a>\n$1}; s{(<a href="\./forge\.html">Unit Forge</a>)}{<a href="./units.html">Units</a> &middot; $1}' "$f"
  if cmp -s "$f" "$f.bak"; then echo "NOCHANGE $f (no Unit Forge link found to anchor on)"; rm "$f.bak"; else echo "linked $f"; fi
done
