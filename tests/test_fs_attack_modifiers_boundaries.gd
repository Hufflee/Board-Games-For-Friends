## Границы 34/36 и настоящий запрос переброса; подготовленные состояния, Dummy, отдельный APPDATA.
## Запуск: --headless --audio-driver Dummy --script res://tests/test_fs_attack_modifiers_boundaries.gd.
extends "res://tests/test_fs_attack_modifiers_next.gd"

const ModifierRules := preload("res://games/four_souls/logic/fs_passive_rules.gd")

func copies_and_view() -> void:
	var g := arena([34, 34, 36, 36])
	check(g.get_view(0).monsters[0].dc == 2 and g.get_view(1).monsters[0].dc == 2,
		"Две ауры34: обоим игрокам видна защита2")
	check(g.monsters[0].dc == 4, "Вид не изменяет исходную защиту")
	check(attack_result(g, 3) == {"итог": 5, "урон_монстру": 1, "урон_игроку": 0},
		"Две копии36 дают +2 один раз, две34 снижают защиту")
	check(g.log.any(func(line: String) -> bool: return "3 +2 → 5 (итог)" in line),
		"Журнал показывает прибавку и эффективный результат")
	g.current = 1
	check(g.get_view(0).monsters[0].dc == 4, "Чужой ход выключает ауры34")
	check(attack_result(g, 3).итог == 3, "Чужая атака не использует36 владельца")
	g = arena([34, 34], 0, 0, 1)
	check(g._monster_evasion(g.monsters[0]) == 1 and g.get_view(0).monsters[0].dc == 1,
		"Нижняя граница эффективной защиты1 в бою и виде")
	check(ModifierRules.monster_evasion(8, []) == 6, "Верхняя граница эффективной защиты6")
	g = arena([34, 34])
	g.curses[0].append(705)
	check(g._monster_evasion(g.monsters[0]) == 3 and g.get_view(0).monsters[0].dc == 3,
		"Проклятие и две ауры используют одну формулу")
	for id: int in FSData.pool("monster", true):
		if FSData.card(id).get("key", "") == "stoney":
			g.monsters.append({"id": id, "hp": 2, "dc": 4, "at": 1})
			break
	check(g.monsters.size() == 2, "Подготовка: найдена настоящая Каменюка")
	check(g._monster_evasion(g.monsters[0]) == 4 and g.get_view(0).monsters[0].dc == 4,
		"Каменюка, проклятие и34 совпадают в попадании и виде")
	g = arena([34])
	if pending(g, 3):
		g._remove_item(0, 0)
		g._finish_responses()
		check(g.last_roll == 3 and g.monsters[0].hp == 100 and g.get_view(0).monsters[0].dc == 4,
			"Уход34 после постановки броска отменяет ауру до разрешения")
	var modifiers: Dictionary = ModifierRules.attack_modifiers([{"id": -1}], 1)
	check(ModifierRules.attack_roll(3, modifiers) == 3 and ModifierRules.attack_hits(6, 4, modifiers),
		"Неизвестная карта не модифицирует атаку")
	modifiers = ModifierRules.attack_modifiers([{"id": 34}], 1)
	modifiers.miss_faces.clear()
	check(ModifierRules.attack_modifiers([{"id": 34}], 1).miss_faces == [1, 6],
		"Списки запрещённых граней не разделяются между вызовами")

func ordinals_and_coal() -> void:
	var g := arena([36])
	for ordinal: int in range(1, 8):
		var wanted: int = 3 if ordinal in [1, 3, 5] else 2
		check(attack_result(g, 2).итог == wanted, "36: граница порядкового номера%d" % ordinal)
	check(g._turn_attack_rolls[0] == 7, "Семь разрешившихся атак посчитаны один раз")
	g = arena([18, 36])
	attack_result(g, 2)
	attack_result(g, 2)
	var before: int = g.monsters[0].hp
	check(attack_result(g, 3).итог == 4, "Уголь и36: третья атака получает +1 к броску")
	check(g.monsters[0].hp == before - 1 and g.attack[0] == 2,
		"Третья атака с36 фиксирует урон до триггера Угля")
	before = g.monsters[0].hp
	check(attack_result(g, 4).итог == 4 and g.monsters[0].hp == before - 2,
		"Четвёртая атака без36, но с накопленным Углём")
	g.new_game([{"name": "А"}, {"name": "Б"}], false, 26)
	preload("res://tests/fs_test_setup.gd").finish(g)
	check(g._turn_attack_rolls.is_empty(), "Новая партия очищает общую историю атак")

