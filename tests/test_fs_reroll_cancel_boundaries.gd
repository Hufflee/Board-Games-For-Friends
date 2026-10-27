## Связанные перебросы при отмене/смерти, спасение, независимый кубик и идентичность цели.
## Подготовленные состояния seed26; --headless --audio-driver Dummy --script res://tests/test_fs_reroll_cancel_boundaries.gd.
extends "res://tests/test_fs_attack_modifiers_review.gd"

func setup(pvp: bool = false) -> FSRules:
	var g := fixture()
	g._gain_item(0, 36)
	g._gain_item(0, 42)
	g._gain_item(0, 13)
	g.monsters.append({"id": 445, "hp": 20, "dc": 4, "at": 1})
	g.hands = [[515, 497], [515]]
	g.character_ready = [true, true]
	g.free_loot = 2
	if pvp:
		g.battle = -1
		g.battle_player = 1
		g.required_player_attacks = 1
	return g

func request_roll(g: FSRules, author: int, value: int) -> void:
	check(g.action(author, "loot", {"card": 515}), "Осколок игрока%d поставлен в стек" % author)
	g._resolve_top()
	check(g.resolving.card == 515, "Открылась исходная способность Осколка")
	check(g.action(author, "effect", {"op": "reroll", "target": 0}), "Запрос переброса штатной операцией")
	check(g.actor() == 0, "Кубик по-прежнему принадлежит исходному игроку0")
	check(g.action(0, "effect_roll"), "Переброс поставлен через action")
	g.stack.back().value = value

func cancel_with_item(g: FSRules) -> void:
	check(g.action(0, "activate", {"item": 2, "tap": false}), "Ручной ответ над ожидающим кубиком")
	g._resolve_top()
	check(g.action(0, "effect", {"op": "cancel_attack"}), "Ответ явно отменяет бой")
	check(g.action(0, "effect_done"), "Отменившая способность штатно завершена")

func finish_shard(g: FSRules, author: int) -> void:
	check(g.phase == "effect" and g.resolving.card == 515 and g.resolving.owner == author,
		"Возврат Осколка его автору%d" % author)
	check(g.action(author, "effect_done"), "Автор%d завершает Осколок" % author)
	g._finish_responses()

func direct_cancel() -> void:
	var g := setup()
	queue_attack(g, 6)
	request_roll(g, 1, 4)
	cancel_with_item(g)
	g._finish_responses()
	check(g.coins == [3, 3] and g.items[0][1].counters == 0,
		"Явная отмена: нет445/42 по осиротевшему кубику4")
	check(g.action(1, "effect", {"op": "coins", "amount": 1}), "Остаток ручной способности Осколка не потерян")
	finish_shard(g, 1)
	check(g.coins == [3, 4] and g.discards.loot.count(515) == 1,
		"Остаток выполнен, исходный Осколок сброшен один раз")
	check(g.stack.is_empty() and g.paused_effects.is_empty(), "После отмены нет зависших возвратов")

func nested_cancel() -> void:
	var g := setup()
	queue_attack(g, 6)
	request_roll(g, 1, 2)
	request_roll(g, 0, 4)
	cancel_with_item(g)
	g._finish_responses()
	finish_shard(g, 0)
	finish_shard(g, 1)
	check(g.coins == [3, 3] and g.items[0][1].counters == 0,
		"Вложенная отмена: ни один технический кубик не превратился в обычный")
	check(g.discards.loot.count(515) == 2, "Два разыгранных Осколка сброшены по одному разу")
	check(g.stack.is_empty() and g.paused_effects.is_empty(), "Вложенная отмена сохранила и завершила оба возврата")

func death_or_save(save: bool) -> void:
	var g := setup(true)
	g.hp[1] = 1
	queue_attack(g, 6)
	request_roll(g, 1, 3 if save else 4)
	check(g.action(0, "loot", {"card": 497}), "Бомба отвечает над ожидающим перебросом PvP")
	g._resolve_top()
	check(g.action(0, "effect", {"op": "damage", "target": 1, "amount": 1}), "Ответ объявляет смерть PvP-цели")
	check(g.action(0, "effect_done"), "Бомба завершена до объявления штрафа")
	check(g.stack.back().kind == "death", "Смерть ещё ожидает разрешения, бой пока не отменён")
	if save:
		g._gain_item(1, 13)
		check(g.action(1, "activate", {"item": 0}), "Цель отвечает до разрешения собственной смерти")
		g._resolve_top()
		check(g.action(1, "effect", {"op": "prevent_death", "target": 1}), "Спасение отменяет ожидающую смерть")
		check(g.action(1, "effect", {"op": "heal", "target": 1, "amount": 4}), "Лечение перед ожидающей атакой")
		check(g.action(1, "effect_done"), "Спасение завершено")
	else:
		g._finish_responses()
		check(g.phase == "death" and g.battle_player == -1, "Подтверждённая смерть удаляет исходный roll")
		check(g.action(1, "death"), "Обычный штраф погибшей цели")
	g._finish_responses()
	finish_shard(g, 1)
	if save:
		check(g.last_roll == 4 and g.hp[1] == 4 and g.battle_player == 1,
			"Спасённый бой продолжается:3 +36 →4, один урон цели")
		check(g.coins == [5, 3] and g.items[0][1].counters == 1 and g._turn_attack_rolls[0] == 1,
			"Спасение сохраняет один итоговый445/42 и одну атаку")
	else:
		check(g.coins == [3, 2] and g.dead[1] and g.items[0][1].counters == 0,
			"Смерть: только штраф1 монеты, без призрачного445/42")
	check(g.discards.loot.count(497) == 1 and g.discards.loot.count(515) == 1,
		"Бомба и Осколок не потеряны и не сброшены дважды")
	check(g.paused_effects.is_empty(), "Смерть/спасение не оставили зависший возврат")

