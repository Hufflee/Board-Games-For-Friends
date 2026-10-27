extends SceneTree
## Регрессии исправлений независимого аудита Four Souls; это fixtures, не полный UI-матч.
## Запуск: --headless --audio-driver Dummy --script res://tests/test_fs_audit_fixes_20261025.gd.
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func make(seed_value: int = 77, count: int = 2) -> FSRules:
	var g := FSRules.new()
	var players := []
	for i in count:
		players.append({"name": "Игрок %d" % i})
	g.new_game(players, false, seed_value)
	preload("res://tests/fs_test_setup.gd").finish(g)
	return g

func monster(id: int) -> Dictionary:
	return {"id": id, "hp": FSData.stat(id, "hp", 1), "dc": FSData.stat(id, "dc", 4), "at": FSData.stat(id, "at", 1)}

func item(id: int, eternal: bool = false) -> Dictionary:
	return {"id": id, "tapped": false, "eternal": eternal, "counters": 0}

func loot_effect(g: FSRules, id: int) -> void:
	var owner := g.current
	g.decks.loot.erase(id)
	g.hands[owner].append(id)
	check(g.action(owner, "loot", {"card": id}), "Лут объявлен")
	check(g.action(owner, "end") and g.phase == "effect", "Следующее действие ждёт ручной лут")

