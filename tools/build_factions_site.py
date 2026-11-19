#!/usr/bin/env python3
"""0.16: adds the Tympan Conclave and the Miasma Bloom to the website (vb/) and writes their sprite sheets.

  * vb/img/tympan.webp, vb/img/miasma.webp   4x4 sprite sheets of the 128 px unit pictures (units first, then structures) -
    the same layout as choir.webp / maw.webp; the root PNG sheets voidborn_<faction>_units.png get the same pictures
  * the unit and structure cards of the home page, with the radar of each unit computed from the unit definitions, scaled
    the way the cards of the first two factions are:   durability sqrt(hp/13000), range range/820, altitude alt/230,
    metal cost metal/2500, value (hp per metal)/14 - every axis clipped to 0.05 .. 1
  * small text changes on index / play / story / roadmap

Safe to run again: generated blocks sit between <!--vb016:...--> markers and are replaced, the text changes are exact
replacements that do nothing once made.      python3 tools/build_factions_site.py
"""
import math, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image
import gen_defs as g

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
VB = ROOT + "/vb"
ACC = {"tympan": "#ffc84a", "miasma": "#e262ff"}
TITLE = {"tympan": ("Tympan Conclave", "Floating ears, horns and drums. Waves of sound with a wide splash that hit harder when many land on one target; radar on the units, and ears that blow a cloak."),
         "miasma": ("Miasma Bloom", "Drifting snouts and flowers. Slow and tough; every hit poisons and scents its target, and the Censer sniffs out mushrooms faster.")}
UNIT_KINDS = ["com", "con", "scout", "raider", "assault", "art", "support", "heavy"]
STRUCT_KINDS = ["fac", "mex", "solar", "heart", "store", "radar", "def1", "def2"]
ROLE = {"con": "Builder", "scout": "Scout", "raider": "Raider", "assault": "Assault", "art": "Long range", "support": "Support", "heavy": "Heavy"}
COM = {"tympan": "Ear Commander", "miasma": "Nose Commander"}
SROLE = {"fac": "Factory", "mex": "Metal extractor", "solar": "Energy", "heart": "Advanced energy", "store": "Storage", "radar": "Radar", "def1": "Light defence", "def2": "Heavy defence"}


def radar(u, acc):
    rng = max([w["range"] for w in u.get("weapons", [])] or [0])
    v = [math.sqrt(u["hp"] / 13000), rng / 820, u["alt"] / 230, u["m"] / 2500, (u["hp"] / u["m"]) / 14]
    v = [min(1.0, max(0.05, x)) for x in v]
    def pt(i, r): a = math.radians(-90 + 72 * i); return f"{100 + 80 * r * math.cos(a):.1f},{100 + 80 * r * math.sin(a):.1f}"
    out = []
    for r in (0.25, 0.5, 0.75, 1.0):
        out.append(f'<polygon points="{" ".join(pt(i, r) for i in range(5))}" fill="none" stroke="{acc}" stroke-opacity=".3"/>')
    for i in range(5):
        x, y = pt(i, 1.0).split(",")
        out.append(f'<line x1="100" y1="100" x2="{x}" y2="{y}" stroke="{acc}" stroke-opacity=".3"/>')
    out.append(f'<polygon points="{" ".join(pt(i, v[i]) for i in range(5))}" fill="{acc}" fill-opacity=".4" stroke="{acc}" stroke-width="2.5"/>')
    return "".join(out)


def cell(i):
    return f"background-position:{(i % 4) * 100 / 3:.2f}% {(i // 4) * 100 / 3:.2f}%"


