"""Секретная монета Things in Rings: тот же бумажный комикс, что у обычной (tools/coin_things_in_rings.py), но «золотой выпуск».
Обод — золотая фольга со звёздочками вместо штрихов, за символом — комиксная вспышка «БАМ!».
Орёл — три кольца на вспышке, решка — «?!» (правило разгадано). Лист 1774×887: слева орёл, справа решка.
Запуск: python -I tools/coin_things_in_rings_secret.py [выход]  → по умолчанию hub/art/coins/things_in_rings_secret_coin.png
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw  # noqa: E402
import coin_things_in_rings as base  # noqa: E402
from coin_common import SIZE, wobble, outline, star, font, text_center, save_sheet, preview, volume, edge  # noqa: E402

INK = base.INK
PAPER = base.PAPER
PAPER_DARK = base.PAPER_DARK
GOLD = (226, 186, 92)
GOLD_DARK = (166, 126, 54)
GOLD_LIGHT = (246, 222, 150)
BURST = (246, 214, 112)
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
    outline(d, rim, INK, SIZE * 0.016)
    outline(d, face, INK, SIZE * 0.009)
    # звёздочки по ободу вместо штрихов пером
    for i in range(14):
        a = math.tau * i / 14 - math.pi / 2
        x, y = c + math.cos(a) * SIZE * 0.425, c + math.sin(a) * SIZE * 0.425
        pts = star(x, y, SIZE * 0.022, SIZE * 0.009, 5, rot=a + math.pi / 2, seed=seed + 60 + i, amp=0.08)
        d.polygon(pts, fill=PAPER)
        outline(d, pts, INK, SIZE * 0.005)
    return img, d, c


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
    burst(img, c, SIZE * 0.36, SIZE * 0.27, 5, (255, 249, 236))  # светлая: жёлтое кольцо не тонет
    r = SIZE * 0.14
    off = SIZE * 0.088
    centers = [(c - off, c - off * 0.55), (c + off, c - off * 0.55), (c, c + off * 1.05)]
    fill = Image.new("RGBA", img.size, (0, 0, 0, 0))
    for index, (x, y) in enumerate(centers):
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).polygon(wobble(x, y, r, 30 + index, 0.02), fill=RINGS[index] + (170,))
        fill.alpha_composite(layer)
    img.alpha_composite(fill)
    d = ImageDraw.Draw(img)
    for index, (x, y) in enumerate(centers):
        outline(d, wobble(x, y, r, 30 + index, 0.02), INK, SIZE * 0.013)
    # в общем центре — золотая звезда: «вещь», подходящая ко всем кольцам
    pts = star(c, c, SIZE * 0.05, SIZE * 0.022)
    d.polygon(pts, fill=GOLD)
    outline(d, pts, INK, SIZE * 0.008)
    return img


def tails():
    img, d, c = blank(29)
    burst(img, c, SIZE * 0.36, SIZE * 0.27, 9)
    d = ImageDraw.Draw(img)
    f = font(base.FONT, SIZE * 0.4, 700)
    sh = SIZE * 0.014
    gap = SIZE * 0.085
    for ch, x, col in [("?", c - gap, CORAL), ("!", c + gap, RINGS[0])]:
        text_center(d, x + sh, c + sh * 1.4, ch, f, fill=INK)
        text_center(d, x, c, ch, f, fill=col, stroke_width=int(SIZE * 0.011), stroke_fill=INK)
    return img


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "hub/art/coins/things_in_rings_secret_coin.png"
    sheet = save_sheet(out, heads(), tails())
    if len(sys.argv) > 2:
        regular = Image.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "hub/art/coins/things_in_rings_coin.png"))
        preview([regular.convert("RGBA"), sheet], sys.argv[2])


if __name__ == "__main__":
    main()
