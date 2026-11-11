extends "res://tests/fs/core/core_owner_1110.gd"
## Four Souls, задачи владельца от 11 ноября: обмен предметом здоровья («Палец!»), душа за Гнева,
## «Добавить душу» в панели хоста.

func run(t: Check) -> void:
	_finger_swaps_health(t)
	_wrath_gives_soul(t)
	_wrath_kills_slayer(t)
	_host_adds_soul(t)


func _finger_swaps_health(t: Check) -> void:
	var s := Scenario.new(t).players(3).dlc().current(0).no_items(0).no_items(1).no_items(2).item(0, 212).item(0, 211).item(1, 39).build()
	var g := s.g
	var mine: Dictionary = g.items[0][g.items[0].size() - 1]
	var milk: Dictionary = g.items[1][g.items[1].size() - 1]
	var owner_max: int = g.max_hp[1]
	var thief_max: int = g.max_hp[0]
	var thief_hp: int = g.hp[0]
	g._swap_items14(0, mine, 1, milk)
	t.equal(g.max_hp[1], owner_max - 1, "Обмен: прежний владелец предмета здоровья теряет его +1")
	t.equal(g.max_hp[0], thief_max + 1, "Обмен: новый владелец получает +1 к максимуму здоровья")
	t.equal(g.hp[0], thief_hp + 1, "Обмен: новый владелец получает и само здоровье")
	t.check(g.hp[1] <= g.max_hp[1], "Обмен: здоровье прежнего владельца не выше нового максимума")
	var index: int = g.items[0].find(milk)
	g._remove_item(0, index, true)
	t.equal(g.max_hp[0], thief_max, "Сброс украденного предмета снимает ровно его бонус")
	t.equal(g.max_hp[1], owner_max - 1, "Сброс у нового владельца не трогает прежнего")


func _wrath_gives_soul(t: Check) -> void:
	for face: int in [2, 5]:
		var wrath = _monster(t, 393, {"hp": 1})
		for seat in 3:
			wrath.g.max_hp[seat] = 4
			wrath.g.hp[seat] = 4
		var souls_before: int = wrath.g.souls[0]
		var coins_before: int = wrath.g.coins[0]
		_attack_roll17(wrath, 6)
		_die(wrath, face)
		for guard in 12:
			if wrath.g.phase == "turn" and wrath.g.resolving.is_empty() and wrath.g.stack.is_empty():
				break
			wrath.close()
		t.equal(wrath.g.hp[1], 4 - (1 if face <= 3 else 2), "Гнев: смерть наносит урон каждому игроку (бросок %d)" % face)
		t.equal(wrath.g.coins[0], coins_before + 6, "Гнев: награда 6 монет (бросок %d)" % face)
		t.equal(wrath.g.souls[0], souls_before + 1, "Гнев: за убийство даётся душа (бросок %d)" % face)


## Активный игрок погибает от смерти Гнева (2 здоровья, бросок 5): награда за убитого монстра всё равно его.
func _wrath_kills_slayer(t: Check) -> void:
	var wrath = _monster(t, 393, {"hp": 1})
	var souls_before: int = wrath.g.souls[0]
	var coins_before: int = wrath.g.coins[0]
	_attack_roll17(wrath, 6)
	_die(wrath, 5)
	for guard in 30:
		if wrath.g.phase == "death":
			var dying: int = wrath.g.actor()
			wrath.g.action(dying, "death", {"loot": int(wrath.g.hands[dying][0]) if not wrath.g.hands[dying].is_empty() else -1, "item": -1})
		elif wrath.g.resolving.is_empty() and wrath.g.stack.is_empty():
			break
		else:
			wrath.close()
	t.equal(wrath.g.souls[0], souls_before + 1, "Гнев убил победителя: душа всё равно получена")
	t.check(wrath.g.coins[0] >= coins_before + 5, "Гнев убил победителя: монеты награды получены (минус штраф смерти)")


func _host_adds_soul(t: Check) -> void:
	var s := Scenario.new(t).players(3).dlc().current(0).build()
	var before: int = s.g.souls[1]
	t.check(s.g.host_add_soul(1), "Панель хоста: «Добавить душу» принята")
	t.equal(s.g.souls[1], before + 1, "Панель хоста: у игрока стало на душу больше")
	t.check(not s.g.host_add_soul(9), "Панель хоста: несуществующее место отклонено")
