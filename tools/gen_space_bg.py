"""Генерирует бесшовные текстуры космоса.

assets/space/nebula.png     — туманности отдельными пятнами: волокна, тёмные прожилки, яркие края;
                              большая часть неба остаётся чёрной
assets/space/stars_far.png  — тысячи слабых звёзд разных цветов и крошечные далёкие галактики
assets/space/stars_near.png — меньше звёзд, ярче; у самых ярких лучи, как на снимках Hubble
assets/space/bokeh.png      — размытые пылинки переднего плана (почти прозрачные)

Бесшовность даёт шум, отфильтрованный в частотной области, и рисование «по модулю» размера.
Запуск: python3 tools/gen_space_bg.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets" / "space"
SIZE = 1024

# Цвета звёзд по температуре: от голубых до красных. Веса — сколько таких на небе
# (глазом и камерой видно больше белых и жёлтых, чем голубых и красных).
STAR_COLORS = [
    ((0.62, 0.74, 1.0), 0.12),  # горячие голубые
    ((0.82, 0.88, 1.0), 0.28),
    ((1.0, 0.98, 0.95), 0.30),  # белые
    ((1.0, 0.9, 0.72), 0.18),   # жёлтые
    ((1.0, 0.74, 0.5), 0.09),   # оранжевые
    ((1.0, 0.55, 0.42), 0.03),  # красные карлики и гиганты
]


def tileable_noise(rng, size, slope, low_cut=1.0):
    """Шум со спектром 1/f^slope: чем больше slope, тем крупнее и мягче детали."""
    white = rng.standard_normal((size, size))
    f = np.fft.fft2(white)
    fx = np.fft.fftfreq(size)[:, None] * size
    fy = np.fft.fftfreq(size)[None, :] * size
    k = np.sqrt(fx * fx + fy * fy)
    k[0, 0] = 1.0
    amp = 1.0 / k ** slope
    amp[k < low_cut] = 0.0
    n = np.real(np.fft.ifft2(f * amp))
    n -= n.min()
    return n / n.max()


def to_image(rgb, a):
    img = np.dstack([np.clip(rgb, 0, 1), np.clip(a, 0, 1)])
    return Image.fromarray((img * 255).astype(np.uint8), "RGBA")


def nebula(rng):
    # Маска: облака занимают ~15% неба, остальное чёрное.
    big = tileable_noise(rng, SIZE, 2.2, low_cut=1.0)
    mask = np.clip((big - 0.62) / 0.2, 0.0, 1.0) ** 1.5
    # Волокнистая структура: гребневый шум даёт нити.
    fil = tileable_noise(rng, SIZE, 1.5, low_cut=3.0)
    ridges = 1.0 - np.abs(fil - 0.5) * 2.0
    fine = tileable_noise(rng, SIZE, 1.1, low_cut=6.0)
    density = mask * (0.35 + 0.65 * ridges ** 3) * (0.7 + 0.6 * fine)
    # Тёмные пылевые прожилки поверх свечения.
    lanes = tileable_noise(rng, SIZE, 1.7, low_cut=2.0)
    density *= np.clip((lanes - 0.25) * 2.5, 0.15, 1.0)
    # Цвет: ионизированный водород (розово-красный), кислород (бирюза) и отражённый свет (синий).
    h_alpha = np.array([0.95, 0.35, 0.45])
    oxygen = np.array([0.3, 0.75, 0.8])
    reflect = np.array([0.35, 0.5, 1.0])
    mix1 = tileable_noise(rng, SIZE, 2.0, low_cut=1.0)[..., None]
    mix2 = tileable_noise(rng, SIZE, 2.0, low_cut=1.0)[..., None]
    rgb = h_alpha * mix1 + oxygen * (1 - mix1) * mix2 + reflect * (1 - mix1) * (1 - mix2)
    rgb = rgb / np.maximum(rgb.max(axis=2, keepdims=True), 1e-4)
    # Яркие края облаков: где плотность быстро растёт.
    gy, gx = np.gradient(density)
    edge = np.clip(np.sqrt(gx * gx + gy * gy) * 40.0, 0.0, 1.0)
    a = density * 0.32 + edge * mask * 0.12
    return to_image(rgb, a)


def splat(img, x, y, r, color, a, spikes=0.0):
    """Звезда: гауссово ядро с ореолом, по желанию с четырьмя лучами. Рисуется по модулю размера."""
    half = int(max(4, r * 6, spikes))
    yy, xx = np.mgrid[-half:half + 1, -half:half + 1]
    ix, iy = int(x), int(y)
    dx, dy = xx - (x - ix), yy - (y - iy)
    d2 = dx * dx + dy * dy
    spot = np.exp(-d2 / (2 * r * r)) + 0.08 * np.exp(-d2 / (2 * (r * 3.5) ** 2))
    if spikes > 0:
        # Лучи дифракции, как у телескопа: тонкие кресты, быстро гаснущие.
        thin = 0.45
        cross = np.exp(-dy * dy / (2 * thin * thin)) * np.exp(-np.abs(dx) / (spikes * 0.35))
        cross += np.exp(-dx * dx / (2 * thin * thin)) * np.exp(-np.abs(dy) / (spikes * 0.35))
        spot = spot + cross * 0.5
    spot = np.clip(spot * a, 0, 1)
    ys = (iy + yy) % SIZE
    xs = (ix + xx) % SIZE
    old_a = img[ys, xs, 3]
    new_a = 1 - (1 - old_a) * (1 - spot)
    w = spot / np.maximum(new_a, 1e-5)
    for c in range(3):
        img[ys, xs, c] = img[ys, xs, c] * (1 - w) + color[c] * w
    img[ys, xs, 3] = new_a


def galaxy(img, rng, x, y):
    """Крошечная далёкая галактика: эллипс с ядром, у части — намёк на спиральные рукава."""
    size = rng.uniform(2.5, 6.0)
    angle = rng.uniform(0, np.pi)
    flat = rng.uniform(0.3, 1.0)
    color = np.array(rng.choice([[1.0, 0.85, 0.65], [0.85, 0.9, 1.0], [1.0, 0.75, 0.6]]))
    half = int(size * 3)
    yy, xx = np.mgrid[-half:half + 1, -half:half + 1].astype(float)
    c, s = np.cos(angle), np.sin(angle)
    u = (xx * c + yy * s) / size
    v = (-xx * s + yy * c) / (size * flat)
    r = np.sqrt(u * u + v * v)
    disk = np.exp(-r * 2.2)
    if rng.random() < 0.5:
        theta = np.arctan2(v, u)
        disk *= 0.6 + 0.4 * np.cos(2 * theta - r * 5.0)
    core = np.exp(-r * r * 12.0)
    spot = np.clip((disk * 0.55 + core * 0.8) * rng.uniform(0.6, 1.0), 0, 1)
    ys = (int(y) + yy.astype(int)) % SIZE
    xs = (int(x) + xx.astype(int)) % SIZE
    old_a = img[ys, xs, 3]
    new_a = 1 - (1 - old_a) * (1 - spot)
    w = spot / np.maximum(new_a, 1e-5)
    for ch in range(3):
        img[ys, xs, ch] = img[ys, xs, ch] * (1 - w) + color[ch] * w
    img[ys, xs, 3] = new_a


def pick_color(rng):
    colors = [c for c, _ in STAR_COLORS]
    weights = np.array([w for _, w in STAR_COLORS])
    return colors[rng.choice(len(colors), p=weights / weights.sum())]


def stars_far(rng):
    img = np.zeros((SIZE, SIZE, 4))
    # Яркость по степенному закону: слабых звёзд намного больше, чем ярких.
    for _ in range(2600):
        a = min(1.0, 0.05 + 0.6 * rng.pareto(2.2) * 0.25)
        splat(img, *rng.uniform(0, SIZE, 2), rng.uniform(0.45, 0.7), pick_color(rng), a)
    for _ in range(28):
        galaxy(img, rng, *rng.uniform(0, SIZE, 2))
    return to_image(img[..., :3], img[..., 3])


def stars_near(rng):
    img = np.zeros((SIZE, SIZE, 4))
    for _ in range(220):
        a = min(1.0, 0.2 + rng.pareto(1.8) * 0.25)
        splat(img, *rng.uniform(0, SIZE, 2), rng.uniform(0.6, 0.95), pick_color(rng), a)
    for _ in range(7):
        splat(img, *rng.uniform(0, SIZE, 2), rng.uniform(0.9, 1.3), pick_color(rng), 1.0, spikes=rng.uniform(10, 22))
    return to_image(img[..., :3], img[..., 3])


def bokeh(rng):
    """Размытые пылинки у самой камеры: мягкие пятна с чуть более ярким краем."""
    img = np.zeros((SIZE, SIZE, 4))
    for _ in range(9):
        x, y = rng.uniform(0, SIZE, 2)
        r = rng.uniform(14, 40)
        half = int(r * 1.3)
        yy, xx = np.mgrid[-half:half + 1, -half:half + 1]
        d = np.sqrt((xx - (x - int(x))) ** 2 + (yy - (y - int(y))) ** 2) / r
        disc = np.clip((1.0 - d) * 3.0, 0, 1) ** 2 * (0.6 + 0.4 * np.clip(d, 0, 1) ** 3)
        a = disc * rng.uniform(0.03, 0.07)
        ys = (int(y) + yy) % SIZE
        xs = (int(x) + xx) % SIZE
        img[ys, xs, 0] = 1.0
        img[ys, xs, 1] = 0.9
        img[ys, xs, 2] = 0.78
        img[ys, xs, 3] = np.maximum(img[ys, xs, 3], a)
    return to_image(img[..., :3], img[..., 3])


def main():
    rng = np.random.default_rng(11)
    OUT.mkdir(parents=True, exist_ok=True)
    nebula(rng).save(OUT / "nebula.png")
    stars_far(rng).save(OUT / "stars_far.png")
    stars_near(rng).save(OUT / "stars_near.png")
    bokeh(rng).save(OUT / "bokeh.png")
    print("Фон сохранён в", OUT)


if __name__ == "__main__":
    main()
