"""Монета «В общих чертах». Запуск: python tools/coin_in_broad_strokes.py [dark | secret | dark_secret] [путь к PNG]."""
from PIL import ImageDraw

from coin_common import SIZE, clip, new_layer, outline
from coin_painted import blank, polygon, sparkle, stroke, write_sheet, xy

INK = "#23302e"
STROKE = "#23272a"
PAPER = "#edf0ea"
GRID = "#c3d1cc"
BLUE = "#2d6cb3"
TAPE = (242, 217, 128)


def draw(heads, variant):
    dark = variant.startswith("dark")
    secret = variant.endswith("secret")
    paper = "#16396a" if dark or secret else PAPER
    grid_color = "#28568f" if dark or secret else GRID
    stroke_color = "#f3f8ff" if dark or secret else STROKE
    sheet = "#1b3f72" if dark or secret else "#fbfcf8"
    tape = "#ffd166" if secret else ("#a6bfe0" if dark else TAPE)
    rim = ("#4f7ab4" if dark else "#ffd166") if dark or secret else "#b9c6c1"
    img, d, inner = blank(paper, rim, "#1a2c45" if dark or secret else "#9fb2ad", INK, 56)
    grid = new_layer()
    dg = ImageDraw.Draw(grid)
    for i in range(10, 91, 8):
        dg.line([xy(i, 10), xy(i, 90)], fill=grid_color, width=int(SIZE*.003))
        dg.line([xy(10, i), xy(90, i)], fill=grid_color, width=int(SIZE*.003))
    img.alpha_composite(clip(grid, inner))
    outline(d, inner, INK, SIZE*.009)
    if secret:
        polygon(d, [(24,26),(76,26),(76,74),(24,74)], paper, tape, 51, 1.6)
        sparkle(d, 50, 20, 5, tape, 53)
    if heads:
        polygon(d, [(26,30),(72,29),(73,73),(26,73)], sheet, rim, 11, .7)
        polygon(d, [(23,35),(32,24),(37,28),(27,39)], tape, tape, 13, .4)
        polygon(d, [(64,71),(74,62),(78,67),(69,76)], tape, tape, 16, .4)
        stroke(d, [(30,49),(50,34),(69,49)], stroke_color, 3.3, 6)
        stroke(d, [(35,52),(35,66),(65,65)], stroke_color, 3.3, 9)
        stroke(d, [(65,65),(65,52)], stroke_color, 3.3, 12)
    else:
        polygon(d, [(28,60),(61,26),(73,38),(40,72),(23,77)], tape, STROKE, 8, 2.1)
        polygon(d, [(28,60),(40,72),(23,77)], "#fbfcf8", STROKE, 12, 1.8)
        polygon(d, [(23,77),(26,68),(32,74)], STROKE, STROKE, 13, .9)
        polygon(d, [(56,31),(63,24),(75,36),(69,43)], ("#4f7ab4" if dark else BLUE), STROKE, 15, 2.1)
        stroke(d, [(36,63),(60,39)], "#687a76", 1.4, 17)
    return img


if __name__ == "__main__":
    write_sheet("in_broad_strokes", draw)
