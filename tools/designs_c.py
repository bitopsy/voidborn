"""Voidborn models - TYMPAN CONCLAVE (the Ear), tier 1 (new in 0.16).

Flying ears: pinnae for wings, conch spirals for bodies, drum membranes for faces, horns for guns and a fringe of
hair-cell cilia underneath.  Piece names follow gen_defs.write_scripts: base, head (+ muzzle) to aim, nano for
builders, pad for factories, halo / crown / petals / rings / dish spin on their own, spin turns while the unit is active.
The 'eye' material column of the atlas is the DRUM MEMBRANE of this faction (see textures.py).
"""
import numpy as np
from mesh import *
from designs_a import RS, V, tiny, crown, hang, roots


# ------------------------------------------------------------------------------------------ shared ear helpers
def spiral(turns, r0, r1, rise, n=40, phase=0.0):
    """A conch / cochlea centre line: a spiral in the XY plane that climbs along +Z by `rise` in total."""
    t = np.linspace(0, 1, n)
    a = phase + 2 * np.pi * turns * t
    r = r0 * (r1 / r0) ** t
    return np.stack([r * np.cos(a), r * np.sin(a), rise * t], -1)


def conch(pos, d, turns, r0, r1, tube0, tube1, rise=0.0, mat='skin', n=44, k=10, phase=0.0):
    """A coiled shell (cochlea): a tube whose own radius grows along a spiral.  Opening faces away from the apex."""
    path = spiral(turns, r0, r1, rise, n, phase)
    rad = np.linspace(tube0, tube1, n)
    return place(tube(path, rad, mat, k), pos, d)


def pinna(pos, d, w, h, t=1.6, mat='skin', rim='dark', glowin=True, up=(0, 1, 0)):
    """An ear flap: a thin ellipsoid with a curled rim and a glowing concha (the inner dish).  Faces along `d`."""
    parts = [place(ellipsoid((w, h, t), mat, 20, 12), pos, d, up=up)]
    parts.append(place(torus(w * 0.98, t * 0.9, rim, 28, 7), pos, d, s=(1, h / w, 1), up=up))
    if glowin:
        dd = norm(d)
        parts.append(place(ellipsoid((w * 0.45, h * 0.42, t * 0.7), 'glow', 14, 8), np.asarray(pos, float) + dd * t * 0.7, d, up=up))
    return parts


def horn(pos, d, length, r0, r1, bend=(0, 0, 0), mat='dark', lip='glow', n=9):
    """An ear trumpet: a tube that flares towards the mouth, with a glowing lip."""
    pos = np.asarray(pos, float)
    path = curve(pos, d, length, bend=bend, n=n)
    rad = r0 + (r1 - r0) * np.linspace(0, 1, n) ** 2.2      # flares slowly, then opens up
    parts = [tube(path, rad, mat, 12)]
    end, prev = path[-1], path[-2]
    parts.append(place(torus(r1, r1 * 0.14, lip, 22, 6), end, end - prev))
    return parts


def drum(pos, d, R, thick=None, rim='dark'):
    """A drum head: a flat disc showing the membrane tile, in a ring of bronze."""
    thick = thick or R * 0.28
    return [place(ellipsoid((R, R, thick), 'eye', 22, 14), pos, d), place(torus(R * 0.96, thick * 0.55, rim, 26, 7), pos, d)]


def cilia(n, R, y, length, r0=0.5, mat='skin', centre=(0, 0, 0), spread=0.18, seed=3, glow_tips=False):
    """A fringe of hair cells: stiff little bristles that hang down from a ring."""
    rs = np.random.RandomState(seed); out = []; centre = centre if centre is not None else (0, 0, 0)
    for i in range(n):
        a = 2 * np.pi * (i + rs.uniform(-.25, .25)) / n
        rr = R * rs.uniform(0.35, 1.0)
        p = V(centre[0] + rr * np.cos(a), centre[1] + y, centre[2] + rr * np.sin(a))
        d = V(np.cos(a) * spread, -1, np.sin(a) * spread)
        out.append(spike(p, d, length * rs.uniform(0.7, 1.15), r0, mat, 4))
        if glow_tips:
            out.append(blob(r0 * 1.9, p + norm(d) * length * 0.95, 'glow', lon=6, lat=4))
    return out


