"""Voidborn TIER 2 models of the two 0.16 factions: Tympan Conclave (Ear) and Miasma Bloom (Nose).
Piece names follow the same conventions as designs_t2.py."""
import numpy as np
from mesh import *
from designs_a import RS, V, tiny, crown, hang, roots
from designs_c import spiral, conch, pinna, horn, drum, cilia, fork
from designs_d import nostril, bristles, trunk, bladder, petals, snout


# ============================================================================= TYMPAN CONCLAVE (T2)
def ty_echo2():
    """Grand Echo Chamber - the Echo Chamber with a cathedral of horns and a great cochlea tower."""
    M = Model('ty_echo2'); M.piece('base'); M.add('base', [])
    rs = RS('echo2')
    M.add('base', ring(36, 8, (0, 12, 0), (0, 1, 0), 'skin', 36, 12))
    M.add('base', blob((31, 2.0, 31), (0, 11, 0), 'glow', lat=6))
    M.add('base', blob((40, 6, 40), (0, 2, 0), 'dark', lat=8))
    M.add('base', roots(8, 80, 22, 6, 'skin', 4))
    M.add('base', conch(V(0, 14, 0), V(0, 1, 0), 2.8, 16, 5, 5, 9, rise=60, mat='skin', n=64, k=14))
    M.add('base', drum(V(0, 62, 14), (0, 0.3, 1), 12))
    M.add('base', [horn(V(26 * np.cos(a), 20, 26 * np.sin(a)), V(np.cos(a), 0.8, np.sin(a)), 22, 2.6, 7.0) for a in np.linspace(0, 6.28, 7)[:-1]])
    M.add('base', cilia(14, 22, 12, 18, 1.4, 'skin', None, seed=12, glow_tips=True))
    M.piece('crown', 'base', (0, 14, 0))
    M.add('crown', [pinna(V(38 * np.cos(a), 12, 38 * np.sin(a)), V(np.cos(a), 0.55, np.sin(a)), 8, 16, 2.0) for a in np.linspace(0, 6.28, 12)[:-1]])
    M.piece('halo', 'base', (0, 92, 0))
    M.add('halo', ring(25, 1.8, (0, 0, 0), (0, 1, 0), 'glow', 32, 6))
    M.add('halo', [fork(V(25 * np.cos(a), 0, 25 * np.sin(a)), V(np.cos(a) * .3, 1, np.sin(a) * .3), 12, 3, 1.1) for a in np.linspace(0, 6.28, 9)[:-1]])
    tiny(M, 'pad', 'base', (0, 18, 0))
    return M


def ty_banshee():
    """Banshee - T2 raider: a streamlined scream, swept pinna-wings and a wide-open horn mouth."""
    M = Model('ty_banshee'); M.piece('base'); M.add('base', [])
    M.add('base', blob((4.2, 4, 11), (0, 9, -3), 'skin'))
    M.add('base', [pinna(V(s * 9, 9, -6), V(s * .6, 0.3, -.8), 11, 5, 0.8, up=(0, 0, 1)) for s in (-1, 1)])
    M.add('base', [pinna(V(s * 6, 13, -9), V(s * .4, 0.9, -.6), 7, 3.6, 0.6, 'dark', 'glow', glowin=False, up=(0, 0, 1)) for s in (-1, 1)])
    M.add('base', cilia(7, 3, 7, 12, 0.7, 'skin', V(0, 0, -7), seed=13))
    M.add('base', spike(V(0, 12, -6), V(0, 0.8, -1), 9, 1.3, 'dark', 5))
    M.piece('head', 'base', (0, 9, 7))
    M.add('head', horn((0, 0, -2), (0, 0, 1), 7, 1.5, 4.6))
    tiny(M, 'muzzle', 'head', (0, 0, 6.5))
    return M


