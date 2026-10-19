"""Writes the building wear textures (phase 5b, user choice 2026-10-19):
assets/textures/decals/scorch.png (256 x 256 RGBA): a black burn mark with soot fading out (alpha).
assets/textures/decals/crack_overlay.png (512 x 512 RGBA): the cracks of cracks.png over a light dark
film (so a cracked chunk looks darker everywhere), for ChunkCracks.

Run from the project root: python3 tools/map_gen/wear_textures.py
"""
import math, random
from PIL import Image, ImageDraw, ImageFilter

random.seed(11)

# Scorch: dark center, rough soot edge, a few streaks.
SIZE = 256
img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
px = img.load()
c = SIZE / 2
for y in range(SIZE):
    for x in range(SIZE):
        dx, dy = x - c + 0.5, y - c + 0.5
        r = math.hypot(dx, dy) / c
        a = math.atan2(dy, dx)
        edge = 0.7 + 0.12 * math.sin(a * 6 + 0.7) + 0.07 * math.sin(a * 13 + 2.1)
        t = min(r / edge, 1.0)
        shade = int(12 + 30 * t + random.randint(-6, 6))
        alpha = int(max(0.0, 1.0 - t ** 1.8 - random.uniform(0.0, 0.08)) * 240)
        px[x, y] = (shade, int(shade * 0.95), int(shade * 0.9), max(0, alpha))
draw = ImageDraw.Draw(img)
for i in range(10):
    a = random.uniform(0, math.tau)
    r0, r1 = random.uniform(0.2, 0.4) * c, random.uniform(0.7, 0.95) * c
    draw.line([(c + math.cos(a) * r0, c + math.sin(a) * r0), (c + math.cos(a) * r1, c + math.sin(a) * r1)],
              fill=(10, 10, 9, 150), width=random.randint(2, 5))
img = img.filter(ImageFilter.GaussianBlur(1.2))
img.save("assets/textures/decals/scorch.png")

# Crack overlay: the existing cracks with a dark film under them.
cracks = Image.open("assets/textures/decals/cracks.png").convert("RGBA")
out = Image.new("RGBA", cracks.size, (0, 0, 0, 0))
cp, op = cracks.load(), out.load()
for y in range(cracks.size[1]):
    for x in range(cracks.size[0]):
        r, g, b, a = cp[x, y]
        film = 70 + random.randint(-12, 12)
        op[x, y] = (r, g, b, max(a, film))
out.save("assets/textures/decals/crack_overlay.png")
print("wrote scorch.png and crack_overlay.png")
