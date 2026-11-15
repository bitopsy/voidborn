import os as _os
ROOT = _os.path.abspath(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), ".."))
"""Voidborn Rift - space map generator (SMF/SMT + mapinfo + skybox)."""
import numpy as np, struct, hashlib, os, sys, math, json
sys.path.insert(0, os.path.dirname(__file__))
from dxt import encode_image, mip_chain_bytes, box_down
from PIL import Image

N = 10                         # map size in 512-elmo units
MAPX = N * 64                  # heightmap squares
SZ = MAPX * 8                  # elmos
OUT = ROOT + '/map'
SHORT = 'voidrift'
MINH, MAXH = -300.0, 700.0
METAL_VALUE = int(sys.argv[1]) if len(sys.argv) > 1 else 255
os.makedirs(OUT + '/maps', exist_ok=True)
rs = np.random.RandomState(2026)

# ------------------------------------------------------------------ noise helpers
def tile_noise(size, beta, seed):
    r = np.random.RandomState(seed)
    f = np.fft.fftfreq(size)[:, None] ** 2 + np.fft.fftfreq(size)[None, :] ** 2
    f[0, 0] = 1
    spec = (r.randn(size, size) + 1j * r.randn(size, size)) / (f ** (beta / 2))
    spec[0, 0] = 0
    n = np.fft.ifft2(spec).real
    n = (n - n.mean()) / (n.std() + 1e-9)
    return n.astype(np.float32)

def fbm_xy(x, z, seed, octs=5, base=900.0):
    r = np.random.RandomState(seed); out = np.zeros_like(x, dtype=np.float32); amp = 1.0; tot = 0
    for o in range(octs):
        for _ in range(3):
            ang = r.uniform(0, 6.283); k = 2 * np.pi / (base / 2 ** o) * r.uniform(0.7, 1.3)
            out += amp * np.sin(k * (x * np.cos(ang) + z * np.sin(ang)) + r.uniform(0, 6.283)); tot += amp
        amp *= 0.55
    return out / tot

# ------------------------------------------------------------------ layout
# kinds: knots (d_norm, height) describe the radial profile of an asteroid
HOME = [(0, 285), (.30, 285), (.34, 195), (.60, 195), (.64, 115), (.88, 115), (.95, 70), (1.02, -40), (1.14, -300)]
EYE = [(0, 95), (.28, 95), (.38, 215), (.62, 215), (.74, 150), (.92, 115), (1.0, -30), (1.12, -300)]
ISLE = [(0, 175), (.52, 175), (.60, 112), (.88, 112), (1.0, -40), (1.12, -300)]
CORN = [(0, 135), (.82, 135), (1.0, -40), (1.14, -300)]
DEB = [(0, 105), (.78, 105), (1.0, -40), (1.15, -300)]
rocks = []   # (cx,cz,R,knots,seed)
def sym(cx, cz, R, knots, seed, mirror=(True, True)):
    pts = {(cx, cz)}
    if mirror[0]: pts |= {(SZ - x, z) for x, z in list(pts)}
    if mirror[1]: pts |= {(x, SZ - z) for x, z in list(pts)}
    for i, (x, z) in enumerate(sorted(pts)): rocks.append((x, z, R, knots, seed + i))
sym(1000, 2560, 860, HOME, 100, (True, False))
sym(2560, 2560, 390, EYE, 200, (False, False))
sym(2560, 960, 340, ISLE, 300, (False, True))
sym(1000, 930, 280, CORN, 400)
for i, (x, z, R) in enumerate([(1750, 1450, 150), (2140, 1850, 105), (1560, 1950, 85)]):
    sym(x, z, R, DEB, 500 + 10 * i)

def polar(deg, r, cx, cz): a = math.radians(deg); return (cx + r * math.cos(a), cz + r * math.sin(a))
spots = []
def spots_sym(pts, mirror=(True, True)):
    S = set(pts)
    if mirror[0]: S |= {(SZ - x, z) for x, z in list(S)}
    if mirror[1]: S |= {(x, SZ - z) for x, z in list(S)}
    spots.extend(sorted(S))
