import numpy as np

def _to565(c):
    r = (c[:, 0] * 31 + 127) // 255; g = (c[:, 1] * 63 + 127) // 255; b = (c[:, 2] * 31 + 127) // 255
    return (r << 11 | g << 5 | b).astype(np.uint32)

def _from565(v):
    r = (v >> 11) & 31; g = (v >> 5) & 63; b = v & 31
    return np.stack([r * 255 / 31, g * 255 / 63, b * 255 / 31], -1)

def encode_blocks(blocks):
    """blocks: (n,16,3) uint8  ->  (n,8) uint8 DXT1"""
    n = len(blocks); out = np.zeros((n, 8), np.uint8)
    B = blocks.astype(np.float32)
    hi = B.max(1); lo = B.min(1)
    inset = (hi - lo) / 16.0
    hi = np.clip(hi - inset, 0, 255).astype(np.int64); lo = np.clip(lo + inset, 0, 255).astype(np.int64)
    a = _to565(hi); b = _to565(lo)
    c0 = np.maximum(a, b); c1 = np.minimum(a, b)
    P0 = _from565(c0); P1 = _from565(c1)
    pal = np.stack([P0, P1, (2 * P0 + P1) / 3, (P0 + 2 * P1) / 3], 1)           # n,4,3
    d = ((B[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(-1)                  # n,16,4
    idx = d.argmin(-1).astype(np.uint32)                                         # n,16
    idx[c0 == c1] = 0
    bits = np.zeros(n, np.uint32)
    for i in range(16): bits |= idx[:, i] << np.uint32(2 * i)
    out[:, 0] = c0 & 255; out[:, 1] = c0 >> 8; out[:, 2] = c1 & 255; out[:, 3] = c1 >> 8
    out[:, 4] = bits & 255; out[:, 5] = (bits >> 8) & 255; out[:, 6] = (bits >> 16) & 255; out[:, 7] = (bits >> 24) & 255
    return out

def encode_image(img, chunk=150000):
    """img (H,W,3) uint8, H,W multiple of 4 -> bytes (row-major blocks)"""
    H, W, _ = img.shape
    bl = img.reshape(H // 4, 4, W // 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(-1, 16, 3)
    res = [encode_blocks(bl[i:i + chunk]) for i in range(0, len(bl), chunk)]
    return np.vstack(res).tobytes()

def box_down(img):
    f = img.astype(np.float32)
    return ((f[0::2, 0::2] + f[1::2, 0::2] + f[0::2, 1::2] + f[1::2, 1::2]) / 4 + 0.5).astype(np.uint8)

def mip_chain_bytes(img, min_size=4):
    out = []; cur = img
    while True:
        out.append(encode_image(cur))
        if cur.shape[0] <= min_size: break
        cur = box_down(cur)
    return b''.join(out)
