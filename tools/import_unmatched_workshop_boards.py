"""Копирует изображения арен из кэша TTS. Запуск из корня: python tools/import_unmatched_workshop_boards.py."""

import json
import re
from pathlib import Path

from PIL import Image


MODS = Path.home() / "Documents/My Games/Tabletop Simulator/Mods"
OUTPUT = Path("build/unmatched_sources/workshop_boards")


def cache_key(value):
    return re.sub(r"[^a-z0-9]", "", value.lower())


def main():
    source = MODS / "Workshop/3627086854.json"
    workshop = json.loads(source.read_text(encoding="utf-8-sig"))
    cache = {
        cache_key(path.stem): path for path in (MODS / "Images").iterdir()
        if path.is_file()
    }
    OUTPUT.mkdir(parents=True, exist_ok=True)
    inventory = {}
    for bag in workshop["ObjectStates"]:
        for board in bag.get("ContainedObjects", []):
            if board.get("Name") != "Custom_Board":
                continue
            name = bag.get("Nickname", "").strip()
            if not name:
                continue
            url = board.get("CustomImage", {}).get("ImageURL", "")
            if not url:
                continue
            identity = re.sub("[^a-z0-9]+", "_", name.lower()).strip("_")
            cached = cache.get(cache_key(url)) or cache.get(cache_key(url.replace("https://", "http://")))
            data = {"name": name, "url": url}
            inventory[identity] = data
            if cached is None:
                continue
            with Image.open(cached) as image:
                image.thumbnail((1700, 1700), Image.Resampling.LANCZOS)
                name = f"{identity}.webp"
                image.convert("RGB").save(OUTPUT / name, quality=92)
                data.update(file=name, size=list(image.size))
    (OUTPUT / "index.json").write_text(json.dumps(inventory, indent=2) + "\n", encoding="utf-8")
    print(f"Полей в списке: {len(inventory)}. Изображений: {sum('file' in x for x in inventory.values())}.")


if __name__ == "__main__":
    main()
