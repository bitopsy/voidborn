#!/usr/bin/env python3
"""Draw the faction logos and the loading screen for the lobby.

    python3 tools/gen_sidepics.py

Writes:
  game/sidepics/choir.png          the Choir of the Eye emblem
  game/sidepics/maw.png            the Maw Swarm emblem
  game/bitmaps/loadpictures/voidborn.jpg   the loading screen (the classic
                                   place a lobby looks for one)

The lobby picks the faction logos out of sidepics/ by the faction name, and
Coilbox falls back to the loading screen until the hub has card art of its own.
Both are drawn here so they stay in the same style as the rest of the art.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SIDE = os.path.join(ROOT, "game", "sidepics")
LOAD = os.path.join(ROOT, "game", "bitmaps", "loadpictures")
S = 512                                  # the emblem is drawn at 512 px


def gradient(size, top, bottom, diagonal=True):
    """A vertical (or diagonal) gradient as an image."""
    w, h = size
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (w, y)], fill=c)
    if diagonal:
        # a soft glow in the upper left, like the nebula on the logo
        glow = Image.new("L", (w, h), 0)
        gd = ImageDraw.Draw(glow)
        gd.ellipse([-w * 0.3, -h * 0.5, w * 0.9, h * 0.7], fill=70)
        glow = glow.filter(ImageFilter.GaussianBlur(w // 8))
        img = Image.composite(Image.new("RGB", (w, h), (120, 90, 220)), img, glow)
    return img


def rounded(img, radius):
    """Round the corners of an image (for the emblem frame)."""
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], radius=radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def glow(draw_target, shape, colour, blur, alpha=170):
    """Draw a shape into a separate layer and blur it, for the glow of an eye."""
    layer = Image.new("RGBA", draw_target.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.ellipse(shape, fill=colour + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    draw_target.alpha_composite(layer)


SS = 2                                   # supersampling for the emblems (drawn at 1024, saved at 512)


def _canvas():
    return Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))


def _bg(top, bottom, glow_rgb, glow_at, glow_r, stars, seed):
    """Void background: vertical gradient, a soft nebula glow and a few stars."""
    import random
    rnd = random.Random(seed)
    N = S * SS
    img = gradient((N, N), top, bottom, diagonal=False).convert("RGBA")
    g = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    gx, gy = glow_at
    ImageDraw.Draw(g).ellipse([(gx - glow_r) * SS, (gy - glow_r) * SS, (gx + glow_r) * SS, (gy + glow_r) * SS],
                              fill=glow_rgb + (120,))
    img.alpha_composite(g.filter(ImageFilter.GaussianBlur(70 * SS // 2)))
    d = ImageDraw.Draw(img)
    for _ in range(stars):
        x, y, r = rnd.randint(0, N), rnd.randint(0, N), rnd.choice((1, 1, 2, 3)) * SS // 2
        a = rnd.randint(90, 220)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(235, 240, 255, a))
    return img


def _bloom(img, shape_fn, colour, blur, alpha):
    """Draw with shape_fn on a layer, blur it and add it: a glow behind crisp art."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shape_fn(ImageDraw.Draw(layer), colour + (alpha,))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur * SS)))


def _frame(img, colour, inner):
    """Bevelled double frame, same family for both factions."""
    d = ImageDraw.Draw(img)
    N = S * SS
    d.rounded_rectangle([8 * SS, 8 * SS, N - 9 * SS, N - 9 * SS], radius=54 * SS, outline=colour + (235,), width=7 * SS)
    d.rounded_rectangle([22 * SS, 22 * SS, N - 23 * SS, N - 23 * SS], radius=42 * SS, outline=inner + (120,), width=2 * SS)
    # corner studs
    for cx, cy in ((46, 46), (S - 46, 46), (46, S - 46), (S - 46, S - 46)):
        r = 5 * SS
        d.ellipse([cx * SS - r, cy * SS - r, cx * SS + r, cy * SS + r], fill=colour + (230,))


def _finish(img):
    out = img.resize((S, S), Image.LANCZOS)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=58, fill=255)
    res = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    res.paste(out, (0, 0), mask)
    return res