def fork(pos, d, length, gap, r0, mat='dark', tip='glow'):
    """A tuning fork: a handle and two parallel prongs."""
    pos = np.asarray(pos, float); d = norm(d); side = norm(np.cross(d, (0, 1, 0)) if abs(d[1]) < 0.9 else np.cross(d, (1, 0, 0)))
    parts = [tube([pos, pos + d * length * 0.35], [r0 * 1.3, r0 * 1.3], mat, 8)]
    for s in (-1, 1):
        a = pos + d * length * 0.35; b = a + side * s * gap + d * 0.0
        c = b + d * length * 0.65
        parts.append(tube([a, b, c], [r0, r0, r0 * 0.85], mat, 8))
        parts.append(blob(r0 * 1.2, c, tip, lon=8, lat=6))
    return parts


# ============================================================================================ units
def ty_auditor():
    """Auditor - the commander: a tall listening ear with two great pinnae, a drum face and a horn that answers."""
    M = Model('ty_auditor'); M.piece('base'); M.add('base', [])
    rs = RS('audi')
    M.add('base', blob((12, 19, 12), (0, 24, 0), 'skin'))
    M.add('base', ring(13.5, 2.2, (0, 33, 0), (0, 1, 0), 'dark'))
    M.add('base', ring(11, 1.5, (0, 14, 0), (0, 1, 0), 'dark'))
    M.add('base', cilia(14, 9, 13, 24, 0.9, 'skin', None, seed=4, glow_tips=True))
    for s in (-1, 1):       # the great pinnae
        M.add('base', pinna(V(s * 19, 31, -2), V(s * 0.9, 0.1, 0.5), 16, 22, 2.2))
        M.add('base', conch(V(s * 11, 20, -3), V(s, 0.2, 0.3), 2.2, 4.0, 1.5, 0.9, 2.2, rise=8, mat='dark'))
    M.piece('halo', 'base', (0, 52, 0))
    M.add('halo', ring(23, 1.6, (0, 0, 0), (0, 1, 0), 'glow'))
    M.add('halo', [fork(V(22 * np.cos(a), 0, 22 * np.sin(a)), V(np.cos(a) * .3, 1, np.sin(a) * .3), 11, 2.6, 0.9) for a in np.linspace(0, 6.28, 7)[:-1]])
    M.piece('head', 'base', (0, 36, 5))
    M.add('head', drum((0, 0, 7), (0, 0, 1), 9.5))
    M.add('head', blob((11, 5, 9), (0, 9.5, 1), 'dark'))
    M.add('head', horn((0, -3, 10), (0, 0, 1), 12, 2.6, 5.6))
    tiny(M, 'muzzle', 'head', (0, -3, 23))
    return M


def ty_tuner():
    """Tuner - the builder: a floating ear whose cilia tune matter into form."""
    M = Model('ty_tuner'); M.piece('base'); M.add('base', [])
    M.add('base', conch(V(0, 13, -2), V(0, 0, 1), 2.0, 6.5, 2.2, 1.6, 4.2, rise=7, mat='skin'))
    M.add('base', pinna(V(0, 15, -4), V(0, 0.2, -1), 10, 12, 1.4))
    M.add('base', ring(9, 0.8, (0, 13, 0), (0, 0.4, 1), 'dark'))
    for i, a in enumerate(np.linspace(0, 2 * np.pi, 5)[:-1] + 0.4):
        p = V(5 * np.cos(a), 8, 5 * np.sin(a) * 0.8)
        M.add('base', tentacle(p, V(np.cos(a) * .4, -0.7, 0.9), 14, 1.2, 'skin', bend=V(0, -2, 7), waves=1, side=V(1, 0, 0), amp=1.2, r1=0.5))
        M.add('base', blob(1.2, p + V(np.cos(a) * 4, -9, 12), 'glow', lon=8, lat=6))
    tiny(M, 'nano', 'base', (0, 2, 12))
    return M


