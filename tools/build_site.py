#!/usr/bin/env python3
"""Rebuild vb/index.html: shared stylesheet, navigation, the new features and the
links to the sub pages.  The big unit and structure blocks are kept as they are.
"""
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
P = os.path.join(ROOT, "vb", "index.html")
src = open(P, encoding="utf-8").read()

# ---------------------------------------------------------------- the nav
NAV = """<nav class="topnav"><div class="wrap">
<a class="brand" href="./index.html">VOID<span>BORN</span></a>
<a class="navlink" href="./index.html" aria-current="page">Home</a>
<a class="navlink" href="./play.html">Play &amp; Download</a>
<a class="navlink" href="./maps.html">Maps</a>
<a class="navlink" href="./forge.html">Unit Forge</a>
<span class="spacer"></span>
<a class="btn sm dc" href="https://discord.com/channels/1481771055063502925/">Discord</a>
</div></nav>

"""

# ------------------------------------------------------- the shared stylesheet
src = re.sub(r"<style>.*?</style>", '<link rel="stylesheet" href="./style.css">', src, flags=re.S)

# the nav goes right after <body>
src = src.replace("<body>\n\n", "<body>\n\n" + NAV, 1)

# ------------------------------------------------------------- the map section
OLD_MAP = re.search(r'<section id="map">.*?</section>', src, re.S).group(0)
NEW_MAP = """<section id="map"><div class="wrap">
<h2>Voidborn Rift, and a family of arenas</h2>
<p class="lead">The official map is <b>Voidborn Rift</b>: a 5120 &times; 5120 void of floating asteroids for 2&ndash;4 players. Two
symmetric home asteroids hold ten metal spots each, with three terrace heights and a crater-ring Eye in the centre. Islands float
in a true void under a star and nebula skybox, and 43 metal spots are up for grabs.</p>
<div class="grid">
<div class="card big"><h3>Voidborn Rift</h3><p>The official arena. No water, only void &ndash; everything flies, and the height you fight at
matters more than the ground you stand on.</p><p style="margin-top:12px"><a class="btn sm" href="./maps.html">All the maps</a></p></div>
<div class="card big"><h3>Ten more arenas</h3><p>The map repository holds ten more: Akuma, Avatar, Blockland, Chess, Paris, Planet Earth,
Planet Mars, Cosmic Spaceship, the USA and Yin-Yang &ndash; from a 2-player duel to a 20-player free-for-all, each with its own
size, terrain, metal layout and preview.</p><p style="margin-top:12px"><a class="btn sm alt" href="./maps.html">Map list with statistics</a></p></div>
</div>
<div class="mapbox" style="margin-top:26px"><div>
<img class="mm" src="img/minimap.webp" width="520" height="520" loading="lazy" decoding="async" alt="Voidborn Rift minimap">
</div><div>
<div class="chips" style="justify-content:flex-start;margin:0"><span class="chip"><b>43</b> metal spots</span><span class="chip">2v2 start spots</span><span class="chip"><b>3</b> terrace heights</span><span class="chip">No water, only void</span></div>
<p class="lead" style="margin-top:18px">Every map is a <code>.sd7</code> archive you drop into the <code>maps/</code> folder of your engine
data directory. No rebuild of the game needed.</p>
</div></div>
</div></section>"""
src = src.replace(OLD_MAP, NEW_MAP)

# ------------------------------------------------------------ the play section
OLD_PLAY = re.search(r'<section id="play">.*?</section>', src, re.S).group(0)
NEW_PLAY = """<section id="play"><div class="wrap">
<h2>Play it in five minutes</h2>
<p class="lead">Voidborn is a standalone game: put two archives in your Spring data folder, then start the engine with a start script.</p>
<pre>&lt;Spring data dir&gt;/games/voidborn.sdz
&lt;Spring data dir&gt;/maps/voidborn_rift.sd7
&lt;Spring data dir&gt;/engine/&lt;version&gt;/spring  /path/to/Play_Choir_vs_Bot.txt</pre>
<p class="lead">When the game screen loads, press Enter or the Start button. Use <b>Play_Maw_vs_Bot.txt</b> for the swarm, or <b>Watch_Bot_vs_Bot.txt</b> to spectate.</p>
<div class="btns" style="justify-content:flex-start;margin-top:20px">
<a class="btn" href="./play.html">Downloads for Linux and Windows</a>
<a class="btn alt" href="https://github.com/skynet-gh/skylobby/releases/latest">SkyLobby for multiplayer</a>
<a class="btn alt" href="https://springrts.com/">The Spring engine</a>
</div>
</div></section>"""
src = src.replace(OLD_PLAY, NEW_PLAY)

