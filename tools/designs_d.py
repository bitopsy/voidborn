"""Voidborn models - MIASMA BLOOM (the Nose), tier 1 (new in 0.16).

Drifting snouts and flowers: nostril faces, trunks that end in a flared bell, bladders of gas on tethers, bristles, petals.
Piece names follow gen_defs.write_scripts (base, head + muzzle to aim, nano, pad, crown / petals / rings / dish turn on their own,
spin turns while the unit is active).  The 'eye' material column of the atlas is the NOSTRIL of this faction (see textures.py).
"""
import numpy as np
from mesh import *
from designs_a import RS, V, tiny, crown, hang, roots


# ------------------------------------------------------------------------------------------ shared nose helpers
def nostril(pos, d, R, rim='skin', depth=0.55):
    """A nostril: a slightly flattened bulge showing the hole tile, with a thick lip."""
    pos = np.asarray(pos, float)
    return [place(ellipsoid((R, R * 0.85, R * depth), 'eye', 22, 14), pos, d), place(torus(R * 0.92, R * 0.2, rim, 24, 7), pos, d, s=(1, 0.85, 1))]


def bristles(n, R, pos, d, length, r0=0.5, mat='dark', fan=0.5, seed=1):
    """Nose hairs: a fan of stiff spikes round a point, leaning along `d`."""
    rs = np.random.RandomState(seed); pos = np.asarray(pos, float); d = norm(d); Rm = look(d); out = []
    for i in range(n):
        a = 2 * np.pi * (i + rs.uniform(-.2, .2)) / n
        radial = Rm @ np.array([np.cos(a), np.sin(a), 0])
        base = pos + radial * R * rs.uniform(0.7, 1.0)
        out.append(spike(base, norm(d + radial * fan), length * rs.uniform(0.75, 1.2), r0, mat, 4))
    return out


def trunk(pos, d, length, r0, r1, bend=(0, 0, 0), waves=0.0, side=(1, 0, 0), amp=0.0, mat='skin', lip='glow', n=11, flare=0.30):
    """A proboscis: a limber tube that narrows, then opens into a flared bell with a glowing lip."""
    pos = np.asarray(pos, float)
    path = curve(pos, d, length, bend=bend, waves=waves, side=side, amp=amp, n=n)
    u = np.linspace(0, 1, n)
    rad = (r0 + (r0 * 0.55 - r0) * np.minimum(u / (1 - flare), 1.0)) + (r1 - r0 * 0.55) * np.clip((u - (1 - flare)) / flare, 0, 1) ** 1.6
    parts = [tube(path, rad, mat, 12)]
    end, prev = path[-1], path[-2]
    parts.append(place(torus(r1, r1 * 0.16, lip, 22, 6), end, end - prev))
    return parts


def bladder(pos, R, mat='glow', tether_from=None, seed=0):
    """A gas bladder: a bulb of glowing gas; with `tether_from` it hangs on a thin cord."""
    pos = np.asarray(pos, float)
    out = [blob((R, R * 1.15, R), pos, mat, lon=12, lat=8)]
    if tether_from is not None:
        out.append(tube([np.asarray(tether_from, float), pos + V(0, R * 0.9, 0)], [0.5, 0.35], 'skin', 5))
    return out


def petals(n, R, y, length, width, mat_a='skin', mat_b='glow', rise=0.55, centre=(0, 0, 0), thick=0.5):
    """A ring of flower petals leaning outwards and up."""
    out = []
    for i in range(n):
        a = 2 * np.pi * i / n
        d = V(np.cos(a), rise, np.sin(a))
        out.append(blob((width, thick, length), V(centre[0] + np.cos(a) * R, centre[1] + y, centre[2] + np.sin(a) * R), mat_a if i % 2 else mat_b, d=d, lon=10, lat=6))
    return out