def ty_whisper():
    """Whisper - scout: all ear.  Two flat pinnae as wings, a drum for a face and a tail of cilia."""
    M = Model('ty_whisper'); M.piece('base'); M.add('base', [])
    M.add('base', blob((3.4, 3.4, 5.5), (0, 7, -2), 'skin'))
    for s in (-1, 1):
        M.add('base', pinna(V(s * 9, 8, -3), V(s * 0.25, 1, 0.1), 9.5, 6.5, 0.9, up=(0, 0, 1)))
    M.add('base', tentacle(V(0, 7, -6), V(0, 0, -1), 20, 1.6, 'skin', bend=V(0, 3, 0), waves=1.5, side=V(0, 1, 0), amp=2, r1=0.2))
    M.add('base', cilia(5, 2.2, 5, 6, 0.4, 'dark', None, seed=5))
    M.piece('head', 'base', (0, 7, 3))
    M.add('head', drum((0, 0, 0), (0, 0, 1), 4.6))
    tiny(M, 'muzzle', 'head', (0, 0, 4.5))
    return M


def ty_tinnitus():
    """Tinnitus - raider: a dart with a tiny shrill trumpet and a ring of bells."""
    M = Model('ty_tinnitus'); M.piece('base'); M.add('base', [])
    M.add('base', blob((3.6, 3.6, 8.5), (0, 5, 0), 'skin'))
    M.add('base', [ring(3.7, 0.5, (0, 5, z), (0, 0, 1), 'dark', 12, 5) for z in (-4, 0, 3)])
    M.add('base', [pinna(V(s * 5, 6.5, -3), V(s * .5, 0.3, -.8), 4.6, 3.2, 0.6) for s in (-1, 1)])
    M.add('base', cilia(6, 2.4, 5, 9, 0.5, 'skin', V(0, 0, -6), seed=6))
    M.piece('head', 'base', (0, 5, 7))
    M.add('head', horn((0, 0, -1), (0, 0, 1), 6, 1.2, 3.6))
    tiny(M, 'muzzle', 'head', (0, 0, 5.5))
    return M


def ty_drummer():
    """Drummer - assault: a bass-drum belly, a club in each hand, a small head crowned with bronze."""
    M = Model('ty_drummer'); M.piece('base'); M.add('base', [])
    rs = RS('drum')
    M.add('base', blob((9.5, 11, 8.5), (0, 18, 0), 'skin'))
    M.add('base', drum(V(0, 17, 8), (0, 0.1, 1), 8.6, 2.6))
    M.add('base', ring(10, 1.8, (0, 12, 0), (0, 1, 0), 'dark'))
    M.add('base', cilia(9, 7, 10, 17, 1.1, 'skin', None, seed=7))
    for s in (-1, 1):
        M.add('base', blob((4.4, 3.2, 4.4), (s * 11, 27, 0), 'dark'))
        M.add('base', pinna(V(s * 13, 22, -4), V(s * .9, 0.1, -.4), 6, 9, 1.1))
        M.add('base', tentacle(V(s * 11, 25, 0), V(s * 0.5, -0.6, 0.6), 16, 2.8, 'skin', bend=V(s * 3, -4, 8), waves=0.8, side=V(0, 1, 0), amp=1.5, r1=2.0))
        stick = V(s * 16, 12, 14)
        M.add('base', tube([stick + V(0, -5, -3), stick + V(0, 4, 4)], [0.9, 0.9], 'dark', 6))
        M.add('base', blob(3.2, stick + V(0, 5, 5), 'glow'))
    M.piece('head', 'base', (0, 30, 3))
    M.add('head', blob((6.2, 5.4, 6), (0, 2, 2), 'skin'))
    M.add('head', drum((0, 2, 7), (0, 0, 1), 4.0))
    M.add('head', crown(3, 5.2, 7, 7, 1.2, 'dark', 0.6))
    tiny(M, 'muzzle', 'head', (0, 2, 11))
    return M


