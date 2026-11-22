"""Voidborn TIER 2 models of the Haptic Grasp (the Hand, touch), new in 0.17.  Same piece conventions as designs_t2b.py."""
import numpy as np
from mesh import *
from designs_a import RS, V, tiny, crown, hang, roots
from designs_f import finger, hand, fist, put, suckers, arm, claws


def ha_palm2():
    """Great Palm - the Open Palm grown: two rings of fingers cupped round the pad and a tall thumb that stands guard."""
    M = Model('ha_palm2'); M.piece('base'); M.add('base', [])
    M.add('base', blob((42, 5, 42), (0, 4, 0), 'dark', lat=8))
    M.add('base', roots(9, 88, 24, 6.5, 'skin', 4))
    M.add('base', blob((35, 4.4, 35), (0, 9, 0), 'skin', lat=8))
    M.add('base', place(ellipsoid((20, 20, 3), 'eye', 24, 12), (0, 12.8, 0), (0, 1, 0), up=(0, 0, 1)))
    M.add('base', ring(37, 2.6, (0, 10, 0), (0, 1, 0), 'dark', 40, 8))
    M.add('base', claws(9, 31, 9, 56, 5.2, 0.7, 'skin', lo=False, rise=0.9))
    M.add('base', claws(9, 24, 10, 34, 3.8, 0.6, 'dark', lo=True, rise=0.8, phase=0.35))
    M.add('base', finger(V(-30, 10, 0), V(-0.5, 1, 0), V(1, 0.2, 0), 70, 6.0, (0.12, 0.2, 0.2), 'skin', False))
    M.piece('crown', 'base', (0, 36, 0))
    M.add('crown', [blob(2.4, V(24 * np.cos(a), 0, 24 * np.sin(a)), 'glow', lon=8, lat=6) for a in np.linspace(0, 2 * np.pi, 10)[:-1]])
    M.add('crown', ring(24, 0.8, (0, 0, 0), (0, 1, 0), 'glow', 32, 4))
    tiny(M, 'pad', 'base', (0, 16, 0))
    return M


def ha_strangler():
    """Strangler - T2 raider, and a bigger bomb: a glowing sac, six tentacles reaching forward to wrap, a hooked hand on each of two."""
    M = Model('ha_strangler'); M.piece('base'); M.add('base', [])
    M.add('base', blob((5.6, 4.6, 8.0), (0, 8, -1), 'skin'))
    M.add('base', blob((5.0, 4.0, 5.6), (0, 12, -1.4), 'glow'))
    M.add('base', ring(5.6, 0.7, (0, 11.4, -1.4), (0, 1, 0), 'dark', 16, 4))
    M.add('base', place(ellipsoid((3.0, 3.0, 1.4), 'eye', 12, 8), (0, 4.2, 2.0), (0, -1, 0), up=(0, 0, 1)))
    for k, x in enumerate((-4.6, -2.8, -1.0, 1.0, 2.8, 4.6)):
        a, p = arm(V(x, 8, 5), V(x * 0.1, 0.0, 1), 17, 1.8, 0.5, 3, bend=V(-x * 0.7, -5, 8), waves=1.2 + 0.25 * k, side=V(0, 1, 0), amp=1.3, n=10)
        M.add('base', a)
    for s in (-1, 1):
        M.add('base', put(hand(3.0, 3.2, 5.2, curl=0.9, spread=0.2, thumb_side=-s, lo=True), V(s * 6.4, 5.4, 5.6), V(s * 0.1, -0.2, 1), V(0, 1, 0)))
    for k in range(4):
        M.add('base', tentacle(V((k - 1.5) * 2.2, 8, -7), V((k - 1.5) * 0.3, 0.1, -1), 13, 1.4, 'skin', bend=V(0, -2, -3), waves=1.3 + 0.3 * k, side=V(1, 0, 0), amp=1.2, r1=0.2))
    return M


