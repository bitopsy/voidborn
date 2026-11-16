"""Voidborn TIER 2 models: the upgraded factories and the T2 roster of both factions.

Registered in gen_assets.py (CHOIR_T2 / MAW_T2).  Piece names follow the conventions of gen_defs.write_scripts:
base, head (+ muzzle) for aiming, nano for builders, pad for factories, halo / crown / rings spin on their own.
"""
import numpy as np
from mesh import *
from designs_a import RS, V, tiny, legs, crown, hang, roots
from designs_b import maw


# ============================================================================= CHOIR OF THE EYE (T2)
def ch_womb2():
    """Great Iris Womb - the T1 womb with a cathedral tower, a great eye and a haloed crown."""
    M = Model('ch_womb2'); M.piece('base'); M.add('base', [])
    rs = RS('womb2')
    M.add('base', ring(36, 8, (0, 12, 0), (0, 1, 0), 'skin', 36, 12))
    M.add('base', blob((31, 2.0, 31), (0, 11, 0), 'glow', lat=6))
    M.add('base', blob((40, 6, 40), (0, 2, 0), 'dark', lat=8))
    M.add('base', roots(8, 80, 22, 6, 'skin', 4))
    # the tower
    path = curve(V(0, 12, 0), V(0, 1, 0), 50, bend=V(0, 0, 3), n=8)
    M.add('base', tube(path, np.linspace(17, 9.5, 8), 'skin', 14))
    M.add('base', [ring(16.5 - 2.4 * i, 1.7, V(0, 22 + i * 10, 0), (0, 1, 0), 'dark', 22, 6) for i in range(4)])
    M.add('base', eye(16, (0, 70, 2), (0, 0.45, 0.9)))
    M.add('base', blob((19, 6, 18), (0, 82, -1), 'dark'))
    M.add('base', crown(7, 12, 80, 13, 2.2, 'dark', 0.45, centre=(0, 0, -1)))
    # small watchers around the rim
    M.add('base', [eye(4.6, V(33 * np.cos(a), 17, 33 * np.sin(a)), V(np.cos(a), 0.25, np.sin(a)), lid=False)
                   for a in np.linspace(0, 6.28, 9)[:-1]])
    M.add('base', hang(8, 15, 40, 34, 1.8, 'skin', rs, 0.35, 1.4, 2.0))
    M.piece('crown', 'base', (0, 14, 0))
    M.add('crown', crown(12, 37, 2, 34, 3.2, 'dark', -0.35, centre=(0, 0, 0)))
    M.add('crown', [ring(4, 0.8, V(37 * np.cos(a), 26, 37 * np.sin(a)) * 0.82, (0, 1, 0), 'glow', 10, 4) for a in np.linspace(0, 6.28, 13)[:-1]])
    M.piece('halo', 'base', (0, 98, 0))
    M.add('halo', ring(25, 1.8, (0, 0, 0), (0, 1, 0), 'glow', 32, 6))
    M.add('halo', [spike(V(25 * np.cos(a), 0, 25 * np.sin(a)), V(np.cos(a), 0.2, np.sin(a)), 8, 1.5, 'dark', 5) for a in np.linspace(0, 6.28, 9)[:-1]])
    tiny(M, 'pad', 'base', (0, 18, 0))
    return M


def ch_saccade():
    """Saccade - dart-shaped striker, all eye and fins."""
    M = Model('ch_saccade'); M.piece('base'); M.add('base', [])
    rs = RS('sacc')
    M.add('base', blob((4.5, 4, 11), (0, 9, -3), 'skin'))
    M.add('base', eye(4.6, (0, 9, 7), (0, 0, 1)))
    M.add('base', [blob((12, 0.7, 4.5), V(s * 9, 9, -5), 'glow', d=(s, 0, -0.35), lon=12, lat=6) for s in (-1, 1)])
    M.add('base', [blob((8, 0.6, 3.2), V(s * 6, 13, -8), 'dark', d=(s, 0.3, -0.4), lon=10, lat=6) for s in (-1, 1)])
    M.add('base', hang(5, 3.2, 7, 12, 0.9, 'skin', rs, 0.3, 1.4, 1.0, centre=(0, 0, -6)))
    M.add('base', spike(V(0, 12, -6), V(0, 0.8, -1), 9, 1.3, 'dark', 5))
    M.piece('head', 'base', (0, 9, 8))
    M.add('head', crown(5, 4.2, 2, 5, 0.9, 'dark', 0.6, centre=(0, 0, -1)))
    tiny(M, 'muzzle', 'head', (0, 0, 6))
    return M


