"""Далёкие пылевые потоки самого протопланетного диска.

Длинные вытянутые волокна вдоль одного направления (вдоль орбиты): в шейдере
фона текстура поворачивается так, чтобы волокна шли по касательной к орбите.
Бесшовная, полупрозрачная, чтобы лечь между далёкими и ближними звёздами.

assets/space/disk_streams.png
Запуск: python3 tools/gen_disk_streams.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets" / "space" / "disk_streams.png"
SIZE = 1024


def aniso_noise(rng, stretch, slope, low_cut):
    """Шум с вытянутыми вдоль x деталями: по x частоты сжаты в stretch раз."""
    white = rng.standard_normal((SIZE, SIZE))
    f = np.fft.fft2(white)
    fy = np.fft.fftfreq(SIZE)[:, None] * SIZE
    fx = np.fft.fftfreq(SIZE)[None, :] * SIZE
    k = np.sqrt((fx * stretch) ** 2 + fy ** 2)
    k[0, 0] = 1.0
    amp = 1.0 / k ** slope
    amp[k < low_cut] = 0.0
    n = np.real(np.fft.ifft2(f * amp))
    n -= n.min()
    return n / n.max()


def main():
    rng = np.random.default_rng(23)
    big = aniso_noise(rng, 4.0, 2.0, 2.0)
    mask = np.clip((big - 0.4) / 0.35, 0, 1) ** 1.4
    fil = aniso_noise(rng, 6.0, 1.6, 2.0)
    ridges = (1.0 - np.abs(fil - 0.5) * 2.0) ** 4
    fine = aniso_noise(rng, 8.0, 1.2, 4.0)
    density = mask * (0.25 + 0.75 * ridges) * (0.6 + 0.8 * fine)
    a = np.clip(density * 0.22, 0, 1)
    # Тёплый отражённый свет звезды на пыли: бурый с золотом, в гуще светлее.
    warm = np.array([0.85, 0.6, 0.38])
    dusty = np.array([0.55, 0.42, 0.36])
    t = np.clip(density * 1.5, 0, 1)[..., None]
    rgb = dusty * (1 - t) + warm * t
    img = np.dstack([rgb, a])
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(OUT, optimize=True)
    print("Потоки диска сохранены в", OUT)


if __name__ == "__main__":
    main()