def ha_gauntlet():
    """Gauntlet - T2 assault: an armoured hand, plated in ink-dark chitin, a fist with spiked knuckles and a pair of open hands for a guard."""
    M = Model('ha_gauntlet'); M.piece('base'); M.add('base', [])
    rs = RS('gaunt')
    M.add('base', blob((12, 11, 12), (0, 20, 0), 'dark'))
    M.add('base', blob((11, 10, 11), (0, 21, 0), 'skin', lon=14, lat=8))
    M.add('base', [ring(12.4 * np.sqrt(max(0.05, 1 - ((y - 20) / 11) ** 2)), 1.2, (0, y, 0), (0, 1, 0), 'dark', 22, 5) for y in (13, 20, 27)])
    M.add('base', hang(11, 8, 12, 20, 2.4, 'skin', rs, 0.3, 1.2, 2.0))
    for s in (-1, 1):
        a, p = arm(V(s * 10, 22, 0), V(s, 0.2, 0.3), 12, 3.2, 2.6, 4, bend=V(s * 3, -2, 6), waves=0.8, side=V(0, 1, 0), amp=1.0)
        M.add('base', a)
        M.add('base', put(hand(6.0, 6.4, 9.0, curl=0.25, spread=0.35, thumb_side=-s, lo=True), p[-1] + V(s * 3, 0, 5), V(s * 0.2, 0.1, 1)))
    M.piece('head', 'base', (0, 26, 9))
    M.add('head', put(fist(9.5, 10, 14.5, mat='dark', wrist=4), (0, 0, 0), (0, 0, 1)))
    M.add('head', [spike(V(x, 7.4, 13.4), V(0, 0.45, 1), 5.2, 1.4, 'glow', 5) for x in (-6.4, -2.1, 2.1, 6.4)])
    M.add('head', crown(6, 8.0, 7, 5, 1.4, 'dark', 0.4, centre=(0, 0, -2)))
    tiny(M, 'muzzle', 'head', (0, 3, 18))
    return M


def ha_lasso():
    """Lasso - T2 artillery: a coil of tentacle wound round a body like rope, its free end thrown out with an open loop of a hand."""
    M = Model('ha_lasso'); M.piece('base'); M.add('base', [])
    rs = RS('lasso')
    M.add('base', blob((7.6, 7.2, 9.6), (0, 11, 0), 'skin'))
    M.add('base', hang(7, 5.6, 6, 15, 1.9, 'skin', rs, 0.3, 1.2, 1.4))
    t = np.linspace(0, 1, 46)
    coil = np.stack([11 * np.cos(2 * np.pi * 3.0 * t), 6 + 22 * t, 11 * np.sin(2 * np.pi * 3.0 * t) * 0.9 - 1], -1)
    rad = np.linspace(2.9, 2.5, 46)
    M.add('base', tube(coil, rad, 'skin', 9))
    M.add('base', suckers(coil, rad, 8, start=0.1, end=0.85))
    top = coil[-1]
    path = curve(top, V(0.1, 0.7, 1), 42, bend=V(0, -9, 22), waves=1.0, side=V(1, 0, 0), amp=4, n=14)
    r2 = np.linspace(2.6, 1.7, 14)
    M.add('base', tube(path, r2, 'skin', 8))
    M.add('base', suckers(path, r2, 5, start=0.2, end=0.8))
    tip = path[-1]
    M.piece('head', 'base', tuple(tip + V(0, 1, 2)))
    M.add('head', put(hand(7.2, 7.6, 12, curl=0.1, spread=0.32, thumb_side=-1, wrist=5), (0, 0, 0), V(0, 0.3, 1), (0, 1, 0)))
    tiny(M, 'muzzle', 'head', (0, 4, 10))
    return M


