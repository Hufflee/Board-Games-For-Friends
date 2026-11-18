"""Сверяет изображения Workshop со справочными графами. Запуск: python tools/compile_unmatched_workshop_maps.py."""

import json
import re
from pathlib import Path

import json5
from PIL import Image, ImageDraw


ROOT = Path("build/unmatched_sources")
ART = Path("games/unmatched/art/boards")
DATA = Path("games/unmatched/logic/um_workshop_maps.gd")
SLUGS = {
    "sherwood": "sherwood-forest",
    "hell_s_kitchen": "hells-kitchen",
    "santa_s_workshop": "santas-workshop",
    "king_solomon_s_mine": "king-solomons-mine",
    "thrilla_in_manila": "thrilla-in-manilla",
    "b_p_r_d_hq": "bprd-hq",
}
NAMES = {
    "phone_booth": "Телефонная будка", "bathroom_stall": "Кабинка туалета",
    "sherwood": "Шервудский лес", "yukon": "Юкон", "soho": "Сохо",
    "baskerville_manor": "Поместье Баскервилей", "king_solomon_s_mine": "Копи царя Соломона",
    "point_pleasant": "Пойнт-Плезант", "mcminnville_or": "Макминнвилл", "azuchi_castle": "Замок Адзути",
    "globe_theatre": "Театр «Глобус»", "sanctum_sanctorum": "Санктум Санкторум",
    "raptor_paddock": "Загон рапторов", "sunnydale_high": "Школа Саннидейла", "navy_pier": "Пирс Нейви",
    "helicarrier": "Хеликэрриер", "streets_of_novigrad": "Улицы Новиграда", "kaer_morhen": "Каэр Морхен",
    "fayrlund_forest": "Лес Ферлунда", "naglfar": "Нагльфар", "hell_s_kitchen": "Адская кухня",
    "t_rex_paddock": "Загон тираннозавра", "the_bronze": "Бронза", "the_raft": "Рафт", "venice": "Венеция",
    "santa_s_workshop": "Мастерская Санты", "yukon_1900": "Юкон 1900", "technodrome": "Технодром",
    "new_york_city": "Нью-Йорк", "heorot": "Хеорот", "tsing_shan_monastery": "Монастырь Циншань",
    "thrilla_in_manila": "Триллер в Маниле", "the_alamo": "Аламо", "the_white_house": "Белый дом",
    "pandemonium": "Пандемониум", "b_p_r_d_hq": "Штаб Б.П.И.З.",
}


def graph(slug):
    page = (ROOT / "workshop_map_graphs" / f"{slug}.html").read_text(encoding="utf-8")
    start = page.index("config:{graph:") + len("config:")
    end = page.index("}},fetchedMapTokens:", start) + 1
    data = json5.loads(page[start:end])
    box = re.search(r'class="[^"]*interactive-map[^"]*" viewBox="0 0 (\d+) (\d+)"', page)
    return data, tuple(map(int, box.groups()))


def geometry(id, image):
    if id in {"phone_booth", "bathroom_stall"}:
        centers = [(image.width / 2, image.height * .73), (image.width / 2, image.height * .27)]
        return {"spaces": [[round(x), round(y), z] for (x, y), z in zip(centers, "ab")],
                "starts": [0, 1], "edges": [[0, 1]]}
    data, (sx, sy) = graph(SLUGS.get(id, id.replace("_", "-")))
    inset = round(min(image.size) * .014)
    groups = list(data["zones"].values())
    spaces = []
    for i, point in enumerate(data["areas"], start=1):
        x = inset + point["x"] * (image.width - 2 * inset) / sx
        y = inset + point["y"] * (image.height - 2 * inset) / sy
        zones = "".join(chr(ord("a") + j) for j, group in enumerate(groups) if i in group)
        assert zones, (id, i)
        spaces.append([round(x), round(y), zones])
    paths = {(int(a) - 1, b - 1) for a, ends in data["graph"].items() for b in ends}
    edges = sorted({tuple(sorted(pair)) for pair in paths})
    one_way = sorted((a, b) for a, b in paths if (b, a) not in paths)
    passages = {(int(a) - 1, b - 1) for a, ends in data.get("passages", {}).items() for b in ends}
    move_only = sorted({tuple(sorted(pair)) for pair in passages - paths})
    starts = [data["positions"][key]["space"] - 1 for key in sorted(data["positions"], key=int)][:4]
    assert len(starts) in (2, 4) and len(set(starts)) == len(starts), id
    if id == "santa_s_workshop":
        one_way = [(0, 19), (1, 19), (2, 20), (5, 23), (8, 9), (33, 25)]
        edges = sorted(set(edges) | {tuple(sorted(pair)) for pair in one_way})
    return dict(spaces=spaces, starts=starts, edges=edges, one_way=one_way, move_only=move_only)


def read_art(id, entry):
    clean = ROOT / f"{id}_clean.webp"
    if id not in ("heorot", "raptor_paddock") and clean.exists():
        return Image.open(clean).convert("RGB")
    if id in ("heorot", "raptor_paddock") and clean.exists():
        height = 962 if id == "heorot" else 963
        with Image.open(clean) as source:
            picture = Image.new("RGB", (1700, height), "#24333b")
            picture.paste(source.convert("RGB").resize((1660, height - 40), Image.Resampling.LANCZOS), (20, 20))
            return picture
    if id == "heorot":
        picture = Image.open(ROOT / "heorot_source.jpeg").convert("RGB")
        picture.thumbnail((1700, 1700), Image.Resampling.LANCZOS)
        return picture
    picture = Image.open(ROOT / "workshop_boards" / entry["file"]).convert("RGB")
    if id == "pandemonium":
        picture = picture.transpose(Image.Transpose.ROTATE_90)
    return picture


def main():
    index = json.loads((ROOT / "workshop_boards/index.json").read_text(encoding="utf-8"))
    maps = {}
    marked = ROOT / "workshop_board_review"
    marked.mkdir(exist_ok=True)
    for id, name in NAMES.items():
        image = read_art(id, index[id])
        info = geometry(id, image)
        maps[id] = dict(name=name, **info, size=list(image.size))
        overlay = image.copy()
        draw = ImageDraw.Draw(overlay)
        for a, b in info["edges"]:
            draw.line([tuple(info["spaces"][i][:2]) for i in (a, b)], fill="#ff1bc7", width=4)
        for x, y, _ in info["spaces"]:
            draw.ellipse((x-8, y-8, x+8, y+8), fill="#25fe62")
        overlay.thumbnail((650, 650))
        overlay.save(marked / f"{id}.jpg", quality=86)
        image.save(ART / f"{id}.webp", quality=91)
    lines = ["{"]
    for id, info in maps.items():
        lines.append(f'\t"{id}": {{')
        for key, value in info.items():
            lines.append(f'\t\t"{key}": {json.dumps(value, ensure_ascii=False)},')
        lines.append("\t},")
    code = "\n".join([*lines, "}"])
    DATA.write_text("extends RefCounted\n## Графы полей Workshop. Источники и сверка: tools/compile_unmatched_workshop_maps.py.\n\nconst MAPS := " + code + "\n", encoding="utf-8")
    print(len(maps), "полей, изображения и графы.")


if __name__ == "__main__":
    main()
