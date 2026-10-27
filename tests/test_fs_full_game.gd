extends SceneTree
## Регрессии длинной партии Four Souls. Запуск: --headless --script res://tests/test_fs_full_game.gd.
var checks := 0
var errors := 0
var local_net: Node

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func make(count: int = 2, expanded: bool = false, seed_value: int = 17) -> FSRules:
	var g := FSRules.new()
	var players := []
	for i in count:
		players.append({"name": "Игрок %d" % i})
	g.new_game(players, expanded, seed_value)
	preload("res://tests/fs_test_setup.gd").finish(g)
	return g

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var target_check := make()
	target_check.monsters = [
		{"id": 272, "hp": 1, "dc": 0, "at": 0},
		{"id": 450, "hp": 1, "dc": 1, "at": 1}]
	check(target_slot(target_check) == 1, "Сценарий выбирает атакуемого монстра вместо Лавочника")
	# Следующее действие уже ждёт ручную карту; бросок этой карты не должен застрять.
	var g := make()
	var owner := g.current
	check(g.action(owner, "activate", {"item": 0}), "Открыта способность")
	check(g.action(owner, "end") and g.phase == "effect", "Конец хода ждёт способность")
	check(g.action(owner, "effect_roll"), "Бросок внутри ожидающей способности")
	check(g.action(owner, "effect_roll") and g.phase == "effect", "Бросок возвращает ручную карту при отложенном конце хода")
	if g.phase == "effect":
		check(g.action(owner, "effect_done") and g.current != owner, "Ручная карта завершена до конца хода")
	# Смерть монстра от предмета вне боя тоже должна заполнять освободившееся место.
	g = make()
	owner = g.current
	g.action(owner, "activate", {"item": 0})
	g.action(owner, "end")
	g.action(owner, "effect", {"op": "monster_damage", "item": 0, "amount": 99})
	g.action(owner, "effect_done")
	check(g.phase == "effect" and g.resolving.get("kind") == "reward", "Предмет открывает награду")
	g.action(g.actor(), "effect_done")
	check(g.monsters.size() == 2 or g.phase == "effect", "После убийства вне боя место заполняется")
	# Два убитых монстра: удаление первого не должно инвалидировать слот второго.
	g = make()
	owner = g.current
	g.action(owner, "activate", {"item": 0})
	g.action(owner, "end")
	for slot in 2:
		g.action(owner, "effect", {"op": "monster_damage", "item": slot, "amount": 99})
	g.action(owner, "effect_done")
	var rewards := 0
	for step in 12:
		if g.phase != "effect":
			break
		if g.resolving.kind == "reward":
			rewards += 1
		if g.resolving.kind == "event" and FSData.card(int(g.resolving.card)).lua.get("type", "") == "curse":
			g.action(g.actor(), "effect", {"op": "attach_curse"})
		g.action(g.actor(), "effect_done")
	check(rewards == 2, "Оба убитых монстра дают награду после сдвига слотов")
	for count in [2, 4, 8]:
		for expanded in [false, true]:
			for seed_value in range(1, 11):
				play_game(count, expanded, seed_value)
	print("FS FULL GAME: %d проверок, ошибок: %d" % [checks, errors])
	quit(1 if errors else 0)

