import numpy as np
from PIL import Image

W, H = 1024, 256
PAL = {
 'choir': dict(skin=(214,198,232), vein=(150,105,205), dark=(62,48,108), trim=(222,184,84), glow=(90,255,235), glow2=(255,215,110),
               sclera=(246,240,236), sveins=(190,80,120), iris_o=(70,40,170), iris_i=(80,255,240), pupil=(8,4,20), team_alpha=True),
 'maw':   dict(skin=(86,34,40),   vein=(255,120,30), dark=(26,22,30), trim=(120,18,24), glow=(170,255,60), glow2=(255,140,30),
               sclera=(232,222,120), sveins=(160,40,20), iris_o=(200,60,10), iris_i=(255,190,40), pupil=(12,2,2), team_alpha=True),
}

def pnoise(rs, u, v, terms=14, fmax=9, power=1.2):
    out = np.zeros_like(u)
    for _ in range(terms):
        fu = rs.randint(0, fmax + 1); fv = rs.randint(0, fmax // 2 + 2)
        a = rs.uniform(0.4, 1.0) / (1 + (fu + fv)) ** (power * 0.5)
        out += a * np.cos(2*np.pi*fu*u + rs.uniform(0, 6.28)) * np.cos(2*np.pi*fv*v)
    return out / max(np.abs(out).max(), 1e-6)

def build(faction, outdir):
    P = PAL[faction]; rs = np.random.RandomState(7 if faction == 'choir' else 11)
    yy, xx = np.mgrid[0:H, 0:256]
    u = xx / 256.0; v = (yy + 0.5) / H
    img = np.zeros((H, W, 4), float); em = np.zeros((H, W, 4), float)
    c = lambda k: np.array(P[k], float)
    # ---- skin tile
    n1 = pnoise(rs, u, v); n2 = pnoise(rs, u, v, 20, 14)
    veins = np.clip(1 - np.abs(n2) * 9, 0, 1) ** 2
    skin = c('skin')[None, None] * (0.80 + 0.2 * n1[..., None]) 
    skin = skin * (1 - 0.55 * veins[..., None]) + c('vein')[None, None] * 0.55 * veins[..., None]
    img[:, 0:256, :3] = skin; img[:, 0:256, 3] = 0
    em[:, 0:256, 0] = veins * (60 if faction == 'maw' else 25); em[:, 0:256, 1] = 25
    # ---- dark plated tile
    n3 = pnoise(rs, u, v, 18, 12); plates = np.clip(1 - np.abs(np.cos(2*np.pi*6*u) * np.cos(2*np.pi*3*v)) * 6, 0, 1)
    dark = c('dark')[None, None] * (0.75 + 0.35 * n3[..., None])
    dark = dark * (1 - plates[..., None]) + c('trim')[None, None] * plates[..., None] * 0.9
    img[:, 256:512, :3] = dark
    band = ((np.abs(v - 0.5) < 0.11) | (np.abs(np.cos(2*np.pi*4*u)) > 0.93)).astype(float)
    img[:, 256:512, 3] = band * 255
    crack = np.clip(1 - np.abs(pnoise(rs, u, v, 16, 12)) * 14, 0, 1) ** 2
    em[:, 256:512, 0] = crack * (130 if faction == 'maw' else 40)
    em[:, 256:512, 1] = 110 * (1 - band * 0) 
    # ---- glow tile
    n4 = pnoise(rs, u, v, 10, 6)
    glow = c('glow')[None, None] * (0.8 + 0.2 * n4[..., None]); mixk = (0.5 + 0.5 * np.cos(2*np.pi*3*v))[..., None]
    glow = glow * mixk + c('glow2')[None, None] * (1 - mixk)
    img[:, 512:768, :3] = glow; img[:, 512:768, 3] = 0
    em[:, 512:768, 0] = 255
    # ---- eye tile (symmetric around v=0.5 so it survives any v-flip)
    rho = np.minimum(v, 1 - v)
    ang = 2 * np.pi * u
    streak = 0.5 + 0.5 * np.cos(ang * 17 + 3 * np.sin(ang * 5))
    t = np.clip(rho / 0.215, 0, 1)
    iris = c('iris_i')[None, None] * (1 - t[..., None]) + c('iris_o')[None, None] * t[..., None]
    iris = iris * (0.65 + 0.5 * streak[..., None])
    sv = np.clip(1 - np.abs(pnoise(rs, u, v, 18, 14)) * 10, 0, 1) ** 2
    scl = c('sclera')[None, None] * (1 - 0.6 * sv[..., None]) + c('sveins')[None, None] * 0.6 * sv[..., None]
    eye = np.where((rho < 0.215)[..., None], iris, scl)
    limb = np.clip((rho - 0.19) / 0.03, 0, 1) * (rho < 0.225)
    eye = eye * (1 - 0.7 * limb[..., None])
    eye = np.where((rho < 0.085)[..., None], c('pupil')[None, None], eye)
    img[:, 768:1024, :3] = eye; img[:, 768:1024, 3] = 0
    emI = np.where(rho < 0.215, 200 * (1 - t) + 90, 0) * (rho >= 0.085)
    em[:, 768:1024, 0] = emI; em[:, 768:1024, 1] = 220
    em[:, 0:256, 1] = 30; em[:, 256:512, 1] = 110
    em[..., 2] = 0; em[..., 3] = 255
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), 'RGBA').save(f'{outdir}/{faction}_tex1.png')
    Image.fromarray(np.clip(em, 0, 255).astype(np.uint8), 'RGBA').save(f'{outdir}/{faction}_tex2.png')
    return np.clip(img, 0, 255).astype(np.uint8)