def _tilted_ring(img, cx, cy, rx, ry, tilt, width, colour, front_only=None):
    """An ellipse ring tilted by `tilt` degrees; front_only 'top'/'bottom' draws just half of it."""
    pts = []
    for i in range(0, 361, 2):
        a = math.radians(i)
        x, y = rx * math.cos(a), ry * math.sin(a)
        t = math.radians(tilt)
        pts.append(((cx + x * math.cos(t) - y * math.sin(t)) * SS, (cy + x * math.sin(t) + y * math.cos(t)) * SS, i))
    d = ImageDraw.Draw(img)
    for (x1, y1, a1), (x2, y2, a2) in zip(pts, pts[1:]):
        half = math.sin(math.radians(a1))
        if front_only == "top" and half > 0: continue
        if front_only == "bottom" and half <= 0: continue
        d.line([(x1, y1), (x2, y2)], fill=colour, width=int(width * SS))


def choir():
    """The Choir of the Eye: a single open eye inside a tilted halo, light spilling down as tendrils."""
    N = S * SS
    img = _bg((10, 22, 58), (4, 7, 22), (60, 140, 255), (256, 230), 230, 46, 7)
    cx, cy = 256, 236
    c = lambda v: int(v * SS)

    # halo, back half first (behind the head), front half after
    _bloom(img, lambda d, col: d.ellipse([c(cx - 190), c(cy - 70), c(cx + 190), c(cy + 70)], outline=col, width=c(16)),
           (90, 190, 255), 10, 200)
    _tilted_ring(img, cx, cy - 6, 186, 56, -14, 11, (150, 225, 255, 255), "top")
    _tilted_ring(img, cx, cy - 6, 160, 44, -14, 4, (210, 245, 255, 220), "top")

    # tendrils: curved strands that fade out downwards
    d = ImageDraw.Draw(img)
    for i, x0 in enumerate((-150, -100, -52, 0, 52, 100, 150)):
        pts = []
        for t in range(0, 41):
            u = t / 40
            x = cx + x0 * (0.55 + 0.45 * u) + math.sin(u * 5 + i) * 14 * u
            y = cy + 120 + u * (150 - abs(x0) * 0.25)
            pts.append((x * SS, y * SS))
        for k in range(len(pts) - 1):
            u = k / len(pts)
            a = int(235 * (1 - u) ** 1.2)
            d.line([pts[k], pts[k + 1]], fill=(170, 215, 255, a), width=max(2, int((9 - 6 * u) * SS)))
    _bloom(img, lambda dd, col: [dd.line([(cx * SS + x0 * SS * 0.8, (cy + 130) * SS), (cx * SS + x0 * SS, (cy + 260) * SS)], fill=col, width=c(6))
                                  for x0 in (-120, -60, 0, 60, 120)], (90, 190, 255), 8, 120)

    # the head: pale shell with a rim light
    _bloom(img, lambda dd, col: dd.ellipse([c(cx - 140), c(cy - 130), c(cx + 140), c(cy + 140)], fill=col), (80, 170, 255), 22, 150)
    d = ImageDraw.Draw(img)
    d.ellipse([c(cx - 128), c(cy - 120), c(cx + 128), c(cy + 128)], fill=(214, 224, 244, 255), outline=(110, 130, 175, 255), width=c(4))
    shade = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(shade).ellipse([c(cx - 128), c(cy - 10), c(cx + 128), c(cy + 160)], fill=(40, 60, 130, 120))
    img.alpha_composite(shade.filter(ImageFilter.GaussianBlur(16 * SS)))
    rim = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(rim).arc([c(cx - 118), c(cy - 110), c(cx + 118), c(cy + 118)], 200, 290, fill=(255, 255, 255, 230), width=c(6))
    img.alpha_composite(rim.filter(ImageFilter.GaussianBlur(2 * SS)))

    # the eye: sclera, radial iris, pupil, catchlights
    ex, ey, er = cx, cy + 4, 92
    _bloom(img, lambda dd, col: dd.ellipse([c(ex - er), c(ey - er), c(ex + er), c(ey + er)], fill=col), (60, 170, 255), 18, 210)
    d = ImageDraw.Draw(img)
    d.ellipse([c(ex - er), c(ey - er), c(ex + er), c(ey + er)], fill=(240, 246, 255, 255), outline=(60, 80, 130, 255), width=c(4))
    ir = 64
    for i in range(72):                       # iris rays
        a = math.radians(i * 5)
        col = (40 + (i * 7) % 60, 130 + (i * 11) % 70, 255, 255)
        d.line([(ex * SS, ey * SS), ((ex + ir * math.cos(a)) * SS, (ey + ir * math.sin(a)) * SS)], fill=col, width=c(5))
    d.ellipse([c(ex - ir), c(ey - ir), c(ex + ir), c(ey + ir)], outline=(20, 60, 160, 255), width=c(5))
    d.ellipse([c(ex - 30), c(ey - 30), c(ex + 30), c(ey + 30)], fill=(6, 12, 40, 255))
    d.ellipse([c(ex - 30), c(ey - 30), c(ex + 30), c(ey + 30)], outline=(150, 220, 255, 255), width=c(3))
    d.ellipse([c(ex - 22), c(ey - 24), c(ex - 4), c(ey - 6)], fill=(255, 255, 255, 245))
    d.ellipse([c(ex + 12), c(ey + 8), c(ex + 22), c(ey + 18)], fill=(150, 210, 255, 220))

    # halo front half passes over the head
    _tilted_ring(img, cx, cy - 6, 186, 56, -14, 11, (150, 225, 255, 255), "bottom")
    _tilted_ring(img, cx, cy - 6, 160, 44, -14, 4, (210, 245, 255, 220), "bottom")

    _frame(img, (130, 205, 255), (200, 235, 255))
    return _finish(img)


