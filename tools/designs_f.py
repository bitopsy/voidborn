"""Voidborn models - HAPTIC GRASP (the Hand, the sense of touch), tier 1 (new in 0.17).

Hands and tentacles: palms for bodies, fingers for legs and weapons, tentacles for arms and skirts, a fingerprint on every
fingertip, palm and sucker.  Slate-blue flesh, rose veins, ink-dark plates and a coral nerve-glow.  Piece names follow
gen_defs.write_scripts: base, head (+ muzzle) to aim, nano for builders, pad for factories; crown / petals / rings / dish
turn on their own, spin turns while the unit is active.  The 'eye' material column of the atlas is the FINGERPRINT of this
faction (see textures.py): it sits on the poles of a flat ellipsoid, so a disc that faces along d shows the whorl.

Hand frame used by hand() / finger(): fingers run along +z, the palm side (where the fingers curl to) is +y, width is x.
put() moves a whole hand (a list of meshes) to a place, pointing its fingers along d with the palm facing `up`.
"""
import numpy as np
from mesh import *
from designs_a import RS, V, tiny, crown, hang, roots


# ------------------------------------------------------------------------------------------ hand and tentacle helpers
def bend_dir(d, c, a):
    """Turn direction d by angle a towards direction c."""
    d = norm(d); c = np.asarray(c, float)
    cp = c - d * np.dot(c, d)
    if np.linalg.norm(cp) < 1e-6:
        cp = np.cross(d, (1, 0, 0))
        if np.linalg.norm(cp) < 1e-6: cp = np.cross(d, (0, 0, 1))
    return norm(d * np.cos(a) + norm(cp) * np.sin(a))


