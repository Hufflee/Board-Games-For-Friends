"""Секретная монета Things in Rings: тот же бумажный комикс, что у обычной (tools/coin_things_in_rings.py), но «золотой выпуск».
Обод — золотая фольга со звёздочками вместо штрихов, за символом — комиксная вспышка «БАМ!».
Орёл — три кольца на вспышке, решка — «?!» (правило разгадано). Лист 1774×887: слева орёл, справа решка.
01.11 (владелец: «круче, ярче, заметнее»): обод — сияющая фольга с тремя цветными дугами колец, за вспышкой —
лучи, по монете — искры; символы светятся.
Запуск: python -I tools/coin_things_in_rings_secret.py [выход]  → по умолчанию hub/art/coins/things_in_rings_secret_coin.png
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw  # noqa: E402
import coin_things_in_rings as base  # noqa: E402
from coin_common import SIZE, wobble, outline, star, font, text_center, save_sheet, preview, volume, edge, glow, clip  # noqa: E402

INK = base.INK
PAPER = base.PAPER
PAPER_DARK = base.PAPER_DARK
GOLD = (240, 196, 72)
GOLD_DARK = (170, 120, 36)
GOLD_LIGHT = (255, 236, 160)
BURST = (255, 212, 84)
SPARK = (255, 252, 236)
CORAL = base.CORAL
RINGS = base.RINGS


def blank(seed):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    c = SIZE / 2
    edge(img, c, SIZE * 0.46, GOLD_DARK, INK, seed + 40)
    d = ImageDraw.Draw(img)
    rim = wobble(c, c, SIZE * 0.46, seed)
    d.polygon(rim, fill=GOLD)
    volume(img, rim, c, SIZE * 0.46, GOLD_LIGHT, GOLD_DARK, 150, seed + 7)
    d = ImageDraw.Draw(img)
    face = wobble(c, c, SIZE * 0.39, seed + 1)
    d.polygon(face, fill=PAPER)
    dots = base.halftone(SIZE, c, SIZE * 0.385, PAPER_DARK + (255,), int(SIZE * 0.022), seed + 2)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(face, fill=255)
    img.paste(dots, (0, 0), Image.composite(dots.split()[3], Image.new("L", img.size, 0), mask))
    # три цветные дуги колец по ободу — сразу видно «Things in Rings», и ярче обычной монеты
    for index in range(3):
        a0 = -math.pi / 2 + math.tau * index / 3 + 0.18
        a1 = a0 + math.tau / 3 - 0.36
        arc = []
        for k in range(40):
            a = a0 + (a1 - a0) * k / 39
            arc.append((c + math.cos(a) * SIZE * 0.452, c + math.sin(a) * SIZE * 0.452))
        for k in range(40):
            a = a1 - (a1 - a0) * k / 39
            arc.append((c + math.cos(a) * SIZE * 0.398, c + math.sin(a) * SIZE * 0.398))
        glow(img, lambda dd, cc, arc=arc: dd.polygon(arc, fill=cc), RINGS[index], SIZE * 0.012, 200)
        d = ImageDraw.Draw(img)
        d.polygon(arc, fill=RINGS[index])
        outline(d, arc, INK, SIZE * 0.007)
    outline(d, rim, INK, SIZE * 0.016)
    outline(d, face, INK, SIZE * 0.009)
    # звёздочки по ободу — в промежутках между дугами, со свечением
    for i in range(3):
        a = -math.pi / 2 + math.tau * i / 3
        x, y = c + math.cos(a) * SIZE * 0.425, c + math.sin(a) * SIZE * 0.425
        pts = star(x, y, SIZE * 0.034, SIZE * 0.013, 5, rot=a + math.pi / 2, seed=seed + 60 + i, amp=0.08)
        glow(img, lambda dd, cc, pts=pts: dd.polygon(pts, fill=cc), SPARK, SIZE * 0.012, 230)
        d = ImageDraw.Draw(img)
        d.polygon(pts, fill=SPARK)
        outline(d, pts, INK, SIZE * 0.006)
    return img, d, c


def rays(img, c, seed):
    """Лучи из центра под вспышкой — «золотой выпуск» сияет."""
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dl = ImageDraw.Draw(lay)
    rnd = random.Random(seed)
    for i in range(18):
        a = math.tau * i / 18 + rnd.uniform(-0.04, 0.04)
        w = 0.07
        col = RINGS[i % 3]
        dl.polygon([(c, c), (c + math.cos(a - w) * SIZE * 0.4, c + math.sin(a - w) * SIZE * 0.4),
                    (c + math.cos(a + w) * SIZE * 0.4, c + math.sin(a + w) * SIZE * 0.4)], fill=col + (110,))
    img.alpha_composite(clip(lay, wobble(c, c, SIZE * 0.385, seed + 1)))


def sparkles(img, c, seed, count=7):
    """Искры-четырёхлучевые звёздочки по полю монеты."""
    rnd = random.Random(seed)
    for i in range(count):
        a = rnd.uniform(0, math.tau)
        r = SIZE * rnd.uniform(0.25, 0.34)
        x, y = c + math.cos(a) * r, c + math.sin(a) * r
        size = SIZE * rnd.uniform(0.018, 0.03)
        pts = star(x, y, size, size * 0.28, 4, rot=0, seed=seed + i, amp=0.05)
        glow(img, lambda dd, cc, pts=pts: dd.polygon(pts, fill=cc), SPARK, SIZE * 0.008, 220)
        d = ImageDraw.Draw(img)
        d.polygon(pts, fill=SPARK)
        outline(d, pts, INK, SIZE * 0.004)


def burst(img, c, r_out, r_in, seed, color=BURST):
    """Комиксная вспышка: неровная многолучевая звезда со сдвинутой тенью."""
    d = ImageDraw.Draw(img)
    rnd = random.Random(seed)
    pts = []
    n = 14
    for i in range(n * 2):
        a = -math.pi / 2 + math.pi * i / n + rnd.uniform(-0.05, 0.05)
        r = (r_out if i % 2 == 0 else r_in) * (1 + rnd.uniform(-0.1, 0.1))
        pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
    sh = SIZE * 0.012
    d.polygon([(x + sh, y + sh * 1.4) for x, y in pts], fill=INK)
    d.polygon(pts, fill=color)
    outline(d, pts, INK, SIZE * 0.009)


def heads():
    img, d, c = blank(23)
    rays(img, c, 3)
    glow(img, lambda dd, cc: dd.ellipse((c - SIZE * 0.3, c - SIZE * 0.3, c + SIZE * 0.3, c + SIZE * 0.3), fill=cc), BURST, SIZE * 0.03, 180)
    burst(img, c, SIZE * 0.36, SIZE * 0.27, 5, (255, 249, 236))  # светлая: жёлтое кольцо не тонет
    r = SIZE * 0.14
    off = SIZE * 0.088
    centers = [(c - off, c - off * 0.55), (c + off, c - off * 0.55), (c, c + off * 1.05)]
    fill = Image.new("RGBA", img.size, (0, 0, 0, 0))
    for index, (x, y) in enumerate(centers):
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).polygon(wobble(x, y, r, 30 + index, 0.02), fill=RINGS[index] + (205,))
        fill.alpha_composite(layer)
    img.alpha_composite(fill)
    d = ImageDraw.Draw(img)
    for index, (x, y) in enumerate(centers):
        outline(d, wobble(x, y, r, 30 + index, 0.02), INK, SIZE * 0.013)
    # в общем центре — золотая звезда: «вещь», подходящая ко всем кольцам
    pts = star(c, c, SIZE * 0.065, SIZE * 0.028)
    glow(img, lambda dd, cc: dd.polygon(pts, fill=cc), SPARK, SIZE * 0.016, 240)
    d = ImageDraw.Draw(img)
    d.polygon(pts, fill=GOLD_LIGHT)
    outline(d, pts, INK, SIZE * 0.009)
    sparkles(img, c, 41)
    return img


def tails():
    img, d, c = blank(29)
    rays(img, c, 7)
    glow(img, lambda dd, cc: dd.ellipse((c - SIZE * 0.3, c - SIZE * 0.3, c + SIZE * 0.3, c + SIZE * 0.3), fill=cc), BURST, SIZE * 0.03, 180)
    burst(img, c, SIZE * 0.36, SIZE * 0.27, 9)
    d = ImageDraw.Draw(img)
    f = font(base.FONT, SIZE * 0.44, 700)
    sh = SIZE * 0.014
    gap = SIZE * 0.09
    for ch, x, col in [("?", c - gap, CORAL), ("!", c + gap, RINGS[0])]:
        glow(img, lambda dd, cc, ch=ch, x=x: text_center(dd, x, c, ch, f, fill=cc, stroke_width=int(SIZE * 0.02), stroke_fill=cc), SPARK, SIZE * 0.014, 230)
        d = ImageDraw.Draw(img)
        text_center(d, x + sh, c + sh * 1.4, ch, f, fill=INK)
        text_center(d, x, c, ch, f, fill=col, stroke_width=int(SIZE * 0.012), stroke_fill=INK)
    sparkles(img, c, 53, 5)
    return img


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "hub/art/coins/things_in_rings_secret_coin.png"
    sheet = save_sheet(out, heads(), tails())
    if len(sys.argv) > 2:
        regular = Image.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "hub/art/coins/things_in_rings_coin.png"))
        preview([regular.convert("RGBA"), sheet], sys.argv[2])


if __name__ == "__main__":
    main()