def snout(pos, d, w, h, l, mat='skin', nr=None, seed=1):
    """A snout: an egg with two nostrils on the front and a fan of bristles around them."""
    pos = np.asarray(pos, float); dd = norm(d); Rm = look(dd)
    nr = nr or w * 0.34
    out = [place(ellipsoid((w, h, l), mat, 20, 12), pos, d)]
    front = pos + dd * l * 0.82
    for s in (-1, 1):
        out += nostril(front + Rm @ np.array([s * w * 0.42, -h * 0.12, 0]), dd, nr)
    out += bristles(9, w * 0.9, front + Rm @ np.array([0, -h * 0.35, 0]), dd, w * 0.9, 0.45, 'dark', 0.6, seed)
    return out


# ============================================================================================ units
def mi_rhinarch():
    """Rhinarch - the commander: a vast drifting snout wearing a crown of petals, a trunk for a gun, gas bladders for ballast."""
    M = Model('mi_rhinarch'); M.piece('base'); M.add('base', [])
    rs = RS('rhin')
    M.add('base', blob((14, 17, 14), (0, 22, 0), 'skin'))
    M.add('base', ring(15, 2.2, (0, 31, 0), (0, 1, 0), 'dark'))
    M.add('base', ring(11.5, 1.5, (0, 13, 0), (0, 1, 0), 'dark'))
    for i in range(9):                         # bladders on tethers
        a = 2 * np.pi * i / 9 + 0.2; r = rs.uniform(5, 11)
        M.add('base', bladder(V(r * np.cos(a), 0 - rs.uniform(0, 8), r * np.sin(a)), rs.uniform(2.3, 3.6), 'glow' if i % 3 else 'skin', V(r * .5 * np.cos(a), 12, r * .5 * np.sin(a))))
    M.add('base', hang(8, 9, 12, 20, 1.8, 'skin', rs, 0.3, 1.2, 2.0))
    for s in (-1, 1):                          # olfactory bulbs on stalks
        M.add('base', tentacle(V(s * 11, 30, 2), V(s * 1, 0.5, 0.3), 16, 1.8, 'skin', bend=V(s * 2, 6, 0), waves=1, side=V(0, 0, 1), amp=1.2, r1=1.0))
        M.add('base', blob(4.4, V(s * 24, 40, 4), 'glow'))
        M.add('base', blob(2.4, V(s * 24, 40, 8), 'eye', d=(0, 0, 1)))
    M.piece('petals', 'base', (0, 42, 0))
    M.add('petals', petals(10, 11, 0, 17, 4.2, 'skin', 'glow', 0.9))
    M.piece('head', 'base', (0, 29, 8))
    M.add('head', snout((0, 0, 4), (0, 0, 1), 11, 9.5, 13))
    M.add('head', trunk((0, -5, 14), (0, -0.05, 1), 20, 3.2, 6.6, bend=V(0, -1, 0), waves=1, side=V(0, 1, 0), amp=2.0))
    tiny(M, 'muzzle', 'head', (0, -6, 34))
    return M


def mi_pollinator():
    """Pollinator - the builder: a small nostril bloom shedding spore-threads that knit structures."""
    M = Model('mi_pollinator'); M.piece('base'); M.add('base', [])
    M.add('base', blob((7.5, 8, 7.5), (0, 13, 0), 'skin'))
    M.add('base', nostril(V(0, 13, 6.4), (0, 0, 1), 4.2))
    M.add('base', petals(6, 6, 20, 8, 2.4, 'skin', 'glow', 0.8))
    M.add('base', ring(9.5, 0.8, (0, 13, 0), (0, 0.4, 1), 'dark'))
    for i, a in enumerate(np.linspace(0, 2 * np.pi, 5)[:-1] + 0.4):
        p = V(5 * np.cos(a), 8, 5 * np.sin(a) * 0.8)
        M.add('base', tentacle(p, V(np.cos(a) * .4, -0.7, 0.9), 14, 1.2, 'skin', bend=V(0, -2, 7), waves=1, side=V(1, 0, 0), amp=1.2, r1=0.5))
        M.add('base', blob(1.3, p + V(np.cos(a) * 4, -9, 12), 'glow', lon=8, lat=6))
    tiny(M, 'nano', 'base', (0, 2, 12))
    return M


