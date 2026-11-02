extends RefCounted
## Последние пробелы auto-индекса: разность душ75 и вторая физическая Потерянная душа676.
const CASES := [
	{"name": "Опознавательный знак снижает защиту на отставание по душам", "card": 75,
	 "setup": {"dlc": true, "current": 0, "character": {0: 821, 1: 821}, "items": {0: [75]}, "souls": {1: [475, 676]}, "monsters": {0: [344, {"hp": 2, "dc": 5, "at": 1}]}},
	 "do": [["roll", 3], ["ok", 0, "attack", {"slot": 0}], ["ok", 0, "roll"], ["close"]],
	 "expect": {"monsters.0.hp": 1, "hp.0": 2}},
	{"name": "Опознавательный знак не действует в чужой ход", "card": 75,
	 "setup": {"dlc": true, "current": 1, "character": {0: 821, 1: 821}, "items": {0: [75]}, "souls": {1: [475, 676]}, "monsters": {0: [344, {"hp": 2, "dc": 5, "at": 1}]}},
	 "do": [["roll", 3], ["ok", 1, "attack", {"slot": 0}], ["ok", 1, "roll"], ["close"]],
	 "expect": {"monsters.0.hp": 2, "hp.1": 1}},
	{"name": "Вторая Потерянная душа тоже сохраняет физическую карту", "card": 676,
	 "setup": {"dlc": true, "current": 0, "character": {0: 821, 1: 821}, "hand": {0: [676]}},
	 "do": [["ok", 0, "loot", {"card": 676}], ["close"]],
	 "expect": {"souls.0": 1, "zone.676": "soul:0", "phase": "turn"}},
]