def ty_trumpeter():
    """Trumpeter - artillery: a bladder body under one enormous ear trumpet."""
    M = Model('ty_trumpeter'); M.piece('base'); M.add('base', [])
    M.add('base', blob((7, 6, 10), (0, 10, 0), 'skin'))
    M.add('base', [ring(7.2, 0.9, (0, 10, z), (0, 0, 1), 'dark', 16, 5) for z in (-5, 0, 5)])
    M.add('base', conch(V(0, 12, -8), V(0, 0.2, -1), 2.0, 4.5, 1.6, 1.4, 3.2, rise=6, mat='dark'))
    M.add('base', pinna(V(0, 18, -5), V(0, 1, -.3), 6, 9, 1.0, up=(0, 0, 1)))
    M.add('base', cilia(8, 5, 6, 12, 0.9, 'skin', V(0, 0, 1), seed=8))
    M.piece('head', 'base', (0, 14, 4))
    M.add('head', blob((4.8, 4.8, 6), (0, 0, 0), 'dark'))
    M.add('head', horn((0, 0, 3), (0, 0.06, 1), 30, 2.2, 8.4, bend=V(0, 3, 0)))
    tiny(M, 'muzzle', 'head', (0, 3, 33))
    return M


def ty_lullaby():
    """Lullaby - support: a drifting conch that sings the wounded whole."""
    M = Model('ty_lullaby'); M.piece('base'); M.add('base', [])
    rs = RS('lull')
    M.add('base', conch(V(0, 17, 0), V(0, 1, 0), 2.3, 8.5, 2.8, 2.4, 5.6, rise=9, mat='skin', n=50, k=12))
    M.add('base', ring(11, 1.2, (0, 13, 0), (0, 1, 0), 'dark'))
    M.add('base', drum(V(0, 14, 9), (0, 0.1, 1), 4.4))
    M.add('base', cilia(14, 9, 12, 22, 1.0, 'skin', None, seed=9, glow_tips=True))
    M.add('base', tentacle(V(0, 10, 0), V(0, -1, 0.1), 17, 2.0, 'glow', waves=1.2, side=V(1, 0, 0), amp=1, r1=0.5))
    tiny(M, 'nano', 'base', (0, -5, 0))
    return M


def ty_cacophon():
    """Cacophon - heavy: a titan cochlea ringed with horns and pinnae, a tuning-fork crown and a drum-face."""
    M = Model('ty_cacophon'); M.piece('base'); M.add('base', [])
    rs = RS('caco')
    M.add('base', conch(V(0, 40, -4), V(0, 0.3, 1), 2.6, 25, 7, 8, 16, rise=26, mat='skin', n=64, k=14))
    M.add('base', blob((24, 20, 24), (0, 38, 0), 'skin'))
    M.add('base', ring(25, 3, (0, 38, 0), (0, 1, 0), 'dark', 36, 8))
    for i in range(6):                         # speaker horns round the belly
        a = 2 * np.pi * i / 6 + 0.3
        d = V(np.cos(a), 0.15, np.sin(a))
        M.add('base', horn(V(0, 34, 0) + d * 20, d, 14, 2.2, 6.0))
    for s in (-1, 1):
        for k_, (y, w, h) in enumerate(((52, 20, 26), (28, 15, 19))):
            M.add('base', pinna(V(s * 28, y, -6), V(s * .9, 0.1, -.3), w, h, 2.6))
    M.add('base', cilia(26, 20, 28, 46, 2.2, 'skin', None, seed=10, glow_tips=True))
    M.add('base', crown(8, 14, 56, 12, 2.5, 'dark', 0.2, centre=(0, 0, -8)))
    M.piece('halo', 'base', (0, 82, 0))
    M.add('halo', ring(44, 2.2, (0, 0, 0), (0, 1, 0), 'glow', 40, 8))
    M.add('halo', [fork(V(44 * np.cos(a), 0, 44 * np.sin(a)), V(np.cos(a) * .3, 1, np.sin(a) * .3), 16, 4, 1.4) for a in np.linspace(0, 6.28, 9)[:-1]])
    M.piece('head', 'base', (0, 42, 22))
    M.add('head', drum((0, 0, 6), (0, 0, 1), 15))
    M.add('head', blob((18, 8, 16), (0, 15, 2), 'dark'))
    M.add('head', horn((0, -2, 14), (0, 0, 1), 20, 4.0, 9.0))
    tiny(M, 'muzzle', 'head', (0, -2, 36))
    return M