def ha_kneader():
    """Kneader - T2 support: three pairs of hands working a glowing mass between them; a fast builder and a mender."""
    M = Model('ha_kneader'); M.piece('base'); M.add('base', [])
    rs = RS('knead')
    M.add('base', blob((9.0, 7.0, 9.0), (0, 17, 0), 'skin'))
    M.add('base', blob(5.2, (0, 19, 0), 'glow'))
    for i in range(6):
        a = 2 * np.pi * i / 6 + 0.2; ca, sa = np.cos(a), np.sin(a)
        M.add('base', put(hand(4.4, 4.8, 9.5, curl=0.5, spread=0.2, thumb_side=-1, lo=True), V(10 * ca, 18, 10 * sa), V(ca * 0.55, 0.85, sa * 0.55), V(-ca, 0.15, -sa)))
    M.add('base', hang(11, 6.4, 12, 19, 1.9, 'skin', rs, 0.3, 1.3, 1.6))
    M.add('base', [ring(9.4, 0.9, (0, 12.5, 0), (0, 1, 0), 'dark', 18, 5), ring(11.5, 0.7, (0, 22, 0), (0, 1, 0), 'glow', 18, 4)])
    tiny(M, 'nano', 'base', (0, 4, 0))
    return M


def ha_hecaton():
    """Hecatoncheir - T2 heavy: the hundred-handed; a mountain of flesh with arms in tiers, a hand on every arm and a fist for a face."""
    M = Model('ha_hecaton'); M.piece('base'); M.add('base', [])
    rs = RS('hecat')
    M.add('base', blob((30, 26, 28), (0, 48, 0), 'skin'))
    M.add('base', ring(31, 3.4, (0, 40, 0), (0, 1, 0), 'dark', 40, 8))
    M.add('base', ring(27, 2.8, (0, 60, 0), (0, 1, 0), 'dark', 40, 8))
    M.add('base', hang(22, 24, 24, 54, 5.0, 'skin', rs, 0.35, 1.3, 4.5))
    for tier, (y, n, L, hw) in enumerate(((60, 7, 40, 8.5), (46, 8, 46, 9.0), (34, 6, 36, 8.0))):
        for i in range(n):
            a = 2 * np.pi * (i + 0.5 * (tier % 2)) / n + 0.1 * tier; ca, sa = np.cos(a), np.sin(a)
            if abs(sa) > 0.82 and sa > 0: continue            # keep the front clear for the face and the gun
            a_, p = arm(V(26 * ca, y, 24 * sa), V(ca, 0.35 - 0.3 * tier, sa), L, 5.6, 3.2, 4, bend=V(ca * 8, -6 + 3 * tier, sa * 6 + 4), waves=1, side=V(0, 1, 0), amp=2.4, n=9)
            M.add('base', a_)
            M.add('base', put(hand(hw, hw * 1.05, hw * 1.5, curl=0.2 + 0.25 * ((i + tier) % 3), spread=0.35, thumb_side=-1 if i % 2 else 1, lo=True),
                              p[-1] + V(ca * 3, 1, sa * 3), V(ca, 0.1, sa)))
    M.piece('crown', 'base', (0, 76, 0))
    M.add('crown', [finger(V(24 * np.cos(a), 0, 24 * np.sin(a)), V(np.cos(a) * 0.6, 0.8, np.sin(a) * 0.6), (0, 1, 0), 15, 2.4, (0.2, 0.4, 0.3), 'skin', True) for a in np.linspace(0, 2 * np.pi, 12)[:-1]])
    M.piece('head', 'base', (0, 50, 24))
    M.add('head', put(fist(16, 17, 24, wrist=6), (0, 0, 0), (0, 0, 1)))
    M.add('head', [spike(V(x, 12, 23), V(0, 0.5, 1), 8, 2.2, 'glow', 5) for x in (-11, -3.7, 3.7, 11)])
    M.add('head', ring(14, 1.6, (0, 0, -4), (0, 0, 1), 'glow', 26, 6))
    tiny(M, 'muzzle', 'head', (0, 4, 30))
    return M


HAPTIC_T2 = dict(ha_palm2=ha_palm2, ha_strangler=ha_strangler, ha_gauntlet=ha_gauntlet, ha_lasso=ha_lasso, ha_kneader=ha_kneader, ha_hecaton=ha_hecaton)
