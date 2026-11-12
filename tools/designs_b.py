"""MAW SWARM - chitinous, toothed, many-legged faction."""
import numpy as np
from mesh import *
from designs_a import RS, V, tiny, legs, crown, hang, roots

def maw(R, pos, d=(0, 0, 1), rings=((1.0, 14, 0.6), (0.68, 10, 0.45)), lip=0.28, throat=True, seed=0, mat='skin'):
    """a toothed circular mouth facing d. returns list of meshes"""
    out = [place(torus(R, R * lip, mat, 26, 8), pos, d)]
    dd = norm(d); pos = np.asarray(pos, float)
    if throat: out.append(blob((R * 0.95, R * 0.95, R * 0.45), pos - dd * R * 0.25, 'glow', d))
    for k, (f, n, ln) in enumerate(rings):
        out += teeth(R * f * 0.92, n, R * ln, pos + dd * (R * 0.05), d, None, 'dark' if k % 2 == 0 else 'glow' if False else 'dark', 0.55, 0.12, seed + k)
    return out

def mw_matriarch():
    M = Model('mw_matriarch'); M.piece('base'); M.add('base', [])
    rs = RS('matri')
    M.add('base', blob((13, 11, 19), (0, 26, -11), 'dark'))
    M.add('base', [ring(12.5 - abs(z) * 0.2, 1.4, (0, 26, z - 11), (0, 0, 1), 'skin', 18, 5) for z in (-12, -4, 4)])
    M.add('base', blob((10, 9, 10), (0, 24, 8), 'skin'))
    M.add('base', [spike(V(0, 36 - abs(z) * 0.08, z - 11), V(0, 1, -0.5), 11 - abs(z) * 0.2, 1.8, 'dark', 5) for z in (-14, -8, -2, 4)])
    M.add('base', [blob(3.6, V(s * 8, 36, -13 + k * 6), 'glow', lon=8, lat=6) for k, s in enumerate((-1, 1, -1, 1))])
    M.add('base', legs(3, V(8, 22, 8), 16, 20, 2.4, 'dark', rs, zspan=7))
    M.add('base', tentacle(V(0, 24, -26), V(0, 0.1, -1), 36, 4.2, 'skin', bend=V(0, 14, 0), waves=1, side=V(1, 0, 0), amp=3, r1=0.4))
    M.add('base', spike(V(0, 38, -52), V(0, 1, -0.6), 12, 2.2, 'glow', 6))
    M.piece('head', 'base', (0, 25, 18))
    M.add('head', maw(9.5, (0, 0, 8), (0, 0, 1), seed=2))
    M.add('head', [eye(2.6, V(s * 4.5, 9.5, 3), V(s * .3, .3, 1), lid=False) for s in (-1, 1)])
    M.add('head', [spike(V(s * 8, 6, 2), V(s * 0.6, 0.4, 1), 12, 1.6, 'dark', 5) for s in (-1, 1)])
    tiny(M, 'muzzle', 'head', (0, 0, 19))
    return M

def mw_weaver():
    M = Model('mw_weaver'); M.piece('base'); M.add('base', [])
    rs = RS('weav')
    M.add('base', blob((7, 6.5, 9), (0, 12, -6), 'dark'))
    M.add('base', blob((5, 4.5, 5.5), (0, 11, 4), 'skin'))
    M.add('base', eye(1.9, (2.2, 13, 8.5), (0.3, 0.1, 1), lid=False)); M.add('base', eye(1.9, (-2.2, 13, 8.5), (-0.3, 0.1, 1), lid=False))
    M.add('base', [spike(V(s * 1.6, 9, 9), V(s * 0.3, -0.4, 1), 7, 1.0, 'dark', 5) for s in (-1, 1)])
    M.add('base', legs(4, V(4, 11, 2), 11, 11, 1.1, 'dark', rs, zspan=3.6))
    M.add('base', blob((2.4, 2.4, 2.4), (0, 8, -14), 'glow', lon=8, lat=6))
    tiny(M, 'nano', 'base', (0, 9, 11))
    return M

