"""Writes the road crater decal texture (assets/textures/decals/crater.png, 256 x 256 RGBA).

Run from the project root: python3 tools/map_gen/crater_texture.py
A scorched, broken-asphalt crater seen from above: a dark burnt center, a rough ring of cracked
asphalt, cracks running out, soot fading at the edge (alpha). Crater (scripts/effects/crater.gd) uses it.
"""
import math, os, random
from PIL import Image, ImageDraw, ImageFilter

SIZE = 256
OUT = "assets/textures/decals/crater.png"
random.seed(7)

img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
px = img.load()
c = SIZE / 2
for y in range(SIZE):
    for x in range(SIZE):
        dx, dy = x - c + 0.5, y - c + 0.5
        r = math.hypot(dx, dy) / c
        a = math.atan2(dy, dx)
        # Rough rim radius: the crater edge is not round.
        rim = 0.55 + 0.06 * math.sin(a * 5 + 1.3) + 0.04 * math.sin(a * 11 + 0.4)
        noise = random.uniform(-0.05, 0.05)
        if r < rim * 0.75:
            shade = 18 + 20 * (r / rim) + random.randint(-6, 6)  # burnt hole
            alpha = 255
        elif r < rim:
            shade = 45 + 30 * ((r - rim * 0.75) / (rim * 0.25)) + random.randint(-12, 12)  # broken ring
            alpha = 255
        else:
            t = (r - rim) / (1.0 - rim + 1e-6)
            shade = 40 + 25 * t + random.randint(-8, 8)  # soot
            alpha = int(max(0.0, 1.0 - t - noise) ** 1.6 * 220)
        shade = max(0, min(255, int(shade)))
        px[x, y] = (shade, int(shade * 0.96), int(shade * 0.92), alpha)

draw = ImageDraw.Draw(img)
# Cracks running out from the rim.
for i in range(14):
    a = random.uniform(0, math.tau)
    r0 = random.uniform(0.45, 0.6) * c
    x, y = c + math.cos(a) * r0, c + math.sin(a) * r0
    for step in range(random.randint(4, 8)):
        a += random.uniform(-0.5, 0.5)
        length = random.uniform(6, 14)
        nx, ny = x + math.cos(a) * length, y + math.sin(a) * length
        draw.line((x, y, nx, ny), fill=(10, 10, 10, 230), width=random.choice((1, 2)))
        x, y = nx, ny
img = img.filter(ImageFilter.SMOOTH)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT)
print("wrote", OUT)
