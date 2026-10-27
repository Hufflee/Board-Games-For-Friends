## Чистый реестр простых обязательных пассивов; вызывается через FSPassives.event_ops.
extends RefCounted

## Отсутствие условия отношения означает событие любого игрока, как в исходных привязках.
const REGISTRY := {
	6: [{"event": "coins", "conditions": {"owner_subject": true, "min_amount": 3},
		"operations": [{"op": "recharge", "amount": 1}]}],
	18: [{"event": "attack_roll", "conditions": {"owner_subject": true, "count": 3},
		"operations": [{"op": "temporary_attack", "amount": 1}]}],
	42: [{"event": "roll", "conditions": {"owner_subject": true},
		"operations": [{"op": "counter", "amount": 1}]}],
	47: [{"event": "monster_death", "conditions": {}, "operations": [{"op": "counter", "amount": 1}]}],
	55: [{"event": "roll", "conditions": {"face": 1}, "operations": [{"op": "counter", "amount": 1}]}],
	56: [{"event": "turn_end", "conditions": {"owner_current": true},
		"operations": [{"op": "counter", "amount": 1}]}],
	76: [{"event": "turn_end", "conditions": {"owner_current": true},
		"operations": [{"op": "coins", "amount": 1}]}],
	85: [{"event": "roll", "conditions": {"face": 2}, "operations": [{"op": "counter", "amount": 1}]}],
	124: [{"event": "damage", "conditions": {"owner_subject": true},
		"operations": [{"op": "kill_self", "amount": 1}]}],
	165: [{"event": "roll", "conditions": {"face": 5}, "operations": [{"op": "coins", "amount": 3}]}],
	166: [{"event": "death", "conditions": {"owner_subject": true},
		"operations": [{"op": "coins", "amount": 8}]}],
	180: [{"event": "damage", "conditions": {"owner_subject": true},
		"operations": [{"op": "counter", "amount": 1}]}],
	184: [{"event": "monster_death", "conditions": {}, "operations": [{"op": "coins", "amount": 3}]}],
	190: [{"event": "death", "conditions": {"owner_subject": true},
		"operations": [{"op": "loot", "amount": 3}]}],
	10: [{"event": "death", "conditions": {"owner_subject": true},
		"operations": [{"op": "counter", "amount": 3}]}],
	223: [{"event": "damage", "conditions": {"owner_subject": true},
		"operations": [{"op": "loot", "amount": 1}]}],
	231: [{"event": "roll", "conditions": {"face": 1}, "operations": [{"op": "loot", "amount": 1}]}],
	237: [{"event": "activate", "conditions": {"owner_subject": true},
		"operations": [{"op": "coins", "amount": 1}]}],
	654: [{"event": "death", "conditions": {}, "operations": [{"op": "loot", "amount": 1}]}],
	677: [{"event": "damage", "conditions": {"owner_subject": true},
		"operations": [{"op": "coins", "amount": 1}]}],
	830: [{"event": "damage", "conditions": {"owner_subject": true},
		"operations": [{"op": "recharge", "amount": 1}]}],
	838: [{"event": "after_death", "conditions": {"owner_subject": true},
		"operations": [{"op": "treasure", "amount": 1}]}],
	857: [
		{"event": "roll", "conditions": {"face": 6}, "operations": [{"op": "coins", "amount": 2}]},
		{"event": "death", "conditions": {"owner_subject": false}, "operations": [{"op": "loot", "amount": 1}]}
	]
}

const EVENTS := ["coins", "attack_roll", "roll", "monster_death", "turn_end", "damage", "death", "activate", "after_death"]

## Постоянные модификаторы атаки: свойства суммируются у всех действующих копий.
## Защита относится к монстрам в ход владельца; бросок и промах — к самому владельцу.
const ATTACK_MODIFIERS := {
	34: {"monster_evasion": -1, "miss_faces": [1, 6]},
	36: {"roll_bonus": 1, "ordinals": [1, 3, 5]}
}

static func attack_modifiers(entries: Array, ordinal: int) -> Dictionary:
	var result: Dictionary = {"monster_evasion": 0, "roll_bonus": 0, "miss_faces": []}
	for entry: Dictionary in entries:
		var binding: Dictionary = ATTACK_MODIFIERS.get(int(entry.id), {})
		result.monster_evasion += int(binding.get("monster_evasion", 0))
		if ordinal in binding.get("ordinals", []):
			result.roll_bonus += int(binding.get("roll_bonus", 0))
		for face: int in binding.get("miss_faces", []):
			if face not in result.miss_faces:
				result.miss_faces.append(face)
	return result

## Сначала все прибавки, затем ограничение d6: две копии не обрезаются по отдельности.
static func attack_roll(value: int, modifiers: Dictionary) -> int:
	return clampi(value + int(modifiers.roll_bonus), 1, 6)

static func attack_hits(value: int, evasion: int, modifiers: Dictionary) -> bool:
	return value >= evasion and value not in modifiers.miss_faces

static func monster_evasion(base: int, entries: Array) -> int:
	var modifiers: Dictionary = attack_modifiers(entries, 0)
	return clampi(base + int(modifiers.monster_evasion), 1, 6)

## Неизвестное или некорректное условие закрывает привязку, а не расширяет её.
static func matches(binding: Dictionary, owner: int, current: int, event: String, data: Dictionary) -> bool:
	if event not in EVENTS or binding.get("event") != event:
		return false
	if not binding.get("conditions") is Dictionary:
		return false
	var conditions: Dictionary = binding.conditions
	for key: Variant in conditions:
		var expected: Variant = conditions[key]
		match key:
			"owner_current", "owner_subject":
				if not expected is bool:
					return false
				var subject: int = current
				if key == "owner_subject":
					if not data.get("seat") is int:
						return false
					subject = data.seat
				if (owner == subject) != expected:
					return false
			"face", "count", "min_amount":
				var field: String = {"face": "value", "count": "count", "min_amount": "amount"}[key]
				if not expected is int or not data.get(field) is int:
					return false
				if expected < 1 or (key == "face" and expected > 6):
					return false
				var actual: int = data[field]
				if key == "min_amount":
					if actual < expected:
						return false
				elif actual != expected:
					return false
			_:
				return false
	return true

## Глубокая копия не разделяет изменяемые словари и вложенные массивы между вызовами.
static func copy_operations(binding: Dictionary) -> Array:
	var operations: Variant = binding.get("operations")
	return operations.duplicate(true) if operations is Array else []

static func event_ops(id: int, owner: int, current: int, event: String, data: Dictionary) -> Array:
	var result: Array = []
	for binding: Dictionary in REGISTRY.get(id, []):
		if matches(binding, owner, current, event, data):
			result.append_array(copy_operations(binding))
	return result