## Запрос создаётся действием карты515, кубик перебрасывает именно владелец исходной атаки.
func begin_reroll(g: FSRules, value: int) -> bool:
	g.hands[1] = [515]
	g.character_ready[1] = true
	check(g.action(1, "loot", {"card": 515}), "Настоящий ответ Осколком от игрока1")
	g._finish_responses()
	check(g.phase == "effect" and g.resolving.card == 515, "Осколок ожидает ручную операцию")
	check(g.action(1, "effect", {"op": "reroll", "target": 0}), "Настоящий reroll_request")
	check(g.actor() == 0, "Владельцем переброса остаётся игрок0")
	check(not g.action(1, "effect_roll"), "Автор Осколка не бросает чужой кубик")
	var accepted: bool = g.action(0, "effect_roll")
	check(accepted, "Исходный владелец делает переброс через action")
	if not accepted:
		return false
	g.stack.back().value = value
	g._resolve_top()
	check(g.phase == "effect" and g.resolving.card == 515, "Возврат к исходной карте ответа")
	return true

func reroll_triggers() -> void:
	var g := arena([36, 165, 42])
	var coins_before: int = g.coins[0]
	if pending(g, 1) and begin_reroll(g, 4):
		check(g.coins[0] == coins_before and g.items[0][2].counters == 0,
			"Промежуточный переброс ещё не вызывает числовые пассивы")
		check(g._turn_attack_rolls.is_empty(), "Переброс ещё не разрешил исходную атаку")
		check(g.action(1, "effect_done"), "Завершение Осколка его автором")
		g._finish_responses()
		check(g.last_roll == 5 and g.monsters[0].hp == 99, "Переброс4 +36 →5 ровно один раз")
		check(g.coins[0] == coins_before + 3, "165 срабатывает по эффективной5, не сырой4")
		check(g.items[0][2].counters == 1 and g._turn_attack_rolls[0] == 1,
			"Один глобальный триггер42 и один порядковый номер")
		check(attack_result(g, 3).итог == 3 and g._turn_attack_rolls[0] == 2,
			"Следующая атака вторая, а не третья")
	g = arena([36, 231, 55, 85])
	var hand_before: int = g.hands[0].size()
	if pending(g, 6) and begin_reroll(g, 1):
		check(g.action(1, "effect_done"), "Завершение переброса на1")
		g._finish_responses()
		check(g.last_roll == 2 and g.hands[0].size() == hand_before,
			"231 не берёт лут по сырой1, ставшей2")
		check(g.items[0][2].counters == 0 and g.items[0][3].counters == 1,
			"55 не срабатывает на сырой1;85 срабатывает на итоговой2 один раз")
	# Небоевой бросок не получает бонус36 и не занимает номер атаки.
	g = arena([36, 231])
	g.phase = "effect"
	g.resolving = {"kind": "item", "owner": 0, "card": 13}
	hand_before = g.hands[0].size()
	check(g.action(0, "effect_roll"), "Небоевой ручной бросок")
	g.stack.back().value = 1
	g._finish_responses()
	check(g.last_roll == 1 and g.hands[0].size() == hand_before + 1 and g._turn_attack_rolls.is_empty(),
		"Небоевая1 остаётся1 и вызывает231, но не36")
	# Прибавка и числовые триггеры не запекаются в промежуточный результат переброса.
	g = arena([36, 165, 42])
	coins_before = g.coins[0]
	if pending(g, 2) and begin_reroll(g, 4):
		g._remove_item(0, 0)
		check(g.action(1, "effect_done"), "Источник36 ушёл после переброса до исходной атаки")
		g._finish_responses()
		check(g.last_roll == 4 and g.coins[0] == coins_before and g.items[0][1].counters == 1,
			"Без источника переброшенная4 не становится5,165 молчит,42 срабатывает один раз")
	g = arena([36, 165, 42, 13])
	coins_before = g.coins[0]
	if pending(g, 6) and begin_reroll(g, 4):
		check(g.action(1, "effect_done"), "Осколок завершён перед следующим ответом")
		check(g.action(0, "activate", {"item": 3}), "Новый ответ над переброшенной атакой")
		g._finish_responses()
		check(g.action(0, "effect", {"op": "roll", "amount": -1}), "Ответ меняет сырую4 на3")
		check(g.action(0, "effect_done"), "Ответ завершён перед итоговой модификацией")
		g._finish_responses()
		check(g.last_roll == 4 and g.coins[0] == coins_before and g.items[0][2].counters == 1,
			"Поздний ответ3 +36 →4: нет165 по прежней5 и нет повторного42")
	g = arena([36])
	g.monsters.append({"id": 440, "hp": 2, "dc": 4, "at": 1})
	check(attack_result(g, 1).урон_игроку == 3, "Хорф440: итоговая2 даёт2 урона плюс1 за промах")
	g = arena([36])
	g.monsters.append({"id": 440, "hp": 2, "dc": 4, "at": 1})
	check(attack_result(g, 2).урон_игроку == 1, "Хорф440: сырая2 стала3, глобальных2 урона нет")
	g = arena([36, 42])
	g.monsters.append({"id": 440, "hp": 2, "dc": 4, "at": 1})
	if pending(g, 6) and begin_reroll(g, 1):
		check(g.hp[0] == 100, "Переброс ещё не запускает Хорфа по сырой грани")
		check(g.action(1, "effect_done"), "Завершение переброса перед Хорфом")
		g._finish_responses()
		check(g.last_roll == 2 and g.hp[0] == 97 and g.items[0][1].counters == 1,
			"Переброс1 +36 →2: Хорф/42 ровно один раз, затем боевой промах")

