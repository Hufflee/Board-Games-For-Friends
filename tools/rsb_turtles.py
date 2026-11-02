"""Черепахи-наклейки Ready Set Bet, силуэт B (выбран владельцем 02.11.2026).

Запуск из любого каталога: python -I tools/rsb_turtles.py
Результат: art/turtle_0..8.png и build/shots/rsb_turtles/compare.png.
Один контур из кривых Безье, круговое расширение маски на 5 px, SS×4.
RGB строго: цвет фишки / белый; сглаживание внешнего края — альфа.
На границе белого и цвета выбирается ближайший из двух цветов, без новых оттенков.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont, ImageChops

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "games/ready_set_bet/art"
OUT = ROOT / "build/shots/rsb_turtles"
OLD = ROOT / "backups/rsb_turtles_20261102/games/ready_set_bet/art"
SS = 4
SIZE = (146, 103)
BIG = tuple(v * SS for v in SIZE)
COLORS = ["32b3e4", "32b3e4", "f5b21b", "f05274", "030404", "f05274", "f5b21b", "32b3e4", "32b3e4"]
NUMBERS = ["2/3", "4", "5", "6", "7", "8", "9", "10", "11/12"]


def path(start, segments):
    """Замкнутый многоугольник из кубических кривых в координатах исходного PNG."""
    points = [start]
    for c1, c2, end in segments:
        a = points[-1]
        for j in range(1, 25):
            t = j / 24
            u = 1 - t
            points.append(tuple(u**3 * a[k] + 3*u*u*t*c1[k] + 3*u*t*t*c2[k] + t**3*end[k] for k in (0, 1)))
    return [(round(x * SS), round(y * SS)) for x, y in points]


def silhouette():
    mask = Image.new("L", BIG)
    d = ImageDraw.Draw(mask)
    # Четыре широкие лапы в шаге; задние видны в просветах между ближними.
    legs = [
        ((42, 62), [((44, 72), (40, 79), (42, 87)), ((45, 88), (49, 87), (50, 91)), ((51, 95), (38, 96), (35, 93)), ((29, 87), (26, 75), (27, 68))]),
        ((81, 62), [((88, 69), (90, 78), (94, 85)), ((101, 85), (105, 88), (104, 91)), ((101, 95), (88, 95), (85, 92)), ((79, 83), (72, 77), (70, 68))]),
        ((33, 62), [((34, 73), (28, 81), (22, 88)), ((22, 92), (19, 96), (16, 93)), ((13, 98), (10, 96), (9, 93)), ((3, 94), (5, 88), (6, 85)), ((13, 78), (15, 67), (20, 63))]),
        ((92, 60), [((102, 68), (108, 79), (113, 88)), ((120, 89), (124, 93), (121, 96)), ((119, 98), (116, 95), (114, 96)), ((111, 99), (107, 97), (103, 96)), ((98, 91), (95, 80), (83, 73))]),
    ]
    for start, curves in legs:
        d.polygon(path(start, curves), fill=255)
    # Хвост, панцирь и длинная шея с головой — одна заливка.
    d.polygon(path((9, 65), [
        ((16, 64), (21, 59), (25, 55)),
        ((34, 32), (50, 7), (75, 7)),
        ((97, 6), (108, 25), (111, 51)),
        ((111, 46), (116, 34), (124, 30)),
        ((132, 26), (141, 31), (141, 40)),
        ((142, 47), (137, 51), (130, 51)),
        ((120, 51), (112, 63), (103, 68)),
        ((83, 81), (47, 78), (27, 70)),
        ((19, 73), (13, 70), (9, 65)),
    ]), fill=255)
    return mask


def expand(mask, radius):
    """Евклидово расширение диском, без квадратных углов MaxFilter."""
    r = round(radius * SS)
    padded = Image.new("L", (BIG[0]+2*r, BIG[1]+2*r))
    padded.paste(mask, (r, r))
    result = padded.copy()
    for y in range(-r, r + 1):
        for x in range(-r, r + 1):
            if x*x + y*y <= r*r:
                result = ImageChops.lighter(result, ImageChops.offset(padded, x, y))
    return result.crop((r, r, r+BIG[0], r+BIG[1]))


def cuts():
    """Только глаз: по решению владельца панцирь сплошной, без линий."""
    mask = Image.new("L", BIG)
    d = ImageDraw.Draw(mask)
    d.ellipse((130*SS, 35*SS, 132*SS, 37*SS), fill=255)
    return mask


def token(index, body, rim, openings):
    rgb = tuple(bytes.fromhex(COLORS[index]))
    px = 27 if index == 8 else (35 if index == 0 else 40)
    f = ImageFont.truetype(str(ART / "fonts/Bitter-Variable.ttf"), px*SS)
    f.set_variation_by_axes([900])
    number = Image.new("L", BIG)
    d = ImageDraw.Draw(number)
    label = NUMBERS[index]
    # Та же оптическая середина (78, 48) и высота около 30 px, что у исходных цифр.
    box = d.textbbox((0, 0), label, font=f)
    width = box[2] - box[0]
    height = box[3] - box[1]
    glyph = Image.new("L", (width, height))
    ImageDraw.Draw(glyph).text((-box[0], -box[1]), label, font=f, fill=255)
    # Длинные номера сохраняют высоту: сжимаем только ширину внутри центрального сегмента.
    width = min(width, (59 if index == 8 else 56)*SS)
    glyph = glyph.resize((width, height), Image.Resampling.LANCZOS)
    number.paste(glyph, (78*SS-width//2, 48*SS-height//2))
    alpha = ImageChops.subtract(rim, openings).resize(SIZE, Image.Resampling.LANCZOS)
    colored = ImageChops.subtract(body, ImageChops.lighter(number, openings)).resize(SIZE, Image.Resampling.LANCZOS)
    img = Image.new("RGBA", SIZE)
    pixels = []
    for a, c in zip(alpha.getdata(), colored.getdata()):
        pixels.append((*(rgb if c > a / 2 else (255, 255, 255)), a) if a else (0, 0, 0, 0))
    img.putdata(pixels)
    return img


def compare(tokens):
    """Две темы, сверху исходники, снизу черепахи; 100% и миниатюры 56×40."""
    result = Image.new("RGB", (1420, 760))
    f = ImageFont.truetype(str(ART / "fonts/Bitter-Variable.ttf"), 17)
    for row, bg in enumerate(["#efe2c4", "#17120d"]):
        y = row*380
        d = ImageDraw.Draw(result)
        d.rectangle((0, y, 1420, y+380), fill=bg)
        ink = "#2b1d14" if row == 0 else "#f3e7cc"
        d.text((16, y+8), "100% · сверху исходные фишки, снизу черепахи B · 146×103", font=f, fill=ink)
        for i, turtle in enumerate(tokens):
            src = ART / f"horse_{i}.png"
            horse = Image.open(src if src.exists() else OLD / src.name).convert("RGBA")
            x = 18+i*155
            result.paste(horse, (x, y+34), horse)
            result.paste(turtle, (x, y+145), turtle)
            for pic, yy in [(horse, y+281), (turtle, y+327)]:
                small = pic.resize((56, 40), Image.Resampling.LANCZOS)
                result.paste(small, (x+45, yy), small)
        d.text((16, y+255), "Меню · 56×40", font=f, fill=ink)
    result.save(OUT / "compare.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    body = silhouette()
    rim = expand(body, 5)
    openings = cuts()
    tokens = [token(i, body, rim, openings) for i in range(9)]
    report = []
    for i, img in enumerate(tokens):
        img.save(ART / f"turtle_{i}.png")
        allowed = {tuple(bytes.fromhex(COLORS[i])), (255, 255, 255)}
        assert img.size == SIZE
        assert {p[:3] for p in img.getdata() if p[3]} == allowed
        assert {p[3] for p in img.getdata()} >= {0, 255}
        report.append({"номер": NUMBERS[i], "цвет": COLORS[i], "границы": img.getbbox(), "RGB_цветов": 2})
    compare(tokens)
    (OUT / "palette.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Готово: 9 фишек; палитра каждой — ровно цвет + белый + прозрачность. Сравнение:", OUT / "compare.png")


if __name__ == "__main__":
    main()