def mi_sniffer():
    """Sniffer - scout: a slim bobbing snout, a long twitching nose, two bright bulbs for ears of the nose."""
    M = Model('mi_sniffer'); M.piece('base'); M.add('base', [])
    M.add('base', blob((3.6, 3.6, 6.5), (0, 7, -2), 'skin'))
    for s in (-1, 1):
        M.add('base', tentacle(V(s * 3, 8, -1), V(s * 1, 0.7, 0.2), 8, 0.8, 'skin', bend=V(s * 2, 3, 0), r1=0.5))
        M.add('base', blob(2.2, V(s * 11, 13, -0.5), 'glow', lon=10, lat=6))
    M.add('base', tentacle(V(0, 7, -7), V(0, 0, -1), 20, 1.8, 'skin', bend=V(0, 3, 0), waves=1.5, side=V(0, 1, 0), amp=2, r1=0.2))
    M.add('base', [bladder(V(0, 3, -4 - 2 * i), 1.2 + 0.2 * i, 'glow') for i in range(3)])
    M.piece('head', 'base', (0, 7, 5))
    M.add('head', trunk((0, 0, -1), (0, 0, 1), 11, 1.6, 2.8, bend=V(0, -1, 0), waves=1, side=V(0, 1, 0), amp=0.8, flare=0.35))
    M.add('head', nostril(V(0, 1.6, 1.5), (0, 0.6, 1), 1.6))
    tiny(M, 'muzzle', 'head', (0, -1, 10.5))
    return M


def mi_sneezer():
    """Sneezer - raider: a puffed bladder with a giant twitching nostril pair and stubby petal wings."""
    M = Model('mi_sneezer'); M.piece('base'); M.add('base', [])
    M.add('base', blob((5, 5.2, 7.5), (0, 6, 0), 'skin'))
    M.add('base', [ring(5.2, 0.55, (0, 6, z), (0, 0, 1), 'dark', 14, 5) for z in (-3.5, 0)])
    M.add('base', [blob((6.5, 0.6, 2.4), V(s * 7, 8, -1), 'glow' if s > 0 else 'skin', d=(s, 0.4, -0.3), lon=10, lat=6) for s in (-1, 1)])
    M.add('base', bladder(V(0, 12.5, -4), 2.8, 'glow'))
    M.add('base', cilia_like(6, 3, 4, 8, V(0, 0, -5)))
    M.piece('head', 'base', (0, 6, 5.5))
    for s in (-1, 1):
        M.add('head', nostril(V(s * 2.6, -0.3, 2.2), (0, 0, 1), 2.4))
    M.add('head', bristles(8, 4.4, (0, -2, 3.5), (0, 0, 1), 4.5, 0.4, 'dark', 0.7, 3))
    tiny(M, 'muzzle', 'head', (0, 0, 5.5))
    return M


def cilia_like(n, R, y, length, centre):
    return [spike(centre + V(R * np.cos(a), y, R * np.sin(a)) * 0.6, V(np.cos(a) * .3, -0.8, np.sin(a) * .3 - 0.5), length, 0.5, 'skin', 4) for a in np.linspace(0, 6.28, n + 1)[:-1]]


def mi_bellows():
    """Bellows - assault: a pleated barrel of a body that heaves gas through a flared snout."""
    M = Model('mi_bellows'); M.piece('base'); M.add('base', [])
    rs = RS('bell')
    M.add('base', blob((10, 10, 13), (0, 18, 0), 'skin'))
    M.add('base', [ring(10.2 * np.sqrt(max(0.1, 1 - (z / 13.0) ** 2)), 1.4, (0, 18, z), (0, 0, 1), 'dark', 22, 6) for z in np.linspace(-10, 10, 7)])
    M.add('base', hang(8, 7, 10, 16, 2.2, 'skin', rs, 0.35, 1.2, 2))
    for s in (-1, 1):
        M.add('base', tentacle(V(s * 9, 22, 2), V(s * 0.8, -0.5, 0.4), 16, 2.6, 'skin', bend=V(s * 3, -5, 6), waves=0.8, side=V(0, 1, 0), amp=1.5, r1=1.8))
        M.add('base', bladder(V(s * 12, 30, -6), 3.6, 'glow', V(s * 8, 25, -3)))
    M.add('base', nostril(V(0, 21, -12.5), (0, 0, -1), 3.8))
    M.piece('head', 'base', (0, 19, 10))
    M.add('head', blob((7, 6, 6), (0, 0, 0), 'dark'))
    M.add('head', trunk((0, 0, 3), (0, 0, 1), 14, 3.6, 7.4, bend=V(0, 1, 0)))
    tiny(M, 'muzzle', 'head', (0, 1, 17.5))
    return M


