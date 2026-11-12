"""Voidborn unit/structure models - shared helpers + CHOIR OF THE EYE (cyclopean faction)."""
import numpy as np
from mesh import *

def RS(name): return np.random.RandomState(abs(hash(name)) % (2**31) if False else sum(ord(c) * (i + 1) for i, c in enumerate(name)))
V = lambda *a: np.array(a, float)

def tiny(M, name, parent, off):
    M.piece(name, parent, off); M.add(name, blob(0.6, (0, 0, 0), 'glow', lon=5, lat=3))

def legs(n, anchor, span, drop, r0, mat='dark', rs=None, spread=1.0, ymid=0.5, back=0.0, zspan=None):
    """n two-segment legs on both sides (n per side)."""
    out = []
    for side in (-1, 1):
        for i in range(n):
            z = (i - (n - 1) / 2) * (zspan if zspan else span * 0.8 / max(n - 1, 1))
            a = V(anchor[0] * side, anchor[1], anchor[2] + z)
            knee = a + V(side * span * 0.7, span * 0.45 * ymid * 2, z * 0.4 * spread)
            foot = a + V(side * span * 1.05, -drop, z * 0.9 * spread + back)
            path = np.array([a, a * 0.5 + knee * 0.5 + V(0, 1, 0), knee, knee * 0.5 + foot * 0.5, foot])
            out.append(tube(path, np.linspace(r0, r0 * 0.3, 5), mat, 6))
    return out

def crown(n, R, y, length, r0, mat='dark', tilt=0.5, seed=0, d0=(0, 0, 1), centre=(0, 0, 0)):
    out = []
    for i in range(n):
        a = 2 * np.pi * i / n
        p = V(centre[0] + R * np.cos(a), centre[1] + y, centre[2] + R * np.sin(a))
        d = V(np.cos(a) * tilt, 1.0, np.sin(a) * tilt)
        out.append(spike(p, d, length, r0, mat, 5))
    return out

def hang(n, R, y, length, r0, mat='skin', rs=None, out_k=0.35, waves=1.3, amp=2.0, centre=(0, 0, 0), seed=1):
    rs = rs or np.random.RandomState(seed); out = []
    for i in range(n):
        a = 2 * np.pi * (i + rs.uniform(-.15, .15)) / n
        p = V(centre[0] + R * np.cos(a), centre[1] + y, centre[2] + R * np.sin(a))
        d = V(np.cos(a) * out_k, -1.0, np.sin(a) * out_k)
        out.append(tentacle(p, d, length * rs.uniform(0.8, 1.15), r0, mat, waves=waves + rs.uniform(-.4, .4),
                            side=V(-np.sin(a), 0, np.cos(a)), amp=amp, r1=0.15))
    return out

# =========================================================================================
def ch_hierophant():
    M = Model('ch_hierophant'); M.piece('base'); M.add('base', [])
    rs = RS('hier')
    M.add('base', blob((13, 19, 13), (0, 24, 0), 'skin'))
    M.add('base', ring(14.5, 2.3, (0, 33, 0), (0, 1, 0), 'dark'))
    M.add('base', ring(11.5, 1.5, (0, 14, 0), (0, 1, 0), 'dark'))
    M.add('base', hang(10, 9.5, 12, 26, 2.8, 'skin', rs, 0.30, 1.3, 2.5))
    for s in (-1, 1):   # little arms ending in glowing orbs
        M.add('base', tentacle(V(s * 12, 28, 2), V(s * 1, -0.2, 0.7), 20, 2.2, 'skin', bend=V(s * 4, -8, 8), waves=1, side=V(0, 1, 0), amp=1.5, r1=1.0))
        M.add('base', blob(3.2, V(s * 22, 20, 16), 'glow'))
        M.add('base', crown(5, 4.0, 1, 5, 1.0, 'dark', 0.8, centre=V(s * 22, 20, 16)))
    M.piece('halo', 'base', (0, 50, 0))
    M.add('halo', ring(24, 1.7, (0, 0, 0), (0, 1, 0), 'glow'))
    M.add('halo', ring(19, 1.2, (0, 2, 0), (1, 1, 0), 'trim' if False else 'glow'))
    M.add('halo', [spike(V(24 * np.cos(a), 0, 24 * np.sin(a)), V(np.cos(a), 0.2, np.sin(a)), 7, 1.4, 'dark', 5) for a in np.linspace(0, 6.28, 9)[:-1]])
    M.piece('head', 'base', (0, 36, 4))
    M.add('head', eye(11, (0, 0, 6), (0, 0, 1)))
    M.add('head', blob((12.5, 6, 11), (0, 10.5, 3), 'dark'))
    M.add('head', crown(7, 9, 9, 13, 1.7, 'dark', 0.45, centre=(0, 0, 2)))
    tiny(M, 'muzzle', 'head', (0, 0, 19))
    return M

