extends SceneTree
## Регрессия HP боя через публичные действия. Запуск: --headless --script res://tests/test_fs_combat_hp.gd.
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func make() -> FSRules:
	var g := FSRules.new()
	g.new_game([{"name": "Первый"}, {"name": "Второй"}], false, 77)
	g.current = 0
	g.monsters[0].hp = 3
	g.monsters[0].dc = 1
	g.attack[0] = 1
	check(g.action(0, "attack", {"slot": 0}), "Объявлена атака")
	check(g.action(0, "roll"), "Бросок после объявления атаки")
	return g

func _initialize() -> void:
	var g := make()
	check(g.monsters[0].hp == 3, "Ответы на первый бросок ещё открыты")
	check(g.action(0, "roll"), "Второй бросок закрывает ответы на первый")
	check(g.monsters[0].hp == 2, "Урон первого попадания применён ровно один раз")
	check(g.get_view(0).monsters[0].hp == 2, "View передаёт уменьшенный HP")
	check(g.action(0, "roll") and g.monsters[0].hp == 1, "Повторное попадание сохраняет предыдущий урон")
	check(g.action(0, "roll") and g.phase == "effect", "Смертельное попадание открывает награду")
	check(g.monsters[0].hp == 0 and g.roll_no == 3, "Награда останавливает следующий бросок, HP равен нулю")
	g = make()
	g.monsters[0].dc = 7
	var hp_before: int = g.hp[0]
	# Первый бросок уже выпал, но порог проверяется при разрешении окна ответов.
	check(g.action(0, "roll"), "Разрешён промах")
	check(g.monsters[0].hp == 3, "Промах не уменьшает HP монстра")
	check(g.hp[0] == hp_before - int(g.monsters[0].at), "Промах уменьшает HP игрока")
	g = make()
	check(g.action(1, "activate", {"item": 0}), "На бросок отвечает другой игрок")
	check(g.action(0, "roll") and g.phase == "effect", "Бросок ждёт ручной ответ")
	check(g.monsters[0].hp == 3, "Ручной ответ не пропущен ради урона")
	check(g.action(1, "effect_done"), "Ручной ответ завершён")
	check(g.monsters[0].hp == 2 and g.roll_no == 2, "После ответа применён урон и выполнен отложенный бросок")
	print("FS COMBAT HP: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