def mi_stinkhorn():
    """Stinkhorn - artillery: a gas-filled body and a long upswept trunk that lobs canisters of reek."""
    M = Model('mi_stinkhorn'); M.piece('base'); M.add('base', [])
    M.add('base', blob((7.5, 6.5, 10), (0, 10, 0), 'skin'))
    M.add('base', [ring(7.7, 0.9, (0, 10, z), (0, 0, 1), 'dark', 16, 5) for z in (-5, 0, 5)])
    M.add('base', [bladder(V(s * 7, 6, -6 + 6 * i), 2.6, 'glow', V(s * 4, 9, -6 + 6 * i)) for s in (-1, 1) for i in range(2)])
    M.add('base', tentacle(V(0, 9, -9), V(0, 0.1, -1), 14, 2.4, 'skin', bend=V(0, 5, 0), waves=1, side=V(1, 0, 0), amp=2.2, r1=0.3))
    M.add('base', nostril(V(0, 12, -8.8), (0, 0.3, -1), 3.0))
    M.piece('head', 'base', (0, 14, 3))
    M.add('head', blob((5, 5, 6), (0, 0, 0), 'dark'))
    M.add('head', trunk((0, 0, 3), (0, 0.15, 1), 30, 3.0, 8.6, bend=V(0, 7, 0), waves=1, side=V(1, 0, 0), amp=2.0, flare=0.26))
    tiny(M, 'muzzle', 'head', (0, 8, 33))
    return M


def mi_censer():
    """Censer - support: a swinging thurible trailing incense, hung from a drifting nostril bloom."""
    M = Model('mi_censer'); M.piece('base'); M.add('base', [])
    rs = RS('cens')
    M.add('base', blob((11, 7.5, 11), (0, 24, 0), 'skin'))
    M.add('base', nostril(V(0, 24, 10), (0, 0, 1), 3.8))
    M.add('base', petals(8, 9, 28, 8, 2.8, 'skin', 'glow', 0.8))
    for i in range(3):
        a = 2 * np.pi * i / 3
        M.add('base', tube([V(7 * np.cos(a), 20, 7 * np.sin(a)), V(3.5 * np.cos(a), 9, 3.5 * np.sin(a))], [0.7, 0.7], 'dark', 6))
    M.add('base', blob(6.6, (0, 5, 0), 'dark'))
    M.add('base', [ring(6.7, 0.7, (0, 5, 0), a, 'glow', 18, 5) for a in ((0, 1, 0), (1, 0, 0), (0, 0, 1))])
    M.add('base', [blob(rs.uniform(1.6, 3.0), V(rs.uniform(-5, 5), 12 + 5 * i, rs.uniform(-5, 5)), 'glow', lon=8, lat=6) for i in range(5)])
    M.add('base', hang(8, 9, 18, 16, 1.2, 'skin', rs, 0.4, 1.4, 1.2))
    tiny(M, 'nano', 'base', (0, -2, 0))
    return M