def ty_malleus():
    """Malleus - T2 assault: an armoured champion that wields a great hammer-bone and a drum shield."""
    M = Model('ty_malleus'); M.piece('base'); M.add('base', [])
    rs = RS('mall')
    M.add('base', blob((11, 13, 9.5), (0, 20, 0), 'skin'))
    M.add('base', ring(11.5, 2.0, (0, 13, 0), (0, 1, 0), 'dark'))
    M.add('base', drum(V(0, 19, 9), (0, 0.1, 1), 9.5, 2.8))
    M.add('base', cilia(10, 8, 11, 18, 1.2, 'skin', None, seed=14))
    M.add('base', [pinna(V(s * 13, 26, -3), V(s * .9, 0.2, -.3), 7, 11, 1.2) for s in (-1, 1)])
    M.add('base', tentacle(V(11, 26, 0), V(0.6, -0.4, 0.6), 15, 3.0, 'skin', bend=V(3, -2, 6), waves=0.8, side=V(0, 1, 0), amp=1.2, r1=2.2))
    M.add('base', tube([V(17, 14, 12), V(19, 28, 18)], [1.3, 1.3], 'dark', 8))
    M.add('base', blob((3.4, 7, 3.4), V(19, 31, 18), 'dark'))
    M.add('base', blob((3.6, 3.6, 3.6), V(19, 36, 18), 'glow'))
    M.add('base', blob((4.5, 3.4, 4.5), (-11, 26, 0), 'dark'))
    M.add('base', tentacle(V(-11, 25, 0), V(-0.5, -0.6, 0.6), 16, 3.0, 'skin', bend=V(-3, -4, 8), waves=0.8, side=V(0, 1, 0), amp=1.5, r1=2.2))
    M.piece('head', 'base', (0, 34, 3))
    M.add('head', blob((6.5, 5.6, 6.2), (0, 2, 2), 'skin'))
    M.add('head', drum((0, 2, 7.5), (0, 0, 1), 4.2))
    M.add('head', crown(5, 6, 7, 8, 1.3, 'dark', 0.6))
    tiny(M, 'muzzle', 'head', (0, 2, 12))
    return M


def ty_foghorn():
    """Foghorn - T2 artillery: a body no more than a stand for the longest horn in the rift."""
    M = Model('ty_foghorn'); M.piece('base'); M.add('base', [])
    M.add('base', blob((8, 6.5, 11), (0, 10, 0), 'skin'))
    M.add('base', [ring(8.2, 1.0, (0, 10, z), (0, 0, 1), 'dark', 16, 5) for z in (-5, 0, 5)])
    M.add('base', conch(V(0, 13, -9), V(0, 0.2, -1), 2.4, 5.5, 1.8, 1.5, 3.6, rise=7, mat='dark'))
    M.add('base', [pinna(V(s * 8, 14, -4), V(s * .8, 0.4, -.3), 5, 9, 1.0) for s in (-1, 1)])
    M.add('base', cilia(10, 6, 6, 14, 1.0, 'skin', V(0, 0, 1), seed=15, glow_tips=True))
    M.piece('head', 'base', (0, 15, 4))
    M.add('head', blob((5, 5, 6), (0, 0, 0), 'dark'))
    M.add('head', horn((0, 0, 3), (0, 0.08, 1), 44, 2.4, 11, bend=V(0, 5, 0)))
    M.add('head', [ring(3.4 + i * 0.5, 0.7, V(0, 0.8, 10 + i * 9), (0, 0, 1), 'glow', 16, 4) for i in range(4)])
    tiny(M, 'muzzle', 'head', (0, 5, 47))
    return M


def ty_siren():
    """Siren - T2 support: a haloed song-conch that rebuilds and mends in chorus."""
    M = Model('ty_siren'); M.piece('base'); M.add('base', [])
    M.add('base', conch(V(0, 18, 0), V(0, 1, 0), 2.6, 9.5, 3.0, 2.6, 6.2, rise=11, mat='skin', n=56, k=12))
    M.add('base', ring(12, 1.3, (0, 14, 0), (0, 1, 0), 'dark'))
    M.add('base', drum(V(0, 15, 10), (0, 0.1, 1), 5.0))
    M.add('base', [pinna(V(s * 12, 22, -2), V(s * .9, 0.3, 0), 6, 11, 1.2) for s in (-1, 1)])
    M.add('base', cilia(18, 10, 13, 24, 1.0, 'skin', None, seed=16, glow_tips=True))
    M.piece('halo', 'base', (0, 36, 0))
    M.add('halo', ring(14, 1.1, (0, 0, 0), (0, 1, 0), 'glow'))
    M.add('halo', [blob(1.6, V(14 * np.cos(a), 0, 14 * np.sin(a)), 'glow', lon=8, lat=6) for a in np.linspace(0, 6.28, 7)[:-1]])
    tiny(M, 'nano', 'base', (0, -5, 0))
    return M


