extends RefCounted
## Пакет P2 «Модификаторы и ауры»: защита монстров в ход владельца, Соевое молоко, Клещ.

const CASES := [
	{"name": "Полифем: монстрам +1 защита в мой ход (5 против защиты 5 — промах)", "card": 143,
	 "setup": {"current": 0, "items": {0: [143]}, "monsters": {0: [344, {"dc": 5}]}, "hp": {0: 2}},
	 "do": [["roll", 5], ["ok", 0, "attack", {"slot": 0}], ["ok", 0, "roll"], ["close"]],
	 "expect": {"monsters.0.hp": 3, "hp.0": 1}},
	{"name": "Полифем: в чужой ход аура не действует", "card": 143,
	 "setup": {"current": 0, "items": {1: [143]}, "monsters": {0: [344, {"dc": 5}]}},
	 "do": [["roll", 5], ["ok", 0, "attack", {"slot": 0}], ["ok", 0, "roll"], ["close"]],
	 "expect": {"monsters.0.hp": 2}},
	{"name": "Соевое молоко: попадание ранит и остальных монстров", "card": 118,
	 "setup": {"current": 0, "items": {0: [118]}, "monsters": {0: [344, {"dc": 1}], 1: [344 + 1, {"hp": 3}]}},
	 "do": [["roll", 6], ["ok", 0, "attack", {"slot": 0}], ["ok", 0, "roll"], ["close"]],
	 "expect": {"monsters.0.hp": 2, "monsters.1.hp": 2}},
	{"name": "Клещ: первое убийство за ход — лечение и доп. атака", "card": 503,
	 "setup": {"dlc": true, "current": 0, "character": {0: 908}, "items": {0: [503]}, "monsters": {0: [344, {"dc": 1, "hp": 1}]}, "hp": {0: 2}},
	 "do": [["roll", 6], ["ok", 0, "attack", {"slot": 0}], ["ok", 0, "roll"], ["close"], ["roll", 2], ["ok", 0, "effect_roll"], ["close"]],
	 "expect": {"hp.0": 3, "attacked": false}},
]