def maw():
    """The Maw Swarm: a ringed lamprey mouth seen head-on, carapace spikes above, acid glow in the throat."""
    N = S * SS
    img = _bg((58, 14, 10), (12, 3, 4), (255, 120, 30), (256, 290), 240, 34, 11)
    cx, cy = 256, 292
    c = lambda v: int(v * SS)
    d = ImageDraw.Draw(img)

    # carapace crest: spikes fanning out behind the mouth
    spikes = []
    for i, ang in enumerate(range(-72, 73, 24)):
        a = math.radians(ang - 90)
        h = 104 - abs(ang) * 0.42
        base = 134
        tip = (cx + (base + h) * math.cos(a), cy + (base + h) * math.sin(a))
        l = (cx + base * math.cos(a - 0.17), cy + base * math.sin(a - 0.17))
        r = (cx + base * math.cos(a + 0.17), cy + base * math.sin(a + 0.17))
        spikes.append((tip, l, r))
    for tip, l, r in spikes:
        poly = [(p[0] * SS, p[1] * SS) for p in (l, tip, r)]
        d.polygon(poly, fill=(48, 14, 12, 255), outline=(190, 80, 36, 255))
        d.line([poly[0], poly[1]], fill=(230, 110, 50, 255), width=c(2.5))

    # the maw: dark flesh disc with a bevelled rim
    _bloom(img, lambda dd, col: dd.ellipse([c(cx - 150), c(cy - 150), c(cx + 150), c(cy + 150)], fill=col), (255, 110, 20), 22, 190)
    d = ImageDraw.Draw(img)
    d.ellipse([c(cx - 142), c(cy - 142), c(cx + 142), c(cy + 142)], fill=(86, 24, 18, 255), outline=(220, 100, 44, 255), width=c(5))
    d.ellipse([c(cx - 124), c(cy - 124), c(cx + 124), c(cy + 124)], fill=(52, 12, 12, 255))

    # three rings of teeth pointing inward, each ring offset from the last
    rings = [(124, 78, 22, 20), (94, 54, 17, 16), (66, 36, 13, 12)]      # outer r, tip r, count-base, offset
    for k, (ro, rt, n, _) in enumerate(rings):
        count = (24, 18, 12)[k]
        for i in range(count):
            a0 = 2 * math.pi * (i + 0.5 * (k % 2)) / count
            half = math.pi / count * 0.82
            p1 = (cx + ro * math.cos(a0 - half), cy + ro * math.sin(a0 - half))
            p2 = (cx + ro * math.cos(a0 + half), cy + ro * math.sin(a0 + half))
            tip = (cx + rt * math.cos(a0), cy + rt * math.sin(a0))
            shade = 245 - k * 22
            d.polygon([(p1[0] * SS, p1[1] * SS), (tip[0] * SS, tip[1] * SS), (p2[0] * SS, p2[1] * SS)],
                      fill=(shade, shade - 14, shade - 52, 255), outline=(120, 70, 40, 255))

    # glowing throat: acid-green core with an orange ring, the same two colours the Matriarch's weapons use
    _bloom(img, lambda dd, col: dd.ellipse([c(cx - 40), c(cy - 40), c(cx + 40), c(cy + 40)], fill=col), (190, 255, 40), 16, 255)
    d = ImageDraw.Draw(img)
    d.ellipse([c(cx - 34), c(cy - 34), c(cx + 34), c(cy + 34)], fill=(255, 150, 30, 255))
    d.ellipse([c(cx - 24), c(cy - 24), c(cx + 24), c(cy + 24)], fill=(190, 255, 50, 255))
    d.ellipse([c(cx - 11), c(cy - 11), c(cx + 11), c(cy + 11)], fill=(250, 255, 200, 255))

    # mandibles curving in from each side of the mouth
    for sgn in (-1, 1):
        pts = []
        for t in range(0, 31):
            u = t / 30
            x = cx + sgn * (152 + 30 * math.sin(u * 1.6))
            y = cy + 60 - u * 170 + 30 * u * u
            pts.append((x * SS, y * SS))
        for k in range(len(pts) - 1):
            u = k / len(pts)
            d.line([pts[k], pts[k + 1]], fill=(150 + int(50 * u), 50 + int(30 * u), 30, 255), width=max(2, int((16 - 12 * u) * SS)))

    _frame(img, (232, 128, 60), (255, 190, 120))
    return _finish(img)


