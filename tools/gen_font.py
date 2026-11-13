#!/usr/bin/env python3
"""Generate game/fonts/VoidbornGlyph.ttf - an angular, blade-stroke "alien" display font.

Every glyph is a skeleton of polylines on a 4x6 grid. Each segment is drawn as a tapered
blade with pointed ends, so joints bristle into thorns. Lowercase maps to the capitals
(common for sci-fi faces and it keeps small UI text legible). Latin-1 accents are built
from a base capital plus an accent blade, so French/Spanish/German text still renders.

Pure python + fontTools, no external font data. Public domain (CC0).
Usage:  python3 tools/gen_font.py            (writes game/fonts/VoidbornGlyph.ttf)
        python3 tools/gen_font.py --preview  (also writes /tmp/vb_font_preview.png)
"""
import math, os, sys
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

S = 115.0          # skeleton unit -> font units
T = 104.0          # stroke thickness
EXTF = 105.0       # claw length past a free (open) stroke end
SIDE = 70.0        # side bearing
UPM = 1000

def diamond(cx, cy, r):
    return [(cx, cy + r), (cx + r, cy), (cx, cy - r), (cx - r, cy), (cx, cy + r)]

G = {}
def g(ch, *strokes): G[ch] = [list(s) for s in strokes]

g('A', [(0,0),(2,6),(4,0)], [(0.9,2),(3.1,2)])
g('B', [(0,0),(0,6),(2.6,6),(3.6,5),(3.6,4.2),(2.6,3.2),(0,3.2)], [(2.6,3.2),(3.8,2.4),(3.8,1),(2.8,0),(0,0)])
g('C', [(4,5.2),(3,6),(1,6),(0,5),(0,1),(1,0),(3,0),(4,0.8)])
g('D', [(0,0),(0,6),(2.4,6),(4,4.4),(4,1.6),(2.4,0),(0,0)])
g('E', [(4,6),(0,6),(0,0),(4,0)], [(0,3),(3,3)])
g('F', [(4,6),(0,6),(0,0)], [(0,3),(3,3)])
g('G', [(4,5),(3,6),(1,6),(0,5),(0,1),(1,0),(3,0),(4,1),(4,3),(2.2,3)])
g('H', [(0,0),(0,6)], [(4,0),(4,6)], [(0,3),(4,3)])
g('I', [(0,6),(2,6)], [(1,6),(1,0)], [(0,0),(2,0)])
g('J', [(4,6),(4,1),(3,0),(1,0),(0,1)])
g('K', [(0,0),(0,6)], [(4,6),(0,2.8)], [(1.2,3.8),(4,0)])
g('L', [(0,6),(0,0),(4,0)])
g('M', [(0,0),(0,6),(2,2.4),(4,6),(4,0)])
g('N', [(0,0),(0,6),(4,0),(4,6)])
g('O', [(2,0),(0.1,2.4),(0.1,3.6),(2,6),(3.9,3.6),(3.9,2.4),(2,0)])
g('P', [(0,0),(0,6),(3,6),(4,5),(4,3.8),(3,2.8),(0,2.8)])
g('Q', [(2,0),(0.1,2.4),(0.1,3.6),(2,6),(3.9,3.6),(3.9,2.4),(2,0)], [(2.3,1.5),(4,-0.7)])
g('R', [(0,0),(0,6),(3,6),(4,5),(4,3.8),(3,2.8),(0,2.8)], [(2,2.8),(4,0)])
g('S', [(4,5),(3,6),(1,6),(0,5),(0,4),(1,3),(3,3),(4,2),(4,1),(3,0),(1,0),(0,1)])
g('T', [(0,6),(4,6)], [(2,6),(2,0)])
g('U', [(0,6),(0,1),(1,0),(3,0),(4,1),(4,6)])
g('V', [(0,6),(2,0),(4,6)])
g('W', [(0,6),(1,0),(2,3.4),(3,0),(4,6)])
g('X', [(0,6),(4,0)], [(4,6),(0,0)])
g('Y', [(0,6),(2,3.2),(4,6)], [(2,3.2),(2,0)])
g('Z', [(0,6),(4,6),(0,0),(4,0)])
# digits (slashed zero so it never reads as the letter O)
g('0', [(2,0),(0.1,2.4),(0.1,3.6),(2,6),(3.9,3.6),(3.9,2.4),(2,0)], [(2,2.2),(2,3.8)])
g('1', [(0.5,4.8),(2,6),(2,0)], [(0.8,0),(3.2,0)])
g('2', [(0,5),(1,6),(3,6),(4,5),(4,4),(0,0),(4,0)])
g('3', [(0,5.2),(1,6),(3,6),(4,5),(4,4),(3,3.2),(1.6,3.2)], [(3,3.2),(4,2.4),(4,1),(3,0),(1,0),(0,0.8)])
g('4', [(3,0),(3,6),(0,2),(4,2)])
g('5', [(4,6),(0.4,6),(0,3.4),(2.6,3.8),(4,2.8),(4,1),(3,0),(1,0),(0,1)])
g('6', [(3.8,5.4),(2.8,6),(1,6),(0,5),(0,1),(1,0),(3,0),(4,1),(4,2.6),(3,3.6),(1,3.6),(0,2.8)])
g('7', [(0,6),(4,6),(1.4,0)])
g('8', [(1,3),(0,4),(0,5),(1,6),(3,6),(4,5),(4,4),(3,3),(1,3),(0,2),(0,1),(1,0),(3,0),(4,1),(4,2),(3,3)])
g('9', [(0.2,0.6),(1.2,0),(3,0),(4,1),(4,5),(3,6),(1,6),(0,5),(0,3.6),(1,2.6),(3,2.6),(4,3.4)])
# punctuation
g('.', [(1,0),(1,0.6)])
g(',', [(1,0.8),(0.4,-0.9)])
g(':', [(1,0),(1,0.6)], [(1,3.4),(1,4)])
g(';', [(1,0.8),(0.4,-0.9)], [(1,3.4),(1,4)])
g('-', [(0.4,3),(3.2,3)])
g('+', [(0.4,3),(3.6,3)], [(2,1.4),(2,4.6)])
g('=', [(0.4,2.2),(3.6,2.2)], [(0.4,3.8),(3.6,3.8)])
g('/', [(0,0),(3,6)])
g('\\', [(0,6),(3,0)])
g('(', [(2,6.4),(0.8,4.4),(0.8,1.6),(2,-0.4)])
g(')', [(0,6.4),(1.2,4.4),(1.2,1.6),(0,-0.4)])
g('[', [(2,6),(0.6,6),(0.6,0),(2,0)])
g(']', [(0,6),(1.4,6),(1.4,0),(0,0)])
g('{', [(2,6.2),(1,5.4),(1,3.6),(0.2,3),(1,2.4),(1,0.6),(2,-0.2)])
g('}', [(0,6.2),(1,5.4),(1,3.6),(1.8,3),(1,2.4),(1,0.6),(0,-0.2)])
g('<', [(3,5),(0.4,3),(3,1)])
g('>', [(0.4,5),(3,3),(0.4,1)])
g('!', [(1,6),(1,2)], [(1,0),(1,0.6)])
g('?', [(0,5),(1,6),(3,6),(4,5),(4,4),(2,2.8),(2,2)], [(2,0),(2,0.6)])
g('%', [(0,0),(4,6)], diamond(0.8,5.1,0.7), diamond(3.2,0.9,0.7))
g('_', [(0,-0.9),(4,-0.9)])
g('*', [(2,4.7),(2,1.7)], [(0.7,4),(3.3,2.4)], [(3.3,4),(0.7,2.4)])
g('#', [(1.2,0),(1.6,6)], [(2.8,0),(3.2,6)], [(0,2),(4,2)], [(0,4.2),(4,4.2)])
g('@', [(4,1),(3,0),(1,0),(0,1),(0,5),(1,6),(3,6),(4,5),(4,2.6),(3,2),(2,2.4),(2,4),(3,4),(3,2)])
g('&', [(4,0),(1,3.4),(1,5),(1.8,6),(2.6,5.2),(2.2,4),(0,1.6),(0.8,0),(2.4,0),(4,2.4)])
g("'", [(1,6),(1,4.6)])
g('"', [(1,6),(1,4.8)], [(3,6),(3,4.8)])
g('|', [(1,6.4),(1,-0.4)])
g('~', [(0,2.6),(1,3.6),(3,2.4),(4,3.4)])
g('$', [(4,5),(3,6),(1,6),(0,5),(0,4),(1,3),(3,3),(4,2),(4,1),(3,0),(1,0),(0,1)], [(2,6.7),(2,-0.7)])
g('^', [(0.4,3.6),(2,6),(3.6,3.6)])
g('`', [(1,6),(2.4,5)])