func cancellation_and_traits() -> void:
	var g := arena([36, 42])
	if pending(g, 3):
		g._end_battle()
		g._finish_responses()
		check(g.monsters[0].hp == 100 and g.items[0][1].counters == 0,
			"Отмена удаляет атаку без призрачного урона/триггера42")
		# Не утверждаем порядковый номер следующей36: отдельного FAQ по отмене нет.
	for id: int in [428, 441]:
		g = arena([36])
		g.monsters[0].id = id
		check(attack_result(g, 5).итог == 6 and g.monsters[0].hp == 100,
			"Пин/Прыгун: эффективная6 сохраняет иммунитет от боевого урона")
	g = arena([36], 0, 0, 1)
	g.monsters[0].id = 281
	check(attack_result(g, 2).итог == 3 and g.monsters[0].last_attack_roll == 3,
		"Тишина запоминает эффективную3")
	check(attack_result(g, 3).урон_игроку == 1, "Тишина: равная итоговая3 — промах")
	g = arena([36, 34])
	g.required_player_attacks = 1
	g.battle = -1
	g.battle_player = 1
	if pending(g, 5):
		g._finish_responses()
		check(g.last_roll == 6 and g.hp[1] == 100 and g.hp[0] == 99,
			"PvP: свой итог6 — промах34, аура не снижает защиту игрока")
	# Подтверждённая смерть цели удаляет ещё не разрешённую атаку с36.
	g = arena([36, 42])
	g.battle = -1
	g.battle_player = 1
	g.hands[0] = [497]
	if pending(g, 3):
		check(g.action(0, "loot", {"card": 497}), "PvP: ответ Бомбой над атакой с36")
		g._finish_responses()
		check(g.action(0, "effect", {"op": "damage", "target": 1, "amount": 99}), "PvP: цель почти погибла")
		check(g.action(0, "effect", {"op": "damage", "target": 1, "amount": 1}), "PvP: летальный ответ")
		check(g.action(0, "effect_done"), "PvP: завершение летального ответа")
		g._finish_responses()
		check(g.phase == "death" and g.battle_player == -1 and g.stack.is_empty(),
			"PvP: смерть цели удаляет бросок36 и сохраняет обычный штраф")
		check(g.items[0][1].counters == 0, "PvP: удалённый бросок не создаёт глобальный триггер42")