def ty_organon():
    """Organon - T2 heavy: a flying organ; ranks of pipes, a cochlea heart, a tuning-fork halo."""
    M = Model('ty_organon'); M.piece('base'); M.add('base', [])
    rs = RS('orga')
    M.add('base', conch(V(0, 52, -6), V(0, 0.3, 1), 2.8, 32, 9, 10, 20, rise=34, mat='skin', n=70, k=14))
    M.add('base', blob((30, 24, 28), (0, 50, 0), 'skin'))
    M.add('base', ring(31, 3.4, (0, 50, 0), (0, 1, 0), 'dark', 40, 8))
    for i in range(15):                            # pipes in a fan, long ones in the middle
        x = (i - 7) * 5.6; L = 60 - abs(i - 7) * 6.5
        M.add('base', tube([V(x, 56, -14), V(x, 56 + L, -14)], [2.2, 2.2], 'dark' if i % 2 else 'skin', 10))
        M.add('base', ring(2.3, 0.5, V(x, 56 + L, -14), (0, 1, 0), 'glow', 12, 4))
    for s in (-1, 1):
        for y, w, h in ((60, 24, 30), (34, 17, 21)):
            M.add('base', pinna(V(s * 36, y, -6), V(s * .9, 0.1, -.3), w, h, 3.0))
    M.add('base', cilia(30, 24, 36, 52, 2.4, 'skin', None, seed=17, glow_tips=True))
    M.piece('halo', 'base', (0, 128, 0))
    M.add('halo', ring(50, 2.4, (0, 0, 0), (0, 1, 0), 'glow', 44, 8))
    M.add('halo', [fork(V(50 * np.cos(a), 0, 50 * np.sin(a)), V(np.cos(a) * .3, 1, np.sin(a) * .3), 18, 4.4, 1.5) for a in np.linspace(0, 6.28, 11)[:-1]])
    M.piece('head', 'base', (0, 52, 24))
    M.add('head', drum((0, 0, 6), (0, 0, 1), 17))
    M.add('head', blob((21, 8, 18), (0, 17, 2), 'dark'))
    M.add('head', horn((0, -2, 15), (0, 0, 1), 26, 5.0, 11.5))
    tiny(M, 'muzzle', 'head', (0, -2, 42))
    return M


# ============================================================================= MIASMA BLOOM (T2)
def mi_nostril2():
    """Great Nostril - the Nostril Pit grown into a tower of snouts that breathes out the swarm's elite."""
    M = Model('mi_nostril2'); M.piece('base'); M.add('base', [])
    rs = RS('nost2')
    M.add('base', ring(36, 8, (0, 12, 0), (0, 1, 0), 'skin', 36, 12))
    M.add('base', blob((31, 2.0, 31), (0, 11, 0), 'glow', lat=6))
    M.add('base', blob((40, 6, 40), (0, 2, 0), 'dark', lat=8))
    M.add('base', roots(8, 80, 22, 6, 'skin', 4))
    path = curve(V(0, 12, 0), V(0, 1, 0), 52, bend=V(0, 0, 4), n=8)
    M.add('base', tube(path, np.linspace(17, 10, 8), 'skin', 14))
    M.add('base', [ring(16.5 - 2.2 * i, 1.7, V(0, 22 + i * 10, 0), (0, 1, 0), 'dark', 22, 6) for i in range(4)])
    M.add('base', snout((0, 70, 0), (0, 0.5, 1), 17, 14, 20))
    M.add('base', [nostril(V(30 * np.cos(a), 17, 30 * np.sin(a)), V(np.cos(a), 0.4, np.sin(a)), 4.6) for a in np.linspace(0, 6.28, 9)[:-1]])
    M.add('base', [bladder(V(15 * np.cos(a), 28 + 10 * (i % 2), 15 * np.sin(a)), 4.0, 'glow', V(12 * np.cos(a), 40, 12 * np.sin(a))) for i, a in enumerate(np.linspace(0, 6.28, 8)[:-1])])
    M.piece('crown', 'base', (0, 14, 0))
    M.add('crown', petals(12, 37, 4, 30, 5.0, 'skin', 'dark', -0.25))
    tiny(M, 'pad', 'base', (0, 18, 0))
    return M