def ch_seer():
    M = Model('ch_seer'); M.piece('base'); M.add('base', [])
    M.add('base', eye(8, (0, 13, 0), (0, 0, 1)))
    M.add('base', ring(11, 0.9, (0, 13, 0), (0, 0.4, 1), 'dark'))
    M.add('base', crown(3, 3, 17, 7, 1.2, 'dark', 0.6, centre=(0, 0, -2)))
    for i, a in enumerate(np.linspace(0, 2 * np.pi, 5)[:-1] + 0.4):
        p = V(5 * np.cos(a), 8, 5 * np.sin(a) * 0.8)
        M.add('base', tentacle(p, V(np.cos(a) * .4, -0.7, 0.9), 14, 1.3, 'skin', bend=V(0, -2, 7), waves=1, side=V(1, 0, 0), amp=1.2, r1=0.5))
        M.add('base', blob(1.2, p + V(np.cos(a) * 4, -9, 12), 'glow', lon=8, lat=6))
    tiny(M, 'nano', 'base', (0, 2, 12))
    return M

def ch_gazer():
    M = Model('ch_gazer'); M.piece('base'); M.add('base', [])
    M.add('base', blob((3.5, 3.5, 5), (0, 7, -3), 'skin'))
    for s in (-1, 1):
        M.add('base', blob((11, 0.5, 5.5), (s * 8.5, 7.5, -3), 'dark', s=None))
        M.add('base', blob((2, 0.7, 4), (s * 14, 7.5, -3), 'glow', lon=8, lat=6))
    M.add('base', tentacle(V(0, 7, -7), V(0, 0, -1), 22, 1.8, 'skin', bend=V(0, 4, 0), waves=1.5, side=V(0, 1, 0), amp=2, r1=0.2))
    M.add('base', blob((0.5, 3, 2.5), (0, 11, -9), 'dark'))
    M.piece('head', 'base', (0, 7, 3))
    M.add('head', eye(5.2, (0, 0, 0), (0, 0, 1)))
    tiny(M, 'muzzle', 'head', (0, 0, 6))
    return M

def ch_lashling():
    M = Model('ch_lashling'); M.piece('base'); M.add('base', [])
    M.add('base', blob((3.5, 3.5, 9), (0, 5, 0), 'skin'))
    M.add('base', [ring(3.6, 0.5, (0, 5, z), (0, 0, 1), 'dark', 12, 5) for z in (-4, 0, 3)])
    rs = RS('lash')
    for i in range(5):
        a = 2 * np.pi * i / 5
        M.add('base', tentacle(V(2 * np.cos(a), 5 + 2 * np.sin(a), -6), V(np.cos(a) * 0.3, np.sin(a) * 0.3, -1), 16, 1.1, 'skin', waves=1.5 + i * .2, side=V(-np.sin(a), np.cos(a), 0), amp=1.5, r1=0.1))
    M.add('base', [blob((0.4, 3.5, 3), (s * 1.2, 8.5, -5), 'glow', lon=6, lat=4) for s in (-1, 1)])
    M.piece('head', 'base', (0, 5, 8))
    M.add('head', eye(3.6, (0, 0, 0), (0, 0, 1), lid=False))
    tiny(M, 'muzzle', 'head', (0, 0, 4))
    return M

