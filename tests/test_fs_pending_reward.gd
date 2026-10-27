extends SceneTree
## Проклятая опухоль активна до ухода из слота, включая бросок её награды.
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _initialize() -> void:
	var g := FSRules.new()
	g.new_game([{"name": "А"}, {"name": "Б"}], false, 26)
	preload("res://tests/fs_test_setup.gd").finish(g)
	g.monsters = [{"id": 376, "hp": 0, "dc": 4, "at": 1, "death_pending": true}]
	g.hp = [2, 2]
	g.damage_shields = [0, 1]
	g.resolving = {"kind": "reward", "card": 376, "slot": 0, "owner": g.current}
	g.phase = "effect"
	g._roll_passives(3)
	check(g.hp == [2, 2], "Тройка не наносит урон")
	g._roll_passives(4)
	check(g.hp == [1, 2], "Четвёрка награды действует до удаления монстра, учитывает щит")
	check(g.damage_shields == [0, 0], "Щит расходуется ровно один раз")
	g.monsters.clear()
	g._roll_passives(4)
	check(g.hp == [1, 2], "После удаления карты четвёрка не наносит урон")
	# Накрытый монстр не активен, даже если он лежит в under.
	g.monsters = [{"id": 349, "hp": 2, "dc": 4, "at": 1,
		"under": {"id": 376, "hp": 3, "dc": 4, "at": 1}}]
	g._roll_passives(4)
	check(g.hp == [1, 2], "Накрытая опухоль не действует")
	# Реальное разрешение effect_roll возвращает прежнюю награду.
	g.monsters = [{"id": 376, "hp": 0, "dc": 4, "at": 1, "death_pending": true}]
	g.hp = [3, 3]
	g.max_hp = [3, 3]
	g.paused_effects = [{"effect": {"kind": "reward", "card": 376, "slot": 0, "owner": g.current},
		"resume": "turn", "peek": {}, "roller": g.current}]
	g.stack = [{"kind": "effect_roll", "value": 4, "owner": g.current}]
	g._resolve_top()
	check(g.hp == [2, 2], "Разрешение броска награды наносит всем по одному урону")
	check(g.phase == "effect" and g.resolving.kind == "reward", "Ручная награда восстанавливается после броска")
	# Переброс принадлежит владельцу исходного кубика, а не владельцу карты ответа.
	g = FSRules.new()
	g.new_game([{"name": "А"}, {"name": "Б"}], false, 26)
	preload("res://tests/fs_test_setup.gd").finish(g)
	g.current = 0
	g.phase = "effect"
	g.resolving = {"kind": "loot", "card": 515, "owner": 1}
	g.stack = [{"kind": "roll", "owner": 0, "value": 3}]
	g._after_stack = "battle_roll"
	var before := g.roll_no
	check(g.action(1, "effect", {"op": "reroll", "target": 0}), "Осколок кубика запрашивает переброс")
	check(g.roll_no == before and g.stack[0].value == 3, "Результат не меняется до жеста")
	check(g.actor() == 0, "Кубик доступен владельцу исходного броска")
	check(not g.action(1, "effect_roll"), "Автор карты не может бросить чужой кубик")
	check(not g.action(1, "effect_done"), "Нельзя завершить карту до переброса")
	check(g.action(0, "effect_roll"), "Владелец исходного броска делает жест")
	check(g.roll_no == before + 1 and g.phase == "priority", "Один жест создаёт один бросок и окно ответов")
	g._finish_responses()
	check(g.phase == "effect" and g.resolving.card == 515, "После переброса возвращается Осколок кубика")
	check(g.stack[0].value == g.last_roll and g.stack[0].get("passives_done", false), "Исходный бросок заменён, пассив не вызывается второй раз")
	print("FS PENDING REWARD: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
