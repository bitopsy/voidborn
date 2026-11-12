import numpy as np
from PIL import Image, ImageDraw
from mesh import merge, norm

def render(model, tex, size=256, yaw=35, pitch=22, bg=(14, 12, 28), spin=None, ss=2, fit=None):
    th, ph = np.radians(yaw), np.radians(pitch)
    Ry = np.array([[np.cos(th), 0, np.sin(th)], [0, 1, 0], [-np.sin(th), 0, np.cos(th)]])
    Rx = np.array([[1, 0, 0], [0, np.cos(ph), -np.sin(ph)], [0, np.sin(ph), np.cos(ph)]])
    R = Rx @ Ry
    tris = []
    def off(n):
        p = model.pieces[n]; return p['offset'] + (off(p['parent']) if p['parent'] else 0)
    for n, p in model.pieces.items():
        for m in p['meshes']:
            V = (m.V + off(n)) @ R.T; N = m.N @ R.T
            tris.append((V, N, m.UV, m.F))
    allv = np.vstack([t[0] for t in tris])
    lo, hi = allv.min(0), allv.max(0); c = (lo + hi) / 2
    scale = (fit or max(hi[0] - lo[0], hi[1] - lo[1])) * 1.08
    S = size * ss
    img = Image.new('RGB', (S, S), bg); d = ImageDraw.Draw(img)
    items = []
    L = norm(np.array([-0.5, 0.8, 0.6]))
    for V, N, UV, F in tris:
        for f in F:
            z = V[f, 2].mean()
            fn = np.cross(V[f[1]] - V[f[0]], V[f[2]] - V[f[0]])
            if fn[2] <= 0: continue          # backface (camera looks down -z; +z toward viewer)
            n = N[f].mean(0); n = n / (np.linalg.norm(n) + 1e-9)
            uv = UV[f].mean(0)
            items.append((z, V[f], n, uv))
    items.sort(key=lambda t: t[0])
    H, W = tex.shape[:2]
    for z, v, n, uv in items:
        tx = int(np.clip(uv[0] * W, 0, W - 1)); ty = int(np.clip(uv[1] * H, 0, H - 1))
        col = tex[ty, tx, :3].astype(float)
        lam = max(0.0, float(n @ L)); sh = 0.30 + 0.85 * lam
        em = 0
        if 0.5 <= uv[0] < 0.75: em = 1.0
        col = np.clip(col * sh + em * col * 0.6, 0, 255)
        pts = [((p[0] - c[0]) / scale * S + S / 2, S / 2 - (p[1] - c[1]) / scale * S) for p in v]
        d.polygon(pts, fill=tuple(int(x) for x in col))
    return img.resize((size, size), Image.LANCZOS)
