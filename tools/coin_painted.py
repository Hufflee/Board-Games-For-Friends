"""Общие заготовки для рисованных монет по стайлбордам. Запускаются скрипты отдельных игр."""
from pathlib import Path
import sys

from PIL import ImageColor, ImageDraw

from coin_common import SIZE, edge, new_layer, outline, save_sheet, shape_wobble, star, volume, wobble

CENTER = SIZE / 2


def xy(x, y):
    """Координаты на эскизе 100×100."""
    return x * SIZE / 100, y * SIZE / 100


def blank(paper, rim, shade, ink, seed):
    img = new_layer()
    edge(img, CENTER, SIZE * .452, ImageColor.getrgb(shade), ImageColor.getrgb(ink), seed, amp=.003)
    d = ImageDraw.Draw(img)
    outer = wobble(CENTER, CENTER, SIZE * .452, seed, .003)
    inner = wobble(CENTER, CENTER, SIZE * .385, seed + 1, .004)
    d.polygon(outer, fill=rim)
    volume(img, outer, CENTER, SIZE * .452, ImageColor.getrgb(paper), ImageColor.getrgb(shade), 80, seed)
    d.polygon(inner, fill=paper)
    outline(d, outer, ink, SIZE * .014)
    outline(d, inner, ink, SIZE * .009)
    return img, d, inner


def polygon(d, points, fill, ink, seed, width=1.4):
    pts = shape_wobble([xy(*p) for p in points], seed, SIZE * .004)
    d.polygon(pts, fill=fill)
    outline(d, pts, ink, SIZE * width / 100)


def stroke(d, points, color, width, seed):
    pts = shape_wobble([xy(*p) for p in points], seed, SIZE * .004)
    w = round(SIZE * width / 100)
    d.line(pts, fill=color, width=w, joint="curve")
    for x, y in pts:
        d.ellipse((x - w/2, y - w/2, x + w/2, y + w/2), fill=color)


def disk(d, x, y, radius, fill, ink, seed, width=1.3):
    pts = wobble(*xy(x, y), SIZE * radius / 100, seed, .025)
    d.polygon(pts, fill=fill)
    outline(d, pts, ink, SIZE * width / 100)


def sparkle(d, x, y, radius, color, seed):
    size = SIZE * radius / 100
    d.polygon(star(*xy(x, y), size, size * .32, 4, seed=seed, amp=.07), fill=color)


def write_sheet(game, draw):
    args = sys.argv[1:]
    variant = args.pop(0) if args and args[0] in ("dark", "secret", "dark_secret") else ""
    suffix = f"_{variant}" if variant else ""
    path = Path(args[0]) if args else (
        Path(__file__).resolve().parents[1] / "hub" / "art" / "coins" / f"{game}{suffix}_coin.png"
    )
    save_sheet(path, draw(True, variant), draw(False, variant))
