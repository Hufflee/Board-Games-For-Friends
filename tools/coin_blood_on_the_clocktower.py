"""Монета «Крови на часовой башне» для антистресса (тёмная готика, как games/blood_on_the_clocktower/ui/bc_style.gd).
Только тёмная тема — у игры нет светлой (решение владельца 05.11).
  blood_on_the_clocktower_coin.png — обычная: почерневшее железо с фиолетовым отливом (как коробка),
                                     обод — готические арки и бусины;
                                     орёл — циферблат башни с римскими цифрами, стрелки без пяти полночь;
                                     решка — капля крови в терновом венке, с потёками от обода.
06.11 владелец: ровнее, менее минималистично, мрачнее — контуры почти без дрожания, больше гравировки.
Лист 1774×887: слева орёл, справа решка. Запуск: python -I tools/coin_blood_on_the_clocktower.py  → hub/art/coins/
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import ImageDraw  # noqa: E402
from coin_common import (SIZE, wobble, outline, new_layer, clip, volume, edge, glow,  # noqa: E402
                         font, text_center, save_sheet, preview)

IRON = (74, 66, 84)
IRON_DARK = (44, 38, 52)
IRON_LIGHT = (118, 108, 128)
FACE = (34, 27, 44)
FACE_LIGHT = (56, 46, 70)
INK = (14, 10, 20)
GOLD = (150, 118, 64)
GOLD_LIGHT = (196, 164, 104)
BLOOD = (122, 24, 38)
BLOOD_DARK = (76, 12, 24)
BLOOD_LIGHT = (164, 60, 70)
BONE = (186, 174, 152)
EDGE = IRON_DARK
TITLE = "editor/fonts/extra/yesevaone/font.ttf"
EVEN = 0.003  # «ровнее»: дрожание контура почти незаметно
SECRET = False


def use_secret():
    """Секретная «полночь пробила»: позолоченный обод, кроваво-красные арки, чёрно-красное поле."""
    global IRON, IRON_DARK, IRON_LIGHT, FACE, FACE_LIGHT, GOLD, GOLD_LIGHT, BONE, EDGE, SECRET
    IRON = (150, 116, 60)
    IRON_DARK = (100, 22, 34)
    IRON_LIGHT = (204, 172, 108)
    FACE = (34, 10, 18)
    FACE_LIGHT = (66, 22, 32)
    GOLD = (212, 176, 98)
    GOLD_LIGHT = (240, 214, 150)
    BONE = (222, 196, 140)
    EDGE = (98, 74, 36)
    SECRET = True


def ring(c, r, seed, n=240):
    return wobble(c, c, r, seed, EVEN, n)


def body(seed):
    """Заготовка: гурт, железный обод с арками и бусинами, тёмное поле с гравированными лучами."""
    img = new_layer()
    c = SIZE / 2
    r = SIZE * 0.455
    edge(img, c, r, EDGE, INK, seed)
    d = ImageDraw.Draw(img)
    rim = ring(c, r, seed + 1)
    d.polygon(rim, fill=IRON)
    face_r = r * 0.8
    face = ring(c, face_r, seed + 2)
    d.polygon(face, fill=FACE)
    # Гравировка поля: тонкие лучи от центра — старый металл.
    for i in range(24):  # 06.11 владелец: меньше лучей (было 72)
        a = math.tau * i / 24
        d.line([(c + math.cos(a) * face_r * 0.18, c + math.sin(a) * face_r * 0.18),
                (c + math.cos(a) * face_r * 0.97, c + math.sin(a) * face_r * 0.97)], fill=FACE_LIGHT, width=int(SIZE * 0.002))
    volume(img, rim, c, r, IRON_LIGHT, INK, 70, seed + 3)
    volume(img, face, c, face_r, FACE_LIGHT, INK, 90, seed + 4)
    d = ImageDraw.Draw(img)
    # Обод: 16 готических арок со стрельчатым верхом, между ними бусины.
    arches = 16
    for i in range(arches):
        a0 = math.tau * (i + 0.12) / arches
        a1 = math.tau * (i + 0.88) / arches
        am = (a0 + a1) / 2
        base_r = r * 0.835
        top_r = r * 0.955
        pts = []
        for k in range(13):
            t = k / 12
            a = a0 + (a1 - a0) * t
            # стрельчатый свод: подъём к середине острый
            lift = (1 - abs(2 * t - 1)) ** 0.7
            pts.append((c + math.cos(a) * (base_r + (top_r - base_r) * (0.35 + 0.65 * lift)),
                        c + math.sin(a) * (base_r + (top_r - base_r) * (0.35 + 0.65 * lift))))
        pts.append((c + math.cos(a1) * base_r, c + math.sin(a1) * base_r))
        pts.append((c + math.cos(a0) * base_r, c + math.sin(a0) * base_r))
        d.polygon(pts, fill=IRON_DARK)
        d.line(pts + [pts[0]], fill=INK, width=int(SIZE * 0.004), joint="curve")
        # бусина между арками
        ab = math.tau * (i + 1) / arches
        bx, by = c + math.cos(ab) * r * 0.9, c + math.sin(ab) * r * 0.9
        br = SIZE * 0.009
        d.ellipse((bx - br, by - br, bx + br, by + br), fill=GOLD, outline=INK, width=int(SIZE * 0.003))
        # огонёк-окошко в арке: тусклое золото
        wx, wy = c + math.cos(am) * r * 0.885, c + math.sin(am) * r * 0.885
        wr = SIZE * 0.005
        d.ellipse((wx - wr, wy - wr * 1.6, wx + wr, wy + wr * 1.6), fill=GOLD)
    outline(d, rim, INK, SIZE * 0.012)
    outline(d, ring(c, r * 0.83, seed + 5), INK, SIZE * 0.006)
    outline(d, face, INK, SIZE * 0.009)
    outline(d, ring(c, face_r * 0.93, seed + 6), IRON_DARK, SIZE * 0.004)
    return img, d, c, face_r


def _hand(c, angle, length, width, tip):
    """Фигурная стрелка: тонкий стержень, ромб посередине, наконечник-пика или ромб."""
    ca, sa = math.cos(angle), math.sin(angle)
    px, py = -sa, ca

    def at(t, side):
        return (c + ca * length * t + px * side, c + sa * length * t + py * side)

    w = width
    pts = [at(-0.12, w * 0.6), at(0.45, w * 0.35), at(0.55, w * 1.3), at(0.65, w * 0.35)]
    if tip == "spade":
        pts += [at(0.82, w * 0.35), at(0.84, w * 1.5), at(1.0, 0), at(0.84, -w * 1.5), at(0.82, -w * 0.35)]
    else:
        pts += [at(0.86, w * 0.35), at(0.9, w * 1.1), at(1.0, 0), at(0.9, -w * 1.1), at(0.86, -w * 0.35)]
    pts += [at(0.65, -w * 0.35), at(0.55, -w * 1.3), at(0.45, -w * 0.35), at(-0.12, -w * 0.6)]
    return pts


def heads():
    img, d, c, r = body(11)
    # Римские цифры по кругу циферблата.
    numerals = ["XII", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
    # 06.11 владелец (секретная): цифры крупнее и заметнее, немного свечения.
    f = font(TITLE, SIZE * (0.068 if SECRET else 0.05))
    places = [(c + math.cos(-math.pi / 2 + math.tau * i / 12) * r * 0.74,
               c + math.sin(-math.pi / 2 + math.tau * i / 12) * r * 0.74) for i in range(12)]
    if SECRET:
        # Силуэт ореола шире цифр (обводка), иначе свечение прячется под ними.
        glow(img, lambda gd, col: [text_center(gd, x, y, label, f, fill=col, stroke_width=int(SIZE * 0.014), stroke_fill=col)
                                   for (x, y), label in zip(places, numerals)],
             GOLD, SIZE * 0.016, 200)
        d = ImageDraw.Draw(img)
    for (x, y), label in zip(places, numerals):
        text_center(d, x, y, label, f, fill=GOLD_LIGHT if SECRET else BONE,
                    stroke_width=int(SIZE * (0.005 if SECRET else 0.003)), stroke_fill=INK)
    # Минутные засечки внутри цифр.
    for i in range(60):
        a = -math.pi / 2 + math.tau * i / 60
        inner = r * (0.52 if i % 5 == 0 else 0.55)
        d.line([(c + math.cos(a) * inner, c + math.sin(a) * inner), (c + math.cos(a) * r * 0.58, c + math.sin(a) * r * 0.58)],
               fill=BONE if i % 5 == 0 else IRON_LIGHT, width=int(SIZE * (0.005 if i % 5 == 0 else 0.0025)))
    outline(d, ring(c, r * 0.6, 30), IRON_DARK, SIZE * 0.004)
    if SECRET:
        # Секрет: у часов прорастают рога — изогнутые, от оси наружу и вверх.
        for side in [-1, 1]:
            horn = _horn(c, side, r)
            d.polygon([(x + SIZE * 0.008, y + SIZE * 0.011) for x, y in horn], fill=INK)
            d.polygon(horn, fill=(176, 156, 124))
            d.line(horn + [horn[0]], fill=INK, width=int(SIZE * 0.005), joint="curve")
    # Стрелки без пяти полночь: часовая почти на XII, минутная на XI (в секрете — обе на XII). Тень — вниз-вправо.
    minute = -math.pi / 2 if SECRET else -math.pi / 2 - math.tau / 12
    hour = -math.pi / 2 if SECRET else -math.pi / 2 - 0.04
    hands = [(hour, r * 0.5, SIZE * 0.014, "diamond"), (minute, r * 0.66, SIZE * 0.011, "spade")]
    if SECRET:
        # Тёплое свечение за стрелками и осью.
        glow(img, lambda gd, col: [gd.polygon(_hand(c, a, ln, w, t), fill=col) for a, ln, w, t in hands]
             + [gd.ellipse((c - SIZE * 0.05, c - SIZE * 0.05, c + SIZE * 0.05, c + SIZE * 0.05), fill=col)],
             GOLD, SIZE * 0.022, 210)
        d = ImageDraw.Draw(img)
    for angle, length, width, tip in hands:
        shadow = [(x + SIZE * 0.008, y + SIZE * 0.011) for x, y in _hand(c, angle, length, width, tip)]
        d.polygon(shadow, fill=INK)
        hand = _hand(c, angle, length, width, tip)
        d.polygon(hand, fill=GOLD)
        d.line(hand + [hand[0]], fill=INK, width=int(SIZE * 0.004), joint="curve")
    # Ось с каплей крови в центре.
    hub = ring(c, SIZE * 0.032, 70, 80)
    d.polygon(hub, fill=GOLD)
    outline(d, hub, INK, SIZE * 0.006)
    d.ellipse((c - SIZE * 0.013, c - SIZE * 0.013, c + SIZE * 0.013, c + SIZE * 0.013), fill=BLOOD, outline=INK, width=int(SIZE * 0.003))
    return img


def _horn(c, side, r):
    """Рог: изогнутая сужающаяся дуга от оси в сторону side (−1 влево, +1 вправо) и вверх."""
    left, right = [], []
    n = 24
    for i in range(n + 1):
        t = i / n
        # центральная линия: из-под оси вбок, затем круто вверх
        # расходятся вверх буквой V, у кончика отгибаются наружу
        x = c + side * r * (0.07 + 0.16 * t + 0.2 * t ** 3)
        y = c - r * (0.04 + 0.5 * t)
        w = r * 0.07 * (1 - t) ** 0.8
        # нормаль к центральной линии по производной
        dx = side * (0.16 + 0.6 * t ** 2)
        dy = -0.5
        length = math.hypot(dx, dy)
        nx, ny = -dy / length, dx / length
        left.append((x - nx * w, y - ny * w))
        right.append((x + nx * w, y + ny * w))
    return left + right[::-1]


def _drop(cx, cy, s):
    """Капля: круглое дно радиуса s с центром (cx, cy) и острие вверху; стороны касаются круга."""
    tip_distance = s * 2.1
    spread = math.acos(s / tip_distance)
    pts = [(cx, cy - tip_distance)]
    n = 80
    start = -math.pi / 2 + spread
    finish = -math.pi / 2 - spread + math.tau
    for i in range(n + 1):
        a = start + (finish - start) * i / n
        pts.append((cx + math.cos(a) * s, cy + math.sin(a) * s))
    return pts


def _thorns(d, c, r):
    """Терновый венок: двойная лоза и шипы наружу и внутрь."""
    for k, rr in enumerate([r * 0.86, r * 0.82]):
        outline(d, ring(c, rr, 90 + k, 160), INK, SIZE * 0.011)
        outline(d, ring(c, rr, 90 + k, 160), IRON_LIGHT, SIZE * 0.005)
    for i in range(28):
        a = math.tau * (i + 0.5 * (i % 2)) / 28
        out = i % 2 == 0
        base = r * (0.87 if out else 0.81)
        tip = r * (0.95 if out else 0.73)
        w = 0.05
        pts = [(c + math.cos(a - w) * base, c + math.sin(a - w) * base), (c + math.cos(a) * tip, c + math.sin(a) * tip),
               (c + math.cos(a + w) * base, c + math.sin(a + w) * base)]
        d.polygon(pts, fill=IRON_LIGHT, outline=INK)


def tails():
    img, d, c, r = body(17)
    _thorns(d, c, r)
    # Потёки крови от верха поля: три струйки с каплями на концах.
    drips = [(-0.3, 0.32), (0.05, 0.18), (0.34, 0.26)]
    if SECRET:
        drips = [(-0.5, 0.22), (-0.3, 0.36), (-0.08, 0.24), (0.14, 0.3), (0.36, 0.2), (0.54, 0.16)]
    for x_off, length in drips:
        x = c + r * x_off
        top = c - math.sqrt(max(0.0, (r * 0.95) ** 2 - (r * x_off) ** 2))
        bottom = top + r * length
        w = SIZE * 0.013
        d.rounded_rectangle((x - w / 2, top, x + w / 2, bottom), radius=w / 2, fill=BLOOD, outline=INK, width=int(SIZE * 0.003))
        drip = _drop(x, bottom + w * 0.4, w * 0.9)
        d.polygon(drip, fill=BLOOD)
        d.line(drip + [drip[0]], fill=INK, width=int(SIZE * 0.003))
    # Большая капля в центре венка.
    s = SIZE * 0.1
    cy = c + SIZE * 0.07
    if SECRET:
        # Красное свечение вокруг капли.
        glow(img, lambda gd, col: gd.polygon(_drop(c, cy, s * 1.3), fill=col), (214, 44, 60), SIZE * 0.04, 240)
        d = ImageDraw.Draw(img)
    d.polygon([(x + SIZE * 0.008, y + SIZE * 0.012) for x, y in _drop(c, cy, s)], fill=INK)
    drop = _drop(c, cy, s)
    d.polygon(drop, fill=BLOOD)
    # Рисованный объём: тёмный край справа снизу, матовый блик слева сверху.
    lay = new_layer()
    ld = ImageDraw.Draw(lay)
    ld.polygon(_drop(c + s * 0.16, cy + s * 0.1, s * 0.94), fill=BLOOD_DARK + (255,))
    ld.polygon(_drop(c - s * 0.06, cy - s * 0.04, s * 0.86), fill=(0, 0, 0, 0))
    img.alpha_composite(clip(lay, drop))
    d = ImageDraw.Draw(img)
    d.ellipse((c - s * 0.5, cy - s * 0.45, c - s * 0.24, cy - s * 0.05), fill=BLOOD_LIGHT)
    d.line(drop + [drop[0]], fill=INK, width=int(SIZE * 0.009), joint="curve")
    return img


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "hub/art/coins"
    sheet = save_sheet(os.path.join(out_dir, "blood_on_the_clocktower_coin.png"), heads(), tails())
    use_secret()
    secret = save_sheet(os.path.join(out_dir, "blood_on_the_clocktower_secret_coin.png"), heads(), tails())
    preview([sheet, secret], os.path.join("build", "coin_blood_on_the_clocktower_preview.png"), bgs=((31, 28, 37), (19, 30, 43)))


if __name__ == "__main__":
    main()