def tympan():
    """The Tympan Conclave (0.16): one great ear with a lobe and a tragus, a drum membrane in its hollow, sound rolling in from the left."""
    N = S * SS
    img = _bg((40, 24, 8), (10, 6, 3), (255, 170, 40), (290, 240), 230, 40, 13)
    c = lambda v: int(v * SS)
    cx, cy = 300, 236
    def tilted(rx, ry, tilt, ox=0, oy=0, a0=0, a1=360, step=3):
        t = math.radians(tilt); out = []
        for k in range(a0, a1 + 1, step):
            a = math.radians(k); x, y = rx * math.cos(a), ry * math.sin(a)
            out.append(((cx + ox + x * math.cos(t) - y * math.sin(t)) * SS, (cy + oy + x * math.sin(t) + y * math.cos(t)) * SS))
        return out
    # sound arriving from the left: arcs round a point beside the ear
    d = ImageDraw.Draw(img)
    for r, al in ((80, 250), (122, 210), (164, 165), (206, 120)):
        box = [c(cx - 60 - r), c(cy - r), c(cx - 60 + r), c(cy + r)]
        _bloom(img, lambda dd, col, box=box: dd.arc(box, 160, 200, fill=col, width=c(13)), (255, 170, 40), 8, al)
        d.arc(box, 160, 200, fill=(255, 218, 130, min(255, al + 40)), width=c(5))
    # the pinna: lobe first, then the big flap, then the rim
    _bloom(img, lambda dd, col: dd.polygon(tilted(122, 166, -12), fill=col), (255, 150, 40), 26, 170)
    d = ImageDraw.Draw(img)
    d.polygon(tilted(34, 40, 0, -8, 168, 0, 360), fill=(232, 186, 156, 255), outline=(120, 70, 40, 255))
    d.polygon(tilted(122, 166, -12), fill=(238, 196, 168, 255), outline=(120, 70, 40, 255))
    d.line(tilted(110, 154, -12, 0, 0, 100, 300), fill=(190, 130, 104, 255), width=c(16), joint="curve")      # the curled helix
    d.line(tilted(110, 154, -12, 0, 0, 100, 300), fill=(248, 218, 194, 255), width=c(5), joint="curve")
    d.line(tilted(66, 100, -12, 6, 6, 120, 330), fill=(168, 112, 88, 255), width=c(11), joint="curve")        # the inner ridge
    shade = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(shade).polygon(tilted(54, 76, -12, -2, 14), fill=(70, 28, 14, 235))
    img.alpha_composite(shade.filter(ImageFilter.GaussianBlur(10 * SS)))
    d = ImageDraw.Draw(img)
    d.polygon(tilted(26, 34, -20, -62, 40), fill=(226, 178, 148, 255), outline=(120, 70, 40, 255))             # the tragus
    # the drum in the hollow
    dx, dy = cx + 2, cy + 18
    _bloom(img, lambda dd, col: dd.ellipse([c(dx - 50), c(dy - 50), c(dx + 50), c(dy + 50)], fill=col), (255, 190, 60), 14, 240)
    d = ImageDraw.Draw(img)
    for i, r in enumerate((48, 39, 30, 21, 12)):
        d.ellipse([c(dx - r), c(dy - r), c(dx + r), c(dy + r)], fill=((236, 208, 160, 255) if i % 2 == 0 else (206, 146, 62, 255)), outline=(110, 70, 30, 255), width=c(2))
    d.ellipse([c(dx - 5), c(dy - 5), c(dx + 5), c(dy + 5)], fill=(255, 244, 210, 255))
    # a cochlea below the lobe
    sx, sy = cx - 6, cy + 222; pts = []
    for t in range(0, 101):
        u = t / 100; a = 2 * math.pi * 2.4 * u; r = 4 + 36 * u
        pts.append(((sx + r * math.cos(a)) * SS, (sy + r * 0.7 * math.sin(a)) * SS))
    _bloom(img, lambda dd, col: dd.line(pts, fill=col, width=c(10), joint="curve"), (255, 170, 40), 7, 230)
    d = ImageDraw.Draw(img)
    for k in range(len(pts) - 1):
        d.line([pts[k], pts[k + 1]], fill=(255, 214, 110, 255), width=max(2, int((3 + 7 * k / 100) * SS)))
    _frame(img, (232, 170, 58), (255, 220, 140))
    return _finish(img)


