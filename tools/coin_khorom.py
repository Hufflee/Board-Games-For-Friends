"""Монеты «Хором!» для антистресса (тетрадная бумага, чернила, коралл и синий — как games/khorom/ui/kh_style.gd).
  khorom_coin.png / khorom_dark_coin.png               — обычная: синяя «обложка тетради» по ободу, в середине листок
      в линейку с красными полями; орёл — два одинаковых облачка реплик (коралл и синее), решка — «!» из названия.
  khorom_secret_coin.png / khorom_dark_secret_coin.png — секретная «наградная наклейка»: золотая розетка с зубчиками;
      орёл — хор из трёх облачек под звездой, решка — красная «5» учителя (пять орлов — пятёрка).
Тёмные варианты — палитра тёмной темы игры. Лист 1774×887: слева орёл, справа решка.
Запуск: python -I tools/coin_khorom.py  → hub/art/coins/
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw  # noqa: E402
from coin_common import (SIZE, wobble, shape_wobble, outline, jitter_line, new_layer, clip, volume, edge,  # noqa: E402
                         star, font, text_center, save_sheet, preview)

HEAD = "games/brodilka/art/fonts/Oswald-Variable.ttf"
ACCENT = (224, 121, 79)
MATCH = (91, 127, 224)
GOOD = (76, 175, 110)
RED = (204, 72, 80)
GOLD = (222, 182, 92)
GOLD_DARK = (156, 116, 48)

LIGHT = {
    "ink": (47, 43, 51), "paper": (251, 246, 236), "paper_shade": (226, 214, 196), "rule": (150, 172, 228),
    "margin": (226, 140, 140), "cover": (96, 122, 190), "cover_dark": (62, 80, 136), "cover_light": (150, 172, 228),
    "bubble_text": (47, 43, 51),
}
DARK = {
    "ink": (24, 21, 29), "paper": (54, 49, 62), "paper_shade": (36, 32, 42), "rule": (80, 96, 150),
    "margin": (150, 82, 92), "cover": (70, 88, 146), "cover_dark": (40, 50, 88), "cover_light": (112, 132, 196),
    "bubble_text": (24, 21, 29),
}


def paper_face(img, c, r, pal, seed):
    """Листок в линейку: синие строки и красное поле слева."""
    face = wobble(c, c, r, seed, 0.01)
    d = ImageDraw.Draw(img)
    d.polygon(face, fill=pal["paper"])
    lines = new_layer()
    dl = ImageDraw.Draw(lines)
    step = SIZE * 0.062
    y = c - r + step * 0.6
    k = 0
    while y < c + r:
        jitter_line(dl, (c - r, y), (c + r, y + SIZE * 0.003), SIZE * 0.005, pal["rule"], seed + 30 + k, 6)
        y += step
        k += 1
    jitter_line(dl, (c - r * 0.62, c - r), (c - r * 0.6, c + r), SIZE * 0.007, pal["margin"], seed + 99, 6)
    img.alpha_composite(clip(lines, face))
    volume(img, face, c, r, (255, 255, 255) if pal is LIGHT else (110, 104, 122), pal["paper_shade"], 70, seed + 5)
    return face


def notebook_body(seed, pal):
    img = new_layer()
    c = SIZE / 2
    edge(img, c, SIZE * 0.462, pal["cover_dark"], pal["ink"], seed + 50)
    d = ImageDraw.Draw(img)
    rim = wobble(c, c, SIZE * 0.462, seed)
    d.polygon(rim, fill=pal["cover"])
    volume(img, rim, c, SIZE * 0.462, pal["cover_light"], pal["cover_dark"], 110, seed + 9)
    d = ImageDraw.Draw(img)
    # «прошивка» обложки — пунктир по ободу
    for i in range(44):
        a0 = math.tau * i / 44
        a1 = a0 + math.tau / 44 * 0.5
        p = (c + math.cos(a0) * SIZE * 0.428, c + math.sin(a0) * SIZE * 0.428)
        q = (c + math.cos(a1) * SIZE * 0.428, c + math.sin(a1) * SIZE * 0.428)
        jitter_line(d, p, q, SIZE * 0.007, pal["cover_light"], seed + 60 + i, 2)
    face = paper_face(img, c, SIZE * 0.38, pal, seed + 1)
    d = ImageDraw.Draw(img)
    outline(d, face, pal["ink"], SIZE * 0.009)
    outline(d, rim, pal["ink"], SIZE * 0.014)
    return img, c


def rosette_body(seed, pal):
    """Наградная наклейка: золотая розетка с зубчиками вместо обложки."""
    img = new_layer()
    c = SIZE / 2
    n = 18

    def scallop(cx, cy, r, amp):
        # круглые «лепестки» наклейки: выпуклые бугорки, острые впадины
        pts = []
        for i in range(n * 10):
            a = math.tau * i / (n * 10)
            k = 1 - amp * (1 - abs(math.cos(n * a / 2)))
            pts.append((cx + math.cos(a) * r * k, cy + math.sin(a) * r * k))
        return shape_wobble(pts, seed, SIZE * 0.0015)
    base = scallop(c + SIZE * 0.007, c + SIZE * 0.026, SIZE * 0.47, 0.07)
    d = ImageDraw.Draw(img)
    d.polygon(base, fill=GOLD_DARK)
    outline(d, base, pal["ink"], SIZE * 0.012)
    rim = scallop(c, c, SIZE * 0.47, 0.07)
    d.polygon(rim, fill=GOLD)
    volume(img, rim, c, SIZE * 0.47, (255, 236, 170), GOLD_DARK, 120, seed + 9)
    d = ImageDraw.Draw(img)
    # гофрировка розетки — лучи
    for i in range(n):
        a = math.tau * (i + 0.5) / n
        p = (c + math.cos(a) * SIZE * 0.39, c + math.sin(a) * SIZE * 0.39)
        q = (c + math.cos(a) * SIZE * 0.44, c + math.sin(a) * SIZE * 0.44)
        jitter_line(d, p, q, SIZE * 0.005, GOLD_DARK, seed + 70 + i, 3)
    outline(d, rim, pal["ink"], SIZE * 0.012)
    face = paper_face(img, c, SIZE * 0.36, pal, seed + 1)
    d = ImageDraw.Draw(img)
    ring = wobble(c, c, SIZE * 0.372, seed + 3, 0.008)
    outline(d, ring, (240, 210, 130), SIZE * 0.01)
    outline(d, face, pal["ink"], SIZE * 0.009)
    return img, c


def bubble(img, cx, cy, w, h, tail_dir, color, pal, seed, dots=True):
    """Облачко реплики: скруглённый неровный овал с хвостиком и тремя точками."""
    d = ImageDraw.Draw(img)
    pts = []
    rnd = random.Random(seed)
    ph = rnd.uniform(0, math.tau)
    for i in range(120):
        a = math.tau * i / 120
        k = 1 + 0.02 * math.sin(3 * a + ph)
        # «суперэллипс» — облачко больше похоже на табличку, чем на яйцо
        ca, sa = math.cos(a), math.sin(a)
        x = math.copysign(abs(ca) ** 0.7, ca) * w * k
        y = math.copysign(abs(sa) ** 0.7, sa) * h * k
        pts.append((cx + x, cy + y))
    tx = cx + tail_dir * w * 0.45
    tail = shape_wobble([(tx - w * 0.22 * tail_dir, cy + h * 0.6), (tx + w * 0.05 * tail_dir, cy + h * 0.6),
                         (tx + w * 0.25 * tail_dir, cy + h * 1.55)], seed + 1, w * 0.02)
    sh = SIZE * 0.012
    d.polygon([(x + sh, y + sh * 1.3) for x, y in pts], fill=pal["ink"])
    d.polygon([(x + sh, y + sh * 1.3) for x, y in tail], fill=pal["ink"])
    d.polygon(tail, fill=color)
    outline(d, tail, pal["ink"], SIZE * 0.011)
    d.polygon(pts, fill=color)
    outline(d, pts, pal["ink"], SIZE * 0.012)
    if dots:
        for k in range(3):
            x = cx + (k - 1) * w * 0.42
            dot = wobble(x, cy, w * 0.11, seed + 10 + k, 0.06, 30)
            d.polygon(dot, fill=pal["bubble_text"])


def heads(pal, seed):
    img, c = notebook_body(seed, pal)
    s = SIZE
    bubble(img, c - s * 0.07, c - s * 0.09, s * 0.15, s * 0.095, -1, ACCENT, pal, seed + 200)
    bubble(img, c + s * 0.08, c + s * 0.08, s * 0.15, s * 0.095, 1, MATCH, pal, seed + 210)
    return img


def tails(pal, seed):
    img, c = notebook_body(seed, pal)
    d = ImageDraw.Draw(img)
    f = font(HEAD, SIZE * 0.5, 700)
    sh = SIZE * 0.016
    text_center(d, c + sh, c + sh * 1.3, "!", f, fill=pal["ink"])
    text_center(d, c, c, "!", f, fill=ACCENT, stroke_width=int(SIZE * 0.011), stroke_fill=pal["ink"])
    return img


def heads_secret(pal, seed):
    img, c = rosette_body(seed, pal)
    s = SIZE
    bubble(img, c - s * 0.13, c + s * 0.08, s * 0.11, s * 0.075, -1, ACCENT, pal, seed + 200)
    bubble(img, c + s * 0.13, c + s * 0.08, s * 0.11, s * 0.075, 1, MATCH, pal, seed + 210)
    bubble(img, c, c - s * 0.01, s * 0.12, s * 0.08, 1, GOOD, pal, seed + 220)
    d = ImageDraw.Draw(img)
    pts = star(c, c - s * 0.2, s * 0.08, s * 0.034, 5, seed=seed + 230, amp=0.05)
    d.polygon([(x + s * 0.01, y + s * 0.013) for x, y in pts], fill=pal["ink"])
    d.polygon(pts, fill=GOLD)
    outline(d, pts, pal["ink"], s * 0.009)
    return img


def tails_secret(pal, seed):
    img, c = rosette_body(seed, pal)
    # красная «5» учителя: чуть наклонена, с росчерком снизу
    f = font(HEAD, SIZE * 0.44, 600)
    lay = new_layer()
    d = ImageDraw.Draw(lay)
    text_center(d, c, c - SIZE * 0.02, "5", f, fill=RED, stroke_width=int(SIZE * 0.004), stroke_fill=RED)
    lay = lay.transform(lay.size, Image.AFFINE, (1, 0.18, -c * 0.18, 0, 1, 0), resample=Image.BICUBIC)
    shadow = Image.new("RGBA", lay.size, pal["ink"] + (0,))
    shadow.putalpha(lay.split()[3].point(lambda v: v * 0.35))
    img.alpha_composite(shadow, (int(SIZE * 0.01), int(SIZE * 0.013)))
    img.alpha_composite(lay)
    d = ImageDraw.Draw(img)
    # росчерк
    pts = []
    for i in range(30):
        t = i / 29
        pts.append((c - SIZE * 0.15 + t * SIZE * 0.31, c + SIZE * 0.2 + math.sin(t * math.pi) * SIZE * 0.03 - t * t * SIZE * 0.05))
    d.line(pts, fill=RED, width=int(SIZE * 0.016), joint="curve")
    return img


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "hub/art/coins"
    sheets = []
    for name, pal in [("khorom", LIGHT), ("khorom_dark", DARK)]:
        sheets.append(save_sheet(os.path.join(out_dir, name + "_coin.png"), heads(pal, 5), tails(pal, 9)))
        sheets.append(save_sheet(os.path.join(out_dir, name + "_secret_coin.png"), heads_secret(pal, 15), tails_secret(pal, 19)))
    if len(sys.argv) > 2:
        preview(sheets, sys.argv[2])


if __name__ == "__main__":
    main()