def ch_hoplite():
    M = Model('ch_hoplite'); M.piece('base'); M.add('base', [])
    rs = RS('hop')
    M.add('base', blob((9.5, 12, 8.5), (0, 18, 0), 'skin'))
    M.add('base', ring(10, 1.8, (0, 12, 0), (0, 1, 0), 'dark'))
    M.add('base', hang(8, 7, 9, 17, 2.4, 'skin', rs, 0.35, 1.2, 2))
    for s in (-1, 1):
        M.add('base', blob((4.5, 3.2, 4.5), (s * 11, 27, 0), 'dark'))
        M.add('base', crown(4, 2.5, 3, 5, 1.0, 'dark', 0.7, centre=V(s * 11, 27, 0)))
        M.add('base', tentacle(V(s * 11, 25, 0), V(s * 0.5, -0.6, 0.6), 17, 3.0, 'skin', bend=V(s * 3, -4, 8), waves=0.8, side=V(0, 1, 0), amp=1.5, r1=2.2))
        club = V(s * 16, 12, 14)
        M.add('base', blob((3.8, 3.8, 7), club, 'dark', d=(0, 0.3, 1)))
        M.add('base', [spike(club + V(np.cos(a) * 3, np.sin(a) * 3, 2), V(np.cos(a), np.sin(a), 0.2), 3.2, 0.9, 'glow', 4) for a in np.linspace(0, 6.28, 7)[:-1]])
    M.piece('head', 'base', (0, 30, 3))
    M.add('head', eye(8, (0, 0, 3), (0, 0, 1)))
    M.add('head', blob((9, 5, 8.5), (0, 7.5, 1.5), 'dark'))
    M.add('head', crown(3, 6.5, 8, 8, 1.4, 'dark', 0.6, centre=(0, 0, 0)))
    tiny(M, 'muzzle', 'head', (0, 0, 12))
    return M

def ch_basilisk():
    M = Model('ch_basilisk'); M.piece('base'); M.add('base', [])
    M.add('base', blob((8, 6.5, 11), (0, 10, 0), 'skin'))
    M.add('base', [ring(8, 1.0, (0, 10, z), (0, 0, 1), 'dark', 16, 5) for z in (-5, 0, 5)])
    neck = curve(V(0, 12, 6), V(0, 1, 0.3), 30, bend=V(0, 0, 10), droop=V(0, 0, 0), waves=1, side=V(1, 0, 0), amp=3, n=12)
    M.add('base', tube(neck, np.linspace(4.3, 2.4, 12), 'skin', 8))
    M.add('base', tentacle(V(0, 9, -9), V(0, 0.1, -1), 26, 3.2, 'skin', bend=V(0, 8, 0), waves=1, side=V(1, 0, 0), amp=3, r1=0.3))
    M.add('base', hang(6, 6, 6, 14, 1.4, 'skin', None, 0.7, 1.0, 1.5, seed=3))
    hp = neck[-1]
    M.piece('head', 'base', tuple(hp + V(0, 1, 3)))
    M.add('head', eye(6.5, (0, 0, 0), (0, 0, 1)))
    M.add('head', crown(7, 5.5, 0.5, 8, 1.0, 'dark', 0.9, centre=(0, 0, -1.5)))
    M.add('head', spike(V(0, 0, 4), V(0, 0, 1), 11, 1.0, 'glow', 5))
    tiny(M, 'muzzle', 'head', (0, 0, 15))
    return M

def ch_weeper():
    M = Model('ch_weeper'); M.piece('base'); M.add('base', [])
    rs = RS('weep')
    M.add('base', blob((11, 7.5, 11), (0, 16, 0), 'skin', lat=12))
    M.add('base', ring(10.5, 1.3, (0, 12, 0), (0, 1, 0), 'dark'))
    M.add('base', eye(4.2, (0, 12, 8), (0, 0, 1)))
    M.add('base', hang(12, 8.5, 12, 22, 1.2, 'skin', rs, 0.4, 1.5, 1.2))
    M.add('base', [blob(1.1, V(8.5 * np.cos(a) * 1.55, -8, 8.5 * np.sin(a) * 1.55) + V(0, 14, 0), 'glow', lon=6, lat=4) for a in np.linspace(0, 6.28, 7)[:-1]] if False else [])
    M.add('base', tentacle(V(0, 10, 0), V(0, -1, 0.1), 17, 2.0, 'glow', waves=1.2, side=V(1, 0, 0), amp=1, r1=0.5))
    tiny(M, 'nano', 'base', (0, -5, 0))
    return M

