"""Собирает карты Лавки Джо для 40 новых предметов «Большой бродилки».

Шаблон — карта из мода (art/cards/shop_clover.webp): её рамка, плашка названия и поле текста.
В окно картинки ставится иллюстрация art/items/<id>.png, на плашку — название, в поле — текст.
Данные (id, название, текст) берутся из games/brodilka/logic/br_data.gd — строки с copies = 1.

Запуск из корня проекта:  python -I tools/br_make_cards.py
Результат: games/brodilka/art/cards/shop_<id>.webp
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "games/brodilka/art"
TEMPLATE = ART / "cards/shop_clover.webp"
FONT = ART / "fonts/Oswald-Variable.ttf"

# области на шаблоне 812×1126
PIC = (89, 94, 728, 512)  # окно картинки (внутри рамки)
PLATE = (237, 495, 579, 559)  # плашка названия (внутри обводки)
BOX = (90, 547, 729, 1038)  # поле текста (внутри обводки)
INK = (62, 40, 22)


def font(size: int, weight: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONT), size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


def parchment(size, seed):
    """Бумага поля текста: тёплый пергамент, лёгкое зерно и затемнение к краям — как на картах мода."""
    w, h = size
    rng = np.random.default_rng(seed)
    base = np.array([248, 228, 184], np.float32)
    noise = Image.fromarray((rng.random((h // 6 + 1, w // 6 + 1)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    n = np.asarray(noise.filter(ImageFilter.GaussianBlur(2)), np.float32) / 255.0
    yy, xx = np.mgrid[0:h, 0:w]
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)).astype(np.float32)
    vign = 1.0 - 0.07 * np.clip(1.0 - edge / 40.0, 0, 1)
    rgb = base[None, None, :] * (0.97 + 0.05 * n)[..., None] * vign[..., None]
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8))


def wrap(draw, text, f, width):
    lines, cur = [], ""
    for word in text.split():
        t = (cur + " " + word).strip()
        if draw.textlength(t, font=f) <= width:
            cur = t
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def make(card: dict, tpl: Image.Image) -> Image.Image:
    im = tpl.copy()
    # картинка: заполняет окно целиком (лишнее по высоте обрезается), углы скруглены как у рамки
    pw, ph = PIC[2] - PIC[0], PIC[3] - PIC[1]
    art = Image.open(ART / "items" / f"{card['id']}.png").convert("RGB")
    s = max(pw / art.width, ph / art.height)
    art = art.resize((round(art.width * s), round(art.height * s)), Image.LANCZOS)
    ox, oy = (art.width - pw) // 2, (art.height - ph) // 2
    art = art.crop((ox, oy, ox + pw, oy + ph))
    im.paste(art, PIC[:2], rounded_mask((pw, ph), 22))
    # поле текста: чистый пергамент (до плашки — плашка лежит поверх и не обрезается)
    bw, bh = BOX[2] - BOX[0], BOX[3] - BOX[1]
    im.paste(parchment((bw, bh), hash(card["id"]) & 0xFFFF), BOX[:2], rounded_mask((bw, bh), 18))
    # плашка с названием (поверх поля текста): старая надпись закрашивается цветом плашки
    plw, plh = PLATE[2] - PLATE[0], PLATE[3] - PLATE[1]
    plate = tpl.crop(PLATE)
    ImageDraw.Draw(plate).rounded_rectangle((3, 3, plw - 4, plh - 4), 10, fill=(233, 214, 167))
    im.paste(plate, PLATE[:2], rounded_mask((plw, plh), 12))
    d = ImageDraw.Draw(im)
    size = 38  # выше плашка не вмещает (низ букв обрезался бы)
    while size > 24 and d.textlength(card["name"].lower(), font=font(size, 500)) > plw - 24:
        size -= 1
    f = font(size, 500)
    d.text(((PLATE[0] + PLATE[2]) / 2, (PLATE[1] + PLATE[3]) / 2 + 1), card["name"].lower(), font=f, fill=INK, anchor="mm")
    size = 68  # крупно: на столе карты мелкие, текст должен читаться и в окне Лавки
    while True:
        f = font(size, 400)
        lines = wrap(d, card["text"], f, bw - 80)
        # строки выравниваем по длине: сужаем ширину, пока число строк не меняется (без «висящего» слова)
        width = bw - 80
        while len(lines) > 1 and width > (bw - 80) * 0.5:
            narrower = wrap(d, card["text"], f, width - 8)
            if len(narrower) != len(lines):
                break
            width -= 8
            lines = narrower
        line_h = size * 1.22
        if len(lines) * line_h <= bh - 80 or size <= 36:
            break
        size -= 2
    cy = (BOX[1] + BOX[3]) / 2 - (len(lines) - 1) * line_h / 2
    for i, ln in enumerate(lines):
        d.text(((BOX[0] + BOX[2]) / 2, cy + i * line_h), ln, font=f, fill=INK, anchor="mm")
    return im


def cards_from_data() -> list:
    src = (ROOT / "games/brodilka/logic/br_data.gd").read_text(encoding="utf-8")
    res = []
    for m in re.finditer(r'\{id = "(\w+)", name = "([^"]+)",[^\n]*copies = 1[^\n]*text = "([^"]+)"\}', src):
        res.append({"id": m.group(1), "name": m.group(2), "text": m.group(3)})
    return res


def main() -> None:
    tpl = Image.open(TEMPLATE).convert("RGB")
    cards = cards_from_data()
    only = set(sys.argv[1:])
    for c in cards:
        if only and c["id"] not in only:
            continue
        make(c, tpl).save(ART / "cards" / f"shop_{c['id']}.webp", quality=90)
    print("карт:", len(cards))


if __name__ == "__main__":
    main()
