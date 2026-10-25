"""Расписные картины для главного меню и пролога.

Стиль — гуашь мазками: сцена собирается из мягких форм (свечения, кольца,
спирали), потом краска размазывается вдоль завихрений вокруг главных объектов
(свёртка вдоль линий потока). Сверху кладутся фактура бумаги, золотые искры
и тёмная виньетка, чтобы на картину удобно ложился текст.

assets/intro/menu.png, p1_path.png, p2_forge.png, p3_cloud.png, p4_grains.png, p5_start.png
Запуск: python3 tools/gen_intro_art.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "intro"
W, H = 1280, 720
YY, XX = np.mgrid[0:H, 0:W].astype(float)


def smooth_noise(rng, cells):
    small = rng.random((max(2, int(H / W * cells)), cells))
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
    return np.asarray(img, dtype=float) / 255.0


def fbm(rng, octaves=(3, 6, 12, 24), gains=(1.0, 0.5, 0.25, 0.12)):
    n = sum(g * smooth_noise(rng, c) for c, g in zip(octaves, gains))
    n -= n.min()
    return n / n.max()


def blob(cx, cy, rx, ry=None, angle=0.0):
    """Мягкое пятно (гаусс), можно вытянуть и повернуть."""
    ry = rx if ry is None else ry
    c, s = np.cos(angle), np.sin(angle)
    dx, dy = XX - cx, YY - cy
    u = (dx * c + dy * s) / rx
    v = (-dx * s + dy * c) / ry
    return np.exp(-(u * u + v * v))


def ring(cx, cy, r, width, tilt=1.0, angle=0.0):
    """Кольцо (эллипс при tilt < 1) — диск, вид под углом."""
    c, s = np.cos(angle), np.sin(angle)
    dx, dy = XX - cx, YY - cy
    u = dx * c + dy * s
    v = (-dx * s + dy * c) / tilt
    d = np.sqrt(u * u + v * v)
    return np.exp(-((d - r) / width) ** 2)


def paint(rgb, layer, color, amount=1.0):
    m = np.clip(layer * amount, 0, 1)[..., None]
    return rgb * (1 - m) + np.asarray(color) * m


def glow(rgb, layer, color, amount=1.0):
    return rgb + np.clip(layer * amount, 0, None)[..., None] * np.asarray(color)


def swirl_field(rng, centers):
    """Поле направлений мазков: шум плюс вихри вокруг главных объектов."""
    angle = fbm(rng, (2, 4, 8), (1.0, 0.5, 0.25)) * np.pi * 2.5
    for cx, cy, radius, twist in centers:
        dx, dy = XX - cx, YY - cy
        d = np.sqrt(dx * dx + dy * dy)
        tang = np.arctan2(dy, dx) + np.pi / 2 + twist
        k = np.exp(-d / radius)
        angle = angle * (1 - k) + tang * k
    return angle


def lic(rgb, angle, steps=16, step_len=1.6):
    acc = rgb.copy()
    total = 1.0
    for sign in (1.0, -1.0):
        px, py = XX.copy(), YY.copy()
        for i in range(steps):
            ix = np.clip(px.astype(int), 0, W - 1)
            iy = np.clip(py.astype(int), 0, H - 1)
            a = angle[iy, ix]
            px += np.cos(a) * step_len * sign
            py += np.sin(a) * step_len * sign
            ix = np.clip(px.astype(int), 0, W - 1)
            iy = np.clip(py.astype(int), 0, H - 1)
            wgt = 1.0 - i / steps
            acc += rgb[iy, ix] * wgt
            total += wgt
    return acc / total


def star(rgb, x, y, r, col, a, spikes=0.0):
    half = int(max(4, r * 5, spikes))
    ix, iy = int(x), int(y)
    y0, y1 = max(0, iy - half), min(H, iy + half + 1)
    x0, x1 = max(0, ix - half), min(W, ix + half + 1)
    if y0 >= y1 or x0 >= x1:
        return
    dx, dy = XX[y0:y1, x0:x1] - x, YY[y0:y1, x0:x1] - y
    d2 = dx * dx + dy * dy
    spot = np.exp(-d2 / (2 * r * r)) + 0.12 * np.exp(-d2 / (2 * (r * 3) ** 2))
    if spikes:
        spot += 0.6 * np.exp(-dy * dy / 0.6) * np.exp(-np.abs(dx) / (spikes * 0.3))
        spot += 0.6 * np.exp(-dx * dx / 0.6) * np.exp(-np.abs(dy) / (spikes * 0.3))
    spot = np.clip(spot * a, 0, 1)[..., None]
    rgb[y0:y1, x0:x1] = rgb[y0:y1, x0:x1] * (1 - spot) + np.asarray(col) * spot


def finish(rgb, rng, centers, sparkle=1.0, vignette=0.5, text_shade=0.0, post=None):
    """Мазки, фактура бумаги, искры, виньетка. post рисует чёткие предметы поверх мазков."""
    grain = np.asarray(Image.fromarray((rng.random((H // 2, W // 2)) * 255).astype(np.uint8))
                       .resize((W, H), Image.BILINEAR), dtype=float) / 255.0
    rgb = rgb * (0.72 + 0.56 * grain)[..., None]
    rgb = lic(rgb, swirl_field(rng, centers))
    rgb = np.round(np.clip(rgb, 0, 1) * 40) / 40  # чуть плоские красочные пятна
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7))
    rgb = np.asarray(img, dtype=float) / 255.0
    if post is not None:
        rgb = post(rgb)
    # Фактура бумаги: мелкие волокна.
    paper = fbm(rng, (60, 120, 240), (1.0, 0.6, 0.4))
    rgb *= (0.93 + 0.1 * paper)[..., None]
    for _ in range(int(500 * sparkle)):
        col = (1.0, 0.9, 0.7) if rng.random() < 0.6 else (0.8, 0.88, 1.0)
        star(rgb, rng.uniform(0, W), rng.uniform(0, H), rng.uniform(0.5, 1.1), col, rng.uniform(0.15, 0.6))
    for _ in range(int(14 * sparkle)):
        star(rgb, rng.uniform(0, W), rng.uniform(0, H), rng.uniform(1.0, 1.6), (1.0, 0.86, 0.55), rng.uniform(0.6, 0.9), rng.uniform(6, 14))
    d = np.sqrt(((XX - W / 2) / (W / 2)) ** 2 + ((YY - H / 2) / (H / 2)) ** 2)
    rgb *= np.clip(1.05 - vignette * d ** 2, 0.3, 1.0)[..., None]
    if text_shade > 0:
        # Низ темнее: туда ложится рассказ.
        rgb *= (1.0 - text_shade * np.clip((YY / H - 0.55) / 0.45, 0, 1) ** 1.5)[..., None]
    return rgb


def base_sky(rng, colors, strength=0.8):
    rgb = np.broadcast_to(np.array([0.02, 0.022, 0.06]), (H, W, 3)).copy()
    for col in colors:
        m = np.clip((fbm(rng) - 0.42) / 0.45, 0, 1) ** 1.5 * strength
        rgb = paint(rgb, m, col)
    return rgb


def save(name, rgb):
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB").save(OUT / name, optimize=True)
    print("сохранено", name)


def young_star_disk(rgb, cx, cy, scale, tilt=0.32, angle=-0.12, rng=None):
    """Молодая звезда в протопланетном диске, вид под углом. Диск с щелью."""
    rgb = glow(rgb, blob(cx, cy, 260 * scale, 200 * scale), (0.35, 0.18, 0.06), 0.9)
    for r, w, col, amt in [(150, 60, (0.75, 0.42, 0.18), 0.85), (260, 50, (0.6, 0.38, 0.2), 0.7),
                           (360, 70, (0.38, 0.32, 0.38), 0.6), (470, 60, (0.28, 0.34, 0.5), 0.45)]:
        layer = ring(cx, cy, r * scale, w * scale, tilt, angle)
        if rng is not None:
            layer *= 0.6 + 0.6 * fbm(rng, (6, 12, 24), (1.0, 0.5, 0.3))
        rgb = paint(rgb, layer, col, amt)
    rgb = glow(rgb, blob(cx, cy, 70 * scale), (1.0, 0.7, 0.35), 1.2)
    rgb = glow(rgb, blob(cx, cy, 28 * scale), (1.0, 0.95, 0.8), 1.5)
    return rgb


def menu(rng):
    """Главное меню: звезда с диском справа, слева тёмное небо под название и кнопки."""
    rgb = base_sky(rng, [(0.16, 0.08, 0.3), (0.05, 0.18, 0.28), (0.3, 0.1, 0.2)], 0.7)
    sx, sy = W * 0.68, H * 0.56
    rgb = young_star_disk(rgb, sx, sy, 1.0, tilt=0.3, angle=-0.18, rng=rng)
    rgb = glow(rgb, blob(W * 0.47, H * 0.71, 5, 5), (1.0, 0.95, 0.85), 1.5)  # наша пылинка в диске
    rgb = finish(rgb, rng, [(sx, sy, 300, 0.25), (W * 0.15, H * 0.3, 220, 0.4), (W * 0.9, H * 0.15, 200, -0.3)],
                 vignette=0.5)
    rgb *= (1.0 - 0.55 * np.clip(1 - XX / (W * 0.45), 0, 1) ** 1.5)[..., None]  # слева темнее под меню
    save("menu.png", rgb)


def p1_path(rng):
    """Путь путника: от искорки пыли через камни и планеты к звезде и чёрной дыре."""
    rgb = base_sky(rng, [(0.12, 0.08, 0.26), (0.08, 0.16, 0.26)], 0.7)
    # Дорога: светящаяся дуга снизу слева вверх направо.
    t = np.linspace(0, 1, 400)
    px = 80 + t * (W - 260)
    py = H * 0.82 - np.sin(t * np.pi * 0.9) * H * 0.35 - t * H * 0.25
    road = np.zeros((H, W))
    for x, y in zip(px[::2], py[::2]):
        road = np.maximum(road, blob(x, y, 14 + 10 * (1 - abs(0.5 - (x / W))), 14))
    rgb = glow(rgb, road, (0.5, 0.42, 0.3), 0.35)
    bx, by = px[-1] + 40, py[-1] - 10
    rgb = glow(rgb, blob(bx, by, 160), (0.6, 0.3, 0.12), 0.5)

    def objects(img):
        # Ступени пути: пылинка, галька, валун, планета, звезда — и чёрная дыра.
        stops = [(0.04, 2.5, (1.0, 0.95, 0.85)), (0.18, 5, (0.8, 0.7, 0.55)), (0.33, 10, (0.62, 0.56, 0.5)),
                 (0.5, 18, (0.45, 0.62, 0.88)), (0.68, 26, (1.0, 0.82, 0.5))]
        for tt, r, col in stops:
            i = int(tt * (len(t) - 1))
            x, y = px[i], py[i]
            img = glow(img, blob(x, y, r * 3), col, 0.3)
            disc = np.clip((1.0 - np.sqrt((XX - x) ** 2 + (YY - y) ** 2) / r) * 3, 0, 1)
            shade = np.clip(0.55 + 0.6 * ((x - XX) * 0.5 + (y - YY) * 0.5) / r, 0.25, 1.2)  # свет слева сверху
            img = paint(img, disc, (0, 0, 0), 1.0)
            img = img + (disc * shade)[..., None] * np.asarray(col)
        img = glow(img, ring(bx, by, 74, 20, 0.33, -0.2), (1.0, 0.55, 0.2), 1.4)
        img = glow(img, ring(bx, by, 47, 5), (1.0, 0.88, 0.65), 1.3)
        hole = np.clip((1.0 - np.sqrt((XX - bx) ** 2 + (YY - by) ** 2) / 42) * 6, 0, 1)
        img = paint(img, hole, (0.0, 0.0, 0.0), 1.0)
        front = ring(bx, by, 74, 14, 0.33, -0.2) * (YY > by - 6)  # передняя часть диска перед дырой
        return glow(img, front, (1.0, 0.6, 0.25), 1.0)

    rgb = finish(rgb, rng, [(bx, by, 160, 0.15), (W * 0.3, H * 0.6, 260, 0.4)], text_shade=0.55, post=objects)
    save("p1_path.png", rgb)


def p2_forge(rng):
    """Кузница элементов: старая звезда взрывается и рассеивает тяжёлые элементы."""
    rgb = base_sky(rng, [(0.22, 0.06, 0.12), (0.06, 0.12, 0.26)], 0.6)
    cx, cy = W * 0.5, H * 0.42
    ang = np.arctan2(YY - cy, XX - cx)
    d = np.sqrt((XX - cx) ** 2 + (YY - cy) ** 2)
    wobble = fbm(rng, (6, 12, 24), (1, .6, .3))
    rays = (0.5 + 0.5 * np.cos(ang * 7 + wobble * 14 + d * 0.01)) ** 2 * (0.4 + 0.8 * wobble)
    shell = np.exp(-((d - 230) / 70) ** 2) * (0.5 + 0.8 * fbm(rng))
    rgb = glow(rgb, shell * (0.6 + 0.4 * rays), (0.9, 0.35, 0.25), 0.8)   # водород, кислород
    rgb = glow(rgb, np.exp(-((d - 170) / 50) ** 2) * rays, (0.3, 0.7, 0.85), 0.5)
    rgb = glow(rgb, np.exp(-d / 120) * rays, (1.0, 0.75, 0.4), 0.4)
    rgb = glow(rgb, blob(cx, cy, 30), (1.0, 0.95, 0.85), 1.6)
    # Крупинки элементов разлетаются: кремний (золото), железо (сталь), углерод (бурый).
    for _ in range(140):
        a = rng.uniform(0, np.pi * 2)
        rr = rng.uniform(120, 420)
        col = [(0.95, 0.8, 0.5), (0.7, 0.78, 0.9), (0.7, 0.45, 0.3)][rng.integers(3)]
        x, y = cx + np.cos(a) * rr * 1.3, cy + np.sin(a) * rr * 0.8
        star(rgb, x, y, rng.uniform(1.0, 2.2), col, 0.9)
    rgb = finish(rgb, rng, [(cx, cy, 260, 0.0)], text_shade=0.55)
    save("p2_forge.png", rgb)


def p3_cloud(rng):
    """Облако газа и пыли сжимается: в центре вспыхивает звезда, вокруг вращается диск."""
    rgb = base_sky(rng, [(0.1, 0.12, 0.22)], 0.5)
    cloud = fbm(rng, (3, 6, 12, 24)) * blob(W * 0.5, H * 0.45, 520, 320)
    rgb = paint(rgb, np.clip((cloud - 0.15) * 2.0, 0, 1), (0.16, 0.1, 0.12), 0.9)
    rgb = young_star_disk(rgb, W * 0.5, H * 0.45, 0.75, tilt=0.28, angle=0.05, rng=rng)
    rgb = finish(rgb, rng, [(W * 0.5, H * 0.45, 330, 0.5)], text_shade=0.55)
    save("p3_cloud.png", rgb)


def p4_grains(rng):
    """Крупный план: пылинки слипаются в рыхлые комочки; за снеговой линией — иней."""
    rgb = base_sky(rng, [(0.18, 0.12, 0.08), (0.08, 0.12, 0.22)], 0.6)
    rgb = glow(rgb, blob(-80, H * 0.4, 520, 420), (0.9, 0.55, 0.25), 0.5)  # свет звезды слева
    cx, cy = W * 0.5, H * 0.42
    grains = []
    for _ in range(46):
        a = rng.uniform(0, np.pi * 2)
        rr = abs(rng.normal(0, 55))
        grains.append((cx + np.cos(a) * rr, cy + np.sin(a) * rr * 0.8, rng.uniform(9, 20),
                       [(0.82, 0.7, 0.5), (0.6, 0.62, 0.7), (0.5, 0.36, 0.28)][rng.integers(3)]))
    flying = [(cx + np.cos(a) * rr, cy + np.sin(a) * rr * 0.7, rng.uniform(2.5, 5.0))
              for a, rr in zip(rng.uniform(0, np.pi * 2, 26), rng.uniform(170, 420, 26))]
    frost = [(rng.uniform(W * 0.8, W * 0.96), rng.uniform(H * 0.1, H * 0.6), rng.uniform(6, 12)) for _ in range(16)]

    def lumpy(img, x, y, r, col, light=(1.0, 0.85, 0.6)):
        # Комочек: неровный край, освещён слева (там звезда).
        ang = np.arctan2(YY - y, XX - x)
        d = np.sqrt((XX - x) ** 2 + (YY - y) ** 2)
        edge = r * (1.0 + 0.18 * np.sin(ang * 5 + x) + 0.1 * np.sin(ang * 9 + y))
        disc = np.clip((edge - d) * 0.8, 0, 1)
        shade = np.clip(0.45 + 0.7 * (x - XX) / r, 0.2, 1.3)
        img = paint(img, disc, np.asarray(col) * 0.35, 1.0)
        return img + (disc * np.clip(shade - 0.45, 0, 1))[..., None] * np.asarray(light) * np.asarray(col) * 1.2

    def objects(img):
        for x, y, r, col in sorted(grains, key=lambda g: g[1]):
            img = lumpy(img, x, y, r, col)
        for x, y, r in flying:
            img = lumpy(img, x, y, r, (0.9, 0.8, 0.6))
        for x, y, r in frost:
            img = lumpy(img, x, y, r, (0.75, 0.88, 1.0), (0.9, 0.95, 1.0))
            star(img, x - r * 0.4, y - r * 0.3, 1.2, (1, 1, 1), 0.9, 8)
        return img

    rgb = finish(rgb, rng, [(cx, cy, 200, 0.6)], text_shade=0.55, post=objects)
    save("p4_grains.png", rgb)


def p5_start(rng):
    """Начало пути: одна пылинка в диске у молодой звезды."""
    rgb = base_sky(rng, [(0.16, 0.08, 0.3), (0.3, 0.1, 0.2)], 0.6)
    rgb = young_star_disk(rgb, W * 0.12, H * 0.5, 1.6, tilt=0.45, angle=0.3, rng=rng)
    x, y = W * 0.68, H * 0.4
    rgb = glow(rgb, blob(x, y, 40), (1.0, 0.9, 0.7), 0.5)
    rgb = glow(rgb, blob(x, y, 6), (1.0, 0.98, 0.9), 1.6)
    for _ in range(60):
        star(rgb, rng.uniform(W * 0.4, W), rng.uniform(0, H * 0.8), rng.uniform(0.8, 1.8), (0.85, 0.75, 0.6), 0.7)
    rgb = finish(rgb, rng, [(W * 0.12, H * 0.5, 420, 0.3), (x, y, 120, 0.8)], text_shade=0.55)
    save("p5_start.png", rgb)


def main():
    rng = np.random.default_rng(1337)
    menu(np.random.default_rng(77))
    p1_path(rng)
    p2_forge(rng)
    p3_cloud(rng)
    p4_grains(rng)
    p5_start(rng)


if __name__ == "__main__":
    main()
