## Узкие проверки реестра: --headless --audio-driver Dummy --script res://tests/test_fs_passive_registry.gd.
extends SceneTree

const Passives := preload("res://games/four_souls/logic/fs_passives.gd")
const Registry := preload("res://games/four_souls/logic/fs_passive_rules.gd")

class GameState extends RefCounted:
	var current: int = 0
	var souls: Array[int] = [1, 4]
	var coins: Array[int] = [0, 5]
	var hands: Array = [[], [1, 2, 3]]

var checks: int = 0
var errors: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

## Ожидания выписаны по прежним веткам, включая отсутствие ограничения владельца у 165/231.
func expected(id: int, owner: int, current: int, event: String, data: Dictionary) -> Array:
	var op: String = ""
	var amount: int = 1
	match event:
		"roll":
			if id == 165 and data.value == 5:
				op = "coins"
				amount = 3
			if id == 231 and data.value == 1:
				op = "loot"
			if id == 857 and data.value == 6:
				op = "coins"
				amount = 2
			if (id == 55 and data.value == 1) or (id == 85 and data.value == 2) or (id == 42 and owner == data.seat):
				op = "counter"
		"coins":
			if id == 6 and owner == data.seat and data.amount >= 3:
				op = "recharge"
		"attack_roll":
			if id == 18 and owner == data.seat and data.count == 3:
				op = "temporary_attack"
		"monster_death":
			if id == 47:
				op = "counter"
			if id == 184:
				op = "coins"
				amount = 3
		"turn_end":
			if owner == current and id in [56, 76]:
				op = "counter" if id == 56 else "coins"
		"damage":
			if owner == data.seat:
				op = {180: "counter", 223: "loot", 677: "coins", 124: "kill_self", 830: "recharge"}.get(id, "")
		"activate":
			if id == 237 and owner == data.seat:
				op = "coins"
		"after_death":
			if id == 838 and owner == data.seat:
				op = "treasure"
		"death":
			if id == 654 or (id == 857 and owner != data.seat):
				op = "loot"
			if owner == data.seat:
				if id == 166:
					op = "coins"
					amount = 8
				if id == 190:
					op = "loot"
					amount = 3
				if id == 10:
					op = "counter"
					amount = 3
	return [] if op.is_empty() else [{"op": op, "amount": amount}]

