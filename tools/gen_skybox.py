#!/usr/bin/env python3
"""The skybox of Voidborn Rift: a starfield with a nebula, as a DDS cubemap.

    python3 tools/gen_skybox.py

Writes map/maps/skybox.dds (six faces, DXT1) and a PNG preview of the faces
so the result can be looked at without the engine.  The map's mapinfo.lua asks
for "skybox.dds", so without this the map falls back to the engine's default
sky and warns about a missing texture.
"""
import math
import os
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dxt import mip_chain_bytes

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "map", "maps")
SIZE = 256
SEED = 2026

# the six faces of a cubemap, in the order the DDS wants them
FACES = [
    ("+X", lambda u, v: (1.0, -v, -u)),
    ("-X", lambda u, v: (-1.0, -v, u)),
    ("+Y", lambda u, v: (u, 1.0, v)),
    ("-Y", lambda u, v: (u, -1.0, -v)),
    ("+Z", lambda u, v: (u, -v, 1.0)),
    ("-Z", lambda u, v: (-u, -v, -1.0)),
]


def directions(face):
    """The unit direction of every pixel of one face."""
    n = SIZE
    step = 2.0 / n
    u = (np.arange(n) + 0.5) * step - 1.0
    vv = (np.arange(n) + 0.5) * step - 1.0
    U, V = np.meshgrid(u, vv)
    d = np.stack([np.broadcast_to(c, U.shape) if np.ndim(c) == 0 else c for c in face(U, V)], axis=2)
    d = d / np.linalg.norm(d, axis=2, keepdims=True)
    return d


def sky(d, stars):
    """The sky at every direction: a nebula, a gradient and the stars."""
    x, y, z = d[..., 0], d[..., 1], d[..., 2]
    img = np.zeros(d.shape[:2] + (3,), np.float32)
    img[..., 0] = 0.020
    img[..., 1] = 0.016
    img[..., 2] = 0.055
    # the deep blue of the void, a little brighter towards the galactic plane
    band = np.exp(-((y * 1.6) ** 2))
    img[..., 0] += 0.045 * band
    img[..., 1] += 0.030 * band
    img[..., 2] += 0.110 * band
    # three nebula lobes
    for cx, cy, cz, r, cr, cg, cb in ((0.55, 0.35, 0.75, 0.55, 0.20, 0.07, 0.34),
                                      (-0.70, -0.10, 0.70, 0.42, 0.17, 0.06, 0.26),
                                      (0.10, 0.60, -0.79, 0.38, 0.12, 0.16, 0.30)):
        dd = (x - cx) ** 2 + (y - cy) ** 2 + (z - cz) ** 2
        g = np.exp(-dd / (r * r))
        img[..., 0] += g * cr
        img[..., 1] += g * cg
        img[..., 2] += g * cb
    # the stars
    img += stars[..., None] * np.array([0.95, 0.95, 1.0], np.float32)
    return np.clip(img, 0, 1)


def make_faces():
    rng = np.random.RandomState(SEED)
    faces = []
    for _, fn in FACES:
        d = directions(fn)
        # the stars: a few bright ones and a dust of faint ones
        r = rng.random((SIZE, SIZE))
        stars = np.zeros((SIZE, SIZE), np.float32)
        bright = r > 0.9975
        stars[bright] = 0.75 + 0.25 * rng.random(bright.sum())
        faint = (r > 0.90) & (r <= 0.9975)
        stars[faint] = 0.10 + 0.16 * rng.random(faint.sum())
        img = (sky(d, stars) * 255).astype(np.uint8)
        faces.append(img)
    return faces


def dds_header(faces, mip_count):
    """A DDS header for a cubemap with DXT1 faces (128 bytes)."""
    DDSD = 0x1 | 0x2 | 0x4 | 0x1000 | 0x80000 | 0x200000 | 0x400000
    # caps, height, width, pitch, depth, mipmapcount, reserved
    DDSCAPS = 0x8 | 0x100000 | 0x400000                       # complex, texture, mipmap
    DDSCAPS2 = 0x200 | 0x400 | 0x800 | 0x1000 | 0x2000 | 0x4000   # the six faces
    DDPF_FOURCC = 0x4
    h = struct.pack('<4sI', b'DDS ', 124)
    h += struct.pack('<IIIIIII', DDSD, SIZE, SIZE, SIZE * SIZE // 2, 0, mip_count, 0)
    h += b'\0' * 40                                        # the rest of dwReserved1
    h += struct.pack('<II', 32, DDPF_FOURCC)                # ddspf size and flags
    h += struct.pack('<4s', b'DXT1')                        # ddspf.dwFourCC
    h += struct.pack('<IIIII', 0, 0, 0, 0, 0)               # bit count and the masks
    h += struct.pack('<IIIII', DDSCAPS, DDSCAPS2, 0, 0, 0)  # caps, caps2, caps3, caps4, reserved
    assert len(h) == 128, len(h)
    return h


def main():
    os.makedirs(OUT, exist_ok=True)
    faces = make_faces()
    # the mip chain of every face
    chains = [mip_chain_bytes(f, 4) for f in faces]
    mips = 1
    while SIZE >> mips > 4:
        mips += 1
    data = dds_header(faces, mips) + b"".join(chains)
    path = os.path.join(OUT, "skybox.dds")
    with open(path, "wb") as fh:
        fh.write(data)
    print(f"  skybox.dds          {len(data):8} bytes  {SIZE}x{SIZE} per face, {mips} mips")

    # a preview: the four side faces in a row, so the result can be seen
    order = [4, 5, 0, 1]          # +Z, -Z, +X, -X
    strip = Image.new("RGB", (SIZE * 4, SIZE))
    for i, idx in enumerate(order):
        strip.paste(Image.fromarray(faces[idx]), (i * SIZE, 0))
    prev = os.path.join(ROOT, "out", "skybox_preview.png")
    os.makedirs(os.path.dirname(prev), exist_ok=True)
    strip.save(prev)
    print(f"  out/skybox_preview.png  {os.path.getsize(prev)} bytes")


if __name__ == "__main__":
    main()
