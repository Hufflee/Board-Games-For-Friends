extends RefCounted
## Мёртвый груз893: иммунитет относится к боевому урону на единице, не ко всему урону.
const CASES := [
	{"name": "Единица предотвращает боевой урон", "card": 893,
	 "setup": {"dlc": true, "current": 0, "character": {0: 821}, "items": {0: [893]}, "monsters": {0: [344, {"hp": 5, "dc": 6, "at": 1}]}},
	 "do": [["roll", 1], ["ok", 0, "attack", {"slot": 0}], ["ok", 0, "roll"], ["close"]],
	 "expect": {"hp.0": 2, "phase": "battle_roll"}},
	{"name": "Двойка не даёт иммунитет", "card": 893,
	 "setup": {"dlc": true, "current": 0, "character": {0: 821}, "items": {0: [893]}, "monsters": {0: [344, {"hp": 5, "dc": 6, "at": 1}]}},
	 "do": [["roll", 2], ["ok", 0, "attack", {"slot": 0}], ["ok", 0, "roll"], ["close"]],
	 "expect": {"hp.0": 1}},
	{"name": "Небоевой урон не предотвращается", "card": 893,
	 "setup": {"dlc": true, "current": 0, "character": {0: 821}, "items": {0: [893]}, "hand": {0: [497]}},
	 "do": [["ok", 0, "loot", {"card": 497}], ["close"], ["choose", 0, "damage", {"target": 0}], ["close"]],
	 "expect": {"hp.0": 1}},
]