def mi_pollenwing():
    """Pollenwing - T2 raider: a quick winged bloom with a dusting spray of pollen."""
    M = Model('mi_pollenwing'); M.piece('base'); M.add('base', [])
    M.add('base', blob((5, 5, 10), (0, 8, -1), 'skin'))
    M.add('base', [blob((11, 0.6, 4.2), V(s * 9, 10, -2), 'glow' if k == 0 else 'skin', d=(s, 0.3, -0.3 + 0.4 * k), lon=10, lat=6) for s in (-1, 1) for k in (0, 1)])
    M.add('base', [bladder(V(0, 4, -8 - 3 * i), 1.8 - 0.3 * i, 'glow') for i in range(3)])
    M.add('base', [bristles(8, 3, V(0, 8, -9), (0, 0.1, -1), 5, 0.4, 'dark', 0.6, 4)])
    M.piece('head', 'base', (0, 8, 8))
    M.add('head', [nostril(V(s * 2.2, 0, 1.6), (0, 0, 1), 2.1) for s in (-1, 1)])
    M.add('head', bristles(8, 4.2, (0, -2, 3), (0, 0, 1), 4.5, 0.4, 'dark', 0.7, 5))
    tiny(M, 'muzzle', 'head', (0, 0, 5.5))
    return M


def mi_bloomguard():
    """Bloomguard - T2 assault: an armoured flower knight; petals for a shield, a snout-cannon and a pod battery."""
    M = Model('mi_bloomguard'); M.piece('base'); M.add('base', [])
    rs = RS('bloomg')
    M.add('base', blob((12, 14, 11), (0, 20, 0), 'skin'))
    M.add('base', [ring(12.2 * np.sqrt(max(0.1, 1 - (y / 15.0) ** 2)), 1.5, (0, 20 + y, 0), (0, 1, 0), 'dark', 22, 6) for y in np.linspace(-10, 10, 5)])
    M.add('base', petals(8, 12, 24, 14, 4.4, 'dark', 'skin', 1.0, centre=(0, 0, 3)))
    M.add('base', hang(9, 8, 10, 18, 2.4, 'skin', rs, 0.35, 1.2, 2))
    M.add('base', [bladder(V(s * 14, 30, -4 + 5 * i), 3.4, 'glow', V(s * 10, 26, -4 + 5 * i)) for s in (-1, 1) for i in range(2)])
    M.add('base', [tentacle(V(s * 11, 25, 0), V(s * 0.5, -0.6, 0.6), 17, 3.0, 'skin', bend=V(s * 3, -4, 8), waves=0.8, side=V(0, 1, 0), amp=1.5, r1=2.2) for s in (-1, 1)])
    M.piece('head', 'base', (0, 31, 6))
    M.add('head', snout((0, 0, 2), (0, 0, 1), 8.5, 7, 10))
    M.add('head', trunk((0, -3, 9), (0, 0, 1), 14, 3.0, 6.8, bend=V(0, -1, 0)))
    tiny(M, 'muzzle', 'head', (0, -4, 23))
    return M


def mi_fumigator():
    """Fumigator - T2 artillery: a swollen gas-tank with a trunk as long as a street and a bell the size of a house."""
    M = Model('mi_fumigator'); M.piece('base'); M.add('base', [])
    M.add('base', blob((9, 8, 12), (0, 11, 0), 'skin'))
    M.add('base', [ring(9.2, 1.0, (0, 11, z), (0, 0, 1), 'dark', 16, 5) for z in (-6, -1, 4)])
    M.add('base', [bladder(V(s * 10, 6 - 3 * i, -8 + 7 * i), 3.2, 'glow', V(s * 5, 10, -8 + 7 * i)) for s in (-1, 1) for i in range(3)])
    M.add('base', tentacle(V(0, 10, -11), V(0, 0.1, -1), 16, 2.6, 'skin', bend=V(0, 5, 0), waves=1, side=V(1, 0, 0), amp=2.4, r1=0.3))
    M.add('base', nostril(V(0, 14, -10.5), (0, 0.3, -1), 3.4))
    M.piece('head', 'base', (0, 16, 4))
    M.add('head', blob((5.5, 5.5, 6.5), (0, 0, 0), 'dark'))
    M.add('head', trunk((0, 0, 3), (0, 0.18, 1), 46, 3.4, 10.5, bend=V(0, 9, 0), waves=1.2, side=V(1, 0, 0), amp=2.6, flare=0.24))
    tiny(M, 'muzzle', 'head', (0, 11, 49))
    return M


