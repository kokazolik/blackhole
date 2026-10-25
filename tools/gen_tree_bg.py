"""Рисованный фон древа навыков: тёмный «расписной» космос мазками кисти.

Цветовые облака размазываются вдоль завихрений (свёртка вдоль линий потока),
поэтому получаются мазки, как на картине, а не фотография. Поверх — золотые
звёзды-искры и тёмная виньетка, чтобы узлы древа читались.

assets/ui/tree_bg.png
Запуск: python3 tools/gen_tree_bg.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "ui" / "tree_bg.png"
W, H = 1600, 900


def smooth_noise(rng, w, h, cells):
    """Плавный шум: случайная сетка, увеличенная бикубически."""
    small = rng.random((max(2, int(h / w * cells)), cells))
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(img, dtype=float) / 255.0


def fbm(rng, w, h, octaves=(4, 8, 16, 32), gains=(1.0, 0.5, 0.25, 0.12)):
    n = sum(g * smooth_noise(rng, w, h, c) for c, g in zip(octaves, gains))
    n -= n.min()
    return n / n.max()


def lic(rgb, angle, steps=22, step_len=1.8):
    """Размазывает картинку вдоль поля направлений — получаются мазки кисти."""
    h, w = angle.shape
    ys, xs = np.mgrid[0:h, 0:w].astype(float)
    acc = rgb.copy()
    total = 1.0
    for sign in (1.0, -1.0):
        px, py = xs.copy(), ys.copy()
        for i in range(steps):
            ix = np.clip(px.astype(int), 0, w - 1)
            iy = np.clip(py.astype(int), 0, h - 1)
            a = angle[iy, ix]
            px += np.cos(a) * step_len * sign
            py += np.sin(a) * step_len * sign
            ix = np.clip(px.astype(int), 0, w - 1)
            iy = np.clip(py.astype(int), 0, h - 1)
            wgt = 1.0 - i / steps
            acc += rgb[iy, ix] * wgt
            total += wgt
    return acc / total


def main():
    rng = np.random.default_rng(7)
    # Палитра: глубокий индиго, фиолет, бирюза и тёплые розово-золотые отсветы.
    base = np.array([0.025, 0.03, 0.08])
    palette = [
        (np.array([0.20, 0.10, 0.38]), 0.9),  # фиолет
        (np.array([0.05, 0.22, 0.32]), 0.8),  # бирюза
        (np.array([0.38, 0.12, 0.26]), 0.55),  # маджента
        (np.array([0.45, 0.30, 0.12]), 0.35),  # тёплое золото
    ]
    rgb = np.broadcast_to(base, (H, W, 3)).copy()
    for color, strength in palette:
        m = fbm(rng, W, H)
        m = np.clip((m - 0.45) / 0.4, 0, 1) ** 1.6 * strength
        rgb = rgb * (1 - m[..., None]) + color * m[..., None]
    # Светлый «рукав» по диагонали, как Млечный Путь на картине.
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    band = np.exp(-((yy - H * 0.55 - (xx - W * 0.5) * -0.35) / (H * 0.22)) ** 2)
    band *= 0.6 + 0.4 * fbm(rng, W, H)
    rgb += band[..., None] * np.array([0.10, 0.08, 0.16])
    # Мелкая неровность красочного слоя: зерно, которое свёртка вытянет в мазки.
    grain = np.asarray(Image.fromarray((rng.random((H // 2, W // 2)) * 255).astype(np.uint8)).resize((W, H), Image.BILINEAR), dtype=float) / 255.0
    rgb *= (0.6 + 0.8 * grain)[..., None]

    # Поле завихрений: угол из шума, плюс несколько вихрей-спиралей.
    angle = fbm(rng, W, H, (3, 6, 12), (1.0, 0.5, 0.25)) * np.pi * 3.0
    for _ in range(7):
        cx, cy = rng.uniform(0.15, 0.85) * W, rng.uniform(0.2, 0.8) * H
        dx, dy = xx - cx, yy - cy
        d = np.sqrt(dx * dx + dy * dy)
        swirl = np.arctan2(dy, dx) + np.pi / 2 + 0.35
        k = np.exp(-d / (W * 0.12))
        angle = angle * (1 - k) + swirl * k
    rgb = lic(rgb, angle)
    # Лёгкая постеризация оттенков даёт ощущение красочных пятен.
    rgb = np.round(rgb * 48) / 48

    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB")
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    rgb = np.asarray(img, dtype=float) / 255.0

    # Звёзды-искры: мелкие точки и редкие золотые четырёхлучевые.
    for _ in range(900):
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        r = rng.uniform(0.5, 1.2)
        a = rng.uniform(0.15, 0.6)
        col = np.array([1.0, 0.92, 0.75]) if rng.random() < 0.5 else np.array([0.8, 0.88, 1.0])
        _star(rgb, x, y, r, col, a, 0)
    for _ in range(26):
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        _star(rgb, x, y, rng.uniform(1.0, 1.8), np.array([1.0, 0.85, 0.5]), rng.uniform(0.6, 0.9), rng.uniform(7, 16))

    # Виньетка: края темнее, центр, где древо, чуть светлее.
    d = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
    rgb *= np.clip(1.08 - 0.55 * d ** 2, 0.35, 1.0)[..., None]

    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB").save(OUT, optimize=True)
    print("Фон древа сохранён в", OUT)


def _star(rgb, x, y, r, col, a, spikes):
    half = int(max(4, r * 5, spikes))
    ix, iy = int(x), int(y)
    y0, y1 = max(0, iy - half), min(H, iy + half + 1)
    x0, x1 = max(0, ix - half), min(W, ix + half + 1)
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(float)
    dx, dy = xx - x, yy - y
    d2 = dx * dx + dy * dy
    spot = np.exp(-d2 / (2 * r * r)) + 0.12 * np.exp(-d2 / (2 * (r * 3) ** 2))
    if spikes:
        spot += 0.6 * np.exp(-dy * dy / 0.5) * np.exp(-np.abs(dx) / (spikes * 0.3))
        spot += 0.6 * np.exp(-dx * dx / 0.5) * np.exp(-np.abs(dy) / (spikes * 0.3))
    spot = np.clip(spot * a, 0, 1)[..., None]
    rgb[y0:y1, x0:x1] = rgb[y0:y1, x0:x1] * (1 - spot) + col * spot


if __name__ == "__main__":
    main()