def ch_colossus():
    M = Model('ch_colossus'); M.piece('base'); M.add('base', [])
    rs = RS('colo')
    M.add('base', blob((25, 21, 25), (0, 38, 0), 'skin'))
    M.add('base', blob((27, 11, 27), (0, 50, -1), 'dark', lat=10))
    M.add('base', ring(26, 3, (0, 38, 0), (0, 1, 0), 'dark', 36, 8))
    for i in range(11):
        z = rs.uniform(-1, 1); a = rs.uniform(0, 6.28); r = np.sqrt(1 - z * z)
        d = V(r * np.cos(a), 0.35 + abs(z) * 0.65, r * np.sin(a)); d = norm(d)
        if d[2] > 0.6: continue
        M.add('base', eye(rs.uniform(3.6, 5.2), V(0, 38, 0) + d * 24, d))
    M.add('base', hang(11, 20, 30, 46, 5.2, 'skin', rs, 0.55, 1.4, 4, seed=5))
    M.add('base', crown(8, 14, 56, 12, 2.5, 'dark', 0.2, centre=(0, 0, -8)))
    M.piece('halo', 'base', (0, 82, 0))
    M.add('halo', ring(46, 2.2, (0, 0, 0), (0, 1, 0), 'glow', 40, 8))
    M.add('halo', [spike(V(46 * np.cos(a), 0, 46 * np.sin(a)), V(np.cos(a), 0.1, np.sin(a)), 12, 2.0, 'dark', 5) for a in np.linspace(0, 6.28, 13)[:-1]])
    M.piece('head', 'base', (0, 42, 22))
    M.add('head', eye(17, (0, 0, 6), (0, 0, 1)))
    M.add('head', blob((19, 8, 17), (0, 16, 2), 'dark'))
    M.add('head', crown(10, 14.5, 12, 15, 2.4, 'dark', 0.5, centre=(0, 0, 0)))
    tiny(M, 'muzzle', 'head', (0, 0, 26))
    return M

# ------------------------------------------------------------------------- structures
def roots(n, R, length, r0, mat='skin', seed=2, y=3):
    rs = np.random.RandomState(seed); out = []
    for i in range(n):
        a = 2 * np.pi * (i + rs.uniform(-0.2, 0.2)) / n
        out.append(tentacle(V(R * 0.36 * np.cos(a), y, R * 0.36 * np.sin(a)), V(np.cos(a), -0.15, np.sin(a)), length, r0, mat,
                            bend=V(0, -3, 0), waves=1, side=V(-np.sin(a), 0, np.cos(a)), amp=2, r1=0.5))
    return out

def ch_womb():
    M = Model('ch_womb'); M.piece('base'); M.add('base', [])
    M.add('base', ring(36, 8, (0, 12, 0), (0, 1, 0), 'skin', 36, 12))
    M.add('base', blob((31, 2.0, 31), (0, 11, 0), 'glow', lat=6))
    M.add('base', blob((40, 6, 40), (0, 2, 0), 'dark', lat=8))
    M.add('base', roots(8, 80, 22, 6, 'skin', 4))
    M.add('base', eye(11, (0, 19, 0), (0, 0.7, 0.8)))
    M.piece('crown', 'base', (0, 14, 0))
    M.add('crown', crown(9, 36, 2, 30, 3.0, 'dark', -0.35, centre=(0, 0, 0)))
    M.add('crown', [ring(4, 0.8, V(36 * np.cos(a), 24, 36 * np.sin(a)) * 0.82, (0, 1, 0), 'glow', 10, 4) for a in np.linspace(0, 6.28, 10)[:-1]])
    tiny(M, 'pad', 'base', (0, 18, 0))
    return M