def mi_perfumer():
    """Perfumer - T2 support: a bloom hung with censers, rebuilding and mending in a haze of scent."""
    M = Model('mi_perfumer'); M.piece('base'); M.add('base', [])
    rs = RS('perf')
    M.add('base', blob((12, 8, 12), (0, 26, 0), 'skin'))
    M.add('base', nostril(V(0, 26, 11), (0, 0, 1), 4.2))
    M.add('base', petals(10, 10, 31, 10, 3.0, 'skin', 'glow', 0.8))
    for i in range(3):
        a = 2 * np.pi * i / 3 + 0.5
        c = V(9 * np.cos(a), 8, 9 * np.sin(a))
        M.add('base', tube([V(8 * np.cos(a), 22, 8 * np.sin(a)), c + V(0, 5, 0)], [0.7, 0.7], 'dark', 6))
        M.add('base', blob(4.6, c, 'dark'))
        M.add('base', [ring(4.7, 0.5, c, ax, 'glow', 14, 4) for ax in ((0, 1, 0), (1, 0, 0))])
    M.add('base', [blob(rs.uniform(1.5, 2.8), V(rs.uniform(-8, 8), 2 + 6 * i, rs.uniform(-8, 8)), 'glow', lon=8, lat=6) for i in range(7)])
    M.add('base', hang(10, 10, 20, 18, 1.2, 'skin', rs, 0.4, 1.4, 1.2))
    tiny(M, 'nano', 'base', (0, -2, 0))
    return M


def mi_titanarum():
    """Titan Arum - T2 heavy: the corpse flower grown to a monster; a pleated spathe round a tall spadix of nostrils."""
    M = Model('mi_titanarum'); M.piece('base'); M.add('base', [])
    rs = RS('titan')
    M.add('base', blob((28, 22, 28), (0, 38, 0), 'skin'))
    M.add('base', ring(29, 3.2, (0, 38, 0), (0, 1, 0), 'dark', 40, 8))
    M.add('base', [blob((10, 38, 3), V(26 * np.cos(a), 62, 26 * np.sin(a)), 'skin' if i % 2 else 'dark', d=V(np.cos(a), 0.12, np.sin(a)), lon=12, lat=8) for i, a in enumerate(np.linspace(0, 6.28, 9)[:-1])])
    M.add('base', tube(curve(V(0, 40, 0), V(0, 1, 0), 78, bend=V(0, 0, 6), n=10), np.linspace(9, 4, 10), 'glow', 12))
    M.add('base', [nostril(V(7.5 * np.cos(a), 54 + 9 * k, 7.5 * np.sin(a)), V(np.cos(a), 0.1, np.sin(a)), 3.0) for k in range(3) for a in np.linspace(0, 6.28, 4)[:-1] + k]) 
    for i in range(16):
        a = 2 * np.pi * i / 16; r = rs.uniform(12, 34)
        M.add('base', bladder(V(r * np.cos(a), 22 - rs.uniform(0, 18), r * np.sin(a)), rs.uniform(3.4, 6.4), 'glow' if i % 2 else 'skin', V(r * .5 * np.cos(a), 30, r * .5 * np.sin(a))))
    M.add('base', hang(12, 22, 26, 46, 5.0, 'skin', rs, 0.55, 1.4, 4, seed=6))
    M.piece('petals', 'base', (0, 70, 0))
    M.add('petals', petals(14, 24, 0, 26, 6.0, 'skin', 'glow', 0.75))
    M.piece('head', 'base', (0, 40, 24))
    M.add('head', snout((0, 0, 4), (0, 0, 1), 19, 15, 19))
    M.add('head', trunk((0, -8, 19), (0, -0.05, 1), 38, 7.0, 15.5, bend=V(0, -3, 0), waves=1, side=V(0, 1, 0), amp=3.4))
    tiny(M, 'muzzle', 'head', (0, -11, 58))
    return M


TYMPAN_T2 = dict(ty_echo2=ty_echo2, ty_banshee=ty_banshee, ty_malleus=ty_malleus, ty_foghorn=ty_foghorn, ty_siren=ty_siren, ty_organon=ty_organon)
MIASMA_T2 = dict(mi_nostril2=mi_nostril2, mi_pollenwing=mi_pollenwing, mi_bloomguard=mi_bloomguard, mi_fumigator=mi_fumigator,
                 mi_perfumer=mi_perfumer, mi_titanarum=mi_titanarum)