def ch_sclera():
    """Sclera Knight - a one-eyed armoured champion with an iris-shield."""
    M = Model('ch_sclera'); M.piece('base'); M.add('base', [])
    rs = RS('scler')
    M.add('base', blob((16, 18, 14), (0, 30, 0), 'skin'))
    M.add('base', blob((18, 7, 16), (0, 44, -1), 'dark', lat=10))
    M.add('base', ring(17, 2.4, (0, 30, 0), (0, 1, 0), 'dark', 28, 8))
    M.add('base', ring(13, 1.8, (0, 20, 0), (0, 1, 0), 'dark', 24, 6))
    M.add('base', hang(10, 11, 18, 26, 2.2, 'skin', rs, 0.35, 1.3, 2.2))
    for s in (-1, 1):   # club arms ending in glowing mace-orbs
        M.add('base', tentacle(V(s * 15, 36, 2), V(s * 1, -0.35, 0.6), 24, 3.4, 'skin', bend=V(s * 5, -8, 10), waves=0.8, side=V(0, 1, 0), amp=1.5, r1=2.0))
        M.add('base', blob(6, V(s * 30, 24, 20), 'glow'))
        M.add('base', crown(7, 6.2, 1, 7, 1.4, 'dark', 0.9, centre=V(s * 30, 24, 20)))
    # shield: a vertical iris ring in front of the chest
    M.add('base', ring(15, 1.6, (0, 32, 17), (0, 0, 1), 'glow', 28, 6))
    M.add('base', eye(7, (0, 32, 14), (0, 0, 1)))
    M.add('base', crown(8, 13, 46, 9, 1.9, 'dark', 0.45, centre=(0, 0, -2)))
    M.piece('head', 'base', (0, 40, 6))
    M.add('head', eye(9, (0, 0, 6), (0, 0, 1)))
    M.add('head', blob((10.5, 5, 9), (0, 8.5, 2), 'dark'))
    tiny(M, 'muzzle', 'head', (0, 0, 16))
    return M


def ch_lance():
    """Lidless Lance - a coiled serpent that carries a lance-length iris beam."""
    M = Model('ch_lance'); M.piece('base'); M.add('base', [])
    rs = RS('lance')
    body = curve(V(0, 14, -34), V(0, 0.1, 1), 62, bend=V(0, 12, 0), waves=1.2, side=V(1, 0, 0), amp=5, n=12)
    M.add('base', tube(body, np.linspace(2.6, 9, 12), 'skin', 10))
    M.add('base', [ring(9.5 - k * 0.4, 1.2, body[k + 4], (0, 0.2, 1), 'dark', 16, 5) for k in range(0, 8, 2)])
    M.add('base', [spike(body[k] + V(0, 7, 0), V(0, 1, -0.4), 8, 1.5, 'glow', 5) for k in range(2, 11, 2)])
    M.add('base', [blob((14, 0.8, 6), body[7] + V(s * 12, 1, 0), 'glow', d=(s, 0, 0.2), lon=12, lat=6) for s in (-1, 1)])
    M.add('base', tentacle(body[0] + V(0, 0, -2), V(0, 0, -1), 22, 2.4, 'skin', waves=1, side=V(1, 0, 0), amp=3, r1=0.3))
    M.piece('head', 'base', tuple(body[-1] + V(0, 3, 6)))
    M.add('head', eye(10, (0, 0, 2), (0, 0, 1)))
    M.add('head', blob((11, 5, 10), (0, 9, 0), 'dark'))
    barrel = curve(V(0, 0, 10), V(0, 0, 1), 46, n=6)
    M.add('head', tube(barrel, [4.2, 3.4, 3.0, 2.6, 2.2, 1.6], 'dark', 8))
    M.add('head', [ring(5.0 - k * 0.5, 0.9, V(0, 0, 18 + k * 9), (0, 0, 1), 'glow', 14, 4) for k in range(4)])
    tiny(M, 'muzzle', 'head', (0, 0, 57))
    return M


