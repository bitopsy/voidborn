# Applying the update to f33.fr/vb

Upload to the site folder (same level as index.html):
- units.html, units.css   (new)
- roadmap.html            (replaces the old one: see note 1)

Then:
1. Nav and footer: run `sh add-units-link.sh /path/to/vb` (idempotent, keeps .bak files), or add by hand
   `<a class="navlink" href="./units.html">Units</a>` before the Unit Forge link.
2. Home page: replace the "See it in a video" section with video-playlist-section.html (one playlist embed, loads only on click).
3. play.html (if it still embeds the single 26-minute video): delete that embed and its script, and put in its place
   `<a class="btn" href="https://youtube.com/playlist?list=PLErmsWWFp8sk&amp;si=sPq5xfspewX0n2hN" rel="noopener">Watch the playlist on YouTube</a>`.

Notes
1. roadmap.html was rebuilt from the repo's roadmap plus docs 0.1-0.19. If the live roadmap has edits that are not in the
   repo, merge them in before overwriting.
2. The playlist ID `PLErmsWWFp8sk` is only 13 characters; YouTube playlist IDs are normally 34. If the embed shows
   "video unavailable", the ID was truncated when it was copied. It is set once, in data-list.
3. Optional clean-up: img/video-015.webp is no longer used by any page.
