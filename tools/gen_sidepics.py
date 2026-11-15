#!/usr/bin/env python3
"""Draw the faction logos and the loading screen for the lobby.

    python3 tools/gen_sidepics.py

Writes:
  game/sidepics/choir.png          the Choir of the Eye emblem
  game/sidepics/maw.png            the Maw Swarm emblem
  game/bitmaps/loadpictures/voidborn.jpg   the loading screen (the classic
                                   place a lobby looks for one)

The lobby picks the faction logos out of sidepics/ by the faction name, and
Coilbox falls back to the loading screen until the hub has card art of its own.
Both are drawn here so they stay in the same style as the rest of the art.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SIDE = os.path.join(ROOT, "game", "sidepics")
LOAD = os.path.join(ROOT, "game", "bitmaps", "loadpictures")
S = 512                                  # the emblem is drawn at 512 px


def gradient(size, top, bottom, diagonal=True):
    """A vertical (or diagonal) gradient as an image."""
    w, h = size
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (w, y)], fill=c)
    if diagonal:
        # a soft glow in the upper left, like the nebula on the logo
        glow = Image.new("L", (w, h), 0)
        gd = ImageDraw.Draw(glow)
        gd.ellipse([-w * 0.3, -h * 0.5, w * 0.9, h * 0.7], fill=70)
        glow = glow.filter(ImageFilter.GaussianBlur(w // 8))
        img = Image.composite(Image.new("RGB", (w, h), (120, 90, 220)), img, glow)
    return img


def rounded(img, radius):
    """Round the corners of an image (for the emblem frame)."""
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], radius=radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def glow(draw_target, shape, colour, blur, alpha=170):
    """Draw a shape into a separate layer and blur it, for the glow of an eye."""
    layer = Image.new("RGBA", draw_target.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.ellipse(shape, fill=colour + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    draw_target.alpha_composite(layer)


def choir():
    """The Choir of the Eye: a pale one-eyed cyclops with a halo."""
    img = gradient((S, S), (74, 44, 160), (18, 12, 44)).convert("RGBA")
    d = ImageDraw.Draw(img)

    # the halo rings around the head
    d.ellipse([88, 66, 424, 214], outline=(196, 202, 220, 235), width=13)
    d.ellipse([118, 84, 394, 196], outline=(150, 158, 186, 150), width=5)

    # the head: a pale metallic dome
    d.ellipse([126, 150, 386, 410], fill=(196, 200, 214, 255), outline=(96, 100, 120, 255), width=4)
    # shading under the dome
    shade = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    sd.ellipse([126, 250, 386, 410], fill=(70, 74, 96, 110))
    shade = shade.filter(ImageFilter.GaussianBlur(14))
    img.alpha_composite(shade)

    # the eye
    glow(img, [178, 196, 334, 372], (120, 90, 255), 26)
    d = ImageDraw.Draw(img)
    d.ellipse([186, 204, 326, 344], fill=(236, 240, 250, 255), outline=(70, 74, 96, 255), width=3)
    d.ellipse([206, 224, 306, 324], fill=(96, 74, 220, 255))
    d.ellipse([226, 244, 286, 304], fill=(24, 16, 58, 255))
    d.ellipse([236, 254, 262, 280], fill=(250, 250, 255, 235))
    d.ellipse([266, 288, 280, 302], fill=(170, 150, 255, 200))

    # the thin legs at the bottom
    for i, x in enumerate((176, 214, 252, 290, 328)):
        d.line([(x, 386), (x + (i - 2) * 16, 452)], fill=(168, 174, 196, 220), width=7)
    d.line([(152, 452), (352, 452)], fill=(120, 126, 150, 190), width=6)

    # the metallic frame of the logo
    d.rounded_rectangle([10, 10, S - 11, S - 11], radius=54, outline=(198, 204, 222, 210), width=8)
    return rounded(img, 54)


def maw():
    """The Maw Swarm: a chitinous head with a glowing amber eye and teeth."""
    img = gradient((S, S), (120, 34, 20), (26, 8, 8)).convert("RGBA")
    d = ImageDraw.Draw(img)

    # the carapace: a wide, low dome with spikes
    d.polygon([(96, 356), (140, 214), (256, 158), (372, 214), (416, 356)], fill=(112, 34, 24, 255))
    d.polygon([(96, 356), (140, 214), (256, 158), (372, 214), (416, 356)],
              outline=(168, 62, 34, 255), width=4)
    for x, h in ((150, 70), (196, 96), (256, 118), (316, 96), (362, 70)):
        d.polygon([(x - 20, 250), (x, 250 - h), (x + 20, 250)], fill=(58, 18, 14, 255),
                  outline=(150, 58, 30, 255))

    # the eye
    glow(img, [176, 214, 336, 350], (255, 176, 32), 30, 200)
    d = ImageDraw.Draw(img)
    d.ellipse([184, 222, 328, 342], fill=(232, 150, 40, 255), outline=(70, 26, 12, 255), width=4)
    d.ellipse([212, 246, 300, 320], fill=(26, 12, 8, 255))
    d.ellipse([232, 262, 268, 292], fill=(255, 236, 180, 240))

    # the teeth along the bottom
    d.polygon([(126, 352), (386, 352), (352, 400), (160, 400)], fill=(58, 18, 14, 255))
    for i in range(9):
        x = 140 + i * 30
        d.polygon([(x, 352), (x + 22, 352), (x + 11, 392)], fill=(238, 228, 206, 255))

    # the legs
    for i, x in enumerate((140, 186, 232, 280, 326, 372)):
        d.line([(x, 396), (x + (i - 2.5) * 20, 452)], fill=(126, 44, 28, 230), width=9)

    d.rounded_rectangle([10, 10, S - 11, S - 11], radius=54, outline=(214, 118, 62, 200), width=8)
    return rounded(img, 54)


def loading():
    """The loading screen: the Rift with the emblem over it."""
    w, h = 1280, 720
    img = gradient((w, h), (58, 30, 128), (10, 7, 22)).convert("RGBA")

    # the map, dimmed, centred and faded out at the edges
    mini = os.path.join(ROOT, "vb", "img", "voidborn-rift.webp")
    if os.path.isfile(mini):
        side = 620
        m = Image.open(mini).convert("RGBA").resize((side, side), Image.LANCZOS)
        # a round mask that fades the picture into the background
        mask = Image.new("L", (side, side), 0)
        md = ImageDraw.Draw(mask)
        md.ellipse([40, 40, side - 41, side - 41], fill=150)
        mask = mask.filter(ImageFilter.GaussianBlur(40))
        m.putalpha(mask)
        img.alpha_composite(m, (w // 2 - side // 2, 66))

    # the emblem (the picture has no transparency of its own, so it gets a frame)
    logo = os.path.join(ROOT, "vb", "img", "logo.webp")
    if os.path.isfile(logo):
        lg = Image.open(logo).convert("RGBA").resize((190, 190), Image.LANCZOS)
        lm = Image.new("L", lg.size, 0)
        ImageDraw.Draw(lm).rounded_rectangle([0, 0, lg.size[0] - 1, lg.size[1] - 1], radius=32, fill=255)
        lg.putalpha(lm)
        img.alpha_composite(lg, (w // 2 - 95, 42))

    d = ImageDraw.Draw(img)
    try:
        from PIL import ImageFont
        big = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 62)
        small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 25)
    except Exception:
        big = small = None

    title = "VOIDBORN"
    tw = d.textlength(title, font=big) if big else 400
    d.text((w / 2 - tw / 2, 262), title, fill=(242, 238, 255, 255), font=big)

    sub = "a 3D space RTS  ·  create your own units"
    sw = d.textlength(sub, font=small) if small else 320
    d.text((w / 2 - sw / 2, 344), sub, fill=(178, 162, 224, 255), font=small)
    d.line([(w / 2 - 80, 336), (w / 2 + 80, 336)], fill=(139, 92, 255, 220), width=3)
    return img.convert("RGB")


def main():
    os.makedirs(SIDE, exist_ok=True)
    os.makedirs(LOAD, exist_ok=True)
    choir().save(os.path.join(SIDE, "choir.png"))
    maw().save(os.path.join(SIDE, "maw.png"))
    loading().save(os.path.join(LOAD, "voidborn.jpg"), quality=88)
    loading().save(os.path.join(LOAD, "voidborn.png"))
    for f in sorted(os.listdir(SIDE)):
        p = os.path.join(SIDE, f)
        print(f"  sidepics/{f:16} {os.path.getsize(p):7} bytes  {Image.open(p).size}")
    for f in sorted(os.listdir(LOAD)):
        p = os.path.join(LOAD, f)
        print(f"  bitmaps/loadpictures/{f:12} {os.path.getsize(p):7} bytes  {Image.open(p).size}")


if __name__ == "__main__":
    main()