func _initialize() -> void:
	var game := GameState.new()
	var ids: Array[int] = [6, 18, 42, 47, 55, 56, 76, 85, 124, 165, 166, 180, 184, 190, 10, 223, 231, 237, 654, 677, 830, 838, 857, -1]
	var events: Array[String] = [
		"roll", "coins", "attack_roll", "monster_death", "turn_start", "turn_end",
		"damage", "activate", "after_death", "death", "неизвестное"
	]
	for id: int in ids:
		for event: String in events:
			for current: int in 2:
				game.current = current
				for owner: int in 2:
					for seat: int in 2:
						for value: int in range(1, 7):
							for count: int in [2, 3, 4]:
								for amount: int in [0, 2, 3, 4]:
									var data: Dictionary = {"seat": seat, "value": value, "count": count, "amount": amount}
									var want: Array = expected(id, owner, current, event, data)
									var got: Array = Passives.event_ops(game, owner, {"id": id}, event, data)
									check(got == want, "Карта %d / %s / владелец %d / ход %d / %s: %s вместо %s" % [id, event, owner, current, data, got, want])
	game.current = 0
	# Неверные условия, типы и отсутствующие данные не должны давать совпадение.
	var invalid_conditions: Array = [
		null, [], {"неизвестное": true}, {"owner_subject": "да"}, {"owner_current": 1},
		{"face": "1"}, {"count": 3.0}, {"min_amount": null}, {"min_amount": -1},
		{"count": 0}, {"face": 7}, {"face": 0}
	]
	for conditions: Variant in invalid_conditions:
		check(not Registry.matches({"event": "roll", "conditions": conditions}, 0, 0, "roll", {"seat": 0, "value": 1, "count": 3, "amount": 4}),
			"Некорректное условие отклоняется: %s" % [conditions])
	for key: String in ["owner_subject", "face", "count", "min_amount"]:
		var value: Variant = true if key == "owner_subject" else 1
		check(not Registry.matches({"event": "roll", "conditions": {key: value}}, 0, 0, "roll", {}), "Нет данных для %s" % key)
		check(not Registry.matches({"event": "roll", "conditions": {key: value}}, 0, 0, "roll",
			{"seat": "0", "value": "1", "count": "1", "amount": "3"}), "Строки вместо чисел для %s" % key)
	check(not Registry.matches({"event": "неизвестное", "conditions": {}}, 0, 0, "неизвестное", {}), "Неизвестное событие отклоняется")
	check(not Registry.matches({"event": "roll"}, 0, 0, "roll", {}), "Отсутствующий словарь условий отклоняется")
	check(Registry.matches({"event": "roll", "conditions": {"owner_current": false}}, 1, 0, "roll", {}),
		"Отношение к текущему игроку: чужой ход")
	check(not Registry.matches({"event": "roll", "conditions": {"owner_current": false}}, 0, 0, "roll", {}),
		"Отношение к текущему игроку: исключён свой ход")
	check(not Registry.matches({"event": "roll", "conditions": {"face": 1, "опечатка": true}}, 0, 0, "roll", {"value": 1}),
		"Известное условие не скрывает неизвестное")
	for id: int in [6, 18, 42, 55, 85, 165, 231, 237, 830]:
		check(Registry.event_ops(id, 0, 0, Registry.REGISTRY[id][0].event, {}).is_empty(), "Отсутствующие данные карты %d" % id)
	# Изменение результата не затрагивает следующий вызов и константный реестр.
	var first: Array = Registry.event_ops(165, 0, 0, "roll", {"value": 5})
	first[0].amount = 100
	first.append({"op": "loot", "amount": 99})
	check(Registry.event_ops(165, 1, 0, "roll", {"value": 5}) == [{"op": "coins", "amount": 3}], "Независимые операции реальных карт")
	var binding: Dictionary = {"operations": [{"op": "loot", "nested": {"values": [1]}}]}
	var copied: Array = Registry.copy_operations(binding)
	copied[0].nested.values.append(2)
	check(Registry.copy_operations(binding)[0].nested.values == [1], "Глубокая копия вложенных значений")
	# Сложные ветки остаются доступны через прежний вход без повторного применения.
	var clock_ops: Array = [{"op": "counter", "amount": 1}, {"op": "coins", "amount": 10}]
	check(Passives.event_ops(game, 0, {"id": 45, "counters": 1}, "turn_start", {}) == clock_ops, "45: порядок нескольких операций")
	check(Passives.event_ops(game, 0, {"id": 90}, "turn_start", {}) == [{"op": "loot", "amount": 3}], "90: разница душ")
	check(Passives.event_ops(game, 0, {"id": 58, "counters": 1}, "turn_end", {}) == [{"op": "loot", "amount": 2}], "58: сравнение руки и жетонов")
	var penny_ops: Array = [{"op": "give_coin", "from": 1, "amount": 1}]
	check(Passives.event_ops(game, 0, {"id": 137}, "coins", {"seat": 1}) == penny_ops, "137: динамический отправитель")
	check(Passives.event_ops(game, 0, {"id": 177}, "damage", {"seat": 0, "amount": 4}) == [{"op": "counter", "amount": 4}], "177: величина урона")
	for id: int in [6, 76, 124, 166, 177, 190, 10, 830]:
		var op: String = {6: "recharge", 76: "coins", 124: "kill_self", 166: "coins", 177: "counter", 190: "loot", 10: "counter", 830: "recharge"}[id]
		check(not Passives.handled_operation(id, op), "Ручная операция карты %d не блокируется шире" % id)
	for pair: Array in [[18, "temporary_attack"], [165, "coins"], [231, "loot"], [55, "counter"], [237, "coins"]]:
		check(Passives.handled_operation(pair[0], pair[1]), "Прежняя автоматическая операция карты %d сохранена" % pair[0])
	print("PASSIVE REGISTRY: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
