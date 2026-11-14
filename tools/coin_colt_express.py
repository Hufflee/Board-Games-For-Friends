"""Монета «Кольт Экспресс». Запуск: python tools/coin_colt_express.py [dark | secret | dark_secret] [путь к PNG]."""
from coin_common import SIZE, outline, star
from coin_painted import blank, disk, polygon, sparkle, stroke, write_sheet, xy

INK = "#3a2416"
PAPER = "#eadab3"
BRASS = "#c48a2c"
RED = "#b2382b"
CREAM = "#f3dca6"


def draw(heads, variant):
    dark = variant.startswith("dark")
    secret = variant.endswith("secret")
    paper = "#2e2947" if dark else PAPER
    brass = "#e2ac4a" if secret or dark else BRASS
    img, d, _ = blank(paper, brass, "#8a5a36", INK, 14)
    if secret:
        for i, (x, y) in enumerate([(22,29),(78,29),(23,71),(76,70)]):
            sparkle(d, x, y, 4, brass, i)
        # Тёмная пробоина в металле с неровным краем.
        polygon(d, [(46,9),(50,7),(54,10),(51,12),(47,12)], INK, INK, 67, .4)
    if dark and heads:
        disk(d, 41, 23, 6, "#ffcd6a", "#ffcd6a", 71, .4)
        disk(d, 44, 21, 6, paper, paper, 71, .4)
    if heads:
        for i, (x, y, r) in enumerate([(59, 28, 3), (65, 24, 4), (73, 23, 3)]):
            disk(d, x, y, r, "#b99363", "#b99363", 18+i, .3)
        # Кабина, котёл, труба и клиновидный путеочиститель.
        polygon(d, [(25,61),(25,41),(38,41),(39,52),(69,51),(71,59),
                    (81,68),(22,68),(22,61)], RED, INK, 6, 2.2)
        polygon(d, [(55,51),(54,41),(51,37),(63,37),(62,41),(60,51)], brass, INK, 7, 1.8)
        stroke(d, [(22,39),(39,38)], INK, 3.8, 8)
        polygon(d, [(28,44),(35,44),(35,53),(28,53)], ("#ffcd6a" if dark else CREAM), INK, 9)
        stroke(d, [(41,56),(62,56)], brass, 2.3, 10)
        stroke(d, [(25,76),(75,75)], "#8a5a36", 2.3, 11)
        for i, (x, r) in enumerate([(31, 8), (50, 7), (65, 6)]):
            disk(d, x, 67, r, brass, INK, 20+i, 2.1)
            disk(d, x, 67, 1.9, INK, INK, 30+i, .25)
    else:
        if secret:
            for i, (x, y) in enumerate([(50,15),(50,85),(19,51),(81,51)]):
                sparkle(d, x, y, 4, brass, 91+i)
        disk(d, 50, 50, 29, "#b99363", "#8a5a36", 30, 1.1)
        pts = star(*xy(50, 50), SIZE*.285, SIZE*.163, 6, seed=28, amp=.025)
        d.polygon(pts, fill=brass)
        outline(d, pts, INK, SIZE*.022)
        for i, (x, y) in enumerate(pts[::2]):
            disk(d, x*100/SIZE, y*100/SIZE, 2.7, brass, INK, 40+i, 1.1)
        disk(d, 50, 50, 9, RED, INK, 31, 1.7)
    return img


if __name__ == "__main__":
    write_sheet("colt_express", draw)