# accents: (name, strokes placed relative to the letter's horizontal centre, vertical offset)
def acc(kind, cx, top):
    y = top + 0.9
    if kind == 'acute':  return [[(cx - .5, y), (cx + .9, y + 1.0)]]
    if kind == 'grave':  return [[(cx + .5, y), (cx - .9, y + 1.0)]]
    if kind == 'circ':   return [[(cx - 1.0, y), (cx, y + 1.0), (cx + 1.0, y)]]
    if kind == 'diaer':  return [[(cx - .9, y + .2), (cx - .9, y + .8)], [(cx + .9, y + .2), (cx + .9, y + .8)]]
    if kind == 'tilde':  return [[(cx - 1.1, y + .2), (cx - .4, y + .9), (cx + .4, y + .2), (cx + 1.1, y + .9)]]
    if kind == 'cedil':  return [[(cx, 0), (cx - .2, -1.0)]]
    if kind == 'ring':   return [diamond(cx, y + .6, .6)]
ACC = {
 'ÀAgrave':0,
}
ACCENTED = {
 'À':('A','grave'),'Á':('A','acute'),'Â':('A','circ'),'Ä':('A','diaer'),'Ã':('A','tilde'),'Å':('A','ring'),
 'È':('E','grave'),'É':('E','acute'),'Ê':('E','circ'),'Ë':('E','diaer'),
 'Ì':('I','grave'),'Í':('I','acute'),'Î':('I','circ'),'Ï':('I','diaer'),
 'Ò':('O','grave'),'Ó':('O','acute'),'Ô':('O','circ'),'Ö':('O','diaer'),'Õ':('O','tilde'),
 'Ù':('U','grave'),'Ú':('U','acute'),'Û':('U','circ'),'Ü':('U','diaer'),
 'Ç':('C','cedil'),'Ñ':('N','tilde'),'Ý':('Y','acute'),
}