# --------------------------------------------- the new features and the forge
NEW_SECTIONS = """<section id="features"><div class="wrap">
<h2>Built for the game, not for a screenshot</h2>
<p class="lead">The interface is written in Lua and runs inside the engine: everything below is drawn by the game itself,
with no external tool and nothing to install.</p>
<div class="grid">
<div class="card big"><h3>A production queue that queues</h3><p>The build panel always lists every mobile unit your factories can build.
Click one and it is queued at the selected factory, or at the first factory that can build it. Every factory has its own
line and they all build in parallel, each tile showing a pie chart and how many are waiting. Middle click holds a line,
right click takes one unit out, ctrl+right cancels the line and refunds what was paid.</p></div>
<div class="card big"><h3>A factory that is not finished yet</h3><p>Order a unit from a hive that is still under construction and it waits for it:
the tile shows a cyan clock, the hover text says <em>pending</em>, and not a single unit of metal is paid until the hive is
done. Then the line starts on its own.</p></div>
<div class="card"><h3>Health bars</h3><p>A bar above every visible unit: green to red for yours and your allies, red for the enemy,
and a second blue bar for the build progress of an unfinished structure.</p></div>
<div class="card"><h3>Sensor ranges</h3><p>The line of sight (green) and the radar (blue) circles on the ground for the units you
select, and for the structure you are placing.</p></div>
<div class="card"><h3>Role icons when you zoom out</h3><p>Far out, every unit turns into a white glyph of its role &ndash; commander,
builder, scout, raider, artillery, heavy &ndash; which the engine tints with the team colour.</p></div>
<div class="card"><h3>Everything is measurable</h3><p>The unit census tracks every unit on the field: totals, histograms of health, speed,
range, damage and experience, and which units are closest to splitting.</p></div>
</div>
</div></section>

<section id="forge"><div class="wrap">
<h2>Create your own units, and pay for them</h2>
<p class="lead">Voidborn is not a closed game. The unit forge takes an existing unit, changes its numbers with sliders, gives it a
brand new 3D body built out of primitives and maps a picture onto it &ndash; then puts a price on it, because a unit that is
stronger than the one it was cloned from is not free.</p>
<div class="grid">
<div class="card"><h3>The price is worked out for you</h3><p>Health, speed, range, damage, reload, sight, altitude, the 3D body and the
group size all add a share of the base metal cost of the unit. The premium also costs build time: the unit takes up to nine
times as long to build as the one it was cloned from.</p></div>
<div class="card"><h3>Units grow and split</h3><p>Every mobile unit grows as it gains experience and splits in two at 0.14 &ndash; by then
it has doubled in size. Both halves keep the health fraction, the orders and the whole design. The host sets both numbers
in the settings panel.</p></div>
</div>
<div class="btns" style="justify-content:flex-start;margin-top:22px">
<a class="btn" href="./forge.html">How the forge, the price and the split work</a>
<a class="btn alt" href="https://github.com/bitopsy/voidborn">Read the source</a>
</div>
</div></section>

"""

anchor = '<section id="join">'
src = src.replace(anchor, NEW_SECTIONS + anchor, 1)

# ------------------------------------------------------------------- the footer
OLD_FOOT = re.search(r'<footer>.*?</footer>', src, re.S).group(0)
NEW_FOOT = """<footer><div class="wrap">
<p><a href="./index.html">Voidborn</a> &middot; <a href="./play.html">Play &amp; Download</a> &middot; <a href="./maps.html">Maps</a> &middot; <a href="./forge.html">Unit Forge</a> &middot;
<a href="https://github.com/bitopsy/voidborn">GitHub</a> &middot; <a href="https://github.com/bitopsy/BAR-Maps">Maps repo</a> &middot; <a href="https://discord.com/channels/1481771055063502925/">Discord</a></p>
<p>Voidborn is a free, open-source game by <a href="https://github.com/bitopsy">bitopsy</a>.</p>
</div></footer>"""
src = src.replace(OLD_FOOT, NEW_FOOT)

# the hero gets a link to the play page as well
src = src.replace('<a class="btn" href="https://github.com/bitopsy/voidborn">Get the game on GitHub</a>',
                  '<a class="btn" href="./play.html">Download and play</a>'
                  '<a class="btn alt" href="https://github.com/bitopsy/voidborn">Get the game on GitHub</a>')

open(P, "w", encoding="utf-8").write(src)
print("index.html rebuilt:", len(src), "bytes")
