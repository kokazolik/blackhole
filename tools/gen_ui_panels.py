"""Расписные рамки для меню, рассказчика и кнопок (растягиваются как 9-slice).

assets/ui/panel_painted.png — тёмная «гуашевая» карточка с золотой двойной рамкой
                              и ромбиками в углах
assets/ui/button_dark.png   — обычная кнопка: тёмная с золотым кантом
assets/ui/button_gold.png   — главная кнопка: тёплое золото с мазками
Запуск: python3 tools/gen_ui_panels.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "ui"


def rounded_sdf(w, h, radius, inset):
    """Расстояние до края скруглённого прямоугольника (отрицательное внутри)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(float) + 0.5
    qx = np.abs(xx - w / 2) - (w / 2 - inset - radius)
    qy = np.abs(yy - h / 2) - (h / 2 - inset - radius)
    out = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2)
    return out + np.minimum(np.maximum(qx, qy), 0) - radius


def strokes(rng, w, h, scale):
    """Мазки кисти: вытянутый по горизонтали шум."""
    small = rng.random((max(2, h // scale), max(2, w // (scale * 4))))
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(img, dtype=float) / 255.0


def card(rng, w, h, radius, fill_a, fill_b, border, ornaments, alpha=0.94):
    sdf = rounded_sdf(w, h, radius, 3)
    inside = np.clip(-sdf, 0, 1)
    t = strokes(rng, w, h, 6) * 0.6 + strokes(rng, w, h, 2) * 0.4
    yy = np.mgrid[0:h, 0:w][0] / h
    fill = np.asarray(fill_a) * (1 - t[..., None]) + np.asarray(fill_b) * t[..., None]
    fill *= (1.0 - 0.25 * yy)[..., None]  # низ чуть темнее
    rgb = fill
    a = inside * alpha
    # Двойная золотая рамка: толстая снаружи и тонкая внутри.
    outer = np.clip(1.5 - np.abs(sdf + 3.0), 0, 1)
    inner = np.clip(1.0 - np.abs(sdf + 9.0) * 0.9, 0, 1) * 0.6
    edge = np.maximum(outer, inner)
    gold = np.asarray(border) * (0.85 + 0.3 * strokes(rng, w, h, 3))[..., None]
    rgb = rgb * (1 - edge[..., None]) + gold * edge[..., None]
    a = np.maximum(a, edge)
    if ornaments:
        # Ромбики в углах и посередине длинных сторон.
        yy, xx = np.mgrid[0:h, 0:w].astype(float)
        for cx, cy in [(radius + 4, radius + 4), (w - radius - 5, radius + 4), (radius + 4, h - radius - 5), (w - radius - 5, h - radius - 5)]:
            d = np.abs(xx - cx) + np.abs(yy - cy)
            m = np.clip(5.0 - d, 0, 1)
            rgb = rgb * (1 - m[..., None]) + np.asarray(border) * m[..., None]
            a = np.maximum(a, m)
    img = np.dstack([np.clip(rgb, 0, 1), np.clip(a, 0, 1)])
    return Image.fromarray((img * 255).astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(0.4))


def main():
    rng = np.random.default_rng(5)
    OUT.mkdir(parents=True, exist_ok=True)
    card(rng, 128, 128, 18, (0.06, 0.04, 0.12), (0.12, 0.07, 0.2), (1.0, 0.8, 0.45), True).save(OUT / "panel_painted.png")
    card(rng, 96, 64, 16, (0.07, 0.05, 0.14), (0.14, 0.09, 0.22), (0.95, 0.75, 0.42), False).save(OUT / "button_dark.png")
    card(rng, 96, 64, 16, (0.85, 0.55, 0.18), (1.0, 0.75, 0.35), (1.0, 0.92, 0.7), False, alpha=1.0).save(OUT / "button_gold.png")
    print("Рамки сохранены в", OUT)


if __name__ == "__main__":
    main()