func effect(g: FSRules, op: String, target: int, amount: int = 1, index: int = 0) -> bool:
	return g.action(g.actor(), "effect", {"op": op, "target": target, "amount": amount, "item": index})

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var g := make()
	var owner := g.current
	loot_effect(g, 636)
	check(effect(g, "self_underdeck", owner), "Солнце перемещается под низ колоды")
	check(not effect(g, "self_underdeck", owner), "Солнце нельзя продублировать под колодой")
	check(effect(g, "extra_turn", owner), "Назначен дополнительный ход")
	check(g.action(owner, "effect_done") and g.current == owner, "Солнце сохраняет владельцу следующий ход")
	check(g.decks.loot[0] == 636 and not g.discards.loot.has(636), "Солнце не дублируется в сбросе")
	g.action(owner, "end")
	check(g.current == 1 - owner, "После дополнительного хода возобновляется обычный порядок")

	g = make(77, 3)
	owner = g.current
	loot_effect(g, 636)
	var recipient := (owner + 2) % 3
	effect(g, "extra_turn", recipient, 2)
	g.action(owner, "effect_done")
	check(g.current == recipient, "Ручной дополнительный ход может принадлежать другому игроку")
	g.action(recipient, "end")
	check(g.current == recipient, "Два дополнительных хода выполняются подряд")
	g.action(recipient, "end")
	check(g.current == (owner + 1) % 3, "После чужих дополнительных ходов сохранено место обычной очереди")

	g = make()
	owner = g.current
	var other := 1 - owner
	g.items[owner].append(item(157))
	g.items[owner].append(item(159))
	g.action(owner, "activate", {"item": 1, "tap": false})
	g.action(owner, "end")
	check(not effect(g, "give_item", other, 1, 0), "Вечный предмет нельзя пожертвовать")
	check(not effect(g, "give_item", owner, 1, 2), "Передача самому себе отвергается")
	check(effect(g, "give_item", other, 1, 2), "Невечный предмет передан получателю")
	check(g.items[other].back().id == 159 and g.items[owner].size() == 2, "Предмет перемещён без копии")
	check(effect(g, "coins", owner, 8), "Награда пожертвования доступна той же панели")

	g = make()
	owner = g.current
	other = 1 - owner
	loot_effect(g, 642)
	check(effect(g, "peek_hands", owner), "Мир раскрывает руки владельцу эффекта")
	check(g.get_view(owner).peek.hands.size() == 2, "Владелец видит обе руки")
	check(g.get_view(other).peek.is_empty() and g.get_view(-1).peek.is_empty(), "Другой игрок и зритель не получают просмотр")
	check(not g.get_view(owner).players[other].has("hand"), "Публичная структура игроков не содержит рук")
	var hidden_before: Array = g.hands[other].duplicate()
	check(not g.action(owner, "peek_take", {"card": hidden_before[0], "dest": "hand"}), "Просмотр руки не даёт присвоить карту")
	check(g.hands[other] == hidden_before, "Просмотр не изменяет чужую руку")
	effect(g, "loot", owner, 2)
	g.action(owner, "effect_done")
	check(g.get_view(owner).peek.is_empty(), "Завершение эффекта очищает приватный просмотр")

	g = make()
	owner = g.current
	loot_effect(g, 524)
	check(effect(g, "prevent_damage", owner), "Сердце души создаёт щит")
	var health: int = g.hp[owner]
	check(effect(g, "damage", owner), "Ручной урон проходит общий обработчик")
	check(g.hp[owner] == health and g.damage_shields[owner] == 0, "Щит поглощает ровно один урон")
	effect(g, "damage", owner)
	check(g.hp[owner] == health - 1, "Израсходованный щит не защищает повторно")
	effect(g, "heal", owner, 99)
	effect(g, "prevent_damage", owner, 2)
	g.action(owner, "effect_done")
	check(g.damage_shields[owner] == 0, "Неиспользованный щит исчезает в конце хода")

	for id in [346, 408]:
		g = make()
		owner = g.current
		g.monsters = [monster(id), monster(433)]
		check(not g.action(owner, "attack", {"slot": 0}) and not g.attacked, "Нельзя атаковать %s и потратить попытку" % FSData.title(id))
		var view := g.get_view(owner)
		check(view.monsters[0].untargetable, "UI получает запрет атаки")
		check(view.monsters[1].dc == (5 if id == 408 else 4), "Аура защиты показана в view")
		check(view.monsters[1].at == (2 if id == 346 else 1), "Аура атаки показана в view")
		g.hands[owner].append(650)
		g.action(owner, "loot", {"card": 650})
		g.action(owner, "end")
		effect(g, "monster_damage", owner, 2, 1)
		g.action(owner, "effect_done")
		check(g.phase == "effect" and g.resolving.kind == "reward" and g.monsters[0].hp == 0, "Смерть другого монстра убивает %s" % FSData.title(id))
		var rewards := []
		for step in 10:
			if g.phase != "effect":
				break
			if g.resolving.kind == "reward":
				rewards.append(int(g.resolving.card))
			if g.resolving.kind == "event" and FSData.card(int(g.resolving.card)).lua.get("type", "") == "curse":
				effect(g, "attach_curse", owner)
			g.action(g.actor(), "effect_done")
		check(rewards.has(id) and rewards.has(433), "Обе смерти дают отдельные награды без потери слота")

	g = make(4)
	owner = g.current
	g.monsters = [monster(433)]
	var health_before: int = g.hp[owner]
	g.action(owner, "attack", {"slot": 0})
	g.action(owner, "roll")
	check(g.last_roll >= 4, "Естественное попадание по Похоти")
	g.action(owner, "roll")
	check(g.hp[owner] == health_before - 1, "Похоть наносит ответный урон при боевом попадании")

	g = make(2)
	owner = g.current
	g.monsters = [monster(452)]
	health_before = g.hp[owner]
	g.action(owner, "attack", {"slot": 0})
	g.action(owner, "roll")
	check(g.last_roll == 1, "Естественная единица против Скакуна")
	g.action(owner, "roll")
	check(g.hp[owner] == health_before - 2 and g.phase == "death", "Скакун наносит двойной урон на единице")

	g = make()
	owner = g.current
	g.items[owner].append(item(121))
	g.items[owner].append(item(849, true))
	g.items[owner][2].tapped = true
	var hand_before: int = g.hands[owner].size()
	g.action(owner, "end")
	check(g.phase == "discard" and g.get_view(owner).discard_limit == hand_before - 1, "Хвост требует сброс даже при руке меньше десяти")
	g.action(owner, "discard", {"card": g.hands[owner][0]})
	check(g.current != owner and not g.items[owner][2].tapped, "Сброс завершает ход и перезаряжает Святой покров")
	g.action(g.current, "end")
	check(g.hands[owner].size() == hand_before + 1, "После сброса Хвост даёт два лута в начале нового хода")

	g = make()
	owner = g.current
	g.items[owner].append(item(566))
	g.action(owner, "activate", {"item": 0})
	g.action(owner, "end")
	check(effect(g, "destroy", owner, 1, 1), "Брелок уничтожен")
	check(g.discards.loot.has(566) and not g.discards.treasure.has(566), "Уничтоженный брелок попадает в лут")

	_test_death_response(false)
	_test_death_response(true)
	_test_manual_monster()
	_test_panel()
	print("FS AUDIT FIXES: %d проверок, ошибок: %d" % [checks, errors])
	quit(1 if errors else 0)

