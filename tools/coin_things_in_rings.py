"""Монета Things in Rings для антистресса: лист 1774×887, слева орёл (три кольца), справа решка (знак вопроса).
Бумажный комикс, как стол игры: кремовая бумага, чернильный контур, сдвинутая «печатная» тень, точки растра.
Рисуется кодом «от руки» (неровные контуры, приглушённые цвета) — решения владельца о монетах.
Запуск: python -I tools/coin_things_in_rings.py [выход]  → по умолчанию hub/art/coins/things_in_rings_coin.png
"""
import math
import random
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIDE = 887
SS = 2  # суперсэмплинг для мягких краёв
PAPER = (241, 230, 210)
PAPER_DARK = (214, 198, 172)
INK = (50, 44, 55)
CORAL = (226, 112, 92)
RINGS = [(76, 159, 194), (228, 183, 59), (220, 89, 96)]
FONT = "games/brodilka/art/fonts/Oswald-Variable.ttf"


def wobble(cx, cy, r, seed, amp=0.012, n=180):
    rnd = random.Random(seed)
    phases = [rnd.uniform(0, math.tau) for _ in range(4)]
    pts = []
    for i in range(n):
        a = math.tau * i / n
        k = 1 + amp * (math.sin(3 * a + phases[0]) + 0.6 * math.sin(5 * a + phases[1]) + 0.4 * math.sin(9 * a + phases[2]))
        pts.append((cx + math.cos(a) * r * k, cy + math.sin(a) * r * k))
    return pts


def outline(d, pts, color, width):
    d.line(pts + [pts[0]], fill=color, width=int(width), joint="curve")


def halftone(size, center, radius, color, step, seed):
    """Точки растра в нижней части монеты — комиксная «тень» без градиентов."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rnd = random.Random(seed)
    for y in range(0, size, step):
        for x in range(0, size, step):
            ox = x + (step / 2 if (y // step) % 2 else 0)
            dist = math.hypot(ox - center, y - center)
            if dist > radius:
                continue
            # гуще к правому нижнему краю
            k = ((ox - center) * 0.5 + (y - center)) / radius
            r = step * 0.32 * max(0.0, min(1.0, k * 1.4 - 0.2)) * (1 + rnd.uniform(-0.1, 0.1))
            if r > 0.6:
                d.ellipse((ox - r, y - r, ox + r, y + r), fill=color)
    return layer


def blank(seed):
    size = SIDE * SS
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2
    # «Печатная» тень, сдвинутая вниз-вправо, как у панелей стола.
    d.polygon(wobble(c + size * 0.012, c + size * 0.02, size * 0.465, seed + 9), fill=INK)
    rim = wobble(c, c, size * 0.46, seed)
    d.polygon(rim, fill=PAPER_DARK)
    face = wobble(c, c, size * 0.405, seed + 1)
    d.polygon(face, fill=PAPER)
    dots = halftone(size, c, size * 0.40, PAPER_DARK + (255,), int(size * 0.022), seed + 2)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(face, fill=255)
    img.paste(dots, (0, 0), Image.composite(dots.split()[3], Image.new("L", img.size, 0), mask))
    outline(d, rim, INK, size * 0.016)
    outline(d, face, INK, size * 0.009)
    # Короткие штрихи по ободу — «нарисовано пером».
    rnd = random.Random(seed + 4)
    for i in range(36):
        a = math.tau * i / 36 + rnd.uniform(-0.03, 0.03)
        p = (c + math.cos(a) * size * 0.418, c + math.sin(a) * size * 0.418)
        q = (c + math.cos(a) * size * 0.448, c + math.sin(a) * size * 0.448)
        d.line([p, q], fill=INK, width=int(size * 0.007))
    return img, d, c, size


def heads():
    img, d, c, size = blank(13)
    # Три кольца, как на поле: заливка полупрозрачная, пересечения темнее, контур чернилами.
    r = size * 0.17
    off = size * 0.105
    centers = [(c - off, c - off * 0.55), (c + off, c - off * 0.55), (c, c + off * 1.05)]
    fill = Image.new("RGBA", img.size, (0, 0, 0, 0))
    for index, (x, y) in enumerate(centers):
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).polygon(wobble(x, y, r, 30 + index, 0.02), fill=RINGS[index] + (150,))
        fill.alpha_composite(layer)
    img.alpha_composite(fill)
    d = ImageDraw.Draw(img)
    for index, (x, y) in enumerate(centers):
        outline(d, wobble(x, y, r, 30 + index, 0.02), INK, size * 0.013)
    # Маленькая «вещь» в общем центре — звёздочка.
    pts = []
    for i in range(10):
        a = -math.pi / 2 + math.tau * i / 10
        rr = size * (0.045 if i % 2 == 0 else 0.02)
        pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr))
    d.polygon(pts, fill=PAPER)
    outline(d, pts, INK, size * 0.007)
    return img


def tails():
    img, d, c, size = blank(17)
    # Крупный знак вопроса: какое правило у колец? Сдвинутая тень — как у заголовков.
    font = ImageFont.truetype(FONT, int(size * 0.52))
    try:
        font.set_variation_by_axes([700])
    except Exception:
        pass
    box = d.textbbox((0, 0), "?", font=font)
    x = c - (box[0] + box[2]) / 2
    y = c - (box[1] + box[3]) / 2
    sh = size * 0.014
    d.text((x + sh, y + sh * 1.4), "?", font=font, fill=INK)
    d.text((x, y), "?", font=font, fill=CORAL, stroke_width=int(size * 0.011), stroke_fill=INK)
    # Три точки-кольца под знаком.
    for index in range(3):
        px = c + (index - 1) * size * 0.075
        py = c + size * 0.33
        dot = wobble(px, py, size * 0.022, 50 + index, 0.05, 40)
        d.polygon(dot, fill=RINGS[index])
        outline(d, dot, INK, size * 0.006)
    return img


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "hub/art/coins/things_in_rings_coin.png"
    sheet = Image.new("RGBA", (SIDE * 2, SIDE), (0, 0, 0, 0))
    for index, side in enumerate([heads(), tails()]):
        side = side.filter(ImageFilter.GaussianBlur(0.6)).resize((SIDE, SIDE), Image.LANCZOS)
        sheet.alpha_composite(side, (index * SIDE, 0))
    sheet.save(out)
    view = Image.new("RGBA", sheet.size, (60, 52, 66, 255))
    view.alpha_composite(sheet)
    view.convert("RGB").resize((SIDE, SIDE // 2), Image.LANCZOS).save(out.replace(".png", "_view.png"))
    print(out)


if __name__ == "__main__":
    main()
