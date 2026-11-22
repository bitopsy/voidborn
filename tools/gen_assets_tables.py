"""Which model functions belong to which faction, and the colours of their build pictures.  Shared by gen_assets.py and the previews."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from designs_a import CHOIR
from designs_b import MAW
from designs_t2 import CHOIR_T2, MAW_T2

TABLES = {'choir': {**CHOIR, **CHOIR_T2}, 'maw': {**MAW, **MAW_T2}}
BG = {'choir': (20, 16, 34), 'maw': (30, 14, 12), 'tympan': (34, 22, 14), 'miasma': (24, 14, 34), 'haptic': (14, 22, 40)}
BORDER = {'choir': (220, 190, 90), 'maw': (255, 120, 30), 'tympan': (255, 200, 70), 'miasma': (226, 98, 255), 'haptic': (96, 176, 255)}
ORDER = ['choir', 'maw', 'tympan', 'miasma', 'haptic']
try:
    from designs_c import TYMPAN
    TABLES['tympan'] = dict(TYMPAN)
except ImportError:
    pass
try:
    from designs_d import MIASMA
    TABLES['miasma'] = dict(MIASMA)
except ImportError:
    pass
try:
    from designs_t2b import TYMPAN_T2, MIASMA_T2
    TABLES.setdefault('tympan', {}).update(TYMPAN_T2); TABLES.setdefault('miasma', {}).update(MIASMA_T2)
except ImportError:
    pass
try:
    from designs_f import HAPTIC
    TABLES['haptic'] = dict(HAPTIC)
except ImportError:
    pass
try:
    from designs_f2 import HAPTIC_T2
    TABLES.setdefault('haptic', {}).update(HAPTIC_T2)
except ImportError:
    pass
