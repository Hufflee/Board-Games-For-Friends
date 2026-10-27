## Независимые интеграции 34/36: публичная защита, итоговые грани, глобальные пассивы и переброс.
## НЕ запускать до передачи medium. Затем: --headless --audio-driver Dummy --script res://tests/test_fs_attack_modifiers_review.gd.
## Подготовленные состояния seed26; HP/DC монстра и исходные значения в стеке тестовые, не естественная партия.
extends "res://tests/test_fs_mixed_next.gd"

func fixture() -> FSRules:
	var g := clean()
	g.hp = [20, 20]
	g.max_hp = [20, 20]
	g.coins = [3, 3]
	g.bank = 94
	g.damage_shields = [0, 0]
	g.dead = [false, false]
	g.temporary_attack.clear()
	g._turn_attack_rolls.clear()
	g.battle = 0
	g.battle_player = -1
	g.monsters = [{"id": 450, "hp": 20, "dc": 4, "at": 1}]
	g.phase = "battle_roll"
	g._after_stack = "battle_roll"
	return g

func require(ok: bool, label: String) -> bool:
	check(ok, "Подготовка: " + label)
	return ok

func queue_attack(g: FSRules, raw: int) -> bool:
	if not require(g.action(0, "roll", {}), "атака создана через action roll"):
		return false
	if not require(not g.stack.is_empty() and g.stack.back().kind == "roll", "ожидающий бросок на вершине"):
		return false
	# Подмена только случайной исходной грани; модификатор/урон/награды выполняют настоящие правила.
	g.stack.back().value = raw
	return true

func resolve_attack(g: FSRules, raw: int) -> bool:
	if not queue_attack(g, raw):
		return false
	g._finish_responses()
	return true

func check_view(g: FSRules, label: String) -> void:
	for seat in [0, 1, -1]:
		var view: Dictionary = g.get_view(seat)
		check(view.last_roll == g.last_roll, label + ": итоговая грань в view места%d" % seat)
		check(view.monsters[0].hp == g.monsters[0].hp, label + ": HP монстра в view места%d" % seat)
		for owner in 2:
			check(view.players[owner].coins == g.coins[owner], label + ": монеты игрока%d в view места%d" % [owner, seat])
			check(view.players[owner].hp == g.hp[owner], label + ": HP игрока%d в view места%d" % [owner, seat])

func dc_floor() -> void:
	var g := fixture()
	g.monsters[0].dc = 1
	g._gain_item(0, 34)
	for seat in [0, 1, -1]:
		check(int(g.get_view(seat).monsters[0].dc) == 1, "34: эффективная защита в view не ниже1, место%d" % seat)
	if resolve_attack(g, 1):
		check(g.last_roll == 1 and int(g.monsters[0].hp) == 20 and g.hp == [19, 20],
			"34: итоговая1 промахивается даже при минимальной защите")
		check_view(g, "34 DC1")

func holy_keeper_head() -> void:
	var g := fixture()
	g._gain_item(0, 36)
	# Голова445 открыта отдельно от атакуемого Сгустка450.
	g.monsters.append({"id": 445, "hp": 20, "dc": 4, "at": 1})
	if not resolve_attack(g, 3):
		return
	check(g.last_roll == 4, "36+445: первая исходная3 разрешилась как4")
	check(g.coins == [5, 3] and g.bank == 92, "445: итоговая4 дала ровно2 монеты бросившему")
	check(int(g.monsters[0].hp) == 19 and g.hp == [20, 20], "Итоговая4 попала и нанесла1 урон")
	check_view(g, "36+445")

func global_penny() -> void:
	var g := fixture()
	g._gain_item(0, 36)
	g._gain_item(1, 165)
	if not resolve_attack(g, 4):
		return
	check(g.last_roll == 5, "36+165: первая исходная4 разрешилась как5")
	check(g.coins == [3, 6] and g.bank == 91, "165 другого игрока получает3 за чужую итоговую5")
	check(int(g.monsters[0].hp) == 19 and g.hp == [20, 20], "Итоговая5 нанесла монстру1 урон")
	check_view(g, "36+165")