def miasma():
    """The Miasma Bloom (0.16): a ring of petals, a great nose with two nostrils, violet vapour curling up from them."""
    N = S * SS
    img = _bg((28, 12, 38), (8, 4, 14), (200, 70, 255), (256, 250), 240, 40, 17)
    c = lambda v: int(v * SS)
    cx, cy = 256, 252
    d = ImageDraw.Draw(img)
    # petals behind the nose, alternating magenta and sulphur
    for i in range(12):
        a = math.radians(i * 30 - 90); L, W = 215, 38
        px, py = cx + math.cos(a) * 80, cy + math.sin(a) * 80
        tip = (cx + math.cos(a) * L, cy + math.sin(a) * L)
        nx, ny = -math.sin(a), math.cos(a)
        poly = [(px * SS, py * SS), ((px + math.cos(a) * 90 + nx * W) * SS, (py + math.sin(a) * 90 + ny * W) * SS), (tip[0] * SS, tip[1] * SS),
                ((px + math.cos(a) * 90 - nx * W) * SS, (py + math.sin(a) * 90 - ny * W) * SS)]
        col = (226, 98, 255) if i % 2 == 0 else (240, 232, 90)
        _bloom(img, lambda dd, cc, poly=poly: dd.polygon(poly, fill=cc), col[:3], 10, 140)
        d = ImageDraw.Draw(img)
        d.polygon(poly, fill=col + (235,), outline=(70, 24, 90, 255))
    # the nose: a moss-green bulb with a bridge and two flared nostrils
    _bloom(img, lambda dd, col: dd.ellipse([c(cx - 118), c(cy - 120), c(cx + 118), c(cy + 130)], fill=col), (170, 220, 90), 22, 150)
    d = ImageDraw.Draw(img)
    d.ellipse([c(cx - 108), c(cy - 112), c(cx + 108), c(cy + 122)], fill=(126, 142, 74, 255), outline=(40, 30, 50, 255), width=c(5))
    d.ellipse([c(cx - 62), c(cy - 100), c(cx + 62), c(cy + 20)], fill=(150, 166, 92, 255))
    shade = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(shade).ellipse([c(cx - 108), c(cy + 20), c(cx + 108), c(cy + 130)], fill=(40, 30, 60, 150))
    img.alpha_composite(shade.filter(ImageFilter.GaussianBlur(16 * SS)))
    d = ImageDraw.Draw(img)
    for sx in (-1, 1):                                       # nostrils: dark hole, wet pink lip
        nxm, nym = cx + sx * 50, cy + 66
        d.ellipse([c(nxm - 38), c(nym - 22), c(nxm + 38), c(nym + 26)], fill=(208, 98, 130, 255), outline=(60, 20, 40, 255), width=c(3))
        d.ellipse([c(nxm - 30), c(nym - 12), c(nxm + 30), c(nym + 20)], fill=(10, 4, 14, 255))
        d.ellipse([c(nxm - 14), c(nym - 12), c(nxm - 4), c(nym - 4)], fill=(120, 60, 90, 200))
        for k in range(4):                                   # a few nose hairs, bristling down and out
            ang = math.radians(60 + k * 20); d.line([((nxm + 28 * math.cos(ang)) * SS, (nym + 22 * math.sin(ang)) * SS), ((nxm + 44 * math.cos(ang) + sx * 6) * SS, (nym + 46 * math.sin(ang)) * SS)], fill=(44, 32, 54, 255), width=c(3))
    # vapour curling up out of the nostrils
    for sx in (-1, 1):
        for j in range(2):
            pts = []
            for t in range(0, 61):
                u = t / 60; x = cx + sx * (50 + 26 * j) + math.sin(u * 7 + j * 2 + sx) * (16 + 22 * u); y = cy + 40 - u * 280
                pts.append((x * SS, y * SS))
            _bloom(img, lambda dd, col, pts=pts: dd.line(pts, fill=col, width=c(14), joint="curve"), (210, 110, 255), 10, 150)
            d = ImageDraw.Draw(img)
            for k in range(len(pts) - 1):
                u = k / len(pts); d.line([pts[k], pts[k + 1]], fill=(236, 190, 255, int(230 * (1 - u))), width=max(2, int((7 - 4 * u) * SS)))
    _frame(img, (204, 90, 240), (240, 190, 255))
    return _finish(img)


