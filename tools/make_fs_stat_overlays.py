"""Собрать PNG-атлас цифр и фона статов Four Souls из имеющихся карт.

Из корня проекта: python tools/make_fs_stat_overlays.py (Pillow, NumPy, OpenCV).
"""

import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


ART = Path(__file__).resolve().parents[1] / "games/four_souls/art"
# Координаты печатных чисел в исходном изображении шириной 650 px.
STAT_AREAS = [(194, 516, 245, 577), (330, 516, 392, 577), (465, 516, 522, 577)]
TEXT_AREAS = [(33, 110, 54, 136), (252, 110, 283, 136), (361, 110, 384, 136)]
ROOM_AREAS = [(362, 413, 415, 472), (513, 413, 576, 472), (671, 411, 723, 472)]
# У этих карт рисунок касается печати. Ограничиваем маску видимой частью цифры.
OVERLAP_AREAS = {
    (261, 1): (331, 532, 389, 575),
    (261, 2): (473, 547, 506, 575),
    (271, 1): (338, 522, 389, 575),
    (306, 1): (331, 532, 389, 575),
    (313, 2): (476, 520, 511, 575),
    (348, 1): (331, 526, 389, 575),
    (465, 1): (331, 528, 389, 575),
}
# Цифры и плюс из печатной строки статов. Девятка — у Гуся.
GLYPHS = [
    (272, (468, 525, 515, 575)),
    (435, (473, 519, 500, 575)),
    (435, (199, 525, 239, 575)),
    (258, (330, 525, 366, 573)),
    (435, (330, 525, 362, 575)),
    (330, (331, 528, 371, 575)),
    (382, (198, 525, 231, 575)),
    (310, (198, 526, 237, 575)),
    (285, (198, 523, 237, 575)),
    (778, (363, 415, 405, 468)),
    (258, (366, 548, 389, 574)),
]


def source(card):
    return Image.open(ART / "cards" / f"{card}.webp").convert("RGB")


def ink_alpha(gray, light_ink=False):
    if light_ink:
        return np.clip((gray.astype(float) - 48) * (255 / 120), 0, 255).astype(np.uint8)
    return np.clip((170 - gray.astype(float)) * (255 / 140), 0, 255).astype(np.uint8)


def glyph(card, area):
    gray = np.asarray(source(card).crop(area).convert("L"))
    ink = ink_alpha(gray)
    _, labels, components, _ = cv2.connectedComponentsWithStats((ink > 65).astype(np.uint8))
    main = 1 + int(components[1:, cv2.CC_STAT_AREA].argmax())
    ink[cv2.dilate((labels == main).astype(np.uint8), np.ones((3, 3), dtype=np.uint8)) == 0] = 0
    alpha = Image.fromarray(ink)
    sprite = Image.new("RGBA", alpha.size, "white")
    sprite.putalpha(alpha)
    return sprite.crop(alpha.getbbox())


def paper(image, area, stat, light_ink=False, overlap=False):
    pixels = np.asarray(image.crop(area))
    gray = cv2.cvtColor(pixels, cv2.COLOR_RGB2GRAY)
    if light_ink:
        mask = (gray > 90).astype(np.uint8)
    elif overlap:
        mask = (gray < 115).astype(np.uint8)
    else:
        dark = (gray < 115).astype(np.uint8)
        _, labels, components, _ = cv2.connectedComponentsWithStats(dark)
        # Не затрагиваем рисунок, заходящий сверху на плашку (Искуситель, Роговик).
        digits = [i for i, (_, y, _, h, _) in enumerate(components[1:], 1)
                  if y >= 4 and h >= 28]
        if not digits:
            raise ValueError(f"Нет цифры в области {area}")
        main = max(digits, key=lambda i: components[i, cv2.CC_STAT_AREA])
        mask = (labels == main).astype(np.uint8)
        if stat == 1:
            for i, (x, y, _, h, size) in enumerate(components[1:], 1):
                if x >= 24 and y >= 26 and h >= 10 and size >= 35:
                    mask[labels == i] = 1
    # Стираем также полупрозрачные края печати, а внешний шов оставляем плавным.
    radius = 3 if light_ink else 7
    footprint = np.ones((radius, radius), dtype=np.uint8)
    mask = cv2.dilate(mask, footprint)
    cleaned = cv2.inpaint(pixels, mask, 3, cv2.INPAINT_TELEA)
    alpha = cv2.GaussianBlur(cv2.dilate(mask, np.ones((5, 5), dtype=np.uint8)) * 255, (5, 5), 0)
    cleaned[alpha == 0] = 0
    return Image.fromarray(np.dstack((cleaned, alpha)))


def main():
    manifest = json.loads((ART / "manifest.json").read_text(encoding="utf-8"))
    ids = [card["id"] for card in manifest["cards"] if card["kind"] == "monster"]
    ids += [3, 88, 467, 757, 778, 913, 914]  # фамильяры, засада, комнаты и Догма
    atlas = Image.new("RGBA", (1920, (1 + (len(ids) + 9) // 10) * 64))
    metadata = {"glyphs": [], "cards": {}}
    for n, (card, area) in enumerate(GLYPHS):
        sprite = glyph(card, area)
        atlas.paste(sprite, (n * 64 + 1, 1))
        metadata["glyphs"].append([n * 64 + 1, 1, *sprite.size])
    for n, card in enumerate(ids):
        image = source(card)
        light_ink = card in (913, 914)
        areas = list(TEXT_AREAS if light_ink else ROOM_AREAS if card in (757, 778) else STAT_AREAS)
        if card == 382:  # Восклицательный знак у атаки — часть печатной карты.
            areas[2] = (465, 516, 502, 577)
        tiles = []
        for stat, area in enumerate(areas):
            overlap = (card, stat) in OVERLAP_AREAS
            area = OVERLAP_AREAS.get((card, stat), area)
            try:
                patch = paper(image, area, stat, light_ink, overlap)
            except ValueError as error:
                raise ValueError(f"Карта {card}, стат {stat}: {error}") from error
            x = n % 10 * 192 + stat * 64 + 1
            y = (n // 10 + 1) * 64 + 1
            atlas.paste(patch, (x, y))
            tiles.append([x, y, *patch.size, *area[:2]])
        metadata["cards"][card] = tiles
    atlas.save(ART / "monster_stats.png", optimize=True)
    (ART / "monster_stats.json").write_text(json.dumps(metadata, separators=(",", ":")) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