def ch_siphon():
    M = Model('ch_siphon'); M.piece('base'); M.add('base', [])
    M.add('base', blob((8, 6, 8), (0, 7, 0), 'skin'))
    M.add('base', roots(5, 26, 11, 2.2, 'skin', 6, 5))
    M.add('base', spike(V(0, 3, 0), V(0, -1, 0), 10, 3.4, 'dark', 7))
    M.add('base', eye(4.2, (0, 12, 0), (0, 1, 0.2)))
    M.piece('spin', 'base', (0, 12, 0))
    M.add('spin', [tentacle(V(5 * np.cos(a), -3, 5 * np.sin(a)), V(np.cos(a), 0.6, np.sin(a)), 11, 1.5, 'dark', bend=V(0, 2, 0), droop=V(np.cos(a) * -3, 3, np.sin(a) * -3), waves=0.5, side=V(0, 1, 0), amp=1, r1=0.2) for a in np.linspace(0, 6.28, 6)[:-1]])
    return M

def ch_sunpetal():
    M = Model('ch_sunpetal'); M.piece('base'); M.add('base', [])
    M.add('base', blob((10, 4, 10), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(6, 40, 14, 3.0, 'skin', 7, 3))
    M.add('base', tube(curve(V(0, 3, 0), V(0, 1, 0), 10, n=4), [4, 3, 2.6, 3], 'skin', 8))
    M.add('base', eye(5.5, (0, 15, 0), (0, 1, 0.1)))
    M.piece('petals', 'base', (0, 13, 0))
    for i in range(10):
        a = 2 * np.pi * i / 10
        d = V(np.cos(a), 0.55, np.sin(a))
        M.add('petals', blob((2.4, 0.5, 13), V(np.cos(a) * 11, 6, np.sin(a) * 11), 'skin' if i % 2 else 'glow', d=d, lon=10, lat=6))
    return M

def ch_heart():
    M = Model('ch_heart'); M.piece('base'); M.add('base', [])
    M.add('base', blob((36, 6, 36), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(10, 100, 24, 5, 'skin', 8, 4))
    M.add('base', blob(15, (0, 34, 0), 'dark'))
    M.add('base', ring(15.5, 1.8, (0, 34, 0), (0, 1, 0), 'glow', 32, 8))
    for a in np.linspace(0, 6.28, 5)[:-1] + 0.6:
        p = V(30 * np.cos(a), 6, 30 * np.sin(a))
        M.add('base', spike(p, V(-np.cos(a) * .25, 1, -np.sin(a) * .25), 38, 3.0, 'skin', 6))
        M.add('base', eye(3.5, p + V(-np.cos(a) * 9, 36, -np.sin(a) * 9), V(-np.cos(a), 0.3, -np.sin(a)), lid=False))
    M.piece('rings', 'base', (0, 34, 0))
    M.add('rings', [ring(24, 1.5, (0, 0, 0), (1, 0.3, 0), 'glow'), ring(30, 1.2, (0, 0, 0), (-0.3, 1, 0.4), 'skin'), ring(36, 1.0, (0, 0, 0), (0.2, 0.2, 1), 'glow', 36, 6)])
    return M

def ch_vault():
    M = Model('ch_vault'); M.piece('base'); M.add('base', [])
    M.add('base', blob((20, 5, 20), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(6, 56, 18, 4, 'skin', 9, 3))
    M.add('base', blob((15, 21, 15), (0, 24, 0), 'skin'))
    M.add('base', [ring(15.5 * np.sqrt(max(0.05, 1 - ((y - 24) / 21) ** 2)), 1.0, (0, y, 0), (0, 1, 0), 'glow', 24, 5) for y in (15, 24, 33)])
    M.add('base', [eye(3.2, V(14.5 * np.cos(a), 24, 14.5 * np.sin(a)), V(np.cos(a), 0, np.sin(a)), lid=False) for a in np.linspace(0, 6.28, 5)[:-1] + 0.3])
    M.add('base', crown(4, 3, 44, 6, 1.4, 'dark', 0.5))
    return M

def ch_watcher():
    M = Model('ch_watcher'); M.piece('base'); M.add('base', [])
    M.add('base', blob((9, 4, 9), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(5, 26, 12, 2.5, 'skin', 10, 3))
    stalk = curve(V(0, 3, 0), V(0, 1, 0), 56, bend=V(5, 0, 6), waves=1, side=V(1, 0, 0), amp=3, n=12)
    M.add('base', tube(stalk, np.linspace(3.6, 2.0, 12), 'skin', 8))
    M.add('base', [ring(3.2, 0.7, stalk[i], (0, 1, 0), 'dark', 12, 4) for i in (3, 6, 9)])
    top = stalk[-1]
    M.piece('head', 'base', tuple(top + V(0, 4, 0)))
    M.add('head', eye(8, (0, 0, 2), (0, 0, 1)))
    M.piece('dish', 'head', (0, 0, 0))
    M.add('dish', ring(13, 0.9, (0, 0, 0), (0, 1, 0), 'glow', 28, 6))
    M.add('dish', [spike(V(13 * np.cos(a), 0, 13 * np.sin(a)), V(np.cos(a) * .3, 1, np.sin(a) * .3), 6, 1.0, 'dark', 5) for a in np.linspace(0, 6.28, 6)[:-1]])
    return M

def ch_stare():
    M = Model('ch_stare'); M.piece('base'); M.add('base', [])
    M.add('base', blob((9, 4, 9), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(5, 30, 12, 2.8, 'skin', 11, 3))
    stalk = curve(V(0, 3, 0), V(0, 1, 0), 24, bend=V(0, 0, 3), n=6)
    M.add('base', tube(stalk, np.linspace(4.0, 2.8, 6), 'skin', 8))
    M.add('base', ring(4.4, 0.9, stalk[2], (0, 1, 0), 'dark', 14, 4))
    M.piece('head', 'base', tuple(stalk[-1] + V(0, 5, 2)))
    M.add('head', eye(6.8, (0, 0, 2), (0, 0, 1)))
    M.add('head', blob((7.6, 4, 7), (0, 6, 0.5), 'dark'))
    M.add('head', crown(5, 5.5, 5.5, 6, 1.1, 'dark', 0.5, centre=(0, 0, -0.5)))
    tiny(M, 'muzzle', 'head', (0, 0, 11))
    return M

def ch_pillar():
    M = Model('ch_pillar'); M.piece('base'); M.add('base', [])
    M.add('base', blob((26, 6, 26), (0, 3, 0), 'dark', lat=8))
    M.add('base', roots(7, 80, 22, 5, 'skin', 12, 4))
    path = curve(V(0, 3, 0), V(0, 1, 0), 52, n=10)
    M.add('base', tube(path, np.linspace(13, 8.5, 10), 'skin', 12))
    M.add('base', [ring(13 - 4.5 * i / 5 + 1, 1.6, V(0, 8 + i * 9, 0), (0, 1, 0), 'dark', 22, 6) for i in range(5)])
    M.add('base', [eye(3, V(11 * np.cos(a) , 22, 11 * np.sin(a)) * (0.88), V(np.cos(a), 0, np.sin(a)), lid=False) for a in np.linspace(0, 6.28, 5)[:-1]])
    M.piece('head', 'base', (0, 62, 0))
    M.add('head', eye(14, (0, 0, 4), (0, 0, 1)))
    M.add('head', blob((16, 7, 15), (0, 12, 1), 'dark'))
    M.add('head', crown(8, 12, 9, 15, 2.2, 'dark', 0.5))
    M.add('head', [eye(4.2, V(s * 17, -2, 0), V(s * 0.4, 0, 1), lid=False) for s in (-1, 1)])
    tiny(M, 'muzzle', 'head', (0, 0, 22))
    return M

CHOIR = dict(ch_hierophant=ch_hierophant, ch_seer=ch_seer, ch_gazer=ch_gazer, ch_lashling=ch_lashling, ch_hoplite=ch_hoplite,
             ch_basilisk=ch_basilisk, ch_weeper=ch_weeper, ch_colossus=ch_colossus, ch_womb=ch_womb, ch_siphon=ch_siphon,
             ch_sunpetal=ch_sunpetal, ch_heart=ch_heart, ch_vault=ch_vault, ch_watcher=ch_watcher, ch_stare=ch_stare, ch_pillar=ch_pillar)
