"""Собирает плотную гору из действующих обычных монет Fidget, без генерации рисунков.

Запуск из корня: python tools/make_coin_poster.py. Повторяемая раскладка, исходники не меняются.
"""
from pathlib import Path
import random
import re

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "hub/art/posters/coin_heap.png"
STYLES = (
    "king_of_12", "doubloon", "wavelength", "dangerous_words", "hues_and_cues",
    "ready_set_bet", "word_slam", "tip_top", "tip_top_18", "not_a_hat",
    "brodilka", "gloom", "four_souls", "stillion", "phantom_ink",
)
SIZE = (1600, 1120)


def sources():
    code = (ROOT / "hub/fidget.gd").read_text(encoding="utf-8")
    block = code.split("const TEXTURES := {", 1)[1].split("\n}", 1)[0]
    textures = dict(re.findall(r'^\s*"([^"]+)": \[(.*?)\],', block, re.M))
    block = code.split("const COIN_REGIONS := {", 1)[1].split("\n}", 1)[0]
    regions = dict(re.findall(r'^\s*"([^"]+)": \[(.*?)\],', block, re.M))
    sprites = []
    for style in STYLES:
        paths = re.findall(r'(?:COINS\s*\+\s*)?"([^"]+)"', textures[style])
        rects = re.findall(r"Rect2\((\d+), (\d+), (\d+), (\d+)\)", regions.get(style, ""))
        for side, path in enumerate(paths):
            relative = path.removeprefix("res://") if path.startswith("res://") else "hub/art/coins/" + path
            sprite = Image.open(ROOT / relative).convert("RGBA")
            if rects:
                x, y, width, height = map(int, rects[side])
                sprite = sprite.crop((x, y, x + width, y + height))
            sprite = sprite.crop(sprite.getbbox())
            sprites.append(sprite)
    return sprites


def main():
    rng = random.Random(251026)
    sprites = sources()
    canvas = Image.new("RGBA", SIZE)
    count = 0

    def place(x, y, diameter):
        nonlocal count
        coin = rng.choice(sprites).resize((diameter, diameter), Image.Resampling.LANCZOS)
        coin = coin.rotate(rng.uniform(-180, 180), Image.Resampling.BICUBIC, expand=True)
        at = (round(x - coin.width / 2), round(y - coin.height / 2))
        shadow = Image.new("RGBA", coin.size, (12, 9, 7, 0))
        shadow.putalpha(coin.getchannel("A").point(lambda a: round(a * 0.48)))
        shadow = shadow.filter(ImageFilter.GaussianBlur(4))
        canvas.alpha_composite(shadow, (at[0] + 4, at[1] + 7))
        canvas.alpha_composite(coin, at)
        count += 1

    # Под нижними слоями нет одноцветной подложки: весь кадр заполняют сами монеты.
    for y in range(-110, SIZE[1] + 180, 92):
        for x in range(-110, SIZE[0] + 180, 92):
            place(x + rng.uniform(-16, 16), y + rng.uniform(-16, 16), rng.randint(235, 270))

    # Холм растёт к центру; ближние монеты крупнее, края уходят за рамку постера.
    for y in range(90, SIZE[1] + 160, 112):
        half_width = 200 + y * 0.75
        centers = list(range(round(SIZE[0] / 2 - half_width), round(SIZE[0] / 2 + half_width), 145))
        rng.shuffle(centers)
        for x in centers:
            place(x + rng.uniform(-40, 40), y + rng.uniform(-40, 40), rng.randint(190, 250) + round(y * 0.04))

    alpha_min = canvas.getchannel("A").getextrema()[0]
    if alpha_min != 255:
        raise RuntimeError(f"В коллаже остались просветы: минимальная альфа {alpha_min}")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(OUTPUT, optimize=True)
    print(f"{OUTPUT}: {SIZE[0]}x{SIZE[1]}, {count} монет, 100% кадра закрыто монетами")


if __name__ == "__main__":
    main()
