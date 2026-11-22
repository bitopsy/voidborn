"""Voidborn TIER 3 models (0.18): one lab and one slow heavy per faction (Choir, Maw, Tympan, Miasma).

Every T3 body is the faction's T2 model grown to a larger size (all pieces keep their names, so the scripts that
gen_defs.write_scripts makes for the T2 units fit them) plus a spinning crown of faction-flavoured ornament on a new
piece called 'rings' (spun by SPIN_ALWAYS in gen_defs.py).  Registered in gen_assets_t3.py (T3 table).
"""
import numpy as np
from mesh import *
from designs_a import RS, V
from designs_t2 import ch_womb2, ch_panopticon, mw_hive2, mw_devourer
from designs_t2b import ty_echo2, ty_organon, mi_nostril2, mi_titanarum


def grow(fn, name, k):
    """the T2 model made k times bigger: offsets and every mesh scaled, piece names and tree unchanged"""
    M = fn(); M.name = name
    for p in M.pieces.values():
        p['offset'] = p['offset'] * k
        for m in p['meshes']: m.xf(s=k)
    return M


def crown_of(M, parent, y, R, n, build, spin_piece='rings'):
    """a ring of n ornaments (build(angle_vector, radial_position) -> mesh list) round the model, on its own spinning piece"""
    M.piece(spin_piece, parent, (0, y, 0))
    M.add(spin_piece, ring(R, 2.6, (0, 0, 0), (0, 1, 0), 'glow', 48, 8))
    M.add(spin_piece, ring(R * 0.82, 1.8, (0, 6, 0), (0.15, 1, 0), 'dark', 40, 6))
    for a in np.linspace(0, 6.2832, n + 1)[:-1]:
        d = V(np.cos(a), 0, np.sin(a))
        M.add(spin_piece, build(d, d * R))
    return M


# ---------------------------------------------------------------- the factories (T2 lab x1.25 + a spinning crown)
def ch_womb3():
    M = grow(ch_womb2, 'ch_womb3', 1.25)
    return crown_of(M, 'base', 70, 58, 10, lambda d, p: [eye(5.5, p, d, lid=False), spike(p, V(0, 1, 0), 16, 2.2, 'dark', 5)])
def mw_hive3():
    M = grow(mw_hive2, 'mw_hive3', 1.25)
    return crown_of(M, 'base', 70, 58, 10, lambda d, p: [spike(p, V(d[0] * 0.3, 1, d[2] * 0.3), 30, 4.0, 'dark', 6), blob(3.2, p + V(0, 8, 0), 'glow', lon=8, lat=5)])
def ty_echo3():
    M = grow(ty_echo2, 'ty_echo3', 1.25)
    return crown_of(M, 'base', 70, 58, 10, lambda d, p: [ring(7, 1.4, p + V(0, 4, 0), d, 'glow', 18, 5), spike(p, V(0, 1, 0), 18, 2.2, 'dark', 5)])
def mi_nostril3():
    M = grow(mi_nostril2, 'mi_nostril3', 1.25)
    return crown_of(M, 'base', 70, 58, 10, lambda d, p: [blob((5, 8, 5), p + V(0, 8, 0), 'skin', lon=10, lat=6), spike(p, V(0, 1, 0), 14, 2.0, 'dark', 5)])


# ---------------------------------------------------------------- the heavies (T2 heavy x1.45 + a spinning crown)
def ch_eidolon():
    """Eidolon - the Panopticon grown into a ghost of itself: a sphere of eyes inside two crowns of eyes."""
    M = grow(ch_panopticon, 'ch_eidolon', 1.45)
    return crown_of(M, 'base', 150, 104, 14, lambda d, p: [eye(7.0, p, d, lid=False), spike(p, V(0, 1, 0), 22, 2.8, 'dark', 5)])
def mw_dreadmaw():
    """Dreadmaw - the Devourer with a second ring of fangs round its gate of teeth."""
    M = grow(mw_devourer, 'mw_dreadmaw', 1.45)
    return crown_of(M, 'base', 120, 100, 14, lambda d, p: [spike(p, V(d[0] * 0.2, 1, d[2] * 0.2), 46, 6.0, 'dark', 6), blob(4.5, p + V(0, 12, 0), 'glow', lon=8, lat=5)])
def ty_carillon():
    """Carillon - the Organon with a ring of bells."""
    M = grow(ty_organon, 'ty_carillon', 1.45)
    return crown_of(M, 'base', 150, 104, 14, lambda d, p: [ring(9, 1.8, p + V(0, 6, 0), d, 'glow', 20, 6), spike(p, V(0, 1, 0), 24, 2.6, 'dark', 5)])
def mi_rafflesia():
    """Rafflesia - the Titan Arum with a ring of corpse-flower buds."""
    M = grow(mi_titanarum, 'mi_rafflesia', 1.45)
    return crown_of(M, 'base', 120, 100, 14, lambda d, p: [blob((8, 12, 8), p + V(0, 10, 0), 'skin', lon=12, lat=8), spike(p, V(0, 1, 0), 22, 2.6, 'dark', 5)])


T3 = {
    'choir': dict(ch_womb3=ch_womb3, ch_eidolon=ch_eidolon),
    'maw': dict(mw_hive3=mw_hive3, mw_dreadmaw=mw_dreadmaw),
    'tympan': dict(ty_echo3=ty_echo3, ty_carillon=ty_carillon),
    'miasma': dict(mi_nostril3=mi_nostril3, mi_rafflesia=mi_rafflesia),
}
