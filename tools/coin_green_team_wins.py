"""Монета Green Team Wins. Запуск: python tools/coin_green_team_wins.py [dark | secret | dark_secret] [путь к PNG]."""
from pathlib import Path

from coin_common import SIZE, font, text_center
from coin_painted import blank, disk, polygon, sparkle, stroke, write_sheet, xy

INK = "#23313a"
TURQUOISE = "#5ccfdf"
PATTERN = "#49bccd"
GREEN = "#7cc242"
CREAM = "#fffdf6"


def draw(heads, variant):
    dark = variant.startswith("dark")
    secret = variant.endswith("secret")
    field = "#1c3b44" if dark else TURQUOISE
    pattern = "#3d585e" if dark else PATTERN
    green = "#8fd654" if secret or dark else GREEN
    img, d, _ = blank(field, green if secret else ("#3d585e" if dark else "#eaf6f3"), pattern, INK, 38)
    if secret:
        for i, (x, y, color) in enumerate([
            (24,28,"#f7a043"), (76,27,green), (18,60,green), (80,60,"#f7a043"),
            (34,74,"#f7a043"), (65,74,green),
        ]):
            sparkle(d, x, y, 3.5, color, i)
        polygon(d, [(38,23),(42,32),(58,32),(62,23),(54,26),(50,19),(46,26)],
                green, INK, 77)
    for i, pts in enumerate([[(23,35),(34,25),(35,36)], [(69,30),(76,34),(68,41)],
                             [(21,59),(30,58),(28,68)], [(65,68),(77,63),(74,75)]]):
        polygon(d, pts, pattern, pattern, 12+i, .5)
    stroke(d, [(38,76),(44,72),(49,76),(55,72),(60,75)], pattern, 2.8, 44)
    if heads:
        polygon(d, [(22,49),(31,41),(44,53),(68,29),(78,39),(44,70)],
                green, INK, 10, 2.8)
    else:
        font_path = Path(__file__).resolve().parents[1] / "games/green_team_wins/art/fonts/BalsamiqSans-Bold.ttf"
        number = font(str(font_path), SIZE*.162)
        for i, (x, y) in enumerate([(28,51),(50,46),(72,52)], 1):
            fill = green if secret and i == 2 else CREAM
            disk(d, x, y, 10.4, fill, INK, 22+i, 2.2)
            text_center(d, *xy(x, y), str(i), number, fill=INK)
    return img


if __name__ == "__main__":
    write_sheet("green_team_wins", draw)
