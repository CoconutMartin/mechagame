"""Writes the building wear textures (phase 5b, user choice 2026-10-19):
assets/textures/decals/scorch.png (256 x 256 RGBA): a black burn mark with soot fading out (alpha).
assets/textures/decals/crack_overlay.png (512 x 512 RGBA): thick dark branching cracks (they wrap, so
the texture repeats) over a light dark film (a cracked chunk looks darker everywhere), for ChunkCracks.

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

# Crack overlay (user request 2026-10-21: stronger crack lines): thick dark branching cracks drawn
# here (wrap around the edges, so the texture repeats without seams) over a light dark film.
CS = 512
cracks = Image.new("RGBA", (CS, CS), (0, 0, 0, 0))
draw = ImageDraw.Draw(cracks)


def crack(x, y, angle, length, width, depth):
    while length > 0 and width >= 1:
        step = random.uniform(10, 22)
        angle += random.uniform(-0.6, 0.6)
        nx, ny = x + math.cos(angle) * step, y + math.sin(angle) * step
        for ox in (-CS, 0, CS):
            for oy in (-CS, 0, CS):
                draw.line([(x + ox, y + oy), (nx + ox, ny + oy)], fill=(14, 13, 12, 245), width=int(width))
        x, y, length = nx % CS, ny % CS, length - step
        width *= random.uniform(0.95, 1.0)
        if depth < 3 and random.random() < 0.18:
            crack(x, y, angle + random.choice((-1, 1)) * random.uniform(0.6, 1.2), length * 0.6, width * 0.55,
                  depth + 1)


for i in range(7):
    crack(random.uniform(0, CS), random.uniform(0, CS), random.uniform(0, math.tau), random.uniform(220, 420),
          random.uniform(7, 10), 0)
cracks = cracks.filter(ImageFilter.GaussianBlur(0.7))
out = Image.new("RGBA", (CS, CS), (0, 0, 0, 0))
cp, op = cracks.load(), out.load()
for y in range(CS):
    for x in range(CS):
        r, g, b, a = cp[x, y]
        film = 55 + random.randint(-10, 10)
        if a > film:
            op[x, y] = (r, g, b, a)
        else:
            op[x, y] = (20, 19, 18, film)
out.save("assets/textures/decals/crack_overlay.png")
print("wrote scorch.png and crack_overlay.png")
