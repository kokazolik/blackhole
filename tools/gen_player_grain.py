"""Генерирует текстуру пылинки игрока: assets/player/player_grain.png.

Игрок — рыхлый агрегат: много мелких зёрен разной формы, слипшихся в один комок.
Текстура в оттенках серого, цвет тела задаётся в игре через modulate по составу.
Рисуем в 4× разрешении и уменьшаем для сглаживания.
Запуск: python3 tools/gen_player_grain.py
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 256
SS = 4
LIGHT = (-0.6, -0.8)  # свет сверху слева, как у пыли в атласе

OUT = Path(__file__).resolve().parent.parent / "assets" / "player" / "player_grain.png"


def grey(k, a=255):
    v = max(0, min(255, int(255 * k)))
    return (v, v, v, a)


def lit(nx, ny):
    return 0.5 + 0.5 * -(nx * LIGHT[0] + ny * LIGHT[1])


def chip(rng, d, cx, cy, r):
    """Угловатое зерно: грани освещены по направлению нормали."""
    n = rng.randint(5, 8)
    pts = []
    for i in range(n):
        a = (i + rng.uniform(-0.3, 0.3)) / n * math.tau
        rr = r * rng.uniform(0.7, 1.0)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        mx, my = (a[0] + b[0]) / 2 - cx, (a[1] + b[1]) / 2 - cy
        ln = math.hypot(mx, my) or 1
        d.polygon([(cx, cy), a, b], fill=grey(0.35 + 0.6 * lit(mx / ln, my / ln)))


def blob(d, cx, cy, r):
    """Округлое зерно: затенение слоями со смещением к свету."""
    steps = 14
    for i in range(steps):
        t = i / steps
        rr = r * (1 - t * 0.85)
        ox, oy = LIGHT[0] * r * 0.35 * t, LIGHT[1] * r * 0.35 * t
        d.ellipse([cx + ox - rr, cy + oy - rr, cx + ox + rr, cy + oy + rr], fill=grey(0.32 + 0.66 * t))


def main():
    rng = random.Random(42)
    big = SIZE * SS
    c = big / 2
    body_r = big * 0.36
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Зёрна раскладываем от края к центру: дальние (по свету) рисуются первыми.
    grains = []
    for _ in range(120):
        a = rng.uniform(0, math.tau)
        # Чуть неровный силуэт: радиус зависит от угла.
        edge = body_r * (0.85 + 0.15 * math.sin(a * 3 + 1.3) * math.cos(a * 2))
        dist = edge * rng.uniform(0, 1) ** 0.6
        x, y = c + math.cos(a) * dist, c + math.sin(a) * dist
        r = big * rng.uniform(0.045, 0.085) * (1.0 - 0.3 * dist / body_r)
        grains.append((x, y, r))
    grains.sort(key=lambda g: (g[0] - c) * LIGHT[0] + (g[1] - c) * LIGHT[1])

    # Тёмная подложка, чтобы между зёрнами не просвечивало.
    for x, y, r in grains:
        d.ellipse([x - r * 0.9, y - r * 0.9, x + r * 0.9, y + r * 0.9], fill=grey(0.18))
    for x, y, r in grains:
        if rng.random() < 0.55:
            chip(rng, d, x, y, r)
        else:
            blob(d, x, y, r)

    # Общее затенение комка: теневая сторона темнее.
    mask = Image.new("L", (big, big), 0)
    md = ImageDraw.Draw(mask)
    for i in range(24):
        t = i / 24
        ox, oy = -LIGHT[0] * body_r * 0.9, -LIGHT[1] * body_r * 0.9
        rr = body_r * (1.1 - t * 0.9)
        md.ellipse([c + ox - rr, c + oy - rr, c + ox + rr, c + oy + rr], fill=int(6 + t * 6) * (i + 1) // 3)
    mask = mask.filter(ImageFilter.GaussianBlur(big * 0.04))
    dark = Image.new("RGBA", (big, big), (0, 0, 0, 255))
    alpha = img.getchannel("A")
    shaded = Image.composite(dark, img, mask)
    shaded.putalpha(alpha)

    out = shaded.filter(ImageFilter.GaussianBlur(SS * 0.4)).resize((SIZE, SIZE), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT)
    print("Текстура сохранена:", OUT)


if __name__ == "__main__":
    main()
