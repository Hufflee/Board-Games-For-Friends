"""Готовит локальные OCR-копии и каталог всех кандидатов на пассивные эффекты.
Скрипт не меняет игровые изображения. Распознанный текст не считается проверкой правил.
"""
from pathlib import Path
import json

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/fs_passive_audit"
INPUT = OUT / "ocr_input"
INPUT.mkdir(parents=True, exist_ok=True)
manifest = json.loads((ROOT / "games/four_souls/art/manifest.json").read_text(encoding="utf-8"))
responses = json.loads((ROOT / "games/four_souls/art/response_catalog.json").read_text(encoding="utf-8"))
catalog = []
for card, response in zip(manifest["cards"], responses["cards"]):
    kind = card["kind"]
    timing = response["response_kind"]
    trinket = kind == "loot" and card.get("lua", {}).get("type") == "trinkets"
    core = timing == "passive" or trinket
    included = core or kind in {"treasure", "eternal", "monster", "room", "character", "bonus"}
    included = included or (kind == "event" and card.get("lua", {}).get("type") == "curse")
    if not included:
        continue
    card_id = int(card["id"])
    item = {"id": card_id, "name": card["name"], "key": card["key"], "kind": kind,
            "base": card["base"], "core_passive": core, "response_kind": timing}
    ocr_path = OUT / "ocr" / f"{card_id}.json"
    if ocr_path.exists():
        item["ocr"] = json.loads(ocr_path.read_text(encoding="utf-8"))["text"]
    catalog.append(item)
    destination = INPUT / f"{card_id}.png"
    if destination.exists():
        continue
    with Image.open(ROOT / "games/four_souls/art/cards" / f"{card_id}.webp") as image:
        # Нижние 60% содержат правила; заголовок берётся из манифеста.
        cropped = image.crop((0, int(image.height * 0.4), image.width, image.height)).convert("L")
        cropped = ImageOps.autocontrast(cropped)
        cropped = cropped.resize((975, round(cropped.height * 975 / cropped.width)))
        cropped.save(destination)
(OUT / "candidates.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8")
print("Candidates", len(catalog), "core passive", sum(item["core_passive"] for item in catalog),
      "OCR", sum("ocr" in item for item in catalog))