# ====================================================================================== structures
def ty_echo():
    """Echo Chamber - factory: a flared bell of flesh, ringed by turning pinnae, a cochlea rising from the middle."""
    M = Model('ty_echo'); M.piece('base'); M.add('base', [])
    M.add('base', ring(36, 8, (0, 12, 0), (0, 1, 0), 'skin', 36, 12))
    M.add('base', blob((31, 2.0, 31), (0, 11, 0), 'glow', lat=6))
    M.add('base', blob((40, 6, 40), (0, 2, 0), 'dark', lat=8))
    M.add('base', roots(8, 80, 22, 6, 'skin', 4))
    M.add('base', conch(V(0, 14, 0), V(0, 1, 0), 2.2, 11, 3.4, 3.0, 6.0, rise=24, mat='skin', n=48, k=12))
    M.add('base', drum(V(0, 20, 10), (0, 0.4, 1), 8.5))
    M.piece('crown', 'base', (0, 14, 0))
    M.add('crown', [pinna(V(37 * np.cos(a), 12, 37 * np.sin(a)), V(np.cos(a), 0.55, np.sin(a)), 7, 14, 1.8, up=(0, 1, 0)) for a in np.linspace(0, 6.28, 10)[:-1]])
    M.add('crown', [ring(4, 0.8, V(36 * np.cos(a), 24, 36 * np.sin(a)) * 0.82, (0, 1, 0), 'glow', 10, 4) for a in np.linspace(0, 6.28, 10)[:-1]])
    tiny(M, 'pad', 'base', (0, 18, 0))
    return M


def ty_cilia():
    """Cilia Tap - metal extractor: a drum plate bristling with hair cells that feel for ore."""
    M = Model('ty_cilia'); M.piece('base'); M.add('base', [])
    M.add('base', blob((8, 6, 8), (0, 7, 0), 'skin'))
    M.add('base', roots(5, 26, 11, 2.2, 'skin', 6, 5))
    M.add('base', spike(V(0, 3, 0), V(0, -1, 0), 10, 3.4, 'dark', 7))
    M.add('base', drum(V(0, 12, 0), (0, 1, 0.1), 5.2, 1.4))
    M.piece('spin', 'base', (0, 12, 0))
    M.add('spin', [spike(V(4.5 * np.cos(a), 0, 4.5 * np.sin(a)), V(np.cos(a) * .3, 1, np.sin(a) * .3), 9 + 3 * (i % 2), 0.8, 'skin' if i % 2 else 'glow', 4)
                   for i, a in enumerate(np.linspace(0, 6.28, 9)[:-1])])
    return M