func ordinary_next_to_cancelled() -> void:
	var g := setup()
	queue_attack(g, 6)
	request_roll(g, 1, 2)
	check(g.action(0, "activate", {"item": 2, "tap": false}), "Независимая способность над связанным перебросом")
	g._resolve_top()
	check(g.action(0, "effect_roll"), "Настоящий самостоятельный небоевой кубик")
	g.stack.back().value = 4
	cancel_with_item(g)
	g._finish_responses()
	check(g.phase == "effect" and g.resolving.card == 13 and g.resolving.owner == 0,
		"Обычный кубик вернулся к своей способности13")
	check(g.last_roll == 4 and g.coins == [5, 3] and g.items[0][1].counters == 1,
		"Независимая4 не переписана: законные445/42 применились один раз")
	check(g.action(0, "effect_done"), "Самостоятельная способность13 завершена")
	g._finish_responses()
	finish_shard(g, 1)
	check(g.coins == [5, 3] and g.items[0][1].counters == 1,
		"Оставшийся переброс отменённой атаки не добавил и не заменил результат обычного кубика")
	check(g.stack.is_empty() and g.paused_effects.is_empty() and g.discards.loot.count(515) == 1,
		"Оба законных возврата завершены, Осколок сброшен один раз")

func ordinary_reroll() -> void:
	var g := setup()
	g.phase = "effect"
	g.resolving = {"kind": "item", "card": 13, "owner": 0}
	g._after_stack = "turn"
	check(g.action(0, "effect_roll"), "Исходный обычный небоевой кубик")
	g.stack.back().value = 2
	request_roll(g, 1, 4)
	g._finish_responses()
	finish_shard(g, 1)
	check(g.phase == "effect" and g.resolving.card == 13 and g.resolving.owner == 0,
		"Обычный переброс вернулся через Осколок к исходной способности13")
	check(g.last_roll == 4 and g.coins == [5, 3] and g.items[0][1].counters == 1,
		"Законный небоевой переброс4 вызывает445/42 ровно один раз без36")
	check(g._turn_attack_rolls.is_empty(), "Законный небоевой переброс не считается атакой")
	check(g.action(0, "effect_done"), "Исходная небоевая способность завершена")
	check(g.discards.loot.count(515) == 1 and g.paused_effects.is_empty(), "Обычный переброс не дублирует сброс и возврат")

## Защитная подготовленная проверка идентичности; не утверждает новый штатный баг.
func identity_guard() -> void:
	var g := setup()
	var original: Dictionary = {"kind": "roll", "owner": 0, "value": 6}
	var ordinary: Dictionary = {"kind": "effect_roll", "owner": 1, "value": 3}
	var token: int = g._roll_token(original)
	var linked: Dictionary = {"kind": "effect_roll", "owner": 0, "value": 4,
		"reroll_index": 0, "reroll_target_token": token, "attack_reroll": true}
	g.stack = [ordinary]
	check(g._reroll_index(linked) == -1 and ordinary.value == 3,
		"Чужой кубик по прежнему индексу не считается исчезнувшей целью")
	check(g._rerolls_attack(linked), "Контекст атаки не исчезает с её целью")
	g.stack = [ordinary, original]
	check(g._reroll_index(linked) == 1, "Сохранённая цель найдена после сдвига по идентификатору")
	check(ordinary.value == 3 and ordinary.owner == 1, "Законный небоевой кубик и его владелец не изменены")
	g.stack = [ordinary, linked]
	g.paused_effects = [{"effect": {"kind": "loot", "card": 515, "owner": 0}, "resume": "turn", "peek": {}}]
	g._resolve_top()
	check(ordinary.value == 3 and not ordinary.get("passives_done", false),
		"Настоящий обработчик не переписывает чужой кубик и его маркер по старому индексу")
	check(g.resolving.card == 515 and g.resolving.owner == 0, "Защитная фикстура сохраняет возврат исходной способности")

func _initialize() -> void:
	direct_cancel()
	nested_cancel()
	death_or_save(false)
	death_or_save(true)
	ordinary_next_to_cancelled()
	ordinary_reroll()
	identity_guard()
	print("REROLL CANCEL BOUNDARIES: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