def faction_blocks(fac):
    units = {u["kind"]: u for u in g.UNITS if u["fac"] == fac}
    name, leg = TITLE[fac]; acc = ACC[fac]
    cards, structs = [], []
    for i, k in enumerate(UNIT_KINDS):
        u = units[k]
        w = ", ".join(f"{x['name']} ({x['range']})" for x in u.get("weapons", [])) or "&mdash;"
        cards.append(f'<article class="u"><div class="top"><div class="ic sp {fac}" style="{cell(i)}"></div>'
                     f'<svg class="rd" viewBox="0 0 200 200" role="img" aria-label="Radar for {u["name"]}">{radar(u, acc)}</svg></div>'
                     f'<h4>{u["name"]}</h4><p class="r">{COM[fac] if k == "com" else ROLE[k]}</p>'
                     f'<p class="m">{u["m"]} metal · {u["hp"]} HP · altitude {u["alt"]}<br>{w}</p></article>')
    for i, k in enumerate(STRUCT_KINDS):
        u = units[k]
        structs.append(f'<div class="s"><div class="ic sp {fac}" style="{cell(8 + i)}"></div><h4>{u["name"]}</h4><p class="r">{SROLE[k]}</p></div>')
    ublock = f'<div style="--acc:{acc}"><h3>{name}</h3><p class="leg">{leg}</p><div class="ug">{"".join(cards)}</div></div>'
    sblock = f'<div style="--acc:{acc}"><h3>{name}</h3><div class="sg">{"".join(structs)}</div></div>'
    return ublock, sblock


