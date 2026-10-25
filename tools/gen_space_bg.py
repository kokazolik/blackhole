"""Генерирует бесшовные текстуры фона: туманности и два слоя звёзд.

assets/space/nebula.png     — мягкие цветные облака (низкая прозрачность)
assets/space/stars_far.png  — много мелких тусклых звёзд
assets/space/stars_near.png — меньше звёзд, крупнее и ярче
Бесшовность даёт шум, отфильтрованный в частотной области (он периодичен сам по себе).
Запуск: python3 tools/gen_space_bg.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets" / "space"
SIZE = 1024


def tileable_noise(rng, size, slope, low_cut=1.0):
    """Шум со спектром 1/f^slope: чем больше slope, тем крупнее и мягче облака."""
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


def nebula(rng):
    # Три поля разных цветов: синее, фиолетовое и бирюзовое, плюс тёмные прожилки пыли.
    colors = [np.array([0.20, 0.30, 0.85]), np.array([0.55, 0.22, 0.70]), np.array([0.15, 0.60, 0.70])]
    rgb = np.zeros((SIZE, SIZE, 3))
    alpha = np.zeros((SIZE, SIZE))
    for col in colors:
        n = tileable_noise(rng, SIZE, 1.9, low_cut=1.5)
        detail = tileable_noise(rng, SIZE, 1.3, low_cut=3.0)
        m = np.clip((n - 0.5) * 2.4, 0.0, 1.0) ** 1.6 * (0.6 + 0.6 * detail)
        rgb += m[..., None] * col
        alpha += m
    lanes = tileable_noise(rng, SIZE, 1.6, low_cut=2.0)
    alpha *= np.clip(1.4 - lanes * 1.2, 0.2, 1.0)
    alpha = np.clip(alpha, 0.0, 1.0)
    rgb = rgb / np.maximum(rgb.max(axis=2, keepdims=True), 1e-4)
    a = alpha * 0.22  # туманности лёгкие, не мешают видеть пыль
    img = np.dstack([rgb, a])
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA")


def stars(rng, count, r_range, a_range):
    img = np.zeros((SIZE, SIZE, 4))
    yy, xx = np.mgrid[-4:5, -4:5]
    for _ in range(count):
        x, y = rng.uniform(0, SIZE, 2)
        r = rng.uniform(*r_range)
        a = rng.uniform(*a_range)
        tint = rng.choice([[0.75, 0.85, 1.0], [0.9, 0.93, 1.0], [0.85, 0.9, 1.0], [1.0, 0.95, 0.9]])  # холодные, чтобы не путать с пылью
        ix, iy = int(x), int(y)
        fx, fy = x - ix, y - iy
        d = np.sqrt((xx - fx) ** 2 + (yy - fy) ** 2)
        spot = np.exp(-(d / r) ** 2 * 2.0) * a
        ys = (iy + yy) % SIZE
        xs = (ix + xx) % SIZE
        for c in range(3):
            img[ys, xs, c] = np.maximum(img[ys, xs, c], tint[c])
        img[ys, xs, 3] = np.maximum(img[ys, xs, 3], spot)
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA")


def main():
    rng = np.random.default_rng(11)
    OUT.mkdir(parents=True, exist_ok=True)
    nebula(rng).save(OUT / "nebula.png")
    stars(rng, 900, (0.45, 0.8), (0.06, 0.22)).save(OUT / "stars_far.png")
    stars(rng, 140, (0.7, 1.3), (0.2, 0.5)).save(OUT / "stars_near.png")
    print("Фон сохранён в", OUT)


if __name__ == "__main__":
    main()
