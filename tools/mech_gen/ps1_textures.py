"""PS1-style skin textures for Sanggigilid (user request 2026-10-11, reference: PS1-era mech games).
Writes 64 x 64 grey detail textures to assets/textures/ps1/ (the shader lays them over the model's
own colors; 0.55 grey = no change):
  metal_panels.png  armor plates: panel seams, light top edges, rivets, vents, grime streaks
  joint_metal.png   joint metal: rings and noise
Run from the project root: python3 tools/mech_gen/ps1_textures.py
"""
import os
import random

from PIL import Image

SIZE = 64
OUT = "assets/textures/ps1"


def clamp(v):
    return max(0, min(255, int(v)))


def noise_image(rng, base, amount):
    return [[base + rng.randint(-amount, amount) for _ in range(SIZE)] for _ in range(SIZE)]


def mottle(img, rng, cell, amount):
    """Blotchy light and dark patches (cell x cell pixel blocks, softened by their neighbors)."""
    n = SIZE // cell
    grid = [[rng.randint(-amount, amount) for _ in range(n)] for _ in range(n)]
    for y in range(SIZE):
        for x in range(SIZE):
            gx, gy = x / cell - 0.5, y / cell - 0.5
            x0, y0 = int(gx // 1), int(gy // 1)
            fx, fy = gx - x0, gy - y0
            v = 0.0
            for dx, dy, w in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
                v += grid[(y0 + dy) % n][(x0 + dx) % n] * w
            img[y][x] += v


def add(img, x, y, v):
    img[y % SIZE][x % SIZE] += v


def save(img, name):
    out = Image.new("L", (SIZE, SIZE))
    out.putdata([clamp(v) for row in img for v in row])
    out.save(os.path.join(OUT, name))
    print("wrote", os.path.join(OUT, name))


def grime(img, rng, streaks):
    """Dark vertical streaks (dirt running down)."""
    for _ in range(streaks):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        length = rng.randint(4, 14)
        for i in range(length):
            add(img, x, y + i, -rng.randint(10, 24) * (1 - i / length))


def metal_panels(rng):
    img = noise_image(rng, 150, 9)
    mottle(img, rng, 8, 16)
    # Panels: a 2 x 2 grid of uneven plates; each plate a little lighter or darker.
    cuts_x = [0, rng.randint(26, 38)]
    cuts_y = [0, rng.randint(22, 30), rng.randint(44, 52)]
    for yi, y0 in enumerate(cuts_y):
        y1 = cuts_y[yi + 1] if yi + 1 < len(cuts_y) else SIZE
        for xi, x0 in enumerate(cuts_x):
            x1 = cuts_x[xi + 1] if xi + 1 < len(cuts_x) else SIZE
            shade = rng.randint(-14, 14)
            for y in range(y0, y1):
                for x in range(x0, x1):
                    img[y][x] += shade
            # Seam (dark line) and a light top and left edge, like a raised plate.
            for x in range(x0, x1):
                img[y0][x] -= 60
                add(img, x, y0 + 1, 28)
            for y in range(y0, y1):
                img[y][x0] -= 60
                add(img, x0 + 1, y, 20)
            # Rivets near the corners.
            for cx, cy in ((x0 + 3, y0 + 3), (x1 - 3, y0 + 3), (x0 + 3, y1 - 3), (x1 - 3, y1 - 3)):
                add(img, cx, cy, 45)
                add(img, cx + 1, cy + 1, -35)
    # Vents: short dark slots in one plate.
    vx, vy = rng.randint(6, 20), rng.randint(32, 40)
    for i in range(4):
        for x in range(vx, vx + 8):
            add(img, x, vy + i * 2, -55)
    # A small light hatch line and scratches.
    for _ in range(10):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        for i in range(rng.randint(2, 5)):
            add(img, x + i, y, 30)
    grime(img, rng, 14)
    return img


def joint_metal(rng):
    img = noise_image(rng, 140, 8)
    mottle(img, rng, 16, 10)
    for y in range(0, SIZE, 6):
        for x in range(SIZE):
            img[y][x] -= 30
            add(img, x, y + 1, 18)
    grime(img, rng, 8)
    return img


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save(metal_panels(random.Random(11)), "metal_panels.png")
    save(joint_metal(random.Random(13)), "joint_metal.png")
