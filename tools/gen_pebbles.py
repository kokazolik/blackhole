"""Текстуры гальки.

assets/player/pebble_<тип>.png  — галька игрока, свой облик для каждого типа тела
                                  (каменная, металлическая, углистая, ледяная, хондрит)
assets/pebbles/pebble_atlas.png — чужие гальки: строки — материалы (силикаты, металл,
                                  углерод, лёд), столбцы — 4 формы; клетка 128×128

Галька гладкая и округлая (её обтесали удары и газ), на срезе видны вкрапления:
круглые застывшие капли-хондры, зёрна металла, мелкая крапинка. Освещение
звездой добавляет шейдер, здесь только лёгкое затенение к краю.
Запуск: python3 tools/gen_pebbles.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def value_noise(rng, size, cells):
    g = rng.random((cells + 1, cells + 1))
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)
    return np.asarray(img, dtype=float) / 255.0


def fbm(rng, size, base=4, octaves=5):
    out = np.zeros((size, size))
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        out += value_noise(rng, size, base * 2 ** o) * amp
        total += amp
        amp *= 0.5
    return out / total


def pebble(rng, size, palette, radius=0.36, chondrules=8, metal_specks=0, frost=0.0, sheen=0.0, cracks=0):
    """palette: (тёмный, светлый) цвет основы. Возвращает RGBA float."""
    yy, xx = (np.mgrid[0:size, 0:size] + 0.5) / size - 0.5
    # Неровный, но гладкий контур: эллипс с плавными буграми.
    ang = np.arctan2(yy, xx)
    rot = rng.uniform(0, np.pi)
    stretch = rng.uniform(0.78, 0.95)
    xr = xx * np.cos(rot) + yy * np.sin(rot)
    yr = -xx * np.sin(rot) + yy * np.cos(rot)
    rad = np.sqrt(xr ** 2 + (yr / stretch) ** 2)
    bumps = sum(rng.uniform(0.0, 0.035) * np.cos(k * ang + rng.uniform(0, 6.28)) for k in (2, 3, 5))
    edge = radius * (1.0 + bumps)
    d = rad / edge  # 1 на краю
    alpha = np.clip((1.0 - d) * size * radius * 0.9, 0, 1)

    # Основа: плавные пятна и мелкая крапинка.
    blot = fbm(rng, size, 3, 4)
    speck = fbm(rng, size, 24, 2)
    t = np.clip(0.35 + 0.9 * (blot - 0.5) + 0.5 * (speck - 0.5), 0, 1)
    dark, light = np.array(palette[0]), np.array(palette[1])
    rgb = dark[None, None] * (1 - t[..., None]) + light[None, None] * t[..., None]

    # Хондры: круглые светлые капли с тёмной каймой.
    for _ in range(chondrules):
        cx, cy = rng.uniform(-0.25, 0.25, 2)
        r = rng.uniform(0.018, 0.05)
        dd = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
        rim = np.exp(-((dd - 1.0) * 4) ** 2) * 0.45
        core = np.clip((1.0 - dd) * 3, 0, 1) * 0.12
        rgb = rgb * (1 - rim[..., None]) + light[None, None] * 1.15 * core[..., None]
    # Зёрна металла: мелкие яркие точки.
    for _ in range(metal_specks):
        cx, cy = rng.uniform(-0.3, 0.3, 2)
        dd = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        rgb += np.exp(-(dd / rng.uniform(0.006, 0.012)) ** 2)[..., None] * 0.6
    # Металл: полосы отражений (видманштеттенова решётка на срезе железного метеорита).
    if sheen > 0:
        for a in rng.uniform(0, np.pi, 3):
            band = np.sin((xx * np.cos(a) + yy * np.sin(a)) * rng.uniform(60, 90) + rng.uniform(0, 6.28))
            rgb += (np.clip(band, 0.85, 1.0) - 0.85)[..., None] * sheen * fbm(rng, size, 4, 2)[..., None] * 2.0
    # Углистое вещество: тонкие светлые прожилки (следы воды в старом теле).
    for _ in range(cracks):
        cx, cy = rng.uniform(-0.25, 0.25, 2)
        a = rng.uniform(0, np.pi)
        along = (xx - cx) * np.cos(a) + (yy - cy) * np.sin(a)
        across = -(xx - cx) * np.sin(a) + (yy - cy) * np.cos(a) + 0.006 * np.sin(along * 30)
        line = np.exp(-(across / 0.004) ** 2) * np.exp(-(along / rng.uniform(0.08, 0.16)) ** 2)
        rgb += line[..., None] * np.array([0.35, 0.3, 0.26])[None, None]
    # Иней: светлые кристаллики по краю и пятнами.
    if frost > 0:
        f = fbm(rng, size, 10, 3)
        fm = np.clip((f - 0.45) * 4, 0, 1) * frost * (0.4 + 0.6 * np.clip(d, 0, 1))
        rgb = rgb * (1 - fm[..., None]) + np.array([0.92, 0.97, 1.0])[None, None] * fm[..., None]

    # Затенение к краю: галька выпуклая.
    shade = 0.72 + 0.28 * np.sqrt(np.clip(1 - d ** 2, 0, 1))
    rgb = np.clip(rgb * shade[..., None], 0, 1)
    return np.dstack([rgb, alpha])


def to_img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGBA")


def main():
    rng = np.random.default_rng(7)
    # Галька игрока: облик зависит от типа тела.
    bodies = {
        "chondrite": dict(palette=((0.42, 0.38, 0.33), (0.92, 0.88, 0.8)), chondrules=22, metal_specks=12),
        "silicate": dict(palette=((0.5, 0.4, 0.29), (0.98, 0.86, 0.66)), chondrules=8, metal_specks=3),
        "metal": dict(palette=((0.36, 0.39, 0.45), (0.8, 0.84, 0.92)), chondrules=0, metal_specks=26, sheen=0.5),
        "carbon": dict(palette=((0.2, 0.16, 0.14), (0.56, 0.46, 0.4)), chondrules=4, metal_specks=2, cracks=7),
        "ice": dict(palette=((0.55, 0.68, 0.8), (0.93, 0.98, 1.0)), chondrules=2, frost=1.0),
    }
    for key, kw in bodies.items():
        img = pebble(np.random.default_rng(11), 512, **kw)
        to_img(img).resize((256, 256), Image.LANCZOS).save(ROOT / "assets" / "player" / f"pebble_{key}.png")

    palettes = {
        "silicate": dict(palette=((0.45, 0.37, 0.27), (0.9, 0.8, 0.62)), chondrules=10, metal_specks=3),
        "metal": dict(palette=((0.3, 0.32, 0.36), (0.72, 0.76, 0.84)), chondrules=2, metal_specks=18),
        "carbon": dict(palette=((0.12, 0.09, 0.08), (0.42, 0.32, 0.27)), chondrules=6, metal_specks=2),
        "ice": dict(palette=((0.52, 0.62, 0.7), (0.9, 0.96, 1.0)), chondrules=3, metal_specks=0, frost=0.9),
    }
    cell = 128
    atlas = Image.new("RGBA", (cell * 4, cell * 4))
    for row, key in enumerate(["silicate", "metal", "carbon", "ice"]):
        for col in range(4):
            a = pebble(rng, cell * 2, **palettes[key])
            atlas.paste(to_img(a).resize((cell, cell), Image.LANCZOS), (col * cell, row * cell))
    (ROOT / "assets" / "pebbles").mkdir(exist_ok=True)
    atlas.save(ROOT / "assets" / "pebbles" / "pebble_atlas.png")
    print("Гальки сохранены")


if __name__ == "__main__":
    main()
