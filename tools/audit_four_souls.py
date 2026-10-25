"""Каталог времени применения всех импортированных карт: python tools/audit_four_souls.py --project ."""
import argparse
import json
from collections import Counter
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--project", type=Path, default=Path.cwd())
args = parser.parse_args()
art = args.project / "games/four_souls/art"
manifest = json.loads((art / "manifest.json").read_text(encoding="utf-8"))
# На этих 45 картах Lua-тип отсутствует: значки/тексты проверены по русским изображениям.
passive_eternals = {838, 855, 857, 861, 867, 877, 881, 885, 903, 910}
paid_eternals = {853, 869, 873, 875, 901}
hybrid_eternals = {843, 879}
catalog = []
for card in manifest["cards"]:
    card_id = card["id"]
    kind = card["kind"]
    lua_type = card.get("lua", {}).get("type", "")
    timing = "none"
    reason = "Не является картой из личной руки или активируемым предметом."
    if kind == "loot":
        timing = "own_turn" if card["key"] == "sun" else "loot"
        reason = "Лут можно разыграть в чужой ход, потратив доступный розыгрыш (обычно поворот персонажа)."
        if timing == "own_turn":
            reason = "На русской карте Солнца дополнительный ход обусловлен своим ходом. В ответную группу не включается."
    elif kind == "eternal":
        timing = ("passive" if card_id in passive_eternals else
                  "paid" if card_id in paid_eternals else
                  "hybrid" if card_id in hybrid_eternals else
                  "conditional" if card_id == 883 else "tap")
        reason = "Визуально проверены значки и текст русской вечной карты; специальная цена/условие остаётся по тексту."
    elif kind == "treasure":
        timing = {"atreasure": "tap", "otreasure": "tap", "paidtreasure": "paid"}.get(lua_type, "passive")
        reason = "Тип способности взят из исходного мода: поворот, платная, одноразовая или пассивная."
        if card_id in {94, 257}:
            timing = "paid" if card_id == 94 else "tap"
            reason = "Особое сокровище: проверен значок на изображении (Экспериментальное лечение / Ящик Пандоры)."
    catalog.append({"id": card_id, "name": card["name"], "source_kind": kind,
                    "source_type": lua_type, "response_kind": timing, "reason": reason})
output = {"rules": ["https://foursouls.com/wp-content/uploads/2022/01/Booklet_cropped.pdf",
                    "https://foursouls.net/rules/turn-structure/",
                    "https://foursouls.net/rules/cards/"], "cards": catalog}
(art / "response_catalog.json").write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Классифицировано:", len(catalog), dict(Counter(c["response_kind"] for c in catalog)))
