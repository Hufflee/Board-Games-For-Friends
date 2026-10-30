"""Обложка «Хором!» (своя, рисуется кодом): перед, зад и торец 900×1200 / 168×1200 в hub/covers.
Стиль игры: тетрадная бумага, чернила, коралловый акцент, синяя подсветка совпадений.
Запуск: python -I tools/cover_khorom.py
"""
from PIL import Image, ImageDraw, ImageFont

OUT = "hub/covers/khorom_%s.png"
PAPER = (251, 246, 236)
PAGE = (233, 225, 211)
INK = (47, 43, 51)
MUTED = (107, 101, 112)
ACCENT = (224, 121, 79)
MATCH = (91, 127, 224)
GOOD = (76, 175, 110)
BAD = (224, 82, 94)
HEAD = "games/brodilka/art/fonts/Oswald-Variable.ttf"
TEXT = "games/dangerous_words/art/fonts/Nunito-Variable.ttf"


def font(path, size, weight):
    f = ImageFont.truetype(path, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def lined(img, step=40, margin=90):
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))  # полупрозрачная линейка — отдельным слоем
    d = ImageDraw.Draw(overlay)
    w, h = img.size
    for y in range(step, h, step):
        d.line([(0, y), (w, y)], fill=(*MATCH, 40), width=2)
    d.line([(margin, 0), (margin, h)], fill=(*BAD, 70), width=3)
    img.alpha_composite(overlay)


def center_text(d, xy, text, f, fill, anchor="mm"):
    d.text(xy, text, font=f, fill=fill, anchor=anchor)


def notebook(img, box, title, rows, tilt=0):
    """Маленький блокнот: заголовок, строки с ответами; rows — [(текст, вид)] вид: plain/match/plate/good/bad."""
    x0, y0, x1, y1 = box
    layer = Image.new("RGBA", (x1 - x0 + 40, y1 - y0 + 40), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle((24, 28, x1 - x0 + 24, y1 - y0 + 28), 26, fill=(0, 0, 0, 50))
    d.rounded_rectangle((16, 16, x1 - x0 + 16, y1 - y0 + 16), 26, fill=PAPER, outline=(*INK, 60), width=3)
    d.text((44, 40), title, font=font(TEXT, 30, 800), fill=INK)
    d.line([(40, 92), (x1 - x0 - 8, 92)], fill=(*INK, 50), width=3)
    row_h = (y1 - y0 - 110) // len(rows)
    for i, (text, kind) in enumerate(rows):
        top = 104 + i * row_h
        area = (52, top + 8, x1 - x0 - 20, top + row_h - 10)
        if kind == "match":
            d.rounded_rectangle(area, 16, fill=(*MATCH, 40), outline=MATCH, width=4)
        if kind in ("good", "bad"):
            color = GOOD if kind == "good" else BAD
            d.rounded_rectangle(area, 16, fill=(*color, 110), outline=color, width=4)
        if kind == "plate":
            d.rounded_rectangle(area, 16, fill=(189, 183, 173), outline=(150, 145, 136), width=3)
            for sx in range(area[0] - 60, area[2], 22):
                a = max(sx, area[0] + 10)
                b = min(sx + (area[3] - area[1]), area[2] - 10)
                if b > a:
                    d.line([(a, area[3] - 4 - (a - sx)), (b, area[3] - 4 - (b - sx))], fill=(255, 255, 255, 60), width=4)
        else:
            d.text((area[0] + 14, (area[1] + area[3]) // 2), text, font=font(TEXT, 34, 700), fill=INK, anchor="lm")
        d.line([(40, top + row_h), (x1 - x0 - 8, top + row_h)], fill=(*MATCH, 70), width=2)
    if tilt:
        layer = layer.rotate(tilt, resample=Image.BICUBIC, expand=True)
    img.alpha_composite(layer, (x0 - 16, y0 - 16))


def front():
    img = Image.new("RGBA", (900, 1200), (*PAGE, 255))
    lined(img)
    d = ImageDraw.Draw(img)
    center_text(d, (450, 150), "ХОРОМ!", font(HEAD, 190, 700), ACCENT)
    center_text(d, (456, 158), "ХОРОМ!", font(HEAD, 190, 700), (*INK, 0))
    center_text(d, (450, 285), "игра на совпадение ответов", font(TEXT, 40, 700), INK)
    # Карточка темы.
    d.rounded_rectangle((210, 340, 690, 470), 22, fill=PAPER, outline=(*INK, 70), width=3)
    center_text(d, (450, 375), "ХОРОМ", font(TEXT, 26, 800), MUTED)
    center_text(d, (450, 425), "Что берут в поход", font(HEAD, 54, 700), INK)
    notebook(img, (70, 540, 430, 1010), "Аня", [("палатка", "match"), ("фонарь", "good"), ("", "plate"), ("компас", "plain")], tilt=4)
    notebook(img, (470, 560, 830, 1030), "Миша", [("палатки", "match"), ("", "plate"), ("фонарик", "good"), ("", "plate")], tilt=-4)
    d = ImageDraw.Draw(img)
    center_text(d, (450, 1110), "3–8 игроков  ·  20–30 минут", font(TEXT, 38, 800), INK)
    return img


def back():
    img = Image.new("RGBA", (900, 1200), (*PAGE, 255))
    lined(img)
    d = ImageDraw.Draw(img)
    center_text(d, (450, 120), "Как играть", font(HEAD, 96, 700), INK)
    blocks = [
        (ACCENT, "ХОРОМ", "Пишите до шести ответов на тему.\nСовпал с чьим-то — очко!"),
        (BAD, "БЕЛАЯ ВОРОНА", "Каждый ответ — очко,\nно совпавший его теряет."),
        (MATCH, "БЛИЦ", "Шесть тем, по ответу на каждую,\nи всего минута."),
    ]
    y = 250
    for color, title, text in blocks:
        d.rounded_rectangle((100, y, 800, y + 220), 24, fill=PAPER, outline=(*INK, 60), width=3)
        d.rounded_rectangle((100, y, 124, y + 220), 12, fill=color)
        d.text((160, y + 36), title, font=font(TEXT, 36, 800), fill=color)
        d.multiline_text((160, y + 96), text, font=font(TEXT, 36, 650), fill=INK, spacing=14)
        y += 260
    center_text(d, (450, 1080), "Ответы открываются по очереди —", font(TEXT, 34, 700), MUTED)
    center_text(d, (450, 1126), "похожие подсветятся сами", font(TEXT, 34, 700), MUTED)
    return img


def spine():
    img = Image.new("RGBA", (168, 1200), (*ACCENT, 255))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 167, 1199), outline=(*INK, 90), width=4)
    title = Image.new("RGBA", (1000, 168), (0, 0, 0, 0))
    td = ImageDraw.Draw(title)
    td.text((500, 84), "ХОРОМ!", font=font(HEAD, 120, 700), fill=PAPER, anchor="mm")
    title = title.rotate(90, expand=True)
    img.alpha_composite(title, (0, 100))
    d.ellipse((54, 1090, 114, 1150), fill=PAPER)
    d.text((84, 1120), "3–8", font=font(TEXT, 22, 800), fill=INK, anchor="mm")
    return img


if __name__ == "__main__":
    for part, make in (("front", front), ("back", back), ("spine", spine)):
        make().convert("RGB").save(OUT % part)
        print(OUT % part)
