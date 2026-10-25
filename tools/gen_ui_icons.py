"""Генерирует иконки интерфейса: assets/ui/book.png (кнопка древа) и assets/ui/reset.png.

Книга — раскрытый том звёздного атласа: страницы с туманностью и звёздами,
над разворотом искра. Рисуем в 4× и уменьшаем для сглаживания.
Запуск: python3 tools/gen_ui_icons.py
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageChops

SIZE = 160
SS = 4
OUT = Path(__file__).resolve().parent.parent / "assets" / "ui"


def page_shape(big, left):
    """Многоугольник страницы: верхний край изогнут, у корешка ниже."""
    c = big / 2
    w = big * 0.36
    top = big * 0.30
    bottom = big * 0.74
    pts = []
    n = 24
    for i in range(n + 1):
        t = i / n
        x = c - t * w if left else c + t * w
        y = top + math.sin(t * math.pi) * -big * 0.04 + (1 - t) * big * 0.04
        pts.append((x, y))
    for i in range(n, -1, -1):
        t = i / n
        x = c - t * w if left else c + t * w
        y = bottom + math.sin(t * math.pi) * -big * 0.03 + (1 - t) * big * 0.035
        pts.append((x, y))
    return pts


def book():
    big = SIZE * SS
    rng = random.Random(3)
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))

    # Мягкое свечение под книгой.
    glow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([big * 0.12, big * 0.2, big * 0.88, big * 0.86], fill=(120, 140, 255, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(big * 0.08))
    img.alpha_composite(glow)

    # Обложка под страницами.
    d = ImageDraw.Draw(img)
    cover = [(big * 0.11, big * 0.34), (big * 0.5, big * 0.40), (big * 0.89, big * 0.34),
             (big * 0.89, big * 0.80), (big * 0.5, big * 0.84), (big * 0.11, big * 0.80)]
    d.polygon(cover, fill=(70, 50, 140, 255))
    d.line(cover + [cover[0]], fill=(255, 205, 120, 255), width=SS * 3)

    # Страницы: заливка-туманность через маску.
    for left in (True, False):
        mask = Image.new("L", (big, big), 0)
        ImageDraw.Draw(mask).polygon(page_shape(big, left), fill=255)
        neb = Image.new("RGBA", (big, big), (28, 30, 70, 255))
        nd = ImageDraw.Draw(neb)
        for _ in range(14):
            x, y = rng.uniform(big * 0.15, big * 0.85), rng.uniform(big * 0.3, big * 0.75)
            r = rng.uniform(big * 0.05, big * 0.12)
            col = rng.choice([(120, 90, 230, 120), (70, 160, 230, 110), (200, 110, 220, 90)])
            nd.ellipse([x - r, y - r, x + r, y + r], fill=col)
        neb = neb.filter(ImageFilter.GaussianBlur(big * 0.03))
        nd = ImageDraw.Draw(neb)
        for _ in range(40):
            x, y = rng.uniform(big * 0.12, big * 0.88), rng.uniform(big * 0.28, big * 0.78)
            r = rng.uniform(SS * 0.8, SS * 2.2)
            nd.ellipse([x - r, y - r, x + r, y + r], fill=(235, 240, 255, 255))
        img.paste(neb, (0, 0), mask)
        d = ImageDraw.Draw(img)
        d.line(page_shape(big, left) + [page_shape(big, left)[0]], fill=(200, 210, 255, 200), width=SS * 2)

    # Корешок.
    d.line([(big * 0.5, big * 0.31), (big * 0.5, big * 0.79)], fill=(255, 215, 140, 255), width=SS * 3)

    # Искра над разворотом.
    cx, cy, r, w = big * 0.5, big * 0.17, big * 0.11, big * 0.025
    spark = [(cx, cy - r), (cx + w, cy - w), (cx + r, cy), (cx + w, cy + w),
             (cx, cy + r), (cx - w, cy + w), (cx - r, cy), (cx - w, cy - w)]
    sg = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(sg).ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 210, 120, 140))
    img.alpha_composite(sg.filter(ImageFilter.GaussianBlur(big * 0.03)))
    d = ImageDraw.Draw(img)
    d.polygon(spark, fill=(255, 225, 150, 255))
    d.ellipse([cx - SS * 3, cy - SS * 3, cx + SS * 3, cy + SS * 3], fill=(255, 255, 240, 255))

    return img.resize((SIZE, SIZE), Image.LANCZOS)


def reset():
    big = 64 * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = big / 2
    r = big * 0.32
    d.arc([c - r, c - r, c + r, c + r], 40, 330, fill=(200, 210, 240, 230), width=SS * 5)
    a = math.radians(40)
    tip = (c + math.cos(a) * r, c + math.sin(a) * r)
    s = big * 0.13
    d.polygon([(tip[0] + s, tip[1] - s * 0.2), (tip[0] - s * 0.6, tip[1] - s * 0.6), (tip[0] - s * 0.1, tip[1] + s)],
              fill=(200, 210, 240, 230))
    return img.resize((64, 64), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    book().save(OUT / "book.png")
    reset().save(OUT / "reset.png")
    print("Иконки сохранены в", OUT)


if __name__ == "__main__":
    main()