def mw_skitter():
    M = Model('mw_skitter'); M.piece('base'); M.add('base', [])
    rs = RS('skit')
    M.add('base', blob((3.6, 3.0, 6.5), (0, 6, -1), 'dark'))
    M.add('base', legs(3, V(2.4, 5, 0), 6, 5, 0.6, 'dark', rs, zspan=2.4))
    for s in (-1, 1):
        M.add('base', blob((6.5, 0.25, 2.8), (s * 7, 8.5, -2), 'glow', lon=10, lat=6))
        M.add('base', tentacle(V(s * 1, 8, 5), V(s * 0.3, 0.8, 1), 9, 0.5, 'dark', bend=V(s * 2, 0, 4), waves=0.5, side=V(0, 1, 0), amp=0.5, r1=0.1))
    M.piece('head', 'base', (0, 6.5, 5))
    M.add('head', eye(3.0, (0, 0, 0.5), (0, 0, 1), lid=False))
    M.add('head', [spike(V(s * 2, -1.5, 1), V(s * 0.3, -0.2, 1), 4.5, 0.7, 'dark', 4) for s in (-1, 1)])
    tiny(M, 'muzzle', 'head', (0, 0, 4))
    return M

def mw_gnasher():
    M = Model('mw_gnasher'); M.piece('base'); M.add('base', [])
    rs = RS('gnash')
    M.add('base', blob((4.5, 4.5, 9), (0, 8, -7), 'skin'))
    M.add('base', [ring(4.6 - k * 0.3, 0.7, (0, 8, -3 - k * 4), (0, 0, 1), 'dark', 12, 4) for k in range(3)])
    for s in (-1, 1):
        M.add('base', blob((11, 0.35, 5), (s * 10, 11, -5), 'dark')); M.add('base', blob((8, 0.3, 3.2), (s * 8, 11, -11), 'glow', lon=10, lat=6))
    M.add('base', tentacle(V(0, 8, -15), V(0, 0, -1), 14, 2.0, 'skin', bend=V(0, -2, 0), waves=1, side=V(0, 1, 0), amp=2, r1=0.2))
    M.add('base', crown(4, 2.5, 12, 4, 1.0, 'dark', 0.3, centre=V(0, 0, -6)))
    M.piece('head', 'base', (0, 8, 2))
    M.add('head', maw(6.0, (0, 0, 3), (0, 0, 1), rings=((1.0, 12, 0.55), (0.62, 8, 0.4)), seed=4))
    tiny(M, 'muzzle', 'head', (0, 0, 9))
    return M

def mw_ravager():
    M = Model('mw_ravager'); M.piece('base'); M.add('base', [])
    rs = RS('rav')
    M.add('base', blob((11, 8, 14), (0, 14, -3), 'dark'))
    M.add('base', [ring(10.5 - abs(z) * 0.3, 1.2, (0, 14, z - 3), (0, 0, 1), 'skin', 18, 5) for z in (-8, -2, 4)])
    M.add('base', [spike(V(s * 6, 20, z), V(s * 0.6, 1, -0.3), 7, 1.6, 'glow', 5) for s in (-1, 1) for z in (-8, -1, 6)])
    M.add('base', legs(3, V(8, 11, 0), 14, 12, 2.0, 'dark', rs, zspan=7))
    M.add('base', tentacle(V(0, 13, -16), V(0, 0.1, -1), 20, 3.0, 'skin', bend=V(0, 10, 0), waves=0.7, side=V(1, 0, 0), amp=2, r1=0.5))
    M.add('base', spike(V(0, 22, -33), V(0, 1, -0.5), 9, 2, 'glow', 5))
    M.piece('head', 'base', (0, 14, 12))
    M.add('head', blob((6, 5, 6.5), (0, 0, 3), 'skin'))
    for s in (-1, 1):
        path = curve(V(s * 3.5, -1, 6), V(s * 0.5, -0.1, 1), 14, bend=V(-s * 9, 0, 3), droop=V(0, -2, 0), n=8)
        M.add('head', tube(path, np.linspace(2.6, 0.2, 8), 'dark', 7))
    M.add('head', [eye(2.0, V(x, 3.5, 8), V(x * .1, .3, 1), lid=False) for x in (-2.5, 0, 2.5)])
    tiny(M, 'muzzle', 'head', (0, 0, 10))
    return M

