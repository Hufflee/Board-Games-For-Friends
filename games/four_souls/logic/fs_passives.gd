class_name FSPassives
extends RefCounted
## Напечатанные постоянные свойства. Состояние и события применяет только хост FSRules.
const SimpleRules := preload("res://games/four_souls/logic/fs_passive_rules.gd")
const ATTACK := {16: 1, 28: 1, 41: 1, 108: 1, 124: 3, 143: 2, 230: 1, 234: 1, 254: 1, 471: 1, 652: 1}
const HEALTH := {39: 1, 79: 1, 88: 2, 112: 1, 147: 2, 174: 1, 249: 1}
const AUTOMATIC_OPS := {
	34: ["temporary_monster_dc"], 36: ["roll"],
	18: ["attack", "temporary_attack"],
	24: ["extra_attack"], 25: ["extra_attack"], 26: ["extra_attack"], 42: ["counter"],
	69: ["coins"], 77: ["coins"], 105: ["extra_buy"], 117: ["extra_attack"], 121: ["loot"],
	173: ["extra_buy"], 196: ["loot"], 200: ["loot"], 221: ["extra_loot"], 226: ["extra_loot"],
	254: ["attack", "extra_attack"], 877: ["extra_attack"], 838: ["treasure"],
	16: ["attack", "loot"], 45: ["counter", "coins", "loot", "treasure"],
	47: ["counter"], 55: ["counter"], 56: ["counter"], 58: ["counter", "loot"],
	85: ["counter"], 90: ["loot"], 161: ["coins"], 165: ["coins"],
	180: ["counter"], 184: ["coins"], 223: ["loot"], 231: ["loot"],
	237: ["coins"], 240: ["loot"], 250: ["loot"], 654: ["loot"],
	677: ["coins"], 857: ["coins", "loot"]}

static func handled_operation(id: int, op: String) -> bool:
	return op in AUTOMATIC_OPS.get(id, []) or (op == "attack" and ATTACK.has(id)) or (op == "max_hp" and HEALTH.has(id))

static func operation(op: String, amount: int = 1) -> Dictionary:
	return {"op": op, "amount": amount}

static func attack_modifiers(entries: Array, ordinal: int) -> Dictionary:
	return SimpleRules.attack_modifiers(entries, ordinal)

static func attack_roll(value: int, modifiers: Dictionary) -> int:
	return SimpleRules.attack_roll(value, modifiers)

static func attack_hits(value: int, evasion: int, modifiers: Dictionary) -> bool:
	return SimpleRules.attack_hits(value, evasion, modifiers)

static func monster_evasion(base: int, entries: Array) -> int:
	return SimpleRules.monster_evasion(base, entries)

## Только однозначные обязательные эффекты. Выбор цели и необязательные действия остаются панелью.
static func event_ops(game: RefCounted, owner: int, item: Dictionary, event: String, data: Dictionary) -> Array:
	var id: int = item.id
	var result: Array = SimpleRules.event_ops(id, owner, int(game.current), event, data)
	# Динамические значения и условия по состоянию остаются отдельными обработчиками.
	match event:
		"turn_start":
			if owner != game.current:
				return result
			if id == 45:
				var next: int = int(item.counters) + 1
				result.append(operation("counter"))
				if next == 2:
					result.append(operation("coins", 10))
				if next == 4:
					result.append(operation("loot", 4))
				if next == 6:
					result.append(operation("treasure", 2))
			if id == 90:
				var most := 0
				for souls: int in game.souls:
					most = maxi(most, souls)
				if most > int(game.souls[owner]):
					result.append(operation("loot", most - int(game.souls[owner])))
		"turn_end":
			if owner != game.current:
				return result
			if FSData.end_turn_recharge(id):
				result.append(operation("recharge"))
			if id == 161 and int(game.coins[owner]) == 0:
				result.append(operation("coins", 6))
			if (id == 240 and game.hands[owner].size() >= 8) or (id == 250 and game.hands[owner].is_empty()) or (id == 58 and game.hands[owner].size() < int(item.counters)):
				result.append(operation("loot", 2))
		"damage":
			if id == 177 and owner == int(data.seat):
				result.append(operation("counter", int(data.amount)))
		"coins":
			if id == 137 and owner != int(data.seat):
				result.append({"op": "give_coin", "from": int(data.seat), "amount": 1})
	return result

static func character_health(id: int) -> int:
	return 1 if id in [848, 866, 884] else (3 if id == 908 else 2)

static func stat_bonus(id: int, entry: Dictionary, hand_size: int, meat_cubes: int) -> Vector2i:
	var bonus := Vector2i(int(ATTACK.get(id, 0)), int(HEALTH.get(id, 0)))
	if id == 228 and hand_size == 0:
		bonus.x += 1
	if id == 30 and meat_cubes >= 2:
		bonus.x += 1
	if id == 31 and meat_cubes >= 2:
		bonus.y += 1
	if id == 518 and int(entry.counters) > 0:
		bonus.y += 1
	if id == 867:
		bonus.y += int(entry.counters)
	return bonus