func counters_use_final_face() -> void:
	var g := fixture()
	g._gain_item(0, 36)
	g._gain_item(1, 55)
	g._gain_item(1, 85)
	# Счётчики источников заданы явно, не зависят от начальной раздачи/текстов item_entry.
	g.items[1][0].counters = 0
	g.items[1][1].counters = 0
	if not resolve_attack(g, 1):
		return
	check(g.last_roll == 2, "36+55/85: первая исходная1 разрешилась как2")
	check(g.items[1][0].counters == 0, "55 не реагирует на исходную1 после модификации")
	check(g.items[1][1].counters == 1, "85 реагирует на итоговую2 ровно один раз")
	check(g.coins == [3, 3] and int(g.monsters[0].hp) == 20 and g.hp == [19, 20],
		"Итоговая2 промахнулась, без посторонних наград")
	for seat in [0, 1, -1]:
		var view: Dictionary = g.get_view(seat)
		check(view.players[1].items[0].counters == 0 and view.players[1].items[1].counters == 1,
			"View места%d показывает настоящие счётчики55/85" % seat)
	check_view(g, "36+55/85")

## Осколок515 — настоящий ответ другого игрока, op reroll создаёт reroll_request исходному владельцу.
## Ожидание: переброс заменяет одну атаку; она получает один +1 и одну награду за итоговую4.
## Не утверждаем конкретный момент выдачи монет внутри промежуточного окна, только верхнюю границу и финал.
func reroll_one_attack() -> void:
	var g := fixture()
	g._gain_item(0, 36)
	g.monsters.append({"id": 445, "hp": 20, "dc": 4, "at": 1})
	g.hands[1] = [515]
	g.character_ready[1] = true
	if not queue_attack(g, 6):
		return
	if not require(g.action(1, "loot", {"card": 515}), "игрок1 отвечает Осколком515"):
		return
	g._resolve_top()
	if not require(g.phase == "effect" and g.resolving.get("card") == 515, "Осколок открыл ручной эффект над атакой"):
		return
	if not require(g.action(1, "effect", {"op": "reroll", "target": 0}), "op reroll принят"):
		return
	if not require(g.resolving.has("reroll_request") and g.actor() == 0, "переброс поручен владельцу исходной атаки"):
		return
	check(not g.action(1, "effect_roll", {}), "Автор Осколка не может перебросить чужую атаку")
	var before: int = g.roll_no
	if not require(g.action(0, "effect_roll", {}), "исходный владелец бросил через action effect_roll"):
		return
	if not require(not g.stack.is_empty() and g.stack.back().kind == "effect_roll", "создан промежуточный effect_roll"):
		return
	g.stack.back().value = 3
	g._finish_responses()
	if not require(g.phase == "effect" and g.resolving.get("card") == 515, "переброс вернулся к Осколку"):
		return
	check(g.roll_no == before + 1, "Переброс создал один новый случайный результат")
	check(int(g._turn_attack_rolls.get(0, 0)) == 0, "Промежуточный effect_roll не завершил отдельную атаку")
	check(int(g.monsters[0].hp) == 20 and g.hp == [20, 20], "До завершения Осколка боевой урон не нанесён")
	check(g.coins[1] == 3 and int(g.coins[0]) in [3, 5], "Промежуточное окно не дало двойную награду или монеты автору ответа")
	if not require(g.action(1, "effect_done", {}), "Осколок завершён настоящим action"):
		return
	g._finish_responses()
	check(g.last_roll == 4, "Переброшенная первая атака: исходная3+1=4, не5")
	check(int(g._turn_attack_rolls.get(0, 0)) == 1, "Переброс учтён ровно как одна разрешённая атака")
	check(g.coins == [5, 3] and g.bank == 92, "445 наградила итоговую4 ровно один раз за всю атаку")
	check(int(g.monsters[0].hp) == 19 and g.hp == [20, 20], "Переброшенная атака нанесла ровно1 урон")
	check(g.discards.loot.count(515) == 1, "Осколок сброшен ровно один раз")
	check_view(g, "36 переброс")
	# Поведение следующей пары атак различает одну атаку от двойного/сбитого счёта переброса.
	if not resolve_attack(g, 3):
		return
	check(g.last_roll == 3 and int(g.monsters[0].hp) == 19 and g.hp == [19, 20],
		"Вторая атака после переброса не получает +1 и промахивается")
	check(g.coins == [5, 3], "Вторая итоговая3 не повторяет награду445")
	if not resolve_attack(g, 3):
		return
	check(g.last_roll == 4 and int(g.monsters[0].hp) == 18 and g.hp == [19, 20],
		"Третья атака после переброса получает один +1 и попадает")
	check(g.coins == [7, 3] and g.bank == 90, "Третья итоговая4 даёт ровно следующую награду445")
	check(int(g._turn_attack_rolls.get(0, 0)) == 3, "После трёх атак с одним перебросом порядковый номер3")
	check_view(g, "36 после переброса и трёх атак")

func _initialize() -> void:
	dc_floor()
	holy_keeper_head()
	global_penny()
	counters_use_final_face()
	reroll_one_attack()
	print("ATTACK MODIFIERS REVIEW: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