def mw_spitter():
    M = Model('mw_spitter'); M.piece('base'); M.add('base', [])
    rs = RS('spit')
    M.add('base', blob((13, 11, 15), (0, 16, -5), 'skin'))
    M.add('base', [blob(3.2, V(13 * np.cos(a), 14 + 8 * np.sin(a * 2), -5 + 13 * np.sin(a)) * V(0.8, 1, 0.8) + V(0, 4, 0), 'glow', lon=8, lat=6) for a in np.linspace(0, 6.28, 8)[:-1]])
    M.add('base', [ring(12.4 - k, 1.3, (0, 16, -5 + k * 5 - 8), (0, 0, 1), 'dark', 16, 4) for k in range(4)])
    M.add('base', legs(3, V(8, 10, -2), 11, 7, 1.8, 'dark', rs, zspan=6))
    M.add('base', tentacle(V(0, 14, -18), V(0, 0, -1), 14, 3.4, 'skin', bend=V(0, 6, 0), waves=1, side=V(1, 0, 0), amp=2, r1=0.5))
    M.piece('head', 'base', (0, 18, 10))
    path = curve(V(0, 0, 0), V(0, 0.15, 1), 22, bend=V(0, 5, 0), n=8)
    M.add('head', tube(path, np.linspace(5, 2.8, 8), 'skin', 8))
    M.add('head', maw(4.8, V(0, 5, 22), norm(V(0, 0.2, 1)), rings=((1.0, 9, 0.6),), seed=5))
    M.add('head', [eye(1.6, V(s * 4, 3, 4), V(s * .5, .3, 1), lid=False) for s in (-1, 1)])
    tiny(M, 'muzzle', 'head', (0, 5, 27))
    return M

def mw_nurse():
    M = Model('mw_nurse'); M.piece('base'); M.add('base', [])
    rs = RS('nurse')
    M.add('base', blob((9, 8, 11), (0, 16, 0), 'skin'))
    M.add('base', blob((6, 7, 6), (0, 8, -1), 'glow'))
    M.add('base', [ring(9 - k, 1.0, (0, 17, -6 + k * 5), (0, 0, 1), 'dark', 16, 4) for k in range(4)])
    M.add('base', hang(10, 6, 9, 13, 1.1, 'skin', rs, 0.5, 1.4, 1.2))
    M.add('base', eye(4.0, (0, 18, 9), (0, 0.1, 1)))
    for s in (-1, 1): M.add('base', blob((6, 0.35, 3), (s * 10, 20, -3), 'glow', lon=10, lat=6))
    tiny(M, 'nano', 'base', (0, 2, 0))
    return M