def ch_lachryma():
    """Lachryma - a haloed tear-mother; her tears mend and her tendrils build."""
    M = Model('ch_lachryma'); M.piece('base'); M.add('base', [])
    rs = RS('lachr')
    M.add('base', blob((16, 11, 16), (0, 26, 0), 'skin', lat=12))
    M.add('base', ring(16, 1.8, (0, 22, 0), (0, 1, 0), 'dark', 26, 6))
    M.add('base', eye(7, (0, 24, 12), (0, 0, 1)))
    M.add('base', hang(14, 11, 22, 32, 1.6, 'skin', rs, 0.4, 1.5, 1.6))
    M.add('base', [blob(2.0, V(14 * np.cos(a), 6 + 3 * np.sin(3 * a), 14 * np.sin(a)), 'glow', lon=8, lat=6) for a in np.linspace(0, 6.28, 9)[:-1]])
    M.add('base', tentacle(V(0, 20, 0), V(0, -1, 0.1), 26, 3.2, 'glow', waves=1.2, side=V(1, 0, 0), amp=1.6, r1=0.6))
    M.piece('rings', 'base', (0, 40, 0))
    M.add('rings', ring(20, 1.3, (0, 0, 0), (0, 1, 0), 'glow', 30, 6))
    M.add('rings', [spike(V(20 * np.cos(a), 0, 20 * np.sin(a)), V(np.cos(a), 0.5, np.sin(a)), 6, 1.2, 'dark', 5) for a in np.linspace(0, 6.28, 8)[:-1]])
    tiny(M, 'nano', 'base', (0, 4, 0))
    return M


def ch_panopticon():
    """Panopticon - the all-seeing flagship: a sphere of eyes in a spinning halo."""
    M = Model('ch_panopticon'); M.piece('base'); M.add('base', [])
    rs = RS('panop')
    M.add('base', blob((32, 28, 32), (0, 62, 0), 'skin'))
    M.add('base', blob((34, 12, 34), (0, 82, -1), 'dark', lat=10))
    M.add('base', ring(34, 3.6, (0, 62, 0), (0, 1, 0), 'dark', 40, 8))
    for i in range(22):
        z = rs.uniform(-1, 1); a = rs.uniform(0, 6.28); r = np.sqrt(1 - z * z)
        d = norm(V(r * np.cos(a), 0.2 + abs(z) * 0.8, r * np.sin(a)))
        if d[2] > 0.55: continue
        M.add('base', eye(rs.uniform(3.8, 6.4), V(0, 62, 0) + d * 31, d))
    M.add('base', hang(14, 28, 46, 70, 6.0, 'skin', rs, 0.55, 1.5, 5, seed=7))
    M.add('base', crown(10, 22, 90, 16, 3.0, 'dark', 0.25, centre=(0, 0, -8)))
    M.piece('halo', 'base', (0, 120, 0))
    M.add('halo', ring(64, 2.8, (0, 0, 0), (0, 1, 0), 'glow', 48, 8))
    M.add('halo', ring(52, 1.8, (0, 3, 0), (0.2, 1, 0), 'glow', 40, 6))
    M.add('halo', [spike(V(64 * np.cos(a), 0, 64 * np.sin(a)), V(np.cos(a), 0.1, np.sin(a)), 16, 2.6, 'dark', 5) for a in np.linspace(0, 6.28, 17)[:-1]])
    M.piece('head', 'base', (0, 66, 30))
    M.add('head', eye(24, (0, 0, 8), (0, 0, 1)))
    M.add('head', blob((27, 11, 24), (0, 22, 3), 'dark'))
    M.add('head', crown(12, 21, 17, 20, 3.0, 'dark', 0.5, centre=(0, 0, 0)))
    M.add('head', [eye(7, V(s * 28, 2, 2), V(s * 0.5, 0, 1), lid=False) for s in (-1, 1)])
    tiny(M, 'muzzle', 'head', (0, 0, 36))
    return M