# home island (west) - 10 spots each side, mirrored in x only
hs = [polar(a, 640, 1000, 2560) for a in (0, 40, -40, 80, -80, 120, -120, 180)] + [(1000, 2440), (1000, 2680)]
spots_sym([(round(x), round(z)) for x, z in hs], (True, False))
spots += [(2560, 2560), (2750, 2560), (2370, 2560), (2560, 2750), (2560, 2370)]            # the Eye
spots_sym([(2560, 960 + dz) for dz in (0,)] + [(2400, 1060), (2720, 1060)] and [(2560, 890), (2400, 1030), (2720, 1030)], (False, True))
spots_sym([(1000, 930), (1090, 1000)] , (True, True))
spots_sym([(1750, 1450)], (True, True))
spots = sorted(set(spots))

STARTS = [(790, 2230), (790, 2890), (SZ - 790, 2230), (SZ - 790, 2890)]
STARTS_ORDER = [0, 2, 1, 3]    # team assignment: ally0 = west pair, ally1 = east pair (see mapinfo)

# ------------------------------------------------------------------ heightmap
g = np.arange(MAPX + 1, dtype=np.float32) * 8.0
X, Z = np.meshgrid(g, g)       # X[z,x]
H = np.full(X.shape, MINH, np.float32)
for (cx, cz, R, knots, sd) in rocks:
    r = np.random.RandomState(sd)
    dx, dz = X - cx, Z - cz
    ang = np.arctan2(dz, dx)
    wob = sum(r.uniform(0.02, 0.07) / (k ** 0.7) * np.cos(k * ang + r.uniform(0, 6.28)) for k in range(2, 9))
    d = np.sqrt(dx * dx + dz * dz) / (R * (1 + wob))
    kd, kh = zip(*knots)
    h = np.interp(d, kd, kh).astype(np.float32)
    # terrace roughness
    rough = fbm_xy(X, Z, sd, 4, 260.0)
    plateau = np.clip((h - 40) / 60, 0, 1)
    h = h + rough * (3.5 * plateau + 22 * (1 - plateau) * (h > -250))
    H = np.maximum(H, h)
# flat pads under metal spots
for (sx, sz) in spots:
    d = np.sqrt((X - sx) ** 2 + (Z - sz) ** 2)
    ix, iz = int(round(sx / 8)), int(round(sz / 8))
    target = H[iz, ix]
    k = np.clip(1 - (d - 36) / 28, 0, 1)
    H = np.where(d < 64, H * (1 - k) + target * k, H)
# start pads
for (sx, sz) in STARTS:
    d = np.sqrt((X - sx) ** 2 + (Z - sz) ** 2); ix, iz = int(round(sx / 8)), int(round(sz / 8)); target = H[iz, ix]
    k = np.clip(1 - (d - 90) / 70, 0, 1); H = np.where(d < 160, H * (1 - k) + target * k, H)
H = np.clip(H, MINH, MAXH)
h16 = np.round((H - MINH) / (MAXH - MINH) * 65535).astype('<u2')
print('rock fraction %.1f%%' % (100 * (H > 0).mean()))