func nested_reroll() -> void:
	var g := arena([36, 165, 42])
	g.hands = [[515], [515]]
	g.character_ready[1] = true
	var coins_before: int = g.coins[0]
	if not pending(g, 1):
		return
	check(g.action(1, "loot", {"card": 515}), "Вложенный: первый Осколок игрока1")
	g._finish_responses()
	check(g.action(1, "effect", {"op": "reroll"}), "Вложенный: первый запрос")
	check(g.action(0, "effect_roll"), "Вложенный: первый кубик игрока0")
	g.stack.back().value = 2
	# Второй Осколок отвечает на ещё не разрешённый кубик первого переброса.
	check(g.action(0, "loot", {"card": 515}), "Вложенный: второй Осколок игрока0")
	g._finish_responses()
	check(g.action(0, "effect", {"op": "reroll"}), "Вложенный: запрос переброса переброса")
	check(g.action(0, "effect_roll"), "Вложенный: второй кубик того же владельца")
	g.stack.back().value = 4
	g._finish_responses()
	check(g.phase == "effect" and g.resolving.owner == 0, "Вложенный: возврат второму автору")
	check(g.action(0, "effect_done"), "Вложенный: завершение второго Осколка")
	g._finish_responses()
	check(g.phase == "effect" and g.resolving.owner == 1, "Вложенный: возврат первому автору")
	check(g.action(1, "effect_done"), "Вложенный: завершение первого Осколка")
	g._finish_responses()
	check(g.last_roll == 5 and g.coins[0] == coins_before + 3 and g.items[0][2].counters == 1,
		"Цепочка перебросов даёт эффективную5 и числовые пассивы ровно один раз")
	check(g._turn_attack_rolls[0] == 1, "Цепочка перебросов занимает один номер атаки")

func manual_guard() -> void:
	var g := arena([34, 36, 13])
	if not pending(g, 2):
		return
	for index: int in [0, 1]:
		var op: String = "temporary_monster_dc" if index == 0 else "roll"
		check(g.action(0, "activate", {"item": index, "tap": false}),
			"Серверный activate действительно открывает источник%d" % int(g.items[0][index].id))
		g._finish_responses()
		for target: int in 2:
			check(not g.action(0, "effect", {"op": op, "amount": -1 if index == 0 else 1, "item": 0, "target": target}),
				"Источник%d не дублирует %s при target%d" % [g.resolving.card, op, target])
		check(g.action(0, "effect_done"), "Завершение панели пассива")
	check(g.monsters[0].dc == 4 and g.stack[0].value == 2,
		"Заблокированные операции не изменили исходную защиту и бросок")
	check(g.action(0, "activate", {"item": 2}), "Другая карта13 открывает свой ручной эффект")
	g._finish_responses()
	check(g.action(0, "effect", {"op": "temporary_monster_dc", "amount": -1, "item": 0}),
		"Законная ручная правка защиты другой картой разрешена")
	check(g.action(0, "effect", {"op": "roll", "amount": 1}), "Правка броска другой картой разрешена")
	check(g.monsters[0].dc == 3 and g.get_view(0).monsters[0].dc == 2,
		"Другая правка защиты складывается с единственной аурой34")
	check(g.action(0, "effect_done"), "Завершение другой карты")
	g._finish_responses()
	check(g.last_roll == 4 and g.monsters[0].hp == 99,
		"Ответ2→3 и отдельная автоматика36→4 применены по одному разу")

func _initialize() -> void:
	copies_and_view()
	ordinals_and_coal()
	reroll_triggers()
	nested_reroll()
	cancellation_and_traits()
	manual_guard()
	print("ATTACK MODIFIER BOUNDARIES: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
