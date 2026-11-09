extends RefCounted
## Время на хосте (FSRules.tick): окно ответов закрывается само — HP монстра и игрока меняются,
## смерть наступает без следующего действия активного игрока (регресс 01.11: «смерть не срабатывает»);
## свои карты в чужой ход — только первые 10 с хода.
const FSCheck = preload("res://tests/fs/fs_check.gd")
const FSScenario = preload("res://tests/fs/fs_scenario.gd")

func run(t: FSCheck) -> void:
	_monster_dies_by_itself(t)
	_player_dies_by_itself(t)
	_heal_applies_by_itself(t)
	_off_turn_window(t)
	_response_resets_window(t)

## Тихие секунды: tick шагами по 0,5 с.
func _wait(s: FSScenario, seconds: float) -> void:
	var steps := int(ceil(seconds / 0.5))
	for _i in steps:
		s.g.tick(0.5)
	s.inv("tick")

func _monster_dies_by_itself(t: FSCheck) -> void:
	var s := FSScenario.new(t).players(2).current(0).character(0, 821).monster(0, 344, {"hp": 1, "dc": 2, "at": 1}).build()
	s.roll(6)
	s.ok(0, "attack", {"slot": 0}, "атака")
	s.ok(0, "roll", null, "попадание")
	t.equal(int(s.g.monsters[0].hp), 1, "До конца окна ответов урон ещё в стеке")
	_wait(s, 5.5)  # RESPONSE_WINDOW = 5 с
	t.check(int(s.g.monsters[0].hp) <= 0 or s.g.resolving.get("kind", "") == "reward", "Окно закрылось само — монстр получил урон")
	# смерть монстра — тоже в стек ответов; ещё одно тихое окно — награда
	if s.g.phase == "priority":
		_wait(s, 5.5)
	t.equal(s.g.phase, "effect", "Смерть монстра сработала сама: награда")
	t.equal(str(s.g.resolving.get("kind", "")), "reward", "Разрешается награда за монстра")

func _player_dies_by_itself(t: FSCheck) -> void:
	var s := FSScenario.new(t).players(2).current(0).character(0, 821).monster(0, 344, {"hp": 5, "dc": 6, "at": 3}).build()
	s.roll(1)
	s.ok(0, "attack", {"slot": 0}, "атака")
	s.ok(0, "roll", null, "промах — монстр бьёт")
	_wait(s, 5.5)
	t.equal(int(s.g.hp[0]), 0, "Урон монстра применился сам")
	if s.g.phase == "priority":
		_wait(s, 5.5)
	t.equal(s.g.phase, "death", "Смерть игрока сработала сама: штраф")
	t.equal(s.g.actor(), 0, "Штраф выбирает погибший")

func _heal_applies_by_itself(t: FSCheck) -> void:
	# небоевой урон через панель эффекта: после «Эффект выполнен» смерть объявляется и разрешается сама
	var s := FSScenario.new(t).players(2).current(0).character(0, 821).hand(0, [497]).hp(1, 1).build()
	s.ok(0, "loot", {"card": 497}, "лут")
	_wait(s, 5.5)
	t.equal(s.g.phase, "effect", "Карта лута дошла до эффекта без ручного закрытия ответов")
	s.choose(0, "damage", {"target": 1})
	_wait(s, 5.5)
	t.equal(s.g.phase, "priority", "09.11: на смерть отвечают дольше — через 5 с штраф ещё не начался")
	_wait(s, 5.0)
	t.equal(s.g.phase, "death", "Смерть второго игрока — сама после тихого окна 10 с")
	t.equal(s.g.actor(), 1, "Штраф выбирает погибший (место 1)")

func _off_turn_window(t: FSCheck) -> void:
	# 06.11 (решение владельца): окна «первые 10 с хода» больше нет — свои карты в чужой ход всегда.
	var s := FSScenario.new(t).players(2).current(0).character(1, 821).hand(1, [497, 478]).build()
	s.g.character_ready[1] = true
	_wait(s, 11.0)
	t.check(s.g.off_turn_open(1), "После 10 с хода чужие карты по-прежнему можно")
	s.ok(1, "loot", {"card": 497}, "лут в чужой ход на 11-й секунде")
	t.check(s.g.off_turn_open(0), "Активному игроку время не мешает")

func _response_resets_window(t: FSCheck) -> void:
	var s := FSScenario.new(t).players(2).current(0).character(0, 821).hand(1, [478]).monster(0, 344, {"hp": 3, "dc": 2, "at": 1}).build()
	s.g.character_ready[1] = true
	s.roll(6)
	s.ok(0, "attack", {"slot": 0}, "атака")
	s.ok(0, "roll", null, "бросок")
	_wait(s, 3.0)
	var before: int = s.g.stack.size()
	s.ok(1, "loot", {"card": 478}, "ответ картой")
	t.check(s.g.stack.size() > before, "Ответ лёг в стек")
	_wait(s, 3.0)
	t.check(s.g.stack.size() > before - 1 and s.g.phase == "priority", "Ответ продлил окно: 3 с после него стек ещё ждёт")