def mi_proboscis():
    """Proboscis - heavy: a vast bladder-bodied bloom with a ring of nostrils and one colossal trunk."""
    M = Model('mi_proboscis'); M.piece('base'); M.add('base', [])
    rs = RS('prob')
    M.add('base', blob((25, 21, 25), (0, 38, 0), 'skin'))
    M.add('base', blob((27, 10, 27), (0, 50, -1), 'dark', lat=10))
    M.add('base', ring(26, 3, (0, 38, 0), (0, 1, 0), 'dark', 36, 8))
    for i in range(9):
        a = 2 * np.pi * i / 9 + 0.2
        d = V(np.cos(a), 0.35, np.sin(a)); d = norm(d)
        if d[2] > 0.55: continue
        M.add('base', nostril(V(0, 38, 0) + d * 23, d, rs.uniform(4, 5.6)))
    for i in range(14):
        a = 2 * np.pi * i / 14; r = rs.uniform(10, 32)
        M.add('base', bladder(V(r * np.cos(a), 22 - rs.uniform(0, 16), r * np.sin(a)), rs.uniform(3, 6), 'glow' if i % 2 else 'skin', V(r * .5 * np.cos(a), 30, r * .5 * np.sin(a))))
    M.add('base', hang(11, 20, 26, 42, 4.6, 'skin', rs, 0.55, 1.4, 4, seed=5))
    M.piece('petals', 'base', (0, 62, 0))
    M.add('petals', petals(12, 20, 0, 24, 6, 'skin', 'glow', 0.7))
    M.piece('head', 'base', (0, 40, 22))
    M.add('head', snout((0, 0, 4), (0, 0, 1), 17, 14, 18))
    M.add('head', trunk((0, -7, 18), (0, -0.05, 1), 34, 6.2, 13.5, bend=V(0, -3, 0), waves=1, side=V(0, 1, 0), amp=3.0))
    tiny(M, 'muzzle', 'head', (0, -10, 52))
    return M


# ====================================================================================== structures
def mi_nostril():
    """Nostril Pit - factory: a broad fleshy rim around two vast nostrils that exhale the swarm."""
    M = Model('mi_nostril'); M.piece('base'); M.add('base', [])
    M.add('base', ring(36, 8, (0, 12, 0), (0, 1, 0), 'skin', 36, 12))
    M.add('base', blob((31, 2.0, 31), (0, 11, 0), 'glow', lat=6))
    M.add('base', blob((40, 6, 40), (0, 2, 0), 'dark', lat=8))
    M.add('base', roots(8, 80, 22, 6, 'skin', 4))
    for s in (-1, 1):
        M.add('base', nostril(V(s * 12, 21, 0), (0, 1, 0.1), 11, 'skin', 0.45))
    M.add('base', bristles(14, 28, (0, 14, 0), (0, 1, 0), 10, 0.9, 'dark', -0.2, 5))
    M.piece('crown', 'base', (0, 14, 0))
    M.add('crown', petals(10, 36, 4, 26, 4.6, 'skin', 'dark', -0.2))
    M.add('crown', [bladder(V(36 * np.cos(a), 24, 36 * np.sin(a)) * 0.82, 2.8, 'glow') for a in np.linspace(0, 6.28, 10)[:-1]])
    tiny(M, 'pad', 'base', (0, 18, 0))
    return M


def mi_truffle():
    """Truffle Snout - metal extractor: a snout rooting into the asteroid, tendrils snuffling round it."""
    M = Model('mi_truffle'); M.piece('base'); M.add('base', [])
    M.add('base', blob((8, 6, 8), (0, 7, 0), 'skin'))
    M.add('base', roots(5, 26, 11, 2.2, 'skin', 6, 5))
    M.add('base', spike(V(0, 3, 0), V(0, -1, 0), 10, 3.4, 'dark', 7))
    M.add('base', nostril(V(0, 12, 0), (0, 1, 0.15), 4.4))
    M.piece('spin', 'base', (0, 12, 0))
    M.add('spin', [tentacle(V(5 * np.cos(a), -3, 5 * np.sin(a)), V(np.cos(a), 0.6, np.sin(a)), 11, 1.5, 'dark', bend=V(0, 2, 0), droop=V(np.cos(a) * -3, 3, np.sin(a) * -3), waves=0.5, side=V(0, 1, 0), amp=1, r1=0.2) for a in np.linspace(0, 6.28, 6)[:-1]])
    return M