def ty_pinna():
    """Sun Pinna - energy: a cupped ear tilted at the stars, petal-flaps turning round the cup."""
    M = Model('ty_pinna'); M.piece('base'); M.add('base', [])
    M.add('base', blob((10, 4, 10), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(6, 40, 14, 3.0, 'skin', 7, 3))
    M.add('base', tube(curve(V(0, 3, 0), V(0, 1, 0), 10, n=4), [4, 3, 2.6, 3], 'skin', 8))
    M.add('base', blob((6.5, 2.2, 6.5), (0, 15, 0), 'glow', lat=8))
    M.add('base', conch(V(0, 15.5, 0), V(0, 1, 0), 1.6, 5, 1.6, 0.8, 1.6, rise=2.2, mat='dark', n=30, k=8))
    M.piece('petals', 'base', (0, 13, 0))
    for i in range(8):
        a = 2 * np.pi * i / 8
        d = V(np.cos(a), 0.7, np.sin(a))
        M.add('petals', pinna(V(np.cos(a) * 10, 5, np.sin(a) * 10), d, 3.6, 8.5, 0.8, 'skin' if i % 2 else 'glow', 'dark', glowin=False, up=(0, 1, 0)))
    return M


def ty_spiral():
    """Harmonic Spiral - advanced energy: a cochlea standing on end, wrapped in turning rings of sound."""
    M = Model('ty_spiral'); M.piece('base'); M.add('base', [])
    M.add('base', blob((36, 6, 36), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(10, 100, 24, 5, 'skin', 8, 4))
    M.add('base', conch(V(0, 8, 0), V(0, 1, 0), 3.0, 22, 6, 4.0, 8.0, rise=48, mat='skin', n=70, k=12))
    M.add('base', blob(11, (0, 40, 0), 'glow'))
    M.add('base', [pinna(V(34 * np.cos(a), 12, 34 * np.sin(a)), V(np.cos(a), 0.3, np.sin(a)), 6, 17, 1.8) for a in np.linspace(0, 6.28, 6)[:-1] + 0.4])
    M.piece('rings', 'base', (0, 40, 0))
    M.add('rings', [ring(22, 1.5, (0, 0, 0), (1, 0.3, 0), 'glow'), ring(29, 1.2, (0, 0, 0), (-0.3, 1, 0.4), 'dark'), ring(36, 1.0, (0, 0, 0), (0.2, 0.2, 1), 'glow', 36, 6)])
    return M


def ty_wax():
    """Wax Vault - storage: a sealed bulb of amber cerumen, banded and dripping."""
    M = Model('ty_wax'); M.piece('base'); M.add('base', [])
    M.add('base', blob((20, 5, 20), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(6, 56, 18, 4, 'skin', 9, 3))
    M.add('base', blob((15, 21, 15), (0, 24, 0), 'glow'))
    M.add('base', blob((15.6, 21.6, 15.6), (0, 25, 0), 'skin', lon=14, lat=8))
    M.add('base', [ring(15.5 * np.sqrt(max(0.05, 1 - ((y - 24) / 21) ** 2)), 1.0, (0, y, 0), (0, 1, 0), 'dark', 24, 5) for y in (15, 24, 33)])
    M.add('base', drum(V(0, 26, 14), (0, 0, 1), 5.6, 1.8))
    M.add('base', hang(8, 12, 12, 12, 1.6, 'glow', None, 0.1, 0.6, 0.6, seed=11))
    M.add('base', crown(4, 3, 44, 6, 1.4, 'dark', 0.5))
    return M


def ty_pinnamast():
    """Auricle Array - radar: a tall stalk carrying one enormous turning ear."""
    M = Model('ty_pinnamast'); M.piece('base'); M.add('base', [])
    M.add('base', blob((9, 4, 9), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(5, 26, 12, 2.5, 'skin', 10, 3))
    stalk = curve(V(0, 3, 0), V(0, 1, 0), 56, bend=V(4, 0, 5), waves=1, side=V(1, 0, 0), amp=3, n=12)
    M.add('base', tube(stalk, np.linspace(3.6, 2.0, 12), 'skin', 8))
    M.add('base', [ring(3.2, 0.7, stalk[i], (0, 1, 0), 'dark', 12, 4) for i in (3, 6, 9)])
    top = stalk[-1]
    M.piece('head', 'base', tuple(top + V(0, 4, 0)))
    M.add('head', blob(4.5, (0, 0, 0), 'skin'))
    M.piece('dish', 'head', (0, 3, 0))
    M.add('dish', pinna(V(0, 0, 4), V(0, 0, 1), 12, 17, 2.0, up=(0, 1, 0)))
    M.add('dish', conch(V(0, 0, 3), V(0, 0, -1), 1.6, 3.4, 1.2, 0.8, 1.8, rise=3.0, mat='dark', n=26, k=7))
    return M


def ty_fork():
    """Tuning Fork - light defence: a stalk that splits into two humming prongs; the note leaves between them."""
    M = Model('ty_fork'); M.piece('base'); M.add('base', [])
    M.add('base', blob((9, 4, 9), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(5, 30, 12, 2.8, 'skin', 11, 3))
    stalk = curve(V(0, 3, 0), V(0, 1, 0), 22, bend=V(0, 0, 2), n=6)
    M.add('base', tube(stalk, np.linspace(4.0, 2.8, 6), 'skin', 8))
    M.add('base', ring(4.4, 0.9, stalk[2], (0, 1, 0), 'dark', 14, 4))
    M.piece('head', 'base', tuple(stalk[-1] + V(0, 3, 1)))
    M.add('head', blob((4.5, 3.5, 5), (0, 0, 0), 'skin'))
    for s in (-1, 1):
        M.add('head', tube([V(s * 3, 1, 0), V(s * 4.6, 5, 1), V(s * 4.6, 6, 8), V(s * 4.2, 6.5, 14)], [1.3, 1.4, 1.1, 0.9], 'dark', 8))
        M.add('head', blob(1.4, V(s * 4.2, 6.5, 14.5), 'glow', lon=8, lat=6))
    M.add('head', drum((0, 0, 3.8), (0, 0, 1), 2.6, 0.9))
    tiny(M, 'muzzle', 'head', (0, 6, 14))
    return M


def ty_gong():
    """Great Gong - heavy defence: a tower holding a vast bronze disc and a horn on a pivot."""
    M = Model('ty_gong'); M.piece('base'); M.add('base', [])
    M.add('base', blob((26, 6, 26), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(7, 80, 22, 5, 'skin', 12, 4))
    path = curve(V(0, 3, 0), V(0, 1, 0), 52, n=10)
    M.add('base', tube(path, np.linspace(12, 8, 10), 'skin', 12))
    M.add('base', [ring(12 - 4 * i / 5 + 1, 1.6, V(0, 8 + i * 9, 0), (0, 1, 0), 'dark', 22, 6) for i in range(5)])
    for s in (-1, 1):
        M.add('base', tube([V(s * 9, 50, 0), V(s * 21, 62, 0), V(s * 22, 80, 0)], [2.2, 2.0, 1.8], 'dark', 8))
    M.add('base', drum(V(0, 78, -6), (0, 0, 1), 22, 4.2))
    M.add('base', pinna(V(0, 66, -14), V(0, 0.2, -1), 12, 15, 2.0))
    M.piece('head', 'base', (0, 62, 2))
    M.add('head', blob((9, 7, 9), (0, 0, 0), 'skin'))
    M.add('head', horn((0, 0, 6), (0, 0, 1), 16, 3.4, 9.5))
    M.add('head', crown(6, 8, 6, 9, 1.8, 'dark', 0.5))
    tiny(M, 'muzzle', 'head', (0, 0, 23))
    return M


TYMPAN = dict(ty_auditor=ty_auditor, ty_tuner=ty_tuner, ty_whisper=ty_whisper, ty_tinnitus=ty_tinnitus, ty_drummer=ty_drummer,
              ty_trumpeter=ty_trumpeter, ty_lullaby=ty_lullaby, ty_cacophon=ty_cacophon, ty_echo=ty_echo, ty_cilia=ty_cilia,
              ty_pinna=ty_pinna, ty_spiral=ty_spiral, ty_wax=ty_wax, ty_pinnamast=ty_pinnamast, ty_fork=ty_fork, ty_gong=ty_gong)