def bounds(strokes):
    xs = [p[0] for s in strokes for p in s]
    return min(xs), max(xs)

def blade(p, q, free_p=True, free_q=True):
    """Tapered segment: free ends become pointed claws, interior joints stay mitred/overlapped."""
    (x1, y1), (x2, y2) = p, q
    dx, dy = x2 - x1, y2 - y1
    L = math.hypot(dx, dy)
    if L < 1e-6:
        dx, dy, L = 0, 1, 1
    dx, dy = dx / L, dy / L
    nx, ny = -dy, dx
    h = T / 2
    sh = min(T * 0.95, L * 0.45)          # where the claw reaches full width
    pts = []
    if free_p:
        pts += [(x1 - dx * EXTF, y1 - dy * EXTF), (x1 + dx * sh + nx * h, y1 + dy * sh + ny * h)]
    else:
        j = h * 0.75
        pts += [(x1 - dx * j + nx * h * 0.9, y1 - dy * j + ny * h * 0.9)]
    if free_q:
        pts += [(x2 - dx * sh + nx * h, y2 - dy * sh + ny * h), (x2 + dx * EXTF, y2 + dy * EXTF),
                (x2 - dx * sh - nx * h, y2 - dy * sh - ny * h)]
    else:
        j = h * 0.75
        pts += [(x2 + dx * j + nx * h * 0.9, y2 + dy * j + ny * h * 0.9), (x2 + dx * j - nx * h * 0.9, y2 + dy * j - ny * h * 0.9)]
    if free_p:
        pts += [(x1 + dx * sh - nx * h, y1 + dy * sh - ny * h)]
    else:
        pts += [(x1 - dx * (h * 0.75) - nx * h * 0.9, y1 - dy * (h * 0.75) - ny * h * 0.9)]
    return pts