## Сценарий решений людей: реальные броски, штрафы и ручная награда за босса.
## Тексты пассивных способностей и особые награды здесь не эмулируются.
func play_game(count: int, expanded: bool, seed_value: int) -> void:
	var g := make(count, expanded, seed_value)
	if OS.get_environment("FS_NET") == "1":
		local_net = root.get_node("Net")
		local_net.host_offline("four_souls")
		local_net.set_bots(count - 1)
		local_net.start_game()
		local_net.fours = g
	var steps := 0
	while g.phase != "game_over" and steps < 30000:
		steps += 1
		var ok := false
		match g.phase:
			"discard_target":
				ok = send(g, g.current, "discard_target", {"target": g.current})
			"forced_discard":
				ok = send(g, g.actor(), "forced_discard", {"item": 0})
			"turn":
				if int(g.get_view(g.current).get("required_player_attacks", 0)) > 0:
					ok = send(g, g.current, "attack_player", {"target": g.get_view(g.current).player_attack_targets[0]})
				elif g.free_loot > 0 and not g.hands[g.current].is_empty():
					ok = send(g, g.current, "loot", {"card": g.hands[g.current][0]})
				elif not g.bought and g.coins[g.current] >= 10:
					ok = send(g, g.current, "buy", {"slot": 0})
				elif not g.attacked:
					ok = send(g, g.current, "attack", {"slot": target_slot(g)})
				else:
					ok = send(g, g.current, "end")
			"priority":
				if g.stack.is_empty():
					check(false, "Окно ответов не может иметь пустой стек: %d/%s/%d" % [count, expanded, seed_value])
					print("EMPTY PRIORITY: ", g._after_stack, " resolving=", g.resolving, " log=", g.log.slice(-8))
					break
				if not g.paused_effects.is_empty() and g.stack.any(func(entry): return entry.kind == "effect_roll"):
					var roller: int = int(g.paused_effects.back().get("roller", g.paused_effects.back().effect.owner))
					ok = send(g, roller, "effect_roll")
				elif g.battle >= 0 or g.battle_player >= 0 or g.stack.back().kind in ["attack", "player_attack"]:
					ok = send(g, g.current, "roll")
				elif not g.attacked:
					ok = send(g, g.current, "attack", {"slot": target_slot(g)})
				else:
					ok = send(g, g.current, "end")
			"battle_roll":
				ok = send(g, g.current, "roll")
			"effect":
				if bool(g.resolving.get("requires_reward_roll", false)) and not g.resolving.has("reward_roll"):
					ok = send(g, g.actor(), "effect_roll")
					continue
				if g.resolving.has("spawn_card"):
					ok = send(g, g.actor(), "place_bloat", {"slot": g.get_view(g.actor()).spawn_slots[0]})
					continue
				var card := FSData.card(int(g.resolving.card))
				if g.resolving.kind == "reward" and str(card.lua.get("type", "")) == "boss":
					send(g, g.actor(), "effect", {"op": "souls", "amount": 1})
				if g.phase == "game_over":
					break
				if g.resolving.kind == "event" and card.lua.get("type", "") == "curse":
					send(g, g.actor(), "effect", {"op": "attach_curse"})
				ok = send(g, g.actor(), "effect_done")
			"death":
				var seat := g.actor()
				var item := -1
				for i in g.items[seat].size():
					if not g.items[seat][i].eternal:
						item = i
						break
				ok = send(g, seat, "death", {"loot": g.hands[seat][0] if not g.hands[seat].is_empty() else -1, "item": item})
			"discard":
				ok = send(g, g.current, "discard", {"card": g.hands[g.current][0]})
		check(ok, "Партия %d/%s/%d, шаг %d, фаза %s: доступно следующее действие" % [count, expanded, seed_value, steps, g.phase])
		if not ok:
			break
		var total := g.bank
		for seat in count:
			total += int(g.coins[seat])
			if steps % 101 == 0:
				check(g.get_view(seat).hand == g.hands[seat], "Личная рука доступна своему месту")
				check(not g.get_view(seat).has("hands"), "Общие состояния не раскрывают чужие руки")
		check(total == 100, "Монеты не теряются за полную партию")
	check(g.phase == "game_over" and g.winner >= 0, "Полная партия %d/%s/%d дошла до победителя за %d действий" % [count, expanded, seed_value, steps])
	if g.phase != "game_over":
		print("ОСТАНОВКА: ", g.phase, " ход ", g.round_no, " монстры ", g.monsters)
	if local_net != null:
		local_net.leave()

## Дополнительный режим FS_NET=1 проходит настоящий hotseat-маршрут Net, без транспорта.
func send(g: FSRules, seat: int, kind: String, arg = null) -> bool:
	if local_net == null:
		return g.action(seat, kind, arg)
	local_net.fs_switch_seat(seat)
	var before := g.revision
	local_net.send_action(kind, arg)
	check(local_net.view.seat == seat, "Hotseat передаёт состояние выбранному месту")
	return g.revision > before

## Слабый персонаж выбирает посильную цель; слишком сильных монстров можно накрыть верхом колоды.
func target_slot(g: FSRules) -> int:
	if int(g.get_view(g.current).get("forced_deck_attacks", 0)) > 0:
		return -1
	var best := -1
	var score := INF
	var visible: Array = g.get_view(g.current).monsters
	for i in g.monsters.size():
		var m: Dictionary = g.monsters[i]
		if bool(visible[i].get("untargetable", false)):
			continue
		var difficulty := float(m.hp) * float(m.at) / maxf(1, 7 - int(m.dc))
		if difficulty < score:
			score = difficulty
			best = i
	return best if score <= 1.5 else -1
