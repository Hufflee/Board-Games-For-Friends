extends RefCounted
## Пакет P3/P4: урон и цена покупки.

const CASES := [
	{"name": "Членская карта: магазин дешевле на 4", "card": 91,
	 "setup": {"dlc": true, "current": 0, "items": {0: [91]}, "coins": {0: 6}},
	 "do": [["ok", 0, "buy", {"slot": 0}], ["close"]],
	 "expect": {"coins.0": 0}},
	{"name": "Сделка Хранителя: магазин дешевле на 3", "card": 889,
	 "setup": {"dlc": true, "current": 0, "items": {0: [889]}, "coins": {0: 7}},
	 "do": [["ok", 0, "buy", {"slot": 0}], ["close"]],
	 "expect": {"coins.0": 0}},
	{"name": "Коробок Хранителя: при получении магазин +2", "card": 62,
	 "setup": {"dlc": true, "current": 0, "items": {0: [62]}},
	 "expect": {"size.shop": 4}},
	{"name": "Проклятый глаз: шестёрка +3 урона", "card": 144,
	 "setup": {"current": 0, "items": {0: [144]}, "monsters": {0: [344, {"dc": 1, "hp": 5}]}},
	 "do": [["roll", 6], ["ok", 0, "attack", {"slot": 0}], ["ok", 0, "roll"], ["close"]],
	 "expect": {"monsters.0.hp": 1}},
	{"name": "Поддельный пенни: каждое получение монет +1", "card": 675,
	 "setup": {"current": 0, "items": {0: [675]}, "hand": {0: [480]}, "coins": {0: 0}},
	 "do": [["ok", 0, "loot", {"card": 480}], ["close"]],
	 "expect": {"coins.0": 3}},
]