def clockwise(pts):
    a = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    return a < 0   # negative signed area == clockwise (y up)

def build_glyph(strokes, xshift):
    pen = TTGlyphPen(None)
    for s in strokes:
        pts_s = [((x - xshift) * S + SIDE, y * S) for x, y in s]
        closed = len(pts_s) > 2 and pts_s[0] == pts_s[-1]
        segs = list(zip(pts_s, pts_s[1:])) if len(pts_s) > 1 else [(pts_s[0], pts_s[0])]
        for i, (p, q) in enumerate(segs):
            fp = (i == 0 and not closed)
            fq = (i == len(segs) - 1 and not closed)
            poly = blade(p, q, fp, fq)
            if not clockwise(poly): poly.reverse()
            pen.moveTo((round(poly[0][0]), round(poly[0][1])))
            for pt in poly[1:]: pen.lineTo((round(pt[0]), round(pt[1])))
            pen.closePath()
    return pen.glyph()

def main():
    order = ['.notdef', 'space']
    cmap, glyphs, adv = {32: 'space'}, {}, {}
    empty = TTGlyphPen(None).glyph()
    glyphs['space'] = empty; adv['space'] = 420

    def add(ch, strokes, name=None):
        name = name or ('uni%04X' % ord(ch))
        x0, x1 = bounds(strokes)
        glyphs[name] = build_glyph(strokes, x0)
        adv[name] = int((x1 - x0) * S + SIDE * 2 + 40)
        cmap[ord(ch)] = name
        order.append(name)

    for ch, strokes in G.items():
        add(ch, strokes)
        if ch.isalpha():
            add(ch.lower(), strokes)                      # lowercase = capitals
    for ch, (base, kind) in ACCENTED.items():
        strokes = [list(s) for s in G[base]]
        x0, x1 = bounds(strokes)
        extra = acc(kind, (x0 + x1) / 2, 6)
        if kind == 'cedil': extra = acc(kind, (x0 + x1) / 2, 0)
        for a in extra: strokes.append(a)
        add(ch, strokes)
        add(ch.lower(), strokes)
    # a few more lowercase-only letters / symbols that appear in French text
    for ch, base in (('ß', 'S'), ('œ', 'O'), ('Œ', 'O'), ('æ', 'A'), ('Æ', 'A'), ('ÿ', 'Y'), ('ý', 'Y')):
        add(ch, G[base])
    add('²', [[(0, 6), (1.6, 6), (1.6, 7.2), (0, 7.2), (0, 8.2), (1.6, 8.2)]])
    add('°', [diamond(1, 6.3, .8)])
    add('€', [[(4, 5), (3, 6), (1, 6), (0, 5), (0, 1), (1, 0), (3, 0), (4, 1)], [(-0.4, 3.6), (2.8, 3.6)], [(-0.4, 2.4), (2.8, 2.4)]])
    add('«', [[(1.6, 5), (0, 3), (1.6, 1)], [(3.2, 5), (1.6, 3), (3.2, 1)]])
    add('»', [[(0, 5), (1.6, 3), (0, 1)], [(1.6, 5), (3.2, 3), (1.6, 1)]])
    add('’', G["'"]); add('‘', G["'"]); add('“', G['"']); add('”', G['"'])
    add('–', G['-']); add('—', [[(0, 3), (4, 3)]]); add('…', [[(0, 0), (0, 0.6)], [(1.6, 0), (1.6, 0.6)], [(3.2, 0), (3.2, 0.6)]])
    add('×', [[(0.4, 4.6), (3.2, 1.4)], [(3.2, 4.6), (0.4, 1.4)]])
    add('·', [[(1, 3), (1, 3.6)]])
    add('•', [diamond(1.2, 3, 1.0)])

    # .notdef: a hollow rune box so missing characters are obvious
    box = [[(0, 0), (3.2, 0), (3.2, 6), (0, 6), (0, 0)], [(0.4, 0.4), (2.8, 5.6)]]
    glyphs['.notdef'] = build_glyph(box, 0); adv['.notdef'] = int(3.2 * S + SIDE * 2 + 40)

    glyph_order = ['.notdef', 'space'] + [n for n in order if n not in ('.notdef', 'space')]
    glyph_order = list(dict.fromkeys(glyph_order))
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf({n: glyphs[n] for n in glyph_order})
    metrics = {}
    for n in glyph_order:
        gl = glyphs[n]
        gl.recalcBounds(None) if hasattr(gl, 'recalcBounds') and False else None
        metrics[n] = (adv[n], 0)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=900, descent=-260, lineGap=60)
    fb.setupNameTable({'familyName': 'Voidborn Glyph', 'styleName': 'Regular',
                       'uniqueFontIdentifier': 'VoidbornGlyph-Regular', 'fullName': 'Voidborn Glyph',
                       'psName': 'VoidbornGlyph-Regular', 'version': 'Version 1.0',
                       'copyright': 'Generated for the Voidborn game. Public domain (CC0).'})
    fb.setupOS2(sTypoAscender=900, sTypoDescender=-260, sTypoLineGap=60, usWinAscent=1000, usWinDescent=300,
                sxHeight=690, sCapHeight=690, achVendID='VBRN', fsType=0, usWeightClass=700)
    fb.setupPost(isFixedPitch=0)
    out = os.path.join(os.path.dirname(__file__), '..', 'game', 'fonts', 'VoidbornGlyph.ttf')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    fb.save(out)
    print('wrote', os.path.normpath(out), len(cmap), 'characters')

    if '--preview' in sys.argv:
        from PIL import Image, ImageDraw, ImageFont
        samples = ['ABCDEFGHIJKLM', 'NOPQRSTUVWXYZ', '0123456789 .,:;!?-+=/()[]<>%#@&$',
                   'Hierophant  Seer  Gazer  Lashling', 'Matriarch  Leviathan  Brood Hive',
                   'BUILD / ORDERS   300 metal  1200 energy', 'Élan à côté, garçon, œuvre — «naïve» €25']
        im = Image.new('RGB', (1100, 90 * len(samples) + 20), (10, 10, 16))
        d = ImageDraw.Draw(im)
        big = ImageFont.truetype(out, 54); small = ImageFont.truetype(out, 14)
        for i, s in enumerate(samples):
            d.text((20, 10 + i * 90), s, font=big, fill=(120, 230, 255))
        im.save('/tmp/vb_font_preview.png')
        im2 = Image.new('RGB', (700, 120), (10, 10, 16)); d2 = ImageDraw.Draw(im2)
        d2.text((10, 10), 'BUILD / ORDERS  Gazer 38m 152e  Matriarch 2500', font=small, fill=(255, 230, 160))
        d2.text((10, 40), 'Sun Iris   Stare Stalk   Tooth Spire   Root Drill', font=ImageFont.truetype(out, 20), fill=(255, 230, 160))
        d2.text((10, 80), 'Dev console> vbcreate dread base=ch_hoplite hp=4000', font=ImageFont.truetype(out, 16), fill=(180, 255, 180))
        im2.save('/tmp/vb_font_small.png')
        print('previews written')

if __name__ == '__main__':
    main()
