"""Tiny procedural mesh library + S3O writer for the Voidborn game."""
import numpy as np, struct, math

MAT_U = {'skin': 0.0, 'dark': 0.25, 'glow': 0.5, 'eye': 0.75}   # atlas columns (each 0.25 wide)

def norm(v):
    v = np.asarray(v, float); n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-9)

def look(d, up=(0, 1, 0)):
    z = norm(d)
    x = np.cross(up, z)
    if np.linalg.norm(x) < 1e-5: x = np.cross((1, 0, 0), z)
    x = norm(x); y = np.cross(z, x)
    return np.stack([x, y, z], axis=1)

class Mesh:
    def __init__(self, V, N, UV, F):
        self.V = np.asarray(V, float); self.N = np.asarray(N, float)
        self.UV = np.asarray(UV, float); self.F = np.asarray(F, int)
        self.mat = None
    def orient(self):
        """flip triangles whose geometric normal opposes the analytic vertex normals"""
        a, b, c = (self.V[self.F[:, i]] for i in range(3))
        fn = np.cross(b - a, c - a)
        an = self.N[self.F].sum(axis=1)
        flip = (fn * an).sum(axis=1) < 0
        self.F[flip] = self.F[flip][:, ::-1]
        return self
    def xf(self, R=None, t=(0, 0, 0), s=None):
        V = self.V.copy(); N = self.N.copy()
        if s is not None: V = V * np.asarray(s); N = norm(N / np.asarray(s))
        if R is not None: V = V @ R.T; N = N @ R.T
        self.V = V + np.asarray(t, float); self.N = N
        return self

def merge(meshes):
    if not meshes: return Mesh(np.zeros((0, 3)), np.zeros((0, 3)), np.zeros((0, 2)), np.zeros((0, 3), int))
    Vs, Ns, Us, Fs, off = [], [], [], [], 0
    for m in meshes:
        Vs.append(m.V); Ns.append(m.N); Us.append(m.UV); Fs.append(m.F + off); off += len(m.V)
    return Mesh(np.vstack(Vs), np.vstack(Ns), np.vstack(Us), np.vstack(Fs))

def _uv(mat, u, v):
    return np.stack([MAT_U[mat] + 0.25 * (0.02 + 0.96 * u), 0.02 + 0.96 * v], axis=-1)

def ellipsoid(r, mat='skin', lon=18, lat=12):
    rx, ry, rz = (r, r, r) if np.isscalar(r) else r
    th = np.linspace(0, np.pi, lat + 1); ph = np.linspace(0, 2 * np.pi, lon + 1)
    T, P = np.meshgrid(th, ph, indexing='ij')
    px, py, pz = np.sin(T) * np.cos(P), np.sin(T) * np.sin(P), np.cos(T)
    V = np.stack([rx * px, ry * py, rz * pz], -1).reshape(-1, 3)
    N = norm(np.stack([px / rx, py / ry, pz / rz], -1).reshape(-1, 3))
    UV = _uv(mat, (P / (2 * np.pi)).reshape(-1), (T / np.pi).reshape(-1))
    F = []
    for i in range(lat):
        for j in range(lon):
            a = i * (lon + 1) + j; b = a + lon + 1
            F += [(a, b, b + 1), (a, b + 1, a + 1)]
    m = Mesh(V, N, UV, F).orient(); m.mat = mat; return m

def torus(R, r, mat='dark', seg=28, ring=10, ry=None):
    u = np.linspace(0, 2 * np.pi, seg + 1); v = np.linspace(0, 2 * np.pi, ring + 1)
    U, Vv = np.meshgrid(u, v, indexing='ij')
    x = (R + r * np.cos(Vv)) * np.cos(U); y = (R + r * np.cos(Vv)) * np.sin(U); z = r * np.sin(Vv)
    V = np.stack([x, y, z], -1).reshape(-1, 3)
    N = np.stack([np.cos(Vv) * np.cos(U), np.cos(Vv) * np.sin(U), np.sin(Vv)], -1).reshape(-1, 3)
    UV = _uv(mat, (U / (2 * np.pi)).reshape(-1), (Vv / (2 * np.pi)).reshape(-1))
    F = []
    for i in range(seg):
        for j in range(ring):
            a = i * (ring + 1) + j; b = a + ring + 1
            F += [(a, b, b + 1), (a, b + 1, a + 1)]
    m = Mesh(V, N, UV, F).orient(); m.mat = mat; return m

