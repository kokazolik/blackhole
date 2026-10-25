"""Генерирует атлас текстур пылинок: assets/dust/dust_atlas.png.

Строки атласа — материалы (силикаты, металл, углерод, лёд), столбцы — 4 варианта формы.
Клетка 64×64. Рисуем в 4× разрешении и уменьшаем для сглаживания.
Запуск: python3 tools/gen_dust_atlas.py
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

CELL = 64
SS = 4  # суперсэмплинг
VARIANTS = 4
MATERIALS = ["silicate", "metal", "carbon", "ice"]
LIGHT = (-0.6, -0.8)  # свет сверху слева

OUT = Path(__file__).resolve().parent.parent / "assets" / "dust" / "dust_atlas.png"


def shade(color, k):
    return tuple(max(0, min(255, int(c * k))) for c in color[:3]) + (color[3] if len(color) > 3 else 255,)


def lit(nx, ny):
    """Освещённость грани по направлению её нормали (0..1)."""
    l = -(nx * LIGHT[0] + ny * LIGHT[1])
    return 0.5 + 0.5 * l


def jagged_polygon(rng, cx, cy, r, n, jitter):
    pts = []
    for i in range(n):
        a = (i + rng.uniform(-0.3, 0.3)) / n * math.tau
        rr = r * rng.uniform(1.0 - jitter, 1.0)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    return pts


def draw_silicate(rng, d, size):
    # Угловатое каменное зерно с гранями: каждая грань освещена по-своему.
    c = size / 2
    pts = jagged_polygon(rng, c, c, size * 0.42, rng.randint(6, 9), 0.35)
    base = (222, 196, 148, 255)
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        mx, my = (a[0] + b[0]) / 2 - c, (a[1] + b[1]) / 2 - c
        ln = math.hypot(mx, my) or 1
        k = 0.55 + 0.6 * lit(mx / ln, my / ln)
        d.polygon([(c, c), a, b], fill=shade(base, k))
    # Внутренние сколы.
    for _ in range(3):
        p = jagged_polygon(rng, c + rng.uniform(-size * 0.12, size * 0.12), c + rng.uniform(-size * 0.12, size * 0.12),
                           size * rng.uniform(0.06, 0.12), 5, 0.4)
        d.polygon(p, fill=shade(base, rng.uniform(0.7, 1.15)))
    # Светлая кромка по освещённой стороне.
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        mx, my = (a[0] + b[0]) / 2 - c, (a[1] + b[1]) / 2 - c
        ln = math.hypot(mx, my) or 1
        if lit(mx / ln, my / ln) > 0.6:
            d.line([a, b], fill=(255, 240, 210, 220), width=SS * 2)


def draw_metal(rng, d, size):
    # Плотная округлая капля железа-никеля с резким бликом.
    c = size / 2
    r = size * 0.36
    base = (150, 165, 190, 255)
    # Форма самородка одна на все слои, чтобы затенение повторяло её.
    shape = [rng.uniform(0.78, 1.0) for _ in range(10)]
    stretch = rng.uniform(0.75, 1.0)
    steps = 24
    for i in range(steps):
        t = i / steps
        rr = r * (1 - t * 0.9)
        ox, oy = LIGHT[0] * r * 0.35 * t, LIGHT[1] * r * 0.35 * t
        k = 0.45 + 0.8 * t
        pts = []
        for j in range(40):
            a = j / 40 * math.tau
            f = j / 40 * len(shape)
            m = shape[int(f) % len(shape)] * (1 - f % 1) + shape[(int(f) + 1) % len(shape)] * (f % 1)
            pts.append((c + ox + math.cos(a) * rr * m, c + oy + math.sin(a) * rr * m * stretch))
        d.polygon(pts, fill=shade(base, k))
    hx, hy = c + LIGHT[0] * r * 0.45, c + LIGHT[1] * r * 0.45
    d.ellipse([hx - r * 0.18, hy - r * 0.14, hx + r * 0.18, hy + r * 0.14], fill=(255, 255, 255, 255))


def draw_carbon(rng, d, size):
    # Рыхлый фрактальный агрегат сажи: много мелких сфер, слипшихся цепочкой.
    c = size / 2
    base = (178, 128, 106, 255)
    pos = [(c, c)]
    blobs = []
    for _ in range(rng.randint(10, 16)):
        px, py = rng.choice(pos)
        a = rng.uniform(0, math.tau)
        rr = size * rng.uniform(0.06, 0.1)
        nx, ny = px + math.cos(a) * rr * 1.5, py + math.sin(a) * rr * 1.5
        if math.hypot(nx - c, ny - c) > size * 0.36:
            continue
        pos.append((nx, ny))
        blobs.append((nx, ny, rr))
    blobs.append((c, c, size * 0.1))
    for x, y, rr in blobs:
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=shade(base, 0.55))
    for x, y, rr in blobs:
        ox, oy = LIGHT[0] * rr * 0.3, LIGHT[1] * rr * 0.3
        d.ellipse([x + ox - rr * 0.6, y + oy - rr * 0.6, x + ox + rr * 0.6, y + oy + rr * 0.6], fill=shade(base, 0.95))


def draw_ice(rng, d, size):
    # Ледяное зерно: шестигранник, полупрозрачная середина, яркая кромка и искра.
    c = size / 2
    r = size * 0.38
    rot = rng.uniform(0, math.tau)
    pts = []
    for i in range(6):
        a = rot + i / 6 * math.tau
        rr = r * rng.uniform(0.82, 1.0)
        pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr))
    d.polygon(pts, fill=(170, 225, 255, 150))
    inner = [(c + (x - c) * 0.6 + LIGHT[0] * r * 0.1, c + (y - c) * 0.6 + LIGHT[1] * r * 0.1) for x, y in pts]
    d.polygon(inner, fill=(215, 245, 255, 190))
    d.line(pts + [pts[0]], fill=(240, 252, 255, 255), width=SS * 2)
    sx, sy = c + LIGHT[0] * r * 0.4, c + LIGHT[1] * r * 0.4
    L = r * 0.45
    d.line([(sx - L, sy), (sx + L, sy)], fill=(255, 255, 255, 255), width=SS)
    d.line([(sx, sy - L), (sx, sy + L)], fill=(255, 255, 255, 255), width=SS)


DRAW = {"silicate": draw_silicate, "metal": draw_metal, "carbon": draw_carbon, "ice": draw_ice}


def main():
    big = CELL * SS
    atlas = Image.new("RGBA", (CELL * VARIANTS, CELL * len(MATERIALS)), (0, 0, 0, 0))
    for row, mat in enumerate(MATERIALS):
        for col in range(VARIANTS):
            rng = random.Random(row * 100 + col + 7)
            img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
            DRAW[mat](rng, ImageDraw.Draw(img), big)
            img = img.filter(ImageFilter.GaussianBlur(SS * 0.4)).resize((CELL, CELL), Image.LANCZOS)
            atlas.paste(img, (col * CELL, row * CELL))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT)
    print("Атлас сохранён:", OUT)


if __name__ == "__main__":
    main()
