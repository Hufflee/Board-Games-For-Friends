extends RefCounted
## Пакет P3 «Урон»: щиты по грани боевого урона, ограничение величины, жетоны вместо урона, удвоения.

const CASES := [
	{"name": "Плацента: боевой урон на четвёрке не проходит", "card": 112,
	 "setup": {"current": 0, "character": {0: 821}, "items": {0: [112]}, "monsters": {0: [344, {"dc": 6, "at": 1}]}},
	 "do": [["roll", 4], ["ok", 0, "attack", {"slot": 0}], ["ok", 0, "roll"], ["close"]],
	 "expect": {"hp.0": 3, "max_hp.0": 3}},
	{"name": "Дурная слава: боевой урон на единице не проходит", "card": 115,
	 "setup": {"current": 0, "character": {0: 821}, "items": {0: [115]}, "monsters": {0: [344, {"dc": 6, "at": 1}]}},
	 "do": [["roll", 1], ["ok", 0, "attack", {"slot": 0}], ["ok", 0, "roll"], ["close"]],
	 "expect": {"hp.0": 2}},
	{"name": "Сухой малыш: любой урон уменьшен до одного", "card": 164,
	 "setup": {"current": 0, "character": {0: 908}, "items": {0: [164]}, "monsters": {0: [344, {"dc": 6, "at": 3}]}},
	 "do": [["roll", 2], ["ok", 0, "attack", {"slot": 0}], ["ok", 0, "roll"], ["close"]],
	 "expect": {"hp.0": 2}},
	{"name": "Мёртвый кот: жетоны тратятся вместо урона", "card": 202,
	 "setup": {"current": 0, "character": {0: 821}, "items": {0: [202]}, "monsters": {0: [344, {"dc": 6, "at": 2}]}},
	 "do": [["roll", 2], ["ok", 0, "attack", {"slot": 0}], ["ok", 0, "roll"], ["close"]],
	 "expect": {"hp.0": 2, "items.0.1.counters": 7}},
	{"name": "Мозоль: небоевой урон не проходит", "card": 514,
	 "setup": {"dlc": true, "current": 0, "character": {0: 821}, "items": {0: [514]}, "hand": {0: [497]}},
	 "do": [["ok", 0, "loot", {"card": 497}], ["close"], ["choose", 0, "damage", {"target": 0}]],
	 "expect": {"hp.0": 2}},
]