def finger(pos, d, curl_to, L, r0, curls=(0.3, 0.5, 0.4), mat='skin', lo=False):
    """One finger: three joints that bend towards `curl_to` by curls[i] radians each, a nail on the back, a fingerprint pad
    on the tip.  `lo` is a cheaper finger for the many small hands of the big units."""
    pos = np.asarray(pos, float); d = norm(d); c = norm(curl_to)
    steps = 6 if lo else 9; n3 = steps // 3
    pts = [pos.copy()]; p = pos.copy()
    for i in range(steps):
        d = bend_dir(d, c, curls[min(i // n3, 2)] / n3)
        p = p + d * L / steps; pts.append(p.copy())
    rad = np.linspace(r0, r0 * 0.62, len(pts))
    parts = [tube(pts, rad, mat, 5 if lo else 7)]
    rt = rad[-1]
    parts.append(blob((rt * 1.25, rt * 1.25, rt * 0.95), pts[-1] + d * rt * 0.15, 'eye', d, lon=8 if lo else 12, lat=5 if lo else 8))
    if not lo:
        parts.append(place(ellipsoid((rt * 0.8, rt * 0.28, rt * 1.5), 'dark', 8, 6), pts[-2] * 0.3 + pts[-1] * 0.7 - c * rt * 0.85, d, up=-c))
    return parts


def hand(w, h, L, curl=0.0, spread=0.25, nf=4, thumb=True, thumb_side=-1, r0=None, mat='skin', wrist=0.0, print_palm=True, lo=False):
    """A hand: palm w wide (half width) and h long (half length), fingers of length L, curl 0 = open, ~0.95 = a fist."""
    r0 = r0 or w * 0.17; t = h * 0.30
    parts = [blob((w, t, h), (0, 0, 0), mat, (0, 0, 1), lon=14 if lo else 18, lat=9 if lo else 12)]
    if print_palm:
        parts.append(place(ellipsoid((w * 0.5, w * 0.5, t * 0.5), 'eye', 12 if lo else 16, 8 if lo else 10), (0, t * 0.8, h * 0.05), (0, 1, 0), up=(0, 0, 1)))
    prof = {3: [0.85, 1.0, 0.8], 4: [0.74, 0.98, 0.92, 0.68], 5: [0.7, 0.9, 1.0, 0.9, 0.68]}.get(nf) or [1.0 - 0.25 * abs(i - (nf - 1) / 2) / max(nf / 2, 1) for i in range(nf)]
    xs = np.linspace(-0.78 * w, 0.78 * w, nf) if nf > 1 else [0.0]
    for x, f in zip(xs, prof):
        parts += finger((x, 0, h * 0.78), (spread * x / w, 0, 1), (0, 1, 0), L * f, r0 * (0.8 + 0.25 * f), (curl * 0.8, curl, curl * 0.85), mat, lo)
    if thumb:
        s = thumb_side
        parts += finger((s * w * 0.92, 0, -h * 0.15), (s * 0.85, 0.0, 0.55), (0, 1, 0), L * 0.78, r0 * 1.15, (curl * 0.4, curl * 0.7, curl * 0.6), mat, lo)
    if wrist:
        parts.append(tube([(0, 0, -h * 0.7), (0, 0, -h * 0.7 - wrist)], [w * 0.72, w * 0.55], 'skin', 10))
    return parts


def fist(w, h, L, **kw):
    kw.setdefault('curl', 1.2); kw.setdefault('spread', 0.0)
    return hand(w, h, L, **kw)


def put(parts, pos=(0, 0, 0), d=(0, 0, 1), up=(0, 1, 0), s=None):
    return [place(m, pos, d, s, up) for m in parts]


def suckers(path, rad, n, mat='eye', start=0.18, end=0.9):
    """Fingerprint pads under a tentacle (the suckers of an octopus arm)."""
    out = []; N = len(path)
    for k in range(n):
        i = int(round((start + (end - start) * k / max(n - 1, 1)) * (N - 1)))
        r = rad[i]
        out.append(place(ellipsoid((r * 0.75, r * 0.75, r * 0.38), mat, 10, 6), path[i] + V(0, -r * 0.85, 0), (0, -1, 0), up=(0, 0, 1)))
    return out


def arm(pos, d, length, r0, r1, n_suck=5, mat='skin', **kw):
    """A tentacle with a row of suckers on its underside."""
    path = curve(pos, d, length, n=kw.pop('n', 10), **kw)
    rad = np.linspace(r0, r1, len(path))
    return [tube(path, rad, mat, 8)] + suckers(path, rad, n_suck), path


def claws(n, R, y, length, r0, curl_in=0.5, mat='skin', lo=True, rise=0.6, phase=0.0, glow_tip=False):
    """n fingers around a ring that rise and curl inwards: a cupped hand seen from above, or a cage."""
    out = []
    for i in range(n):
        a = phase + 2 * np.pi * i / n
        ca, sa = np.cos(a), np.sin(a)
        out += finger(V(R * ca, y, R * sa), V(ca * 0.25, rise, sa * 0.25), V(-ca, 0.0, -sa), length, r0, (curl_in * 0.7, curl_in, curl_in * 0.8), mat, lo)
    return out


# ============================================================================================ units
def ha_manus():
    """Manus - the commander: a hand the size of a house on a trunk of braided tentacle, palm open towards the enemy."""
    M = Model('ha_manus'); M.piece('base'); M.add('base', [])
    rs = RS('manus')
    trunk = curve(V(0, 6, 0), V(0, 1, 0), 26, bend=V(0, 0, 2), n=8)
    M.add('base', tube(trunk, np.linspace(9.5, 6.8, 8), 'skin', 12))
    M.add('base', [ring(8.4 - 0.5 * i, 1.3, V(0, 11 + 7 * i, 0), (0, 1, 0), 'dark', 18, 5) for i in range(3)])
    M.add('base', blob((12, 7, 12), (0, 6, 0), 'dark'))
    M.add('base', hang(11, 8.5, 6, 28, 2.5, 'skin', rs, 0.35, 1.3, 2.4))
    for s in (-1, 1):                       # two smaller hands on tentacle arms, half open, ready
        a, p = arm(V(s * 7, 22, 0), V(s, 0.1, 0.4), 15, 2.6, 1.7, 4, bend=V(s * 3, -4, 8), waves=1, side=V(0, 1, 0), amp=1.2)
        M.add('base', a)
        M.add('base', put(hand(4.8, 5.0, 6.5, curl=0.3, spread=0.3, thumb_side=-s, lo=True), p[-1] + V(s * 1.5, 0.5, 4), V(s * 0.15, 0.1, 1)))
    M.piece('crown', 'base', (0, 30, 0))
    M.add('crown', [finger(V(13 * np.cos(a), 0, 13 * np.sin(a)), V(np.cos(a) * 0.7, 0.55, np.sin(a) * 0.7), (0, 1, 0), 8, 1.4, (0.2, 0.4, 0.3), 'skin', True)
                    for a in np.linspace(0, 2 * np.pi, 8)[:-1]])
    M.piece('head', 'base', (0, 36, 4))
    M.add('head', put(hand(10.5, 11, 16, curl=0.16, spread=0.3, thumb_side=-1, wrist=9), (0, 0, 0), (0, 1, 0), (0, 0, 1)))
    M.add('head', ring(6.4, 0.9, (0, 0, 3.9), (0, 0, 1), 'glow', 20, 5))
    tiny(M, 'muzzle', 'head', (0, 3, 10))
    return M


def ha_palp():
    """Palp - the builder: a small hand that hangs by its fingertips like a spider and knits flesh with the palm."""
    M = Model('ha_palp'); M.piece('base'); M.add('base', [])
    M.add('base', blob((6.2, 3.4, 6.2), (0, 12, 0), 'skin'))
    M.add('base', place(ellipsoid((3.4, 3.4, 1.6), 'eye', 14, 8), (0, 9.3, 0), (0, -1, 0), up=(0, 0, 1)))
    M.add('base', ring(6.4, 0.6, (0, 12, 0), (0, 1, 0), 'dark', 16, 4))
    for i, a in enumerate(np.linspace(0, 2 * np.pi, 6)[:-1] + 0.3):
        ca, sa = np.cos(a), np.sin(a)
        M.add('base', finger(V(5.4 * ca, 12, 5.4 * sa), V(ca, 0.25, sa), V(0, -1, 0), 13, 1.5, (0.55, 0.7, 0.6)))
    M.add('base', tentacle(V(0, 12, -5), V(0, 0.2, -1), 12, 1.7, 'skin', bend=V(0, -3, -4), waves=1.2, side=V(1, 0, 0), amp=1.4, r1=0.3))
    tiny(M, 'nano', 'base', (0, 7, 0))
    return M


def ha_whisker():
    """Whisker - the scout: a pea of nerve with two small hands for wings and one long, quivering feeler in front."""
    M = Model('ha_whisker'); M.piece('base'); M.add('base', [])
    M.add('base', blob((3.2, 3.0, 6.2), (0, 8, -1), 'skin'))
    for s in (-1, 1):
        M.add('base', put(hand(3.4, 3.2, 5.2, curl=0.0, spread=0.55, nf=3, thumb=False, lo=True), V(s * 4.5, 8.5, -2), V(s * 0.95, 0.08, -0.3)))
    M.add('base', tentacle(V(0, 8, -6), V(0, 0, -1), 11, 1.5, 'skin', bend=V(0, 2, 0), waves=1.5, side=V(0, 1, 0), amp=1.2, r1=0.2))
    M.piece('head', 'base', (0, 8, 6))
    M.add('head', place(ellipsoid((2.7, 2.7, 1.5), 'eye', 14, 8), (0, 0, 0.8), (0, 0, 1)))
    M.add('head', tentacle(V(0, 0, 1.5), V(0, 0.05, 1), 17, 0.7, 'dark', bend=V(0, 2.5, 0), waves=2.0, side=V(0, 1, 0), amp=0.9, r1=0.12, n=12))
    tiny(M, 'muzzle', 'head', (0, 2, 18))
    return M


def ha_clutch():
    """Clutch - the raider, and a bomb: a hand leaping with its fingers hooked, a glowing swollen sac on its back."""
    M = Model('ha_clutch'); M.piece('base'); M.add('base', [])
    M.add('base', blob((5.0, 3.6, 6.4), (0, 6, 0), 'skin'))
    M.add('base', blob((4.0, 3.2, 4.8), (0, 9.1, -0.6), 'glow'))
    M.add('base', ring(4.6, 0.55, (0, 8.6, -0.6), (0, 1, 0), 'dark', 14, 4))
    M.add('base', place(ellipsoid((2.6, 2.6, 1.2), 'eye', 12, 8), (0, 3.2, 1.0), (0, -1, 0), up=(0, 0, 1)))
    for x, f in zip((-3.4, -1.1, 1.1, 3.4), (0.75, 1.0, 0.95, 0.7)):
        M.add('base', finger(V(x, 6, 5.0), V(x * 0.05, -0.1, 1), V(0, -1, 0), 9.5 * f, 1.25, (0.35, 0.75, 0.85), 'skin', True))
    M.add('base', finger(V(-4.6, 6, 0.5), V(-0.8, -0.2, 0.6), V(0, -1, 0), 7.5, 1.4, (0.3, 0.6, 0.7), 'skin', True))
    for k in range(3):
        M.add('base', tentacle(V((k - 1) * 2.4, 6, -5.5), V((k - 1) * 0.35, 0.1, -1), 11, 1.2, 'skin', bend=V(0, -2, -3), waves=1.3 + 0.3 * k, side=V(1, 0, 0), amp=1.1, r1=0.2))
    return M


def ha_fist():
    """Fist - the assault unit: a clenched fist on a stout body, a smaller fist at each side, tentacles for a skirt."""
    M = Model('ha_fist'); M.piece('base'); M.add('base', [])
    rs = RS('fist')
    M.add('base', blob((9.5, 9, 9.5), (0, 17, 0), 'skin'))
    M.add('base', ring(10.2, 1.7, (0, 12, 0), (0, 1, 0), 'dark'))
    M.add('base', hang(9, 7, 11, 18, 2.0, 'skin', rs, 0.30, 1.2, 1.8))
    for s in (-1, 1):
        a, p = arm(V(s * 8, 19, 0), V(s, 0.2, 0.2), 10, 2.8, 2.3, 3, bend=V(s * 2, -2, 5), waves=0.8, side=V(0, 1, 0), amp=1.0)
        M.add('base', a)
        M.add('base', put(fist(4.8, 5.2, 7.2, thumb_side=-s, lo=True), p[-1] + V(s * 3, -0.5, 4.5), V(0, 0, 1), V(s * 0.3, 1, 0)))
    M.piece('head', 'base', (0, 22, 7))
    M.add('head', put(fist(8, 8.6, 12.5, mat='skin'), (0, 0, 0), (0, 0, 1)))
    M.add('head', [spike(V(x, 6.2, 11.5), V(0, 0.5, 1), 4.2, 1.2, 'dark', 5) for x in (-5.4, -1.8, 1.8, 5.4)])
    tiny(M, 'muzzle', 'head', (0, 3, 15))
    return M


def ha_reacher():
    """Reacher - artillery: a bladder body and the longest arm in the rift, ending in an open, lobbing hand."""
    M = Model('ha_reacher'); M.piece('base'); M.add('base', [])
    rs = RS('reach')
    M.add('base', blob((7.2, 6.4, 9.2), (0, 10, 0), 'skin'))
    M.add('base', [ring(7.3, 0.9, (0, 10, z), (0, 0, 1), 'dark', 16, 5) for z in (-4.5, 0, 4.5)])
    M.add('base', hang(6, 5, 6, 14, 1.8, 'skin', rs, 0.3, 1.2, 1.4))
    path = curve(V(0, 12, -2), V(0, 1, 0.3), 36, bend=V(0, 0, 18), waves=1, side=V(1, 0, 0), amp=3, n=14)
    rad = np.linspace(5.0, 2.8, 14)
    M.add('base', tube(path, rad, 'skin', 10))
    M.add('base', suckers(path, rad, 6, start=0.15, end=0.8))
    M.add('base', [ring(rad[i] + 0.4, 0.7, path[i], path[i + 1] - path[i - 1], 'dark', 12, 4) for i in (3, 7, 11)])
    tip = path[-1]
    M.piece('head', 'base', tuple(tip + V(0, 1.5, 2)))
    M.add('head', put(hand(7, 7.4, 11, curl=0.12, spread=0.3, thumb_side=-1, wrist=5), (0, 0, 0), V(0, 0.35, 1), (0, 1, 0)))
    tiny(M, 'muzzle', 'head', (0, 4, 9))
    return M


def ha_caress():
    """Caress - support: four gentle hands cupped round a glowing orb, tentacles trailing; it mends by stroking."""
    M = Model('ha_caress'); M.piece('base'); M.add('base', [])
    rs = RS('caress')
    M.add('base', blob((7.0, 6.0, 7.0), (0, 16, 0), 'skin'))
    M.add('base', blob(4.2, (0, 18, 0), 'glow'))
    for i in range(4):
        a = 2 * np.pi * i / 4 + 0.4; ca, sa = np.cos(a), np.sin(a)
        M.add('base', put(hand(4.0, 4.4, 8.5, curl=0.42, spread=0.2, thumb_side=-1, lo=True), V(8.5 * ca, 17, 8.5 * sa), V(ca * 0.55, 0.85, sa * 0.55), V(-ca, 0.15, -sa)))
    M.add('base', hang(9, 5, 11, 16, 1.7, 'skin', rs, 0.3, 1.3, 1.5))
    M.add('base', ring(7.4, 0.8, (0, 12, 0), (0, 1, 0), 'dark', 16, 5))
    tiny(M, 'nano', 'base', (0, 4, 0))
    return M


def ha_polydactyl():
    """Polydactyl - the heavy: a titan hand with seven fingers and two thumbs on a wrist of tentacles, small hands at its sides."""
    M = Model('ha_polydactyl'); M.piece('base'); M.add('base', [])
    rs = RS('poly')
    trunk = curve(V(0, 8, 0), V(0, 1, 0), 44, bend=V(0, 0, 4), n=10)
    M.add('base', tube(trunk, np.linspace(21, 14, 10), 'skin', 16))
    M.add('base', [ring(19 - 1.2 * i, 2.2, V(0, 14 + 9 * i, 0), (0, 1, 0), 'dark', 24, 6) for i in range(4)])
    M.add('base', blob((26, 12, 26), (0, 8, 0), 'dark'))
    M.add('base', hang(18, 18, 8, 46, 4.6, 'skin', rs, 0.35, 1.3, 4.0))
    for s in (-1, 1):                         # two smaller hands, the other weapon
        a, p = arm(V(s * 15, 40, 0), V(s, 0.1, 0.5), 28, 5.2, 3.2, 6, bend=V(s * 6, -8, 16), waves=1, side=V(0, 1, 0), amp=2.4)
        M.add('base', a)
        M.add('base', put(hand(8.5, 9, 13, curl=0.35, spread=0.35, thumb_side=-s, lo=True), p[-1] + V(s * 2, 1, 9), V(s * 0.1, 0.1, 1)))
    M.piece('crown', 'base', (0, 54, 0))
    M.add('crown', [finger(V(27 * np.cos(a), 0, 27 * np.sin(a)), V(np.cos(a) * 0.7, 0.6, np.sin(a) * 0.7), (0, 1, 0), 15, 2.4, (0.2, 0.4, 0.3), 'skin', True)
                    for a in np.linspace(0, 2 * np.pi, 11)[:-1]])
    M.piece('head', 'base', (0, 62, 8))
    M.add('head', put(hand(24, 24, 32, curl=0.14, spread=0.5, nf=7, thumb_side=-1, wrist=18, lo=True), (0, 0, 0), (0, 1, 0), (0, 0, 1)))
    M.add('head', finger(V(-22, -3.6, 0), V(-0.85, 0.55, 0), V(0, 0, 1), 24, 3.6, (0.2, 0.5, 0.5), 'skin', True))      # the second thumb
    M.add('head', ring(13, 1.4, (0, 0, 8), (0, 0, 1), 'glow', 26, 6))
    tiny(M, 'muzzle', 'head', (0, 4, 20))
    return M


# ====================================================================================== structures
def ha_palm():
    """Open Palm - factory: an enormous palm, held up, its fingers curled into a cup round the pad where units are born."""
    M = Model('ha_palm'); M.piece('base'); M.add('base', [])
    M.add('base', blob((40, 5, 40), (0, 4, 0), 'dark', lat=8))
    M.add('base', roots(8, 82, 22, 6, 'skin', 4))
    M.add('base', blob((33, 4.2, 33), (0, 9, 0), 'skin', lat=8))
    M.add('base', place(ellipsoid((18, 18, 3), 'eye', 24, 12), (0, 12.6, 0), (0, 1, 0), up=(0, 0, 1)))
    M.add('base', ring(35, 2.4, (0, 10, 0), (0, 1, 0), 'dark', 36, 8))
    M.add('base', claws(7, 29, 9, 40, 4.6, 0.62, 'skin', lo=False, rise=0.8))
    M.piece('crown', 'base', (0, 28, 0))
    M.add('crown', [blob(2.0, V(20 * np.cos(a), 0, 20 * np.sin(a)), 'glow', lon=8, lat=6) for a in np.linspace(0, 2 * np.pi, 8)[:-1]])
    M.add('crown', ring(20, 0.7, (0, 0, 0), (0, 1, 0), 'glow', 28, 4))
    tiny(M, 'pad', 'base', (0, 16, 0))
    return M


def ha_tap():
    """Fingertip Probe - metal extractor: a hand hanging over the rock, five fingertips drumming into the ore."""
    M = Model('ha_tap'); M.piece('base'); M.add('base', [])
    M.add('base', blob((9, 5, 9), (0, 4, 0), 'dark', lat=8))
    M.add('base', roots(5, 28, 11, 2.4, 'skin', 6, 4))
    M.add('base', tube([V(0, 4, 0), V(0, 16, 0)], [3.4, 2.6], 'skin', 8))
    M.add('base', blob((7.2, 2.6, 7.2), (0, 17, 0), 'skin'))
    M.add('base', place(ellipsoid((3.6, 3.6, 1.2), 'eye', 14, 8), (0, 15.6, 0), (0, -1, 0), up=(0, 0, 1)))
    M.piece('spin', 'base', (0, 16, 0))
    M.add('spin', [finger(V(4.8 * np.cos(a), 0, 4.8 * np.sin(a)), V(np.cos(a) * 0.5, -1, np.sin(a) * 0.5), V(-np.cos(a), -0.2, -np.sin(a)), 12, 1.5, (0.1, 0.2, 0.2), 'skin', True)
                   for a in np.linspace(0, 2 * np.pi, 6)[:-1]])
    return M


def ha_pad():
    """Warm Pad - energy: a flat palm lifted to the stars; its fingers lie open like petals and drink the heat."""
    M = Model('ha_pad'); M.piece('base'); M.add('base', [])
    M.add('base', blob((11, 4, 11), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(6, 42, 14, 3.0, 'skin', 7, 3))
    M.add('base', tube(curve(V(0, 3, 0), V(0, 1, 0), 10, n=4), [4.2, 3.2, 2.8, 3.4], 'skin', 8))
    M.add('base', blob((7.5, 2.4, 7.5), (0, 15, 0), 'skin', lat=8))
    M.add('base', place(ellipsoid((5.4, 5.4, 1.6), 'eye', 16, 8), (0, 16.8, 0), (0, 1, 0), up=(0, 0, 1)))
    M.piece('petals', 'base', (0, 15, 0))
    for i in range(8):
        a = 2 * np.pi * i / 8; ca, sa = np.cos(a), np.sin(a)
        M.add('petals', finger(V(ca * 6, 0, sa * 6), V(ca, 0.4, sa), V(0, 1, 0), 12.5, 1.8, (0.1, 0.18, 0.2), 'skin' if i % 2 else 'dark', True))
    return M


def ha_pulse():
    """Pulse Point - advanced energy: a cage of fingers closed round a throbbing, glowing knuckle of nerve."""
    M = Model('ha_pulse'); M.piece('base'); M.add('base', [])
    M.add('base', blob((36, 6, 36), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(10, 100, 24, 5, 'skin', 8, 4))
    M.add('base', tube([V(0, 6, 0), V(0, 24, 0)], [13, 10], 'skin', 14))
    M.add('base', claws(8, 21, 12, 56, 4.4, 0.55, 'skin', lo=True, rise=1.0))
    M.add('base', blob(13, (0, 40, 0), 'glow'))
    M.piece('rings', 'base', (0, 40, 0))
    M.add('rings', [ring(20, 1.4, (0, 0, 0), (1, 0.3, 0), 'glow'), ring(26, 1.1, (0, 0, 0), (-0.3, 1, 0.4), 'dark'), ring(32, 0.9, (0, 0, 0), (0.2, 0.2, 1), 'glow', 36, 6)])
    return M


def ha_cup():
    """Cupped Palms - storage: two hands held together palms up, a pool of glowing metal and energy in the hollow."""
    M = Model('ha_cup'); M.piece('base'); M.add('base', [])
    M.add('base', blob((26, 5, 26), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(6, 60, 18, 4, 'skin', 9, 3))
    M.add('base', put(hand(11, 12, 17, curl=0.62, spread=0.15, nf=4, thumb_side=1, wrist=10, lo=True), V(-8, 12, -8), V(0, 0.1, 1), V(0, 1, 0)))
    M.add('base', put(hand(11, 12, 17, curl=0.62, spread=0.15, nf=4, thumb_side=-1, wrist=10, lo=True), V(8, 12, 8), V(0, 0.1, -1), V(0, 1, 0)))
    M.add('base', blob((11, 7, 11), (0, 17, 0), 'glow'))
    M.add('base', [blob(1.8, V(7 * np.cos(a), 25 + 3 * np.sin(3 * a), 7 * np.sin(a)), 'glow', lon=8, lat=6) for a in np.linspace(0, 2 * np.pi, 7)[:-1]])
    return M


def ha_vibrissa():
    """Whisker Mast - radar: a tall stalk crowned with a tuft of stiff whiskers that feel the tremble of the void."""
    M = Model('ha_vibrissa'); M.piece('base'); M.add('base', [])
    M.add('base', blob((9, 4, 9), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(5, 26, 12, 2.5, 'skin', 10, 3))
    stalk = curve(V(0, 3, 0), V(0, 1, 0), 54, bend=V(4, 0, 5), waves=1, side=V(1, 0, 0), amp=3, n=12)
    M.add('base', tube(stalk, np.linspace(3.6, 1.8, 12), 'skin', 8))
    M.add('base', suckers(stalk, np.linspace(3.6, 1.8, 12), 5, start=0.1, end=0.55))
    M.add('base', [ring(3.1, 0.7, stalk[i], (0, 1, 0), 'dark', 12, 4) for i in (3, 6, 9)])
    top = stalk[-1]
    M.piece('head', 'base', tuple(top + V(0, 2, 0)))
    M.add('head', blob(3.6, (0, 0, 0), 'skin'))
    M.piece('dish', 'head', (0, 2, 0))
    M.add('dish', [tentacle(V(0, 0, 0), V(np.cos(a) * 0.9, 0.45, np.sin(a) * 0.9), 15, 0.8, 'dark', bend=V(np.cos(a) * 3, 2, np.sin(a) * 3), waves=1, side=V(0, 1, 0), amp=0.6, r1=0.1)
                   for a in np.linspace(0, 2 * np.pi, 11)[:-1]])
    M.add('dish', [blob(1.3, V(np.cos(a) * 15, 8, np.sin(a) * 15), 'glow', lon=6, lat=4) for a in np.linspace(0, 2 * np.pi, 11)[:-1]])
    return M


def ha_prickle():
    """Pinch Finger - light defence: a stalk that ends in a finger and a thumb; the pinch snaps shut on whatever comes near."""
    M = Model('ha_prickle'); M.piece('base'); M.add('base', [])
    M.add('base', blob((9, 4, 9), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(5, 30, 12, 2.8, 'skin', 11, 3))
    stalk = curve(V(0, 3, 0), V(0, 1, 0), 20, bend=V(0, 0, 3), n=6)
    M.add('base', tube(stalk, np.linspace(4.2, 3.0, 6), 'skin', 8))
    M.add('base', ring(4.6, 0.9, stalk[2], (0, 1, 0), 'dark', 14, 4))
    M.piece('head', 'base', tuple(stalk[-1] + V(0, 2, 1)))
    M.add('head', blob((4.6, 3.6, 5), (0, 0, 0), 'skin'))
    M.add('head', finger(V(0, 1.6, 2), V(0, 0.15, 1), V(0, -1, 0), 15, 2.2, (0.22, 0.35, 0.3), 'skin', False))
    M.add('head', finger(V(0, -1.6, 2), V(0, -0.15, 1), V(0, 1, 0), 12, 2.4, (0.2, 0.32, 0.28), 'dark', False))
    tiny(M, 'muzzle', 'head', (0, 0, 15))
    return M


def ha_slam():
    """Slam Fist - heavy defence: a pillar of tentacle holding a great fist above the rock, ready to come down."""
    M = Model('ha_slam'); M.piece('base'); M.add('base', [])
    M.add('base', blob((26, 6, 26), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(7, 80, 22, 5, 'skin', 12, 4))
    path = curve(V(0, 3, 0), V(0, 1, 0), 54, bend=V(0, 0, 6), waves=1, side=V(1, 0, 0), amp=2, n=11)
    rad = np.linspace(13, 8.5, 11)
    M.add('base', tube(path, rad, 'skin', 14))
    M.add('base', suckers(path, rad, 6, start=0.1, end=0.7))
    M.add('base', [ring(rad[i] + 1.0, 1.6, path[i], (0, 1, 0), 'dark', 22, 6) for i in (2, 5, 8)])
    M.piece('head', 'base', tuple(path[-1] + V(0, 6, 4)))
    M.add('head', put(fist(12, 13, 16, wrist=6), (0, 0, 0), (0, 0, 1)))
    M.add('head', [spike(V(x, 9, 16), V(0, 0.5, 1), 5.5, 1.6, 'dark', 5) for x in (-8, -2.7, 2.7, 8)])
    tiny(M, 'muzzle', 'head', (0, 4, 20))
    return M


HAPTIC = dict(ha_manus=ha_manus, ha_palp=ha_palp, ha_whisker=ha_whisker, ha_clutch=ha_clutch, ha_fist=ha_fist, ha_reacher=ha_reacher,
              ha_caress=ha_caress, ha_polydactyl=ha_polydactyl, ha_palm=ha_palm, ha_tap=ha_tap, ha_pad=ha_pad, ha_pulse=ha_pulse,
              ha_cup=ha_cup, ha_vibrissa=ha_vibrissa, ha_prickle=ha_prickle, ha_slam=ha_slam)
