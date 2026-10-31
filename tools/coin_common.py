"""Общие приёмы для монет антистресса, нарисованных кодом (coin_poker.py, coin_khorom.py, coin_things_in_rings_secret.py).
Лист 1774×887: слева орёл, справа решка, по 887×887, прозрачный фон.
Стиль монет (решение владельца 2026-10-25): мультяшно, неровные «рисованные» линии, крупные символы,
приглушённые цвета, рисованный объём без глянца и сильных бликов.
Сам по себе не запускается — его импортируют скрипты монет.
"""
import math
import random
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIDE = 887
SS = 2  # суперсэмплинг для мягких краёв
SIZE = SIDE * SS


def wobble(cx, cy, r, seed, amp=0.012, n=180):
    """Неровный круг «от руки»."""
    rnd = random.Random(seed)
    phases = [rnd.uniform(0, math.tau) for _ in range(4)]
    pts = []
    for i in range(n):
        a = math.tau * i / n
        k = 1 + amp * (math.sin(3 * a + phases[0]) + 0.6 * math.sin(5 * a + phases[1]) + 0.4 * math.sin(9 * a + phases[2]))
        pts.append((cx + math.cos(a) * r * k, cy + math.sin(a) * r * k))
    return pts


def shape_wobble(pts, seed, amp):
    """Чуть сдвинуть точки фигуры — промахи руки."""
    rnd = random.Random(seed)
    return [(x + rnd.uniform(-amp, amp), y + rnd.uniform(-amp, amp)) for x, y in pts]


def outline(d, pts, color, width):
    d.line(pts + [pts[0]], fill=color, width=int(width), joint="curve")


def jitter_line(d, p, q, width, color, seed, steps=8):
    rnd = random.Random(seed)
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = p[0] + (q[0] - p[0]) * t + rnd.uniform(-1, 1) * width * 0.12
        y = p[1] + (q[1] - p[1]) * t + rnd.uniform(-1, 1) * width * 0.12
        pts.append((x, y))
    d.line(pts, fill=color, width=int(width), joint="curve")


def new_layer():
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def mask_of(pts):
    m = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


def clip(layer, pts):
    """Оставить слой только внутри фигуры."""
    a = layer.split()[3]
    from PIL import ImageChops
    layer.putalpha(ImageChops.multiply(a, mask_of(pts)))
    return layer


def volume(img, face, c, r, light, shade, strength=70, seed=0):
    """Рисованный объём: светлый серп сверху-слева и тень снизу-справа внутри лица монеты, без градиентов."""
    lay = new_layer()
    d = ImageDraw.Draw(lay)
    d.polygon(wobble(c, c, r, seed + 2), fill=light + (strength,))
    d.polygon(wobble(c + r * 0.06, c + r * 0.09, r * 0.99, seed + 3), fill=(0, 0, 0, 0))
    img.alpha_composite(clip(lay, face))
    lay = new_layer()
    d = ImageDraw.Draw(lay)
    d.polygon(wobble(c, c, r, seed + 4), fill=shade + (strength,))
    d.polygon(wobble(c - r * 0.05, c - r * 0.08, r * 0.99, seed + 5), fill=(0, 0, 0, 0))
    img.alpha_composite(clip(lay, face))


def edge(img, c, r, color, ink, seed, drop=0.028):
    """Гурт: толщина монеты видна снизу — тёмный край под ободом."""
    d = ImageDraw.Draw(img)
    pts = wobble(c + SIZE * drop * 0.25, c + SIZE * drop, r, seed)
    d.polygon(pts, fill=color)
    outline(d, pts, ink, SIZE * 0.012)
    # вертикальные насечки на видимой части гурта
    rnd = random.Random(seed + 1)
    for i in range(40):
        a = math.pi * (0.08 + 0.84 * i / 39)
        x = c + math.cos(a) * r * 0.985
        y0 = c + math.sin(a) * r * 0.985
        if y0 < c + r * 0.25:
            continue
        jitter_line(d, (x, y0 + SIZE * drop * 0.05), (x + SIZE * drop * 0.2, y0 + SIZE * drop * 0.85),
                    SIZE * 0.004, ink + (110,) if len(ink) == 3 else ink, seed + 10 + i, 3)
        rnd.random()


def glow(img, draw_fn, color, radius, alpha=150):
    """Неоновое свечение: рисуем фигуру отдельно, размываем, кладём под неё."""
    lay = new_layer()
    draw_fn(ImageDraw.Draw(lay), color + (alpha,))
    lay = lay.filter(ImageFilter.GaussianBlur(radius))
    img.alpha_composite(lay)


def star(cx, cy, r_out, r_in, n=5, rot=-math.pi / 2, seed=None, amp=0.0):
    rnd = random.Random(seed)
    pts = []
    for i in range(n * 2):
        a = rot + math.pi * i / n
        r = (r_out if i % 2 == 0 else r_in) * (1 + rnd.uniform(-amp, amp))
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def font(path, px, weight=None):
    f = ImageFont.truetype(path, int(px))
    if weight is not None:
        try:
            f.set_variation_by_axes([weight])
        except Exception:
            pass
    return f


def text_center(d, c, cy, s, f, **kw):
    box = d.textbbox((0, 0), s, font=f, stroke_width=kw.get("stroke_width", 0))
    x = c - (box[0] + box[2]) / 2
    y = cy - (box[1] + box[3]) / 2
    d.text((x, y), s, font=f, **kw)
    return x, y


def save_sheet(out, heads_img, tails_img, view_bg=(60, 52, 66)):
    sheet = Image.new("RGBA", (SIDE * 2, SIDE), (0, 0, 0, 0))
    for index, side in enumerate([heads_img, tails_img]):
        side = side.filter(ImageFilter.GaussianBlur(0.6)).resize((SIDE, SIDE), Image.LANCZOS)
        sheet.alpha_composite(side, (index * SIDE, 0))
    sheet.save(out)
    print(out)
    return sheet


def preview(sheets, out, bgs=((233, 225, 211), (31, 28, 37))):
    """Проверочный лист: все монеты на светлом и тёмном фоне, крупно и в размере игры (48 px)."""
    rows = []
    for bg in bgs:
        row = Image.new("RGBA", (len(sheets) * 460, 300), bg + (255,))
        for i, sh in enumerate(sheets):
            big = sh.resize((400, 200), Image.LANCZOS)
            row.alpha_composite(big, (i * 460 + 30, 10))
            small = sh.resize((96, 48), Image.LANCZOS)
            row.alpha_composite(small, (i * 460 + 180, 230))
        rows.append(row)
    img = Image.new("RGBA", (rows[0].width, 300 * len(rows)))
    for i, r in enumerate(rows):
        img.alpha_composite(r, (0, i * 300))
    img.convert("RGB").save(out)
    print(out)
