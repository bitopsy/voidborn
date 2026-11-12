import numpy as np, struct, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from dxt import encode_image
OUT = '/home/claude/vb/map'
S = 1024
rs = np.random.RandomState(5)
def face_dirs(face):
    c = (np.arange(S) + 0.5) / S * 2 - 1
    u, v = np.meshgrid(c, c)    # u across columns, v down rows
    one = np.ones_like(u)
    d = {0: (one, -v, -u), 1: (-one, -v, u), 2: (u, one, v), 3: (u, -one, -v), 4: (u, -v, one), 5: (-u, -v, -one)}[face]
    d = np.stack(d, -1); return d / np.linalg.norm(d, axis=-1, keepdims=True)
def smooth3(d, seed, octs=4):
    r = np.random.RandomState(seed); o = np.zeros(d.shape[:-1], np.float32); amp = 1; tot = 0
    for k in range(octs):
        for _ in range(4):
            w = r.randn(3); w /= np.linalg.norm(w); f = r.uniform(1.5, 3) * 2 ** k
            o += amp * np.sin(f * (d @ w) * 3 + r.uniform(0, 6.28)); tot += amp
        amp *= 0.5
    return o / tot
faces = [np.zeros((S, S, 3), np.float32) for _ in range(6)]
for f in range(6):
    d = face_dirs(f)
    n1 = smooth3(d, 11); n2 = smooth3(d, 12); n3 = smooth3(d, 13, 5)
    neb = np.clip(n1 * 0.5 + 0.35, 0, 1) ** 2.2
    img = np.zeros((S, S, 3), np.float32)
    img += np.array([2, 3, 8], np.float32)
    img += neb[..., None] * (np.array([26, 12, 52], np.float32) * (0.6 + 0.4 * n2[..., None]))
    neb2 = np.clip(n2 * 0.5 + 0.25, 0, 1) ** 2.5
    img += neb2[..., None] * np.array([6, 30, 44], np.float32)
    band = np.exp(-(d @ np.array([0.3, 0.8, 0.5]) / np.linalg.norm([0.3, 0.8, 0.5])) ** 2 / 0.02)
    img += (band * np.clip(n3 * 0.6 + 0.6, 0, 1))[..., None] * np.array([34, 32, 46], np.float32)
    faces[f] = img
# stars: random unit vectors splatted into faces
N = 9000
v = rs.randn(N, 3); v /= np.linalg.norm(v, axis=1, keepdims=True)
mag = rs.pareto(2.2, N) * 0.35 + 0.15
col = np.array([[1, 1, 1], [0.8, 0.9, 1], [1, 0.9, 0.75]])[rs.randint(0, 3, N)]
for i in range(N):
    x, y, z = v[i]; ax = np.abs(v[i]).argmax()
    if ax == 0: face = 0 if x > 0 else 1; u, vv, m = (-z * np.sign(x)) , -y, abs(x)
    elif ax == 1: face = 2 if y > 0 else 3; u, vv, m = x, (z if y > 0 else -z), abs(y)
    else: face = 4 if z > 0 else 5; u, vv, m = (x * np.sign(z)), -y, abs(z)
    px = int((u / m * 0.5 + 0.5) * S); py = int((vv / m * 0.5 + 0.5) * S)
    b = min(mag[i], 1.6) * 255
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            xx, yy = px + dx, py + dy
            if 0 <= xx < S and 0 <= yy < S:
                w = 1.0 if dx == 0 and dy == 0 else 0.18
                faces[face][yy, xx] += col[i] * b * w
data = b''.join(encode_image(np.clip(f, 0, 255).astype(np.uint8)) for f in faces)
hdr = b'DDS ' + struct.pack('<7I11I', 124, 0x81007, S, S, S * S // 2, 0, 1, *([0] * 11))
hdr += struct.pack('<2I4s5I', 32, 4, b'DXT1', 0, 0, 0, 0, 0)
hdr += struct.pack('<5I', 0x1008, 0xFE00, 0, 0, 0)
assert len(hdr) == 128, len(hdr)
open(OUT + '/skybox.dds', 'wb').write(hdr + data)
print('skybox', len(hdr + data))