# ------------------------------------------------------------------ metal map (16-elmo cells)
MM = np.zeros((MAPX // 2, MAPX // 2), np.uint8)
for (sx, sz) in spots:
    cx, cz = int(sx // 16), int(sz // 16)
    MM[cz:cz + 2, cx:cx + 2] = METAL_VALUE
    MM[cz - 1, cx - 1:cx + 3] = 0

# ------------------------------------------------------------------ texture (1px/elmo)
TEX = MAPX * 8
nA = tile_noise(512, 2.2, 1); nB = tile_noise(512, 1.4, 2); nC = tile_noise(512, 3.0, 3)
def tilev(n, ys, xs, sc=1): return n[(ys // sc)[:, None] % 512, (xs // sc)[None, :] % 512]
gx = np.arange(MAPX + 1)
Gy, Gx = np.gradient(H, 8.0)
slope = np.sqrt(Gx ** 2 + Gy ** 2).astype(np.float32)
def up(arr, y0, y1):
    """bilinear sample of a (MAPX+1)^2 grid to texel rows y0..y1, all columns"""
    ys = (np.arange(y0, y1) + 0.5) / 8.0 - 0.5; xs = (np.arange(TEX) + 0.5) / 8.0 - 0.5
    ys = np.clip(ys, 0, MAPX - 1e-3); xs = np.clip(xs, 0, MAPX - 1e-3)
    y0i = ys.astype(int); x0i = xs.astype(int); fy = (ys - y0i)[:, None]; fx = (xs - x0i)[None, :]
    a = arr[y0i][:, x0i]; b = arr[y0i][:, x0i + 1]; c = arr[y0i + 1][:, x0i]; d = arr[y0i + 1][:, x0i + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
spot_arr = np.array(spots, np.float32)
def texture_band(y0, y1):
    hh = up(H, y0, y1); sl = up(slope, y0, y1)
    ys = np.arange(y0, y1); xs = np.arange(TEX)
    n1 = tilev(nA, ys, xs); n2 = tilev(nB, ys, xs, 2); n3 = tilev(nC, ys, xs, 4)
    base = np.array([44, 49, 64], np.float32); hi = np.array([88, 92, 112], np.float32); warm = np.array([96, 82, 78], np.float32)
    t = np.clip(0.5 + 0.22 * n1 + 0.12 * n2, 0, 1)[..., None]
    col = base * (1 - t) + hi * t
    wm = np.clip((n3 * 0.5 + 0.1), 0, 1)[..., None] * 0.35
    col = col * (1 - wm) + warm * wm
    # higher terraces lighter and cooler
    col *= (0.88 + 0.22 * np.clip((hh - 60) / 240, 0, 1))[..., None]
    # strata on cliffs
    cl = np.clip((sl - 0.5) / 1.2, 0, 1)
    strata = 0.5 + 0.5 * np.sin(hh * 0.55 + n2 * 2.0)
    cliff = np.array([34, 30, 40], np.float32) * (0.8 + 0.5 * strata[..., None])
    col = col * (1 - cl[..., None]) + cliff * cl[..., None]
    # panel lines on flat built-up areas (very subtle)
    flat = np.clip(1 - sl / 0.35, 0, 1) * np.clip((hh - 90) / 60, 0, 1)
    xx = xs[None, :].astype(np.float32); yy = ys[:, None].astype(np.float32)
    grid = ((np.abs((xx % 128) - 64) > 62.2) | (np.abs((yy % 128) - 64) > 62.2)).astype(np.float32)
    col *= (1 - 0.16 * grid * flat)[..., None]
    # bright rim along the edge of every rock (thin, cool)
    rim = np.clip(1 - np.abs(hh - 14) / 22, 0, 1) * np.clip(sl / 0.4, 0, 1)
    col = col * (1 - 0.55 * rim[..., None]) + np.array([150, 190, 215], np.float32) * 0.55 * rim[..., None]
    # ore glow at metal spots
    if len(spot_arr):
        sel = spot_arr[(spot_arr[:, 1] > y0 - 90) & (spot_arr[:, 1] < y1 + 90)]
        for sx, sz in sel:
            d = np.sqrt((xx - sx) ** 2 + (yy - sz) ** 2)
            ring = np.clip(1 - np.abs(d - 26) / 5, 0, 1); core = np.clip(1 - d / 22, 0, 1)
            amber = np.array([255, 176, 60], np.float32)
            m = np.maximum(ring * 0.9, core * 0.55)[..., None]
            col = col * (1 - m) + amber * m
    # start pads: faint cyan ring
    for sx, sz in STARTS:
        if y0 - 140 < sz < y1 + 140:
            d = np.sqrt((xx - sx) ** 2 + (yy - sz) ** 2)
            ring = np.clip(1 - np.abs(d - 80) / 3.5, 0, 1)[..., None] * 0.5
            col = col * (1 - ring) + np.array([90, 220, 255], np.float32) * ring
    # void: deep space (never visible with voidWater, but shows on minimap)
    void = (hh < 0)[..., None]
    sp = (n1 > 3.1)[..., None] * 160
    col = np.where(void, np.array([5, 6, 14], np.float32) + sp, col)
    return np.clip(col, 0, 255).astype(np.uint8)

tiles_idx = np.zeros((MAPX // 4, MAPX // 4), np.int32); tile_bytes = []; seen = {}
mini_rows = []
for ty in range(MAPX // 4):
    band = texture_band(ty * 32, ty * 32 + 32)                       # 32 x TEX x 3
    mini_rows.append(band[::5][:, ::5] if False else band)
    mini_rows[-1] = Image.fromarray(band).resize((TEX // 5, 6), Image.BILINEAR) if False else None
    for tx in range(MAPX // 4):
        tile = band[:, tx * 32:(tx + 1) * 32]
        key = hashlib.md5(tile.tobytes()).digest()
        if key not in seen:
            seen[key] = len(tile_bytes)
            lv = [tile]; 
            for _ in range(3): lv.append(box_down(lv[-1]))
            tile_bytes.append(b''.join(encode_image(l) for l in lv))
        tiles_idx[ty, tx] = seen[key]
    if ty % 20 == 0: print('texture row', ty, 'unique tiles', len(tile_bytes), flush=True)
print('unique tiles:', len(tile_bytes), 'of', (MAPX // 4) ** 2)

# minimap: render at 1024 from H directly (cheaper than reusing the big texture)
def mini_img(S=1024):
    ys = np.arange(S) * (TEX / S); out = np.zeros((S, S, 3), np.uint8)
    for r0 in range(0, S, 128):
        rows = ys[r0:r0 + 128]; band = np.zeros((len(rows), S, 3), np.uint8)
        # sample the big pipeline at coarse resolution by calling texture_band on a few rows then pick
        pass
    return out
# simpler: rebuild a reduced texture by sampling one texel per 5 (cheap enough)
def minimap(S=1024):
    step = TEX / S; rows = []
    for r0 in range(0, S, 64):
        y0 = int(r0 * step); y1 = int((r0 + 64) * step)
        band = texture_band(y0, y1)
        im = Image.fromarray(band).resize((S, 64), Image.BOX); rows.append(np.array(im))
    return np.vstack(rows)
mini = minimap()
mini_dxt = mip_chain_bytes(mini, 4)
assert len(mini_dxt) == 699048, len(mini_dxt)
Image.fromarray(mini).save(OUT + '/minimap_preview.png')

# ------------------------------------------------------------------ write SMT
with open(f'{OUT}/maps/{SHORT}.smt', 'wb') as f:
    f.write(struct.pack('<16sIIII', b'spring tilefile\0', 1, len(tile_bytes), 32, 1))
    for tb in tile_bytes: f.write(tb)

# ------------------------------------------------------------------ write SMF
hdr_size = 80
off_h = hdr_size
off_type = off_h + h16.size * 2
type_map = np.zeros((MAPX // 2, MAPX // 2), np.uint8)
off_tiles = off_type + type_map.size
tiles_section = struct.pack('<ii', 1, len(tile_bytes)) + struct.pack('<i', len(tile_bytes)) + (SHORT + '.smt').encode() + b'\0' + tiles_idx.astype('<i4').tobytes()
off_mini = off_tiles + len(tiles_section)
off_metal = off_mini + len(mini_dxt)
off_feat = off_metal + MM.size
feat_section = struct.pack('<ii', 0, 0)
with open(f'{OUT}/maps/{SHORT}.smf', 'wb') as f:
    f.write(struct.pack('<16sIIiiiiiffiiiiiii', b'spring map file\0', 1, 0x56425246, MAPX, MAPX, 8, 8, 32, MINH, MAXH,
                        off_h, off_type, off_tiles, off_mini, off_metal, off_feat, 0))
    f.write(h16.tobytes()); f.write(type_map.tobytes()); f.write(tiles_section); f.write(mini_dxt); f.write(MM.tobytes()); f.write(feat_section)
print('smf size', os.path.getsize(f'{OUT}/maps/{SHORT}.smf'))
json.dump(dict(spots=spots, starts=STARTS, size=SZ), open(ROOT + '/out/mapmeta.json', 'w'))
Image.fromarray(((np.clip(H, -50, 300) + 50) / 350 * 255).astype(np.uint8)).save(OUT + '/height_preview.png')
print('spots', len(spots))