def sheets():
    kinds = UNIT_KINDS + STRUCT_KINDS
    for fac in ("tympan", "miasma"):
        by = {u["kind"]: u["id"] for u in g.UNITS if u["fac"] == fac}
        sh = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
        for i, k in enumerate(kinds):
            im = Image.open(f"{ROOT}/game/unitpics/{by[k]}.png").convert("RGBA")
            sh.paste(im, ((i % 4) * 128, (i // 4) * 128))
        sh.save(f"{ROOT}/voidborn_{fac}_units.png")
        sh.convert("RGB").save(f"{VB}/img/{fac}.webp", quality=84, method=6)


def put(src, tag, html, anchor):
    """insert (or replace) a generated block between markers, just before `anchor`"""
    block = f"<!--vb016:{tag}-->{html}<!--/vb016:{tag}-->\n"
    if f"<!--vb016:{tag}-->" in src:
        return re.sub(rf"<!--vb016:{tag}-->.*?<!--/vb016:{tag}-->\n?", lambda m: block, src, flags=re.S)
    assert anchor in src, anchor
    return src.replace(anchor, block + anchor, 1)


def sub(src, old, new):
    return src.replace(old, new) if old in src else src


def main():
    sheets()
    css = open(f"{VB}/style.css", encoding="utf-8").read()
    if ".tympan{" not in css:
        css = css.replace(".maw{background-image:url(img/maw.webp)}", ".maw{background-image:url(img/maw.webp)}\n.tympan{background-image:url(img/tympan.webp)}\n.miasma{background-image:url(img/miasma.webp)}")
        open(f"{VB}/style.css", "w", encoding="utf-8").write(css)

    # ---------------- index
    p = f"{VB}/index.html"; s = open(p, encoding="utf-8").read()
    tu, ts = faction_blocks("tympan"); mu, ms = faction_blocks("miasma")
    s = put(s, "units", tu + mu, '\n</div></section>\n\n<section id="structures">')
    s = put(s, "structs", ts + ms, '\n</div></section>\n\n<section id="map">')
    s = sub(s, "Two alien armies. One shattered void.", "Four alien armies. One shattered void.")
    s = sub(s, "<b>16</b> units, 2 factions", "<b>32</b> units, 4 factions")
    s = sub(s, "put two archives in your Spring data folder", "put two archives in your Spring data folder")
    s = sub(s, "Play Choir or Maw against a bot at three skill levels, or run Bot vs Bot", "Play any of the four factions against a bot at three skill levels, or run Bot vs Bot")
    s = sub(s, "Each unit’s radar reads", "Four factions, one for each sense organ: the eye, the mouth, the ear and the nose. Each unit’s radar reads")
    open(p, "w", encoding="utf-8").write(s)

    # ---------------- play
    p = f"{VB}/play.html"; s = open(p, encoding="utf-8").read()
    s = s.replace("Voidborn 0.15.sdz", "Voidborn 0.16.sdz")
    if "Play_Tympan_vs_Bot.txt" not in s:
        row = lambda f, d: f'<li><a href="https://github.com/bitopsy/voidborn/raw/master/{f}" rel="noopener">{f}</a><span>{d}</span></li>\n'
        anchor = '<li><a href="https://github.com/bitopsy/voidborn/raw/master/Watch_Bot_vs_Bot.txt"'
        s = s.replace(anchor, row("Play_Tympan_vs_Bot.txt", "you (Tympan) vs the bot") + row("Play_Miasma_vs_Bot.txt", "you (Miasma) vs the bot") + anchor, 1)
        s = s.replace('<span>two bots, spectate</span></li>\n', '<span>two bots, spectate</span></li>\n' + row("Watch_4Factions_FFA.txt", "four bots, one of each faction"), 1)
    if "Play_Choose_Faction_vs_Bot.txt" not in s:
        row = lambda f, d: f'<li><a href="https://github.com/bitopsy/voidborn/raw/master/{f}" rel="noopener">{f}</a><span>{d}</span></li>\n'
        anchor = '<li><a href="https://github.com/bitopsy/voidborn/raw/master/Watch_Bot_vs_Bot.txt"'
        s = s.replace(anchor, row("Play_Choose_Faction_vs_Bot.txt", "you vs the bot, pick your faction in the menu") + anchor, 1)
    open(p, "w", encoding="utf-8").write(s)

    # ---------------- roadmap
    p = f"{VB}/roadmap.html"; s = open(p, encoding="utf-8").read()
    s = sub(s, "<b>6</b> projects in flight", "<b>5</b> projects in flight, <b>1</b> shipped")
    a = s.find("<h3>A third faction</h3>")
    if a >= 0:
        b = s.index("</div>", a)
        new = ("<h3>Third and fourth faction</h3>\n<p class=\"state\">Shipped in 0.16 &ndash; balance open</p>\n"
               "<p>The Choir has the eye and the Maw the mouth; 0.16 adds the <b>Tympan Conclave</b> (the ear: sound, Resonance, radar and "
               "ears that blow a cloak) and the <b>Miasma Bloom</b> (the nose: poison, scent and a hunger for mushrooms), each with the full "
               "roster, a Tier 2 and its own art. Four ways to play need a balance pass of their own.</p>\n"
               "<p class=\"when\">Play them, tell us what is too strong, and watch the four-faction bot game: <code>Watch_4Factions_FFA.txt</code>.</p>\n")
        s = s[:a] + new + s[b:]
    open(p, "w", encoding="utf-8").write(s)

    # ---------------- story
    p = f"{VB}/story.html"; s = open(p, encoding="utf-8").read()
    s = sub(s, "<h2>Two ways to look at the dark</h2>", "<h2>Four ways to look at the dark</h2>")
    s = sub(s, "The Choir and the Maw do not disagree about the Rift. They disagree about what to do with it.",
            "The four armies do not disagree about the Rift. They disagree about which of the senses to trust in it: the eye, the mouth, the ear or the nose.")
    cards = """
<div class="card big" style="--acc:#ffc84a">
<h3>The Tympan Conclave</h3>
<p class="leg">An ear that learned to answer.</p>
<p>The Conclave <b>listens</b>. In the dark of the Rift the first thing to arrive is not light but sound, and the Conclave
turned that into a doctrine: hear first, strike first, strike together. Its units see little and hear a great deal &ndash;
scouts, support units and the commander carry radar of their own &ndash; and what they hear they hit with waves of
pressure that break more than they pierce.</p>
<p>Alone, a Tympan unit is ordinary. Together it is not: each of them that hits the same target within a moment of the
others makes every later hit ring louder. Their ears also give away the quiet: an enemy commander that cloaks too
close to a Conclave listener hears its own cloak go.</p>
<p class="leg">Strength: focus fire, long warning, area damage, and nothing hides from them for long.</p>
<p class="leg">Weakness: short sight, splash that does not care where it lands, and every unit alone is only a unit.</p>
</div>

<div class="card big" style="--acc:#e262ff">
<h3>The Miasma Bloom</h3>
<p class="leg">A nose that learned to bloom.</p>
<p>The Bloom <b>smells</b>. It does not need to see what it has tasted: every shell, dart and jet it lands leaves a
poison that works for seconds after the shot and a scent that keeps the target on the Bloom&rsquo;s map for ten. Its
units are slow, soft-looking and hard to kill, and what they leave behind is a cloud nobody wants to stand in.</p>
<p>The Bloom feeds on endings. The Censer drifts over the wreckage and eats the mushrooms that grow from it faster
than anyone else, and its commander, the Rhinarch, is a drifting snout in a crown of petals that breathes
poison across half the field.</p>
<p class="leg">Strength: damage that keeps working, no hiding place, and a lot of health for the metal.</p>
<p class="leg">Weakness: slow, and short on reach in the early game; poison does nothing to a unit that is already dying.</p>
</div>
"""
    s = put(s, "factions", cards, "\n</div>\n</div></section>\n\n<section id=\"units\">")
    def ucard(name, leg, text, acc):
        return f'<div class="u" style="--acc:{acc}"><h4>{name}</h4>\n<p class="leg">{leg}</p>\n<p>{text}</p></div>\n\n'
    ty = ('<h3>The Tympan Conclave</h3>\n<div class="ug">\n\n'
          + ucard("Auditor", "Commander &middot; 4300 HP &middot; 2500 metal", "Builds, carries radar and ears, and answers with a Crescendo at 520. It fires the same Destabilisation Gun as the others, and its Perforate takes 2600 points of armour.", "#ffc84a")
          + ucard("Whisper", "Scout &middot; 220 HP &middot; 40 metal", "Radar to 1500 and ears to 450: it finds the enemy long before it sees it, and blows the cloak of anything that hides nearby.", "#ffc84a")
          + ucard("Drummer", "Assault &middot; 1500 HP &middot; 190 metal", "A Bass Wave that reaches 360 with a wide splash. A pack of them, all on one target, is the Conclave&rsquo;s middle of the map.", "#ffc84a")
          + ucard("Trumpeter", "Artillery &middot; 620 HP &middot; 235 metal", "A Sonic Boom at 800, from one colossal ear-trumpet; with radar of its own it fires at what it has only heard.", "#ffc84a")
          + ucard("Cacophon", "Heavy &middot; 9800 HP &middot; 1600 metal", "A Shockwave at 600 and the Lesser Voices at 380. It does not win a duel, it wins the fight round it.", "#ffc84a")
          + ucard("Organon", "T2 Heavy &middot; 35000 HP &middot; 4200 metal", "A Requiem at 780 and a Hundred Voices at 470: fifteen pipes and one chord. The unit the Grand Echo Chamber exists for.", "#ffc84a")
          + '</div>\n\n')
    mi = ('<h3>The Miasma Bloom</h3>\n<div class="ug">\n\n'
          + ucard("Rhinarch", "Commander &middot; 4700 HP &middot; 2500 metal", "Noxious Breath at 520, Asphyxiate at 240 and the Destabilisation Gun. Everything it hits is poisoned and scented.", "#e262ff")
          + ucard("Sniffer", "Scout &middot; 260 HP &middot; 34 metal", "Long sight (680) and a Spore Dart that poisons what it touches: a scout that marks its target.", "#e262ff")
          + ucard("Bellows", "Assault &middot; 2300 HP &middot; 170 metal", "A pleated barrel that heaves Fume Bolts at 340. Cheap, tough, and the poison keeps working after it has gone.", "#e262ff")
          + ucard("Stinkhorn", "Artillery &middot; 700 HP &middot; 215 metal", "A Reek Canister at 800 with a splash of 100: the cloud outlasts the blast.", "#e262ff")
          + ucard("Censer", "Support &middot; 820 HP &middot; 150 metal", "Builds, repairs and eats mushrooms about a third faster than the other first-tier supports.", "#e262ff")
          + ucard("Titan Arum", "T2 Heavy &middot; 48000 HP &middot; 3800 metal", "The corpse flower grown to a monster: Putrefaction at 700 and a Corpse Cloud at 600, behind the most health in the game.", "#e262ff")
          + '</div>\n\n')
    s = put(s, "units", ty + mi, '<div class="note">\n<b>The small ones matter too.</b>')
    open(p, "w", encoding="utf-8").write(s)
    print("site written: index, play, roadmap, story, style.css, img/tympan.webp, img/miasma.webp")


if __name__ == "__main__":
    main()
