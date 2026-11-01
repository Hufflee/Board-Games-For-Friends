"""Монеты «Покера» для антистресса (неоновый Лас-Вегас, как games/poker/ui/pk_style.gd). Светлой темы у покера нет.
  poker_coin.png        — обычная «джекпот»: золотая, по ободу гирлянда лампочек;
                          орёл — фиолетовая корона с неоновыми камнями, решка — розовый король «K» в сиянии.
  poker_secret_coin.png — секретная: фишка-жетон из тёмно-фиолетового сукна в ярком неоне — светящиеся вставки
                          по ободу, двойное неоновое кольцо; орёл — пика неоновой трубкой, решка — золотой туз «A».
  (01.11 владелец: в «джекпоте» 7 → K, жетону больше сияния, и монеты поменялись местами.)
Лист 1774×887: слева орёл, справа решка. Запуск: python -I tools/coin_poker.py  → hub/art/coins/
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import ImageDraw  # noqa: E402
from coin_common import (SIZE, wobble, shape_wobble, outline, jitter_line, new_layer, clip, volume, edge, glow,  # noqa: E402
                         star, font, text_center, save_sheet, preview)

# Неон чуть приглушён (решение о монетах: без кричащих цветов).
PINK = (236, 86, 168)
PINK_LIGHT = (255, 170, 214)
CYAN = (78, 206, 236)
CYAN_LIGHT = (170, 236, 250)
GOLD = (236, 190, 86)
GOLD_DARK = (168, 120, 40)
GOLD_LIGHT = (250, 226, 150)
FELT = (62, 30, 106)
FELT_CENTER = (84, 46, 138)
RAIL = (31, 15, 53)
INK = (22, 10, 36)
HEAD = "hub/art/fonts/RussoOne-Regular.ttf"


def spade(cx, cy, s, seed):
    """Пика одним контуром: перевёрнутое сердце + ножка. Возвращает список многоугольников (для маски)."""
    rnd = random.Random(seed)
    ph = rnd.uniform(0, math.tau)
    pts = []
    n = 120
    for i in range(n):
        t = math.tau * i / n
        k = 1 + 0.015 * math.sin(3 * t + ph)  # лёгкая неровность руки, без зазубрин
        x = 16 * math.sin(t) ** 3 * k
        y = (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) * k
        pts.append((cx + x * s, cy + y * s - 2 * s))
    stem = [(cx - 1.4 * s, cy + 2 * s), (cx + 1.4 * s, cy + 2 * s), (cx + 2.0 * s, cy + 8 * s), (cx + 6.0 * s, cy + 14.5 * s),
            (cx - 6.2 * s, cy + 14.5 * s), (cx - 2.0 * s, cy + 8 * s)]
    return [pts, stem]


def neon_shape(img, polys, color, light, width, fill=(48, 20, 80)):
    """Неоновая трубка по общему контуру нескольких фигур (объединение через маску)."""
    from PIL import Image, ImageFilter
    m = Image.new("L", (SIZE, SIZE), 0)
    dm = ImageDraw.Draw(m)
    for p in polys:
        dm.polygon(p, fill=255)
    if fill is not None:
        lay = new_layer()
        lay.paste(fill + (255,), (0, 0), m)
        img.alpha_composite(lay)
    soft = m.filter(ImageFilter.GaussianBlur(width * 0.5))
    # полоса вокруг границы: где размытая маска около середины
    band = soft.point(lambda v: max(0, 255 - abs(v - 128) * 255 // 125))
    core = soft.point(lambda v: max(0, 255 - abs(v - 128) * 255 // 40))
    halo = band.filter(ImageFilter.GaussianBlur(SIZE * 0.014))
    wide = band.filter(ImageFilter.GaussianBlur(SIZE * 0.03))
    for mask, col, k in [(wide, color, 1.0), (halo, color, 1.0), (halo, color, 1.0), (band, color, 1.0), (core, light, 1.0)]:
        lay = new_layer()
        lay.paste(col + (255,), (0, 0), mask.point(lambda v, k=k: int(v * k)))
        img.alpha_composite(lay)


def chip_body(seed, secret):
    img = new_layer()
    c = SIZE / 2
    edge(img, c, SIZE * 0.462, GOLD_DARK if secret else RAIL, INK, seed + 50)
    d = ImageDraw.Draw(img)
    rim = wobble(c, c, SIZE * 0.462, seed)
    d.polygon(rim, fill=GOLD if secret else FELT)
    face = wobble(c, c, SIZE * 0.36, seed + 1, 0.01)
    if secret:
        # гирлянда лампочек по ободу — как над столом в игре
        rnd = random.Random(seed + 7)
        for i in range(20):
            a = math.tau * i / 20 + 0.08
            x, y = c + math.cos(a) * SIZE * 0.412, c + math.sin(a) * SIZE * 0.412
            col = PINK if i % 2 == 0 else CYAN
            r = SIZE * 0.022
            glow(img, lambda dd, cc, x=x, y=y, r=r: dd.ellipse((x - r * 1.5, y - r * 1.5, x + r * 1.5, y + r * 1.5), fill=cc), col, SIZE * 0.012, 140)
            d = ImageDraw.Draw(img)
            bulb = wobble(x, y, r * (1 + rnd.uniform(-0.05, 0.05)), seed + 100 + i, 0.05, 40)
            d.polygon(bulb, fill=col)
            d.ellipse((x - r * 0.55 - r * 0.2, y - r * 0.55 - r * 0.2, x - r * 0.05, y - r * 0.05), fill=PINK_LIGHT if col == PINK else CYAN_LIGHT)
            outline(d, bulb, INK, SIZE * 0.005)
    else:
        # вставки, как на казино-фишке: 8 полос по ободу, розовые и голубые — светятся неоном
        for i in range(8):
            a0 = math.tau * i / 8 + 0.16
            a1 = a0 + 0.30
            col = PINK if i % 2 == 0 else CYAN
            pts = []
            for k in range(13):
                a = a0 + (a1 - a0) * k / 12
                pts.append((c + math.cos(a) * SIZE * 0.452, c + math.sin(a) * SIZE * 0.452))
            for k in range(13):
                a = a1 - (a1 - a0) * k / 12
                pts.append((c + math.cos(a) * SIZE * 0.372, c + math.sin(a) * SIZE * 0.372))
            pts = shape_wobble(pts, seed + 20 + i, SIZE * 0.002)
            glow(img, lambda dd, cc, pts=pts: dd.polygon(pts, fill=cc), col, SIZE * 0.016, 230)
            d = ImageDraw.Draw(img)
            d.polygon(pts, fill=col)
            light = PINK_LIGHT if col == PINK else CYAN_LIGHT
            inner = [(x + (c - x) * 0.04, y + (c - y) * 0.04) for x, y in pts]
            d.line(inner + [inner[0]], fill=light, width=int(SIZE * 0.006), joint="curve")
            outline(d, pts, INK, SIZE * 0.006)
    d.polygon(face, fill=(244, 210, 122) if secret else FELT_CENTER)
    volume(img, face, c, SIZE * 0.36, (255, 244, 200) if secret else (150, 110, 210), GOLD_DARK if secret else RAIL, 80, seed + 3)
    volume(img, rim, c, SIZE * 0.462, (255, 240, 190) if secret else (130, 90, 190), INK, 55, seed + 9)
    d = ImageDraw.Draw(img)
    # тонкое золотое кольцо вокруг лица
    ring = wobble(c, c, SIZE * 0.372, seed + 2, 0.01)
    outline(d, ring, GOLD_DARK if secret else GOLD, SIZE * 0.008)
    outline(d, face, INK, SIZE * 0.008)
    outline(d, rim, INK, SIZE * 0.014)
    if not secret:
        # двойное неоновое кольцо вокруг лица: розовое снаружи, голубое внутри — фишка «горит»
        neon_path(img, [wobble(c, c, SIZE * 0.352, seed + 70, 0.006)], PINK, PINK_LIGHT, SIZE * 0.009)
        neon_path(img, [wobble(c, c, SIZE * 0.318, seed + 71, 0.006)], CYAN, CYAN_LIGHT, SIZE * 0.006)
    return img, c


def neon_path(img, polys, color, light, width, closed=True):
    """Неоновая трубка по контуру фигур: размытое свечение, трубка, светлая середина."""
    def path(p):
        return p + [p[0]] if closed else p

    def draw(dd, cc, w=width):
        for p in polys:
            dd.line(path(p), fill=cc, width=int(w * 2.4), joint="curve")
    glow(img, draw, color, SIZE * 0.022, 200)  # широкое сияние
    glow(img, draw, color, SIZE * 0.009, 230)  # плотное у самой трубки
    d = ImageDraw.Draw(img)
    for p in polys:
        d.line(path(p), fill=color, width=int(width), joint="curve")
        d.line(path(p), fill=light, width=int(width * 0.35), joint="curve")


def heads():
    img, c = chip_body(31, False)
    # заливка — тёмное «стекло», трубка — розовая
    neon_shape(img, spade(c, c - SIZE * 0.02, SIZE * 0.0118, 5), PINK, PINK_LIGHT, SIZE * 0.03)
    return img


def tails():
    img, c = chip_body(37, False)
    ring = wobble(c, c, SIZE * 0.27, 61, 0.012)
    neon_path(img, [ring], CYAN, CYAN_LIGHT, SIZE * 0.013)
    d = ImageDraw.Draw(img)
    f = font(HEAD, SIZE * 0.34)
    sh = SIZE * 0.012
    # туз светится золотом
    glow(img, lambda dd, cc: text_center(dd, c, c, "A", f, fill=cc, stroke_width=int(SIZE * 0.02), stroke_fill=cc), GOLD, SIZE * 0.02, 200)
    d = ImageDraw.Draw(img)
    text_center(d, c + sh, c + sh * 1.3, "A", f, fill=INK)
    text_center(d, c, c, "A", f, fill=GOLD, stroke_width=int(SIZE * 0.009), stroke_fill=INK)
    return img


def crown(cx, cy, s, seed):
    """Корона: зубцы с шариками."""
    pts = [(cx - 1.0 * s, cy + 0.45 * s), (cx - 1.08 * s, cy - 0.5 * s), (cx - 0.5 * s, cy - 0.05 * s),
           (cx, cy - 0.75 * s), (cx + 0.5 * s, cy - 0.05 * s), (cx + 1.08 * s, cy - 0.5 * s), (cx + 1.0 * s, cy + 0.45 * s)]
    tips = [(cx - 1.08 * s, cy - 0.5 * s), (cx, cy - 0.75 * s), (cx + 1.08 * s, cy - 0.5 * s)]
    return shape_wobble(pts, seed, s * 0.02), tips


def heads_secret():
    img, c = chip_body(41, True)
    d = ImageDraw.Draw(img)
    s = SIZE * 0.2
    cy = c + SIZE * 0.03
    body, tips = crown(c, cy, s, 9)
    sh = SIZE * 0.012
    d.polygon([(x + sh, y + sh * 1.3) for x, y in body], fill=GOLD_DARK)
    d.polygon(body, fill=FELT)
    volume(img, body, c, s, (150, 110, 210), RAIL, 60, 70)
    d = ImageDraw.Draw(img)
    outline(d, body, INK, SIZE * 0.012)
    # обруч короны и камни
    band = [(c - 1.0 * s, cy + 0.2 * s), (c + 1.0 * s, cy + 0.2 * s), (c + 1.0 * s, cy + 0.45 * s), (c - 1.0 * s, cy + 0.45 * s)]
    band = shape_wobble(band, 12, s * 0.015)
    d.polygon(band, fill=GOLD)
    outline(d, band, INK, SIZE * 0.009)
    for i, x in enumerate([-0.6, 0.0, 0.6]):
        col = CYAN if i == 1 else PINK
        gx, gy = c + x * s, cy + 0.325 * s
        r = s * 0.1
        glow(img, lambda dd, cc, gx=gx, gy=gy, r=r: dd.ellipse((gx - r * 1.6, gy - r * 1.6, gx + r * 1.6, gy + r * 1.6), fill=cc), col, SIZE * 0.01, 150)
        d = ImageDraw.Draw(img)
        gem = wobble(gx, gy, r, 80 + i, 0.04, 30)
        d.polygon(gem, fill=col)
        outline(d, gem, INK, SIZE * 0.006)
    for i, (tx, ty) in enumerate(tips):
        ball = wobble(tx, ty, s * 0.11, 90 + i, 0.04, 30)
        d.polygon(ball, fill=GOLD)
        outline(d, ball, INK, SIZE * 0.008)
    # искры-звёздочки по бокам
    for i, (x, y, r) in enumerate([(-0.27, -0.2, 0.035), (0.27, -0.22, 0.03), (0.0, 0.25, 0.028)]):
        pts = star(c + x * SIZE, c + y * SIZE, SIZE * r, SIZE * r * 0.3, 4, seed=200 + i, amp=0.06)
        d.polygon(pts, fill=PINK_LIGHT if i != 1 else CYAN_LIGHT)
        outline(d, pts, INK, SIZE * 0.005)
    return img


def tails_secret():
    img, c = chip_body(43, True)
    # лучи-«сияние» из центра, приглушённые
    lay = new_layer()
    dl = ImageDraw.Draw(lay)
    rnd = random.Random(3)
    for i in range(16):
        a = math.tau * i / 16 + rnd.uniform(-0.03, 0.03)
        w = 0.09
        p = [(c, c), (c + math.cos(a - w) * SIZE * 0.4, c + math.sin(a - w) * SIZE * 0.4), (c + math.cos(a + w) * SIZE * 0.4, c + math.sin(a + w) * SIZE * 0.4)]
        dl.polygon(p, fill=(PINK if i % 2 == 0 else CYAN) + (70,))
    img.alpha_composite(clip(lay, wobble(c, c, SIZE * 0.36, 44, 0.01)))
    d = ImageDraw.Draw(img)
    f = font(HEAD, SIZE * 0.42)
    sh = SIZE * 0.014
    text_center(d, c + sh, c + sh * 1.3 + SIZE * 0.01, "K", f, fill=INK)
    text_center(d, c, c + SIZE * 0.01, "K", f, fill=PINK, stroke_width=int(SIZE * 0.01), stroke_fill=INK)
    return img


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "hub/art/coins"
    # поменялись местами (01.11): «джекпот» с королём — обычная, неоновый жетон — секретная
    regular = save_sheet(os.path.join(out_dir, "poker_coin.png"), heads_secret(), tails_secret())
    secret = save_sheet(os.path.join(out_dir, "poker_secret_coin.png"), heads(), tails())
    if len(sys.argv) > 2:
        preview([regular, secret], sys.argv[2], ((18, 8, 34), (233, 222, 247)))


if __name__ == "__main__":
    main()