def mw_leviathan():
    M = Model('mw_leviathan'); M.piece('base'); M.add('base', [])
    rs = RS('levi')
    M.add('base', blob((24, 22, 30), (0, 36, -30), 'dark'))
    for k, (z, r) in enumerate([(-62, 18), (-90, 14), (-114, 10)]):
        M.add('base', blob((r, r * 0.9, 18), (0, 34 + k * 3, z), 'skin' if k % 2 == 0 else 'dark'))
    M.add('base', tentacle(V(0, 40, -124), V(0, 0.2, -1), 40, 8, 'skin', bend=V(0, 18, 0), waves=1, side=V(1, 0, 0), amp=5, r1=0.5))
    M.add('base', [spike(V(0, 36 + 22 - abs(z + 30) * 0.12, z), V(0, 1, -0.5), 16 - abs(z + 30) * 0.06, 3.2, 'glow', 5) for z in (-8, -24, -40, -56, -74, -92)])
    M.add('base', [blob((16, 0.8, 9), V(s * 24, 28, -34), 'glow', d=(s, 0, 0.3), lon=12, lat=6) for s in (-1, 1)])
    M.add('base', legs(3, V(18, 28, -30), 22, 16, 3.4, 'skin', rs, zspan=12))
    M.piece('head', 'base', (0, 38, 4))
    M.add('head', maw(24, (0, 0, 8), (0, 0, 1), rings=((1.0, 22, 0.55), (0.74, 16, 0.5), (0.48, 11, 0.4)), seed=9, lip=0.24))
    M.add('head', hang(8, 26, 10, 30, 4.0, 'skin', rs, 0.7, 1.2, 4, centre=V(0, 0, 0)) if False else [
        tentacle(V(26 * np.cos(a), 26 * np.sin(a), 6), V(np.cos(a) * 0.4, np.sin(a) * 0.4, 1), 30, 4.0, 'skin', waves=1.2, side=V(-np.sin(a), np.cos(a), 0), amp=4, r1=0.5) for a in np.linspace(0, 6.28, 9)[:-1]])
    M.add('head', [eye(3.6, V(s * 14, 28, 2), V(s * .3, .5, 1), lid=False) for s in (-1, 1)])
    tiny(M, 'muzzle', 'head', (0, 0, 30))
    return M

