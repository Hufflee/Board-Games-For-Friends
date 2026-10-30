"""Монета The Gang для антистресса: лист 1774×887, слева орёл (циферблат сейфа), справа решка (звезда ограбления).
Рисуется кодом «от руки»: неровные контуры, приглушённые цвета, крупные символы (решения владельца о монетах).
Запуск: python -I tools/coin_the_gang.py  → hub/art/coins/the_gang_coin.png
"""
import math
import random
import sys
from PIL import Image, ImageDraw, ImageFilter

SIDE = 887
SS = 2  # суперсэмплинг для мягких краёв
BRASS = (184, 154, 82)
BRASS_DARK = (128, 104, 52)
BRASS_LIGHT = (214, 190, 122)
INK = (38, 31, 22)
RED = (142, 60, 46)
CREAM = (226, 212, 172)


def wobble(cx, cy, r, seed, amp=0.012, n=180):
    rnd = random.Random(seed)
    phases = [rnd.uniform(0, math.tau) for _ in range(4)]
    pts = []
    for i in range(n):
        a = math.tau * i / n
        k = 1 + amp * (math.sin(3 * a + phases[0]) + 0.6 * math.sin(5 * a + phases[1]) + 0.4 * math.sin(9 * a + phases[2]))
        pts.append((cx + math.cos(a) * r * k, cy + math.sin(a) * r * k))
    return pts


def jitter_line(d, p, q, width, color, seed):
    rnd = random.Random(seed)
    steps = 8
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = p[0] + (q[0] - p[0]) * t + rnd.uniform(-1, 1) * width * 0.12
        y = p[1] + (q[1] - p[1]) * t + rnd.uniform(-1, 1) * width * 0.12
        pts.append((x, y))
    d.line(pts, fill=color, width=int(width), joint="curve")


def outline(d, pts, color, width):
    d.line(pts + [pts[0]], fill=color, width=int(width), joint="curve")


def blank(seed):
    size = SIDE * SS
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2
    rim = wobble(c, c, size * 0.47, seed)
    d.polygon(rim, fill=BRASS_DARK)
    face = wobble(c, c, size * 0.43, seed + 1)
    d.polygon(face, fill=BRASS)
    # Рисованный объём: светлый серп сверху, без бликов и глянца.
    light = wobble(c - size * 0.015, c - size * 0.02, size * 0.40, seed + 2)
    shade = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ds = ImageDraw.Draw(shade)
    ds.polygon(light, fill=BRASS_LIGHT + (70,))
    ds.polygon(wobble(c + size * 0.02, c + size * 0.035, size * 0.40, seed + 3), fill=(0, 0, 0, 0))
    img.alpha_composite(shade)
    outline(d, rim, INK, size * 0.014)
    outline(d, face, INK, size * 0.008)
    # Насечки по ободу, чуть неровные.
    rnd = random.Random(seed + 4)
    for i in range(48):
        a = math.tau * i / 48 + rnd.uniform(-0.01, 0.01)
        p = (c + math.cos(a) * size * 0.435, c + math.sin(a) * size * 0.435)
        q = (c + math.cos(a) * size * 0.462, c + math.sin(a) * size * 0.462)
        jitter_line(d, p, q, size * 0.006, INK, seed + 10 + i)
    return img, d, c, size


def heads():
    img, d, c, size = blank(7)
    # Циферблат сейфа: кольцо делений, ручка-«штурвал» и указатель.
    dial = wobble(c, c, size * 0.31, 21, 0.01)
    d.polygon(dial, fill=CREAM)
    outline(d, dial, INK, size * 0.012)
    for i in range(24):
        a = math.tau * i / 24 - math.pi / 2
        long = i % 6 == 0
        p = (c + math.cos(a) * size * (0.235 if long else 0.255), c + math.sin(a) * size * (0.235 if long else 0.255))
        q = (c + math.cos(a) * size * 0.295, c + math.sin(a) * size * 0.295)
        jitter_line(d, p, q, size * (0.013 if long else 0.008), INK, 40 + i)
    for i in range(3):
        a = math.tau * i / 3 - math.pi / 2 + 0.12
        q = (c + math.cos(a) * size * 0.2, c + math.sin(a) * size * 0.2)
        jitter_line(d, (c, c), q, size * 0.035, INK, 70 + i)
        knob = wobble(q[0], q[1], size * 0.03, 80 + i, 0.05, 40)
        d.polygon(knob, fill=RED)
        outline(d, knob, INK, size * 0.008)
    hub = wobble(c, c, size * 0.075, 90, 0.04, 60)
    d.polygon(hub, fill=RED)
    outline(d, hub, INK, size * 0.01)
    # Указатель сверху.
    tri = [(c - size * 0.03, c - size * 0.395), (c + size * 0.03, c - size * 0.395), (c, c - size * 0.335)]
    d.polygon(tri, fill=RED)
    outline(d, tri, INK, size * 0.008)
    return img


def tails():
    img, d, c, size = blank(11)
    # Веера красных лучей по краю — как на коробке.
    for corner in range(4):
        base = math.pi / 4 + corner * math.pi / 2
        for k in range(-2, 3):
            a = base + k * 0.11
            p = (c + math.cos(a) * size * 0.27, c + math.sin(a) * size * 0.27)
            q = (c + math.cos(a) * size * 0.39, c + math.sin(a) * size * 0.39)
            jitter_line(d, p, q, size * 0.012, RED, 200 + corner * 10 + k)
    # Крупная звезда ограбления.
    rnd = random.Random(5)
    pts = []
    for i in range(10):
        a = -math.pi / 2 + math.tau * i / 10
        r = size * (0.26 if i % 2 == 0 else 0.11) * (1 + rnd.uniform(-0.03, 0.03))
        pts.append((c + math.cos(a) * r, c + math.sin(a) * r + size * 0.01))
    d.polygon(pts, fill=CREAM)
    outline(d, pts, INK, size * 0.016)
    return img


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "hub/art/coins/the_gang_coin.png"
    sheet = Image.new("RGBA", (SIDE * 2, SIDE), (0, 0, 0, 0))
    for index, side in enumerate([heads(), tails()]):
        side = side.filter(ImageFilter.GaussianBlur(0.6)).resize((SIDE, SIDE), Image.LANCZOS)
        sheet.alpha_composite(side, (index * SIDE, 0))
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main()