def mi_lily():
    """Sunlily - energy: a scented flower turning its petals to the stars."""
    M = Model('mi_lily'); M.piece('base'); M.add('base', [])
    M.add('base', blob((10, 4, 10), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(6, 40, 14, 3.0, 'skin', 7, 3))
    M.add('base', tube(curve(V(0, 3, 0), V(0, 1, 0), 10, n=4), [4, 3, 2.6, 3], 'skin', 8))
    M.add('base', blob(5.0, (0, 15, 0), 'glow'))
    M.add('base', [spike(V(2.2 * np.cos(a), 17, 2.2 * np.sin(a)), V(np.cos(a) * .2, 1, np.sin(a) * .2), 6, 0.5, 'dark', 4) for a in np.linspace(0, 6.28, 8)[:-1]])
    M.piece('petals', 'base', (0, 13, 0))
    M.add('petals', petals(10, 10, 5, 13, 2.8, 'skin', 'glow', 0.6))
    return M


def mi_amber():
    """Ambergris Core - advanced energy: a congealed lump of perfume that burns like a star, held in a cage of petals."""
    M = Model('mi_amber'); M.piece('base'); M.add('base', [])
    M.add('base', blob((36, 6, 36), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(10, 100, 24, 5, 'skin', 8, 4))
    M.add('base', blob(16, (0, 34, 0), 'glow'))
    M.add('base', blob(17, (0, 34, 0), 'skin', lon=10, lat=6))
    for a in np.linspace(0, 6.28, 6)[:-1] + 0.6:
        p = V(30 * np.cos(a), 6, 30 * np.sin(a))
        M.add('base', spike(p, V(-np.cos(a) * .25, 1, -np.sin(a) * .25), 40, 3.0, 'skin', 6))
        M.add('base', bladder(p + V(-np.cos(a) * 9, 40, -np.sin(a) * 9), 4.0, 'glow'))
    M.piece('rings', 'base', (0, 34, 0))
    M.add('rings', [ring(24, 1.5, (0, 0, 0), (1, 0.3, 0), 'glow'), ring(30, 1.2, (0, 0, 0), (-0.3, 1, 0.4), 'skin'), ring(36, 1.0, (0, 0, 0), (0.2, 0.2, 1), 'glow', 36, 6)])
    return M


def mi_musk():
    """Musk Sac - storage: a cluster of swollen scent glands with a puckered valve."""
    M = Model('mi_musk'); M.piece('base'); M.add('base', [])
    M.add('base', blob((20, 5, 20), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(6, 56, 18, 4, 'skin', 9, 3))
    M.add('base', blob((12, 18, 12), (0, 22, 0), 'skin'))
    M.add('base', [blob((8, 12, 8), V(11 * np.cos(a), 16, 11 * np.sin(a)), 'skin' if i % 2 else 'glow') for i, a in enumerate(np.linspace(0, 6.28, 5)[:-1] + 0.5)])
    M.add('base', [ring(12.5 * np.sqrt(max(0.05, 1 - ((y - 22) / 18) ** 2)), 1.0, (0, y, 0), (0, 1, 0), 'dark', 24, 5) for y in (14, 22, 30)])
    M.add('base', nostril(V(0, 36, 3), (0, 1, 0.3), 5))
    return M


def mi_scentstalk():
    """Scent Stalk - radar: a tall stalk crowned with nostril pods that taste the currents of the void."""
    M = Model('mi_scentstalk'); M.piece('base'); M.add('base', [])
    M.add('base', blob((9, 4, 9), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(5, 26, 12, 2.5, 'skin', 10, 3))
    stalk = curve(V(0, 3, 0), V(0, 1, 0), 56, bend=V(4, 0, 5), waves=1, side=V(1, 0, 0), amp=3, n=12)
    M.add('base', tube(stalk, np.linspace(3.6, 2.0, 12), 'skin', 8))
    M.add('base', [ring(3.2, 0.7, stalk[i], (0, 1, 0), 'dark', 12, 4) for i in (3, 6, 9)])
    top = stalk[-1]
    M.piece('head', 'base', tuple(top + V(0, 4, 0)))
    M.add('head', blob((6, 5, 6), (0, 0, 0), 'skin'))
    M.add('head', [nostril(V(5.2 * np.cos(a), 0.5, 5.2 * np.sin(a)), V(np.cos(a), 0.1, np.sin(a)), 2.5) for a in np.linspace(0, 6.28, 6)[:-1]])
    M.piece('dish', 'head', (0, 4, 0))
    M.add('dish', ring(11, 0.9, (0, 0, 0), (0, 1, 0), 'glow', 28, 6))
    M.add('dish', [spike(V(11 * np.cos(a), 0, 11 * np.sin(a)), V(np.cos(a) * .3, 1, np.sin(a) * .3), 7, 0.9, 'dark', 5) for a in np.linspace(0, 6.28, 8)[:-1]])
    return M


def mi_reek():
    """Reek Pod - light defence: a stalk with a bladder-pod and a short trunk that spits poison darts."""
    M = Model('mi_reek'); M.piece('base'); M.add('base', [])
    M.add('base', blob((9, 4, 9), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(5, 30, 12, 2.8, 'skin', 11, 3))
    stalk = curve(V(0, 3, 0), V(0, 1, 0), 22, bend=V(0, 0, 2), n=6)
    M.add('base', tube(stalk, np.linspace(4.0, 2.8, 6), 'skin', 8))
    M.add('base', ring(4.4, 0.9, stalk[2], (0, 1, 0), 'dark', 14, 4))
    M.add('base', [bladder(V(s * 7, 15, -2), 2.8, 'glow', V(s * 3, 12, -1)) for s in (-1, 1)])
    M.piece('head', 'base', tuple(stalk[-1] + V(0, 4, 1)))
    M.add('head', blob((6.4, 5, 6), (0, 0, 0), 'skin'))
    M.add('head', trunk((0, -0.5, 4), (0, 0.05, 1), 10, 2.2, 4.4, bend=V(0, 1, 0), flare=0.3))
    M.add('head', nostril(V(0, 3, 3), (0, 0.7, 1), 2.1))
    tiny(M, 'muzzle', 'head', (0, 0.5, 14.5))
    return M


def mi_stench():
    """Stench Tower - heavy defence: a thick trunk-tower crowned by a flared bell and bladders of heavy gas."""
    M = Model('mi_stench'); M.piece('base'); M.add('base', [])
    rs = RS('stench')
    M.add('base', blob((26, 6, 26), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(7, 80, 22, 5, 'skin', 12, 4))
    path = curve(V(0, 3, 0), V(0, 1, 0), 52, bend=V(0, 0, 5), n=10)
    M.add('base', tube(path, np.linspace(13, 8.5, 10), 'skin', 12))
    M.add('base', [ring(13 - 4.5 * i / 5 + 1, 1.6, V(0, 8 + i * 9, 0), (0, 1, 0), 'dark', 22, 6) for i in range(5)])
    M.add('base', [nostril(V(11.5 * np.cos(a), 24, 11.5 * np.sin(a)), V(np.cos(a), 0, np.sin(a)), 3.4) for a in np.linspace(0, 6.28, 5)[:-1]])
    M.add('base', [bladder(V(s * 17, 20 + 8 * i, 0), 4.6, 'glow' if i else 'skin', V(s * 10, 18 + 8 * i, 0)) for s in (-1, 1) for i in range(2)])
    M.piece('head', 'base', (0, 62, 4))
    M.add('head', blob((12, 9, 12), (0, 0, 0), 'skin'))
    M.add('head', trunk((0, 0, 8), (0, 0.1, 1), 22, 5.0, 11.5, bend=V(0, 5, 0), waves=1, side=V(1, 0, 0), amp=2.5))
    M.add('head', petals(8, 10, 8, 9, 2.8, 'skin', 'glow', 0.8))
    tiny(M, 'muzzle', 'head', (0, 5, 30))
    return M


MIASMA = dict(mi_rhinarch=mi_rhinarch, mi_pollinator=mi_pollinator, mi_sniffer=mi_sniffer, mi_sneezer=mi_sneezer, mi_bellows=mi_bellows,
              mi_stinkhorn=mi_stinkhorn, mi_censer=mi_censer, mi_proboscis=mi_proboscis, mi_nostril=mi_nostril, mi_truffle=mi_truffle,
              mi_lily=mi_lily, mi_amber=mi_amber, mi_musk=mi_musk, mi_scentstalk=mi_scentstalk, mi_reek=mi_reek, mi_stench=mi_stench)