def mw_hive():
    M = Model('mw_hive'); M.piece('base'); M.add('base', [])
    rs = RS('hive')
    M.add('base', blob((40, 7, 40), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(9, 96, 24, 6, 'skin', 21, 4))
    M.add('base', blob((28, 18, 28), (0, 18, -4), 'skin'))
    M.add('base', [blob(rs.uniform(7, 11), V(30 * np.cos(a), 11, 26 * np.sin(a) * 0.9 - 6), 'glow' if i % 2 else 'skin') for i, a in enumerate(np.linspace(0, 6.28, 8)[:-1] + 1.7)])
    M.add('base', maw(15, (0, 17, 24), (0, 0.05, 1), rings=((1.0, 16, 0.5), (0.7, 11, 0.4)), seed=11))
    M.add('base', [spike(V(18 * np.cos(a), 26, 14 * np.sin(a) - 8), V(np.cos(a) * 0.4, 1, np.sin(a) * 0.4 - .3), 15, 2.6, 'dark', 5) for a in np.linspace(0, 6.28, 11)[:-1]])
    M.piece('crown', 'base', (0, 36, -4))
    M.add('crown', blob(6, (0, 2, 0), 'glow'))
    tiny(M, 'pad', 'base', (0, 12, 30))
    return M

def mw_extractor():
    M = Model('mw_extractor'); M.piece('base'); M.add('base', [])
    rs = RS('extr')
    M.add('base', blob((9, 5, 9), (0, 4, 0), 'dark', lat=8))
    M.add('base', roots(5, 28, 11, 2.4, 'skin', 22, 3))
    M.add('base', spike(V(0, 3, 0), V(0, -1, 0), 10, 3.6, 'dark', 7))
    M.add('base', blob((5.5, 7, 5.5), (0, 11, 0), 'glow'))
    M.add('base', eye(2.8, (0, 18, 0), (0, 1, 0.2), lid=False))
    M.piece('spin', 'base', (0, 11, 0))
    M.add('spin', [tube(curve(V(5 * np.cos(a), -2, 5 * np.sin(a)), V(np.cos(a), 1, np.sin(a)), 11, bend=V(-np.cos(a) * 4, 3, -np.sin(a) * 4), n=7), np.linspace(1.9, 0.2, 7), 'dark', 6) for a in np.linspace(0, 6.28, 6)[:-1]])
    return M

def mw_sunbloom():
    M = Model('mw_sunbloom'); M.piece('base'); M.add('base', [])
    rs = RS('sunb')
    M.add('base', blob((11, 4.5, 11), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(6, 44, 14, 3, 'skin', 23, 3))
    M.add('base', blob((6, 8, 6), (0, 10, 0), 'skin'))
    M.piece('fronds', 'base', (0, 14, 0))
    for i in range(12):
        a = 2 * np.pi * i / 12
        d = V(np.cos(a) * 0.9, 1.0, np.sin(a) * 0.9)
        p = V(np.cos(a) * 3.5, 0, np.sin(a) * 3.5)
        M.add('fronds', tentacle(p, d, 22, 1.7, 'skin', bend=V(np.cos(a) * 9, -4, np.sin(a) * 9), waves=1, side=V(-np.sin(a), 0, np.cos(a)), amp=1.5, r1=0.5))
        M.add('fronds', blob(1.7, p + d * 22 * 0.55 + V(np.cos(a) * 8.5, -2.5, np.sin(a) * 8.5), 'glow', lon=8, lat=6))
    M.add('base', eye(3.4, (0, 17, 0), (0, 1, 0.2), lid=False))
    return M

def mw_core():
    M = Model('mw_core'); M.piece('base'); M.add('base', [])
    rs = RS('core')
    M.add('base', blob((38, 7, 38), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(10, 100, 24, 5.5, 'skin', 24, 4))
    M.add('base', blob((16, 23, 16), (0, 32, 0), 'glow'))
    M.add('base', [eye(3.0, V(0, 32, 0) + norm(V(np.cos(a), 0.3 * np.sin(3 * a), np.sin(a))) * 16, V(np.cos(a), 0, np.sin(a)), lid=False) for a in np.linspace(0, 6.28, 4)[:-1] + 0.5])
    M.piece('ribs', 'base', (0, 32, 0))
    for a in np.linspace(0, 6.28, 9)[:-1]:
        path = np.array([V(np.cos(a) * r, y, np.sin(a) * r) for y, r in [(-26, 12), (-16, 24), (0, 28), (16, 24), (28, 8), (32, 2)]])
        M.add('ribs', tube(path, [3, 2.6, 2.2, 2.2, 1.6, 1.0], 'dark', 6))
    return M

def mw_cyst():
    M = Model('mw_cyst'); M.piece('base'); M.add('base', [])
    rs = RS('cyst')
    M.add('base', blob((22, 5, 22), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(7, 58, 18, 4, 'skin', 25, 3))
    M.add('base', blob(15, (0, 20, 0), 'skin'))
    for a, r, h in [(0.3, 8, 10), (1.9, 9, 12), (3.4, 7, 9), (4.9, 8, 11)]:
        M.add('base', blob(r, V(17 * np.cos(a), h, 17 * np.sin(a)), 'skin'))
        M.add('base', blob(r * 0.4, V(17 * np.cos(a), h, 17 * np.sin(a)) + V(np.cos(a), 0.7, np.sin(a)) * r * 0.85, 'glow', lon=8, lat=6))
    M.add('base', [ring(12 * np.sqrt(max(0.1, 1 - ((y - 20) / 15) ** 2)) + 1, 0.9, (0, y, 0), (0, 1, 0), 'glow', 20, 5) for y in (12, 20, 28)])
    M.add('base', eye(3.6, (0, 33, 0), (0, 1, 0.3), lid=False))
    return M

def mw_sensor():
    M = Model('mw_sensor'); M.piece('base'); M.add('base', [])
    M.add('base', blob((9, 4, 9), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(5, 26, 11, 2.4, 'skin', 26, 3))
    stalk = curve(V(0, 3, 0), V(0, 1, 0), 50, bend=V(-4, 0, 7), waves=1.5, side=V(1, 0, 0), amp=2.2, n=12)
    M.add('base', tube(stalk, np.linspace(3.4, 1.8, 12), 'dark', 7))
    M.add('base', [blob((2.6, 2.6, 2.6), stalk[i] + V(2, 0, 0), 'skin', lon=8, lat=6) for i in (3, 6, 9)])
    M.piece('head', 'base', tuple(stalk[-1] + V(0, 3, 0)))
    M.add('head', eye(3.8, (0, 0, 0.5), (0, 0, 1), lid=False))
    M.piece('dish', 'head', (0, 0, 0))
    M.add('dish', blob((13, 3.2, 13), (0, 0, 0), 'glow', lat=6) if False else
          [ring(11, 1.2, (0, 0, 0), (0, 1, 0), 'skin', 24, 6), blob((11, 0.5, 11), (0, -0.4, 0), 'glow', lat=4)])
    M.add('dish', [spike(V(11 * np.cos(a), 0, 11 * np.sin(a)), V(np.cos(a) * .2, 1, np.sin(a) * .2), 9, 1.1, 'dark', 5) for a in np.linspace(0, 6.28, 7)[:-1]])
    return M

def mw_spine():
    M = Model('mw_spine'); M.piece('base'); M.add('base', [])
    M.add('base', blob((10, 4.5, 10), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(5, 30, 12, 3, 'skin', 27, 3))
    stalk = curve(V(0, 3, 0), V(0, 1, 0), 22, bend=V(0, 0, 4), n=6)
    M.add('base', tube(stalk, np.linspace(4.6, 3.2, 6), 'skin', 8))
    M.add('base', [spike(V(3.5 * np.cos(a), 6, 3.5 * np.sin(a)), V(np.cos(a), 0.9, np.sin(a)), 7, 1.1, 'dark', 5) for a in np.linspace(0, 6.28, 7)[:-1]])
    M.piece('head', 'base', tuple(stalk[-1] + V(0, 4, 3)))
    M.add('head', blob((6, 5.5, 6.5), (0, 0, 0), 'skin'))
    M.add('head', maw(4.8, (0, 0, 5), (0, 0, 1), rings=((1.0, 9, 0.6),), seed=14))
    M.add('head', eye(1.7, (0, 5.5, 1), (0, 0.5, 1), lid=False))
    tiny(M, 'muzzle', 'head', (0, 0, 9))
    return M

def mw_bastion():
    M = Model('mw_bastion'); M.piece('base'); M.add('base', [])
    rs = RS('bast')
    M.add('base', blob((28, 6, 28), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(8, 80, 22, 5.5, 'skin', 28, 4))
    M.add('base', blob((18, 15, 18), (0, 16, 0), 'skin'))
    M.add('base', [blob((7, 12, 3), V(20 * np.cos(a), 18, 20 * np.sin(a)), 'dark', d=V(np.cos(a), 0, np.sin(a)), lon=10, lat=6) for a in np.linspace(0, 6.28, 7)[:-1]])
    M.add('base', [spike(V(12 * np.cos(a), 28, 12 * np.sin(a)), V(np.cos(a) * 0.5, 1, np.sin(a) * 0.5), 14, 2.6, 'dark', 5) for a in np.linspace(0, 6.28, 9)[:-1] + 0.2])
    M.piece('head', 'base', (0, 30, 0))
    M.add('head', blob((14, 11, 15), (0, 2, 0), 'skin'))
    M.add('head', maw(11, (0, 0, 13), (0, 0, 1), rings=((1.0, 15, 0.55), (0.66, 10, 0.45)), seed=16))
    M.add('head', [tube(curve(V(s * 8, 8, 0), V(s * 0.2, 1, 0.5), 15, bend=V(0, 0, 8), n=6), np.linspace(2.8, 1.8, 6), 'dark', 7) for s in (-1, 1)])
    M.add('head', [eye(3.0, V(s * 6, 11, 8), V(s * .2, .3, 1), lid=False) for s in (-1, 1)])
    tiny(M, 'muzzle', 'head', (0, 0, 22))
    return M

MAW = dict(mw_matriarch=mw_matriarch, mw_weaver=mw_weaver, mw_skitter=mw_skitter, mw_gnasher=mw_gnasher, mw_ravager=mw_ravager,
           mw_spitter=mw_spitter, mw_nurse=mw_nurse, mw_leviathan=mw_leviathan, mw_hive=mw_hive, mw_extractor=mw_extractor,
           mw_sunbloom=mw_sunbloom, mw_core=mw_core, mw_cyst=mw_cyst, mw_sensor=mw_sensor, mw_spine=mw_spine, mw_bastion=mw_bastion)