def loading():
    """The loading screen: the Rift with the emblem over it."""
    w, h = 1280, 720
    img = gradient((w, h), (58, 30, 128), (10, 7, 22)).convert("RGBA")

    # the map, dimmed, centred and faded out at the edges
    mini = os.path.join(ROOT, "vb", "img", "voidborn-rift.webp")
    if os.path.isfile(mini):
        side = 620
        m = Image.open(mini).convert("RGBA").resize((side, side), Image.LANCZOS)
        # a round mask that fades the picture into the background
        mask = Image.new("L", (side, side), 0)
        md = ImageDraw.Draw(mask)
        md.ellipse([40, 40, side - 41, side - 41], fill=150)
        mask = mask.filter(ImageFilter.GaussianBlur(40))
        m.putalpha(mask)
        img.alpha_composite(m, (w // 2 - side // 2, 66))

    # the emblem (the picture has no transparency of its own, so it gets a frame)
    logo = os.path.join(ROOT, "vb", "img", "logo.webp")
    if os.path.isfile(logo):
        lg = Image.open(logo).convert("RGBA").resize((190, 190), Image.LANCZOS)
        lm = Image.new("L", lg.size, 0)
        ImageDraw.Draw(lm).rounded_rectangle([0, 0, lg.size[0] - 1, lg.size[1] - 1], radius=32, fill=255)
        lg.putalpha(lm)
        img.alpha_composite(lg, (w // 2 - 95, 42))

    d = ImageDraw.Draw(img)
    try:
        from PIL import ImageFont
        big = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 62)
        small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 25)
    except Exception:
        big = small = None

    title = "VOIDBORN"
    tw = d.textlength(title, font=big) if big else 400
    d.text((w / 2 - tw / 2, 262), title, fill=(242, 238, 255, 255), font=big)

    sub = "a 3D space RTS  ·  create your own units"
    sw = d.textlength(sub, font=small) if small else 320
    d.text((w / 2 - sw / 2, 344), sub, fill=(178, 162, 224, 255), font=small)
    d.line([(w / 2 - 80, 336), (w / 2 + 80, 336)], fill=(139, 92, 255, 220), width=3)
    return img.convert("RGB")


def main():
    os.makedirs(SIDE, exist_ok=True)
    os.makedirs(LOAD, exist_ok=True)
    import sys
    tympan().save(os.path.join(SIDE, "tympan.png"))
    miasma().save(os.path.join(SIDE, "miasma.png"))
    if "new" in sys.argv[1:]:                # python3 tools/gen_sidepics.py new  -> only the two 0.16 emblems
        return
    choir().save(os.path.join(SIDE, "choir.png"))
    maw().save(os.path.join(SIDE, "maw.png"))
    loading().save(os.path.join(LOAD, "voidborn.jpg"), quality=88)
    loading().save(os.path.join(LOAD, "voidborn.png"))
    for f in sorted(os.listdir(SIDE)):
        p = os.path.join(SIDE, f)
        print(f"  sidepics/{f:16} {os.path.getsize(p):7} bytes  {Image.open(p).size}")
    for f in sorted(os.listdir(LOAD)):
        p = os.path.join(LOAD, f)
        print(f"  bitmaps/loadpictures/{f:12} {os.path.getsize(p):7} bytes  {Image.open(p).size}")


if __name__ == "__main__":
    main()
