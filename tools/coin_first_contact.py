"""Светлая монета «Первый контакт». Запуск: python tools/coin_first_contact.py [secret | dark_secret] [путь к PNG]."""
from math import sin, pi

from PIL import ImageColor

from coin_common import SIZE, glow
from coin_painted import blank, disk, polygon, sparkle, stroke, write_sheet, xy

INK = "#3b2a17"
OCHRE = "#b5741f"
PAPER = "#efe1bb"
SHIP = "#123c45"
ALIEN = "#15a99c"


def draw(heads, variant):
    dark = variant == "dark_secret"
    field = ("#232338" if heads else "#0d2a31") if dark else (PAPER if heads else SHIP)
    ink = "#f0e4c8" if dark else INK
    alien = "#3fe0cf" if variant else ALIEN
    img, d, _ = blank(field, alien if variant else "#b8975a", OCHRE, INK, 22)
    if variant:
        for i, (x, y) in enumerate([(20,41),(80,41),(25,65),(76,63)]):
            sparkle(d, x, y, 3.5, alien, i)
        # Корабль и пирамида дополняют прежние символы.
        disk(d, 50, 21, 6, alien, SHIP, 82, 1.1)
        stroke(d, [(40,23),(60,23)], alien, 3.4, 83)
        polygon(d, [(43,78),(50,70),(58,78)], "#e0a23e", ink, 84, .9)
    if heads:
        # Росчерк под глазом и бровь иероглифа.
        stroke(d, [(23,38),(36,31),(52,30),(67,33)], OCHRE, 3.4, 11)
        stroke(d, [(47,51),(46,67)], ink, 4.5, 12)
        stroke(d, [(55,51),(56,62),(62,69),(69,71),(73,67)], ink, 4.5, 13)
        top = [(x, 46 - 9*sin(pi*(x-24)/49)) for x in range(24, 74, 4)]
        bottom = [(x, 46 + 9*sin(pi*(x-24)/49)) for x in range(72, 24, -4)]
        polygon(d, [*top, (74,46), *bottom], "#f4e9cb", INK, 19, 3.3)
        disk(d, 49, 45.5, 8, OCHRE, INK, 16, 1.8)
        disk(d, 49, 45.5, 3.6, INK, INK, 17, .3)
    else:
        if variant:
            glow(img, lambda brush, color: brush.line(
                [xy(50,26), xy(72,65), xy(28,65), xy(50,26)], fill=color, width=int(SIZE*.07)
            ), ImageColor.getrgb(alien), SIZE*.025, 165)
        else:
            disk(d, 50, 50, 28, SHIP, "#7d6644", 17, 1.2)
        stroke(d, [(50,26),(72,65),(28,65),(50,26)], alien, 5.5, 19)
        disk(d, 50, 53, 5, "#eafffb", alien, 21, 1.3)
    return img


if __name__ == "__main__":
    write_sheet("first_contact", draw)