func _test_death_response(mantle: bool) -> void:
	var g := make(2)
	var owner := g.current
	var other := 1 - owner
	g.monsters = [monster(387)]
	g.items[other].append(item(849 if mantle else 824, true))
	g.action(owner, "attack", {"slot": 0})
	g.action(owner, "roll")
	g.action(owner, "roll")
	check(g.phase == "death", "Смертельный промах объявляет смерть до штрафа")
	check(g.action(other, "activate", {"item": 1}), "Другой игрок отвечает на уже объявленную смерть")
	check(not g.action(other, "pass"), "Кнопка и действие pass не возвращены")
	var coins_before: int = g.coins[owner]
	check(g.action(owner, "death", {"loot": g.hands[owner][0], "item": -1}), "Принятие штрафа сначала открывает ручной ответ")
	check(g.phase == "effect" and g.actor() == other, "Ответ остаётся у владельца способности")
	check(effect(g, "prevent_death" if mantle else "heal", owner, 1 if mantle else 99), "Игрок вручную спасает выбранную цель")
	g.action(other, "effect_done")
	check(g.coins[owner] == coins_before and g._death_queue.is_empty(), "Спасённый не платит штраф, очередь смерти очищена")
	if mantle:
		check(g.current != owner and g.battle == -1 and g.stack.is_empty(), "Святой покров отменяет неразрешённое и завершает ход")
	else:
		check(g.current == owner and g.phase == "priority", "Обычное лечение сохраняет бой и отложенный бросок")

func _test_manual_monster() -> void:
	var g := make()
	var owner := g.current
	check(not g.action(owner, "monster_trigger", {"slot": 99}), "Нельзя вызвать несуществующего монстра")
	check(g.action(owner, "monster_trigger", {"slot": 0}), "Срабатывание открытого монстра объявлено")
	g.action(owner, "end")
	check(g.phase == "effect" and g.resolving.kind == "monster_trigger", "Срабатывание открывает ручной текст, не автоматизирует карту")
	check(not g.action(owner, "monster_trigger", {"slot": 0}), "Нельзя вложить триггер в ручную фазу")
	g.action(owner, "effect_done")
	g.dead[g.current] = true
	check(not g.action(g.current, "monster_trigger", {"slot": 0}), "Умерший не вызывает срабатывание")
	g.phase = "game_over"
	check(not g.action(owner, "monster_trigger", {"slot": 0}), "После игры срабатывание недоступно")

## Проверяем адаптер существующей ручной панели; это не эмуляция кликов полного матча.
func _test_panel() -> void:
	var net := root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(net.fours)
	var g := make()
	var owner := g.current
	loot_effect(g, 642)
	net.fours = g
	net.fs_switch_seat(owner)
	var table_script: GDScript = load("res://games/four_souls/ui/fs_table.gd")
	var table: Control = table_script.new()
	table._v = g.get_view(owner)
	var col := VBoxContainer.new()
	table._effect_controls(col)
	var selectors := []
	var apply: Button
	for node in col.get_children():
		if node is OptionButton:
			selectors.append(node)
		if node is Button and node.text == "Применить":
			apply = node
	var operations: Array = table_script.OPS + table_script.EXTRA_OPS
	for i in operations.size():
		if operations[i][0] == "peek_hands":
			selectors[1].select(i)
	apply.pressed.emit()
	check(g.get_view(owner).peek.has("hands"), "Ручная панель отправляет новую операцию просмотра рук через Net")
	col.free()
	table.free()
	net.leave()