def tube(path, radii, mat='skin', k=8, caps=True):
    P = np.asarray(path, float); n = len(P)
    rad = np.asarray(radii, float) if not np.isscalar(radii) else np.full(n, radii)
    T = np.zeros_like(P)
    T[1:-1] = P[2:] - P[:-2]; T[0] = P[1] - P[0]; T[-1] = P[-1] - P[-2]
    T = norm(T)
    nrm = np.cross(T[0], (0, 1, 0))
    if np.linalg.norm(nrm) < 1e-4: nrm = np.cross(T[0], (1, 0, 0))
    nrm = norm(nrm)
    V, N, UV = [], [], []
    for i in range(n):
        nrm = nrm - T[i] * np.dot(nrm, T[i]); nrm = norm(nrm)
        b = np.cross(T[i], nrm)
        for j in range(k + 1):
            a = 2 * np.pi * j / k
            d = np.cos(a) * nrm + np.sin(a) * b
            V.append(P[i] + rad[i] * d); N.append(d)
            UV.append(_uv(mat, j / k, i / max(n - 1, 1)))
    V, N, UV = map(np.array, (V, N, UV))
    F = []
    for i in range(n - 1):
        for j in range(k):
            a = i * (k + 1) + j; b = a + k + 1
            F += [(a, b, b + 1), (a, b + 1, a + 1)]
    m = Mesh(V, N, UV, F).orient(); parts = [m]
    if caps:
        for idx, sgn in ((0, -1), (n - 1, 1)):
            if rad[idx] < 1e-3: continue
            ring_ids = np.arange(idx * (k + 1), idx * (k + 1) + k)
            c = len(V)
            Vc = np.vstack([P[idx][None], V[ring_ids]]); Nc = np.tile(T[idx] * sgn, (k + 1, 1))
            UVc = np.tile(UV[ring_ids[0]], (k + 1, 1))
            Fc = [(0, 1 + (j + 1) % k, 1 + j) if sgn > 0 else (0, 1 + j, 1 + (j + 1) % k) for j in range(k)]
            mc = Mesh(Vc, Nc, UVc, Fc); a_, b_, c_ = (mc.V[mc.F[:, i]] for i in range(3))
            fn = np.cross(b_ - a_, c_ - a_); flip = (fn * (T[idx] * sgn)).sum(1) < 0
            mc.F[flip] = mc.F[flip][:, ::-1]; parts.append(mc)
    out = merge(parts); out.mat = mat; return out

# ---------------- placement helpers (all return meshes already in piece space) -----------
def place(m, pos=(0, 0, 0), d=(0, 0, 1), s=None, up=(0, 1, 0)):
    return m.xf(look(d, up), pos, s)

def blob(r, pos=(0, 0, 0), mat='skin', d=(0, 0, 1), s=None, lon=18, lat=12):
    return place(ellipsoid(r, mat, lon, lat), pos, d, s)

def eye(r, pos, d=(0, 0, 1), lid=True):
    parts = [blob(r, pos, 'eye', d, lon=22, lat=14)]
    if lid:
        dd = norm(d)
        parts.append(place(torus(r * 0.93, r * 0.16, 'skin', 24, 8), np.asarray(pos) + dd * r * 0.30, d))
    return parts

def ring(R, r, pos=(0, 0, 0), axis=(0, 1, 0), mat='dark', seg=28, rs=8):
    return place(torus(R, r, mat, seg, rs), pos, axis)

def spike(pos, d, length, r0, mat='dark', k=6):
    d = norm(d); path = [np.asarray(pos, float), np.asarray(pos, float) + d * length]
    return tube(path, [r0, 0.0], mat, k)