# ============================================================================= MAW SWARM (T2)
def mw_hive2():
    """Great Brood Hive - the hive grown a second mound, a ribcage of spires and a fanged throat."""
    M = Model('mw_hive2'); M.piece('base'); M.add('base', [])
    rs = RS('hive2')
    M.add('base', blob((40, 7, 40), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(9, 96, 24, 6, 'skin', 21, 4))
    M.add('base', blob((28, 18, 28), (0, 18, -4), 'skin'))
    M.add('base', blob((20, 22, 20), (0, 40, -8), 'dark'))
    M.add('base', blob((13, 15, 13), (0, 60, -10), 'skin'))
    M.add('base', [blob(rs.uniform(7, 11), V(30 * np.cos(a), 11, 26 * np.sin(a) * 0.9 - 6), 'glow' if i % 2 else 'skin') for i, a in enumerate(np.linspace(0, 6.28, 8)[:-1] + 1.7)])
    M.add('base', maw(17, (0, 18, 25), (0, 0.05, 1), rings=((1.0, 18, 0.55), (0.7, 12, 0.45), (0.45, 8, 0.35)), seed=13))
    M.add('base', [spike(V(18 * np.cos(a), 26, 14 * np.sin(a) - 8), V(np.cos(a) * 0.4, 1, np.sin(a) * 0.4 - .3), 15, 2.6, 'dark', 5) for a in np.linspace(0, 6.28, 11)[:-1]])
    M.add('base', [spike(V(13 * np.cos(a), 56, 13 * np.sin(a) - 10), V(np.cos(a) * 0.3, 1, np.sin(a) * 0.3), 20, 2.4, 'dark', 5) for a in np.linspace(0, 6.28, 7)[:-1]])
    M.add('base', [blob(4.2, V(22 * np.cos(a), 44, 22 * np.sin(a) - 8), 'glow', lon=8, lat=6) for a in np.linspace(0, 6.28, 6)[:-1] + 0.5])
    M.piece('crown', 'base', (0, 78, -10))
    M.add('crown', blob(8, (0, 2, 0), 'glow'))
    M.add('crown', [spike(V(10 * np.cos(a), 0, 10 * np.sin(a)), V(np.cos(a), 0.8, np.sin(a)), 12, 1.6, 'dark', 5) for a in np.linspace(0, 6.28, 7)[:-1]])
    tiny(M, 'pad', 'base', (0, 12, 32))
    return M


def mw_shear():
    """Shearwing - a four-winged wasp with a flaying breath."""
    M = Model('mw_shear'); M.piece('base'); M.add('base', [])
    rs = RS('shear')
    M.add('base', blob((5, 4.5, 8), (0, 10, -4), 'dark'))
    M.add('base', blob((3.6, 3.4, 4.6), (0, 9, 5), 'skin'))
    M.add('base', blob((3.8, 3.6, 9), (0, 9.5, -15), 'skin'))
    M.add('base', [blob((13, 0.5, 4.2), V(s * 10, 13, -4 - k * 5), 'glow' if k else 'skin', d=(s, 0.25, -0.3), lon=12, lat=6)
                   for s in (-1, 1) for k in (0, 1)])
    M.add('base', [eye(1.5, V(s * 2, 11, 7.5), V(s * .3, .2, 1), lid=False) for s in (-1, 1)])
    M.add('base', spike(V(0, 9, -23), V(0, -0.1, -1), 12, 1.8, 'dark', 5))
    M.add('base', legs(2, V(3, 7, -3), 6, 6, 0.8, 'dark', rs, zspan=4))
    M.piece('head', 'base', (0, 9, 8))
    M.add('head', maw(3.6, (0, 0, 2), (0, 0, 1), rings=((1.0, 9, 0.7),), seed=4))
    M.add('head', [spike(V(s * 3, 1, 3), V(s * 0.6, 0, 1), 8, 1.0, 'dark', 5) for s in (-1, 1)])
    tiny(M, 'muzzle', 'head', (0, 0, 8))
    return M


def mw_warmaw():
    """Warmaw - an armoured war-beast: plated back, spore pods, a mouth that is a siege engine."""
    M = Model('mw_warmaw'); M.piece('base'); M.add('base', [])
    rs = RS('warmaw')
    M.add('base', blob((19, 15, 26), (0, 25, -6), 'dark'))
    M.add('base', [ring(18 - abs(z) * 0.1, 1.8, (0, 25, z - 6), (0, 0, 1), 'skin', 20, 5) for z in (-16, -6, 4, 14)])
    M.add('base', blob((13, 11, 12), (0, 22, 16), 'skin'))
    M.add('base', [spike(V(0, 38 - abs(z) * 0.06, z - 6), V(0, 1, -0.4), 14, 2.6, 'dark', 5) for z in (-20, -10, 0, 10, 20)])
    M.add('base', [blob(3.6, V(s * 17, 31, -2 - k * 9), 'glow', lon=8, lat=6) for s in (-1, 1) for k in range(3)])
    M.add('base', legs(3, V(14, 20, -4), 20, 20, 3.4, 'dark', rs, zspan=11))
    M.add('base', tentacle(V(0, 22, -32), V(0, 0.1, -1), 24, 4.6, 'skin', bend=V(0, 10, 0), waves=1, side=V(1, 0, 0), amp=3, r1=0.4))
    M.piece('head', 'base', (0, 24, 22))
    M.add('head', maw(12, (0, 0, 8), (0, 0, 1), rings=((1.0, 18, 0.55), (0.7, 12, 0.5)), seed=6, lip=0.26))
    M.add('head', [eye(2.8, V(s * 7, 10, 2), V(s * .3, .3, 1), lid=False) for s in (-1, 1)])
    M.add('head', [spike(V(s * 11, 6, 2), V(s * 0.6, 0.4, 1), 14, 2.0, 'dark', 5) for s in (-1, 1)])
    tiny(M, 'muzzle', 'head', (0, 0, 22))
    return M


def mw_rupturer():
    """Rupturer - a swollen bile-sac on stilts; its throat is a mortar."""
    M = Model('mw_rupturer'); M.piece('base'); M.add('base', [])
    rs = RS('rupt')
    M.add('base', blob((22, 18, 24), (0, 30, -6), 'skin'))
    M.add('base', [blob(rs.uniform(3.6, 5.4), V(22 * np.cos(a) * 0.9, 30 + 12 * np.sin(a * 2), -6 + 23 * np.sin(a)) * V(0.85, 1, 0.85) + V(0, 6, 0), 'glow', lon=8, lat=6)
                   for a in np.linspace(0, 6.28, 11)[:-1]])
    M.add('base', [ring(21 - k * 1.2, 1.7, (0, 30, -6 + k * 7 - 12), (0, 0, 1), 'dark', 18, 5) for k in range(5)])
    M.add('base', legs(4, V(12, 22, -4), 16, 22, 2.4, 'dark', rs, zspan=8))
    M.add('base', tentacle(V(0, 26, -28), V(0, 0, -1), 20, 4.6, 'skin', bend=V(0, 8, 0), waves=1, side=V(1, 0, 0), amp=2, r1=0.5))
    M.piece('head', 'base', (0, 34, 14))
    path = curve(V(0, 0, 0), V(0, 0.25, 1), 40, bend=V(0, 8, 0), n=9)
    M.add('head', tube(path, np.linspace(8, 3.6, 9), 'skin', 10))
    M.add('head', maw(6.4, V(0, 10, 40), norm(V(0, 0.3, 1)), rings=((1.0, 10, 0.6), (0.65, 7, 0.5)), seed=8))
    M.add('head', [eye(2.0, V(s * 6, 4, 6), V(s * .5, .3, 1), lid=False) for s in (-1, 1)])
    tiny(M, 'muzzle', 'head', (0, 11, 48))
    return M


def mw_midwife():
    """Midwife - a brood-tender that cradles a cluster of glowing egg-sacs."""
    M = Model('mw_midwife'); M.piece('base'); M.add('base', [])
    rs = RS('midw')
    M.add('base', blob((13, 11, 16), (0, 24, 0), 'skin'))
    M.add('base', blob((9, 9, 9), (0, 12, -2), 'glow'))
    M.add('base', [blob(rs.uniform(3.2, 4.6), V(11 * np.cos(a), 7 + 2 * np.sin(a * 3), 11 * np.sin(a)), 'glow' if i % 2 else 'skin', lon=8, lat=6)
                   for i, a in enumerate(np.linspace(0, 6.28, 8)[:-1])])
    M.add('base', [ring(13 - k * 0.8, 1.3, (0, 24, -8 + k * 5), (0, 0, 1), 'dark', 18, 4) for k in range(4)])
    M.add('base', hang(12, 8, 18, 18, 1.4, 'skin', rs, 0.5, 1.4, 1.6))
    M.add('base', eye(5.4, (0, 26, 12), (0, 0.1, 1)))
    M.add('base', [blob((12, 0.4, 5), V(s * 15, 30, -3), 'glow', d=(s, 0.2, 0), lon=12, lat=6) for s in (-1, 1)])
    M.add('base', [blob((9, 0.4, 3.6), V(s * 13, 27, -9), 'skin', d=(s, 0.2, -0.3), lon=10, lat=6) for s in (-1, 1)])
    tiny(M, 'nano', 'base', (0, 4, 0))
    return M


def mw_devourer():
    """Devourer - a world-eater: a train of armoured segments behind a gate of teeth."""
    M = Model('mw_devourer'); M.piece('base'); M.add('base', [])
    rs = RS('devour')
    M.add('base', blob((34, 30, 42), (0, 52, -34), 'dark'))
    for k, (z, r) in enumerate([(-86, 26), (-122, 21), (-154, 16), (-180, 11)]):
        M.add('base', blob((r, r * 0.9, 24), (0, 48 + k * 3, z), 'skin' if k % 2 == 0 else 'dark'))
    M.add('base', tentacle(V(0, 54, -190), V(0, 0.2, -1), 50, 10, 'skin', bend=V(0, 22, 0), waves=1, side=V(1, 0, 0), amp=6, r1=0.6))
    M.add('base', [spike(V(0, 52 + 30 - abs(z + 40) * 0.1, z), V(0, 1, -0.5), 22 - abs(z + 40) * 0.07, 4.0, 'glow', 5)
                   for z in (-6, -24, -42, -62, -84, -108, -132, -158)])
    M.add('base', [blob((22, 1.0, 12), V(s * 34, 42, -40), 'glow', d=(s, 0, 0.3), lon=12, lat=6) for s in (-1, 1)])
    M.add('base', [blob((16, 0.8, 9), V(s * 28, 44, -78), 'skin', d=(s, 0, 0.2), lon=12, lat=6) for s in (-1, 1)])
    M.add('base', [blob(5.0, V(s * 30, 60, -16 - k * 18), 'glow', lon=8, lat=6) for s in (-1, 1) for k in range(3)])
    M.add('base', legs(4, V(24, 40, -40), 28, 24, 4.6, 'skin', rs, zspan=15))
    M.piece('head', 'base', (0, 54, 6))
    M.add('head', maw(36, (0, 0, 10), (0, 0, 1), rings=((1.0, 26, 0.55), (0.76, 19, 0.5), (0.52, 13, 0.42), (0.3, 8, 0.35)), seed=11, lip=0.22))
    M.add('head', [tentacle(V(38 * np.cos(a), 38 * np.sin(a), 8), V(np.cos(a) * 0.4, np.sin(a) * 0.4, 1), 38, 5.0, 'skin', waves=1.2,
                           side=V(-np.sin(a), np.cos(a), 0), amp=5, r1=0.6) for a in np.linspace(0, 6.28, 11)[:-1]])
    M.add('head', [eye(5, V(s * 22, 38, 4), V(s * .3, .5, 1), lid=False) for s in (-1, 1)])
    tiny(M, 'muzzle', 'head', (0, 0, 40))
    return M


CHOIR_T2 = dict(ch_womb2=ch_womb2, ch_saccade=ch_saccade, ch_sclera=ch_sclera, ch_lance=ch_lance,
                ch_lachryma=ch_lachryma, ch_panopticon=ch_panopticon)
MAW_T2 = dict(mw_hive2=mw_hive2, mw_shear=mw_shear, mw_warmaw=mw_warmaw, mw_rupturer=mw_rupturer,
              mw_midwife=mw_midwife, mw_devourer=mw_devourer)