def curve(pos, d, length, bend=(0, 0, 0), droop=(0, 0, 0), waves=0.0, side=(1, 0, 0), amp=0.0, n=9):
    pos = np.asarray(pos, float); d = norm(d); out = []
    for i in range(n):
        s = i / (n - 1)
        p = pos + d * length * s + np.asarray(bend) * s * s + np.asarray(droop) * s ** 2
        p = p + np.asarray(side) * amp * np.sin(2 * np.pi * waves * s) * s
        out.append(p)
    return np.array(out)

def tentacle(pos, d, length, r0, mat='skin', k=7, r1=0.0, **kw):
    path = curve(pos, d, length, **kw); n = len(path)
    rad = np.linspace(r0, r1, n) * (1 + 0.15 * np.sin(np.linspace(0, 9, n)))
    return tube(path, rad, mat, k)

def teeth(R, n, length, pos, axis=(0, 0, 1), r0=None, mat='dark', inward=0.6, jitter=0.0, seed=0):
    rs = np.random.RandomState(seed); ms = []
    ax = norm(axis); Rm = look(ax)
    for i in range(n):
        a = 2 * np.pi * i / n + rs.uniform(-jitter, jitter)
        radial = Rm @ np.array([np.cos(a), np.sin(a), 0])
        base = np.asarray(pos, float) + radial * R
        d = norm(-radial * inward + ax * (1 - inward) * 1.0 + ax * 0.3)
        ms.append(spike(base, d, length * rs.uniform(0.8, 1.15), r0 or length * 0.18, mat, 5))
    return ms

def finish(parts):
    return merge([p for p in parts])

# ------------------- unit container & S3O writer ----------------------------------------
class Model:
    def __init__(self, name):
        self.name = name; self.pieces = {}; self.order = []
    def piece(self, name, parent=None, offset=(0, 0, 0)):
        self.pieces[name] = dict(parent=parent, offset=np.asarray(offset, float), meshes=[])
        self.order.append(name); return name
    def add(self, name, parts):
        if isinstance(parts, Mesh): parts = [parts]
        for p in parts:
            if isinstance(p, list): self.pieces[name]['meshes'] += p
            else: self.pieces[name]['meshes'].append(p)
    def world_vertices(self):
        out = []
        def off(n):
            p = self.pieces[n]; return p['offset'] + (off(p['parent']) if p['parent'] else 0)
        for n, p in self.pieces.items():
            for m in p['meshes']: out.append(m.V + off(n))
        return np.vstack(out)
    def children(self, n): return [c for c in self.order if self.pieces[c]['parent'] == n]

def write_s3o(model, path, tex1, tex2):
    W = model.world_vertices()
    lo, hi = W.min(0), W.max(0); mid = (lo + hi) / 2
    radius = float(np.linalg.norm(W - mid, axis=1).max()); height = float(hi[1])
    buf = bytearray(b'\0' * 52)
    def add_str(s):
        off = len(buf); buf.extend(s.encode() + b'\0'); return off
    def wpiece(name):
        p = model.pieces[name]
        kids = [wpiece(c) for c in model.children(name)]
        m = merge(p['meshes']); nv = len(m.V)
        voff = len(buf)
        vert = np.hstack([m.V, m.N, m.UV]).astype('<f4'); buf.extend(vert.tobytes())
        toff = len(buf); buf.extend(m.F.reshape(-1).astype('<u4').tobytes())
        koff = len(buf); buf.extend(struct.pack('<%dI' % len(kids), *kids)) if kids else None
        noff = add_str(name)
        while len(buf) % 4: buf.append(0)
        poff = len(buf)
        buf.extend(struct.pack('<10I3f', noff, len(kids), koff if kids else 0, nv, voff, 0, 0,
                               m.F.size, toff, 0, *map(float, p['offset'])))
        return poff
    root = wpiece(model.order[0])
    t1 = add_str(tex1); t2 = add_str(tex2)
    hdr = struct.pack('<12sI5f4I', b'Spring unit\0', 0, radius, height, *map(float, mid), root, 0, t1, t2)
    buf[:52] = hdr
    open(path, 'wb').write(buf)
    return dict(radius=radius, height=height, mid=mid, lo=lo, hi=hi)
