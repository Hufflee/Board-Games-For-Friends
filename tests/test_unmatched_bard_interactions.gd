extends SceneTree
## Редкие взаимодействия новых колод: очередь, отмена, закрытая рука и командная защита.
const Setup := preload("res://games/unmatched/logic/um_setup.gd")
const Rules := preload("res://games/unmatched/logic/um_rules.gd")
const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")
var checks := 0
var errors := 0
var live: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cauldron()
	_end_turn()
	_conditional_cancel()
	_enchantments()
	_secrets()
	_team_swap()
	_team_follow_up()
	_tomoe()
	_blind_boost()
	_line_placement()
	for r: RefCounted in live: r.clear_choices()
	live.clear()
	print("Unmatched, взаимодействия новых колод: %d проверок, %d ошибок." % [checks, errors])
	quit(int(errors > 0))


func game(heroes: PackedStringArray) -> RefCounted:
	var rng := RandomNumberGenerator.new()
	rng.seed = 633
	var owners := PackedInt32Array([11, 12] if heroes.size() == 2 else [11, 12, 13, 14])
	var setup: RefCounted = Setup.create("marmoreal", heroes, owners, rng)
	for step in 30:
		var pending: Dictionary = setup.pending()
		if pending.is_empty(): break
		if pending.get("choose_size", false):
			setup.choose_size(owners[pending.seat], true)
		else:
			setup.place(owners[pending.seat], pending.cells[0])
	var r := Rules.new(setup)
	live.append(r)
	r.actions_left = 10
	setup.fighters[0][0].space = 13
	setup.fighters[1][0].space = 7
	return r


func hand(r: RefCounted, owner: int, numbers: Array) -> void:
	var deck := Catalog.deck_for(r.game.heroes[owner], owner)
	r.game.hands[owner] = deck.filter(func(card: Dictionary) -> bool: return int(card.key.get_slice(":", 1)) in numbers)
	r.game.decks[owner] = deck.filter(func(card: Dictionary) -> bool: return int(card.key.get_slice(":", 1)) not in numbers)


func answer(r: RefCounted, selected: Variant) -> void:
	var request: Dictionary = r._effect_request
	check(not request.is_empty(), "Есть обязательный ожидаемый запрос")
	if not request.is_empty():
		check(r.choose_effect(r.game.controllers[request.seat], request.id, selected), "Принят выбранный вариант %s" % str(selected))


func fight(r: RefCounted, attack: String, defense: String, defender_seat: int = 1) -> void:
	check(r.begin_attack(11, 0, defender_seat, 0, attack), "Атака начата")
	var view: Dictionary = r.attack_view(r.game.controllers[defender_seat])
	var choice: Dictionary = view.get("choice", {})
	check(not choice.is_empty(), "Выбор защиты существует")
	if choice.is_empty(): return
	check(r.choose_combat_card(r.game.controllers[defender_seat], {"request": choice.id, "hand": defender_seat,
		"cards": [] if defense.is_empty() else [defense]}), "Защита принята")
	check(r.resolve_combat(), "Бой принят очередью эффектов")


func _cauldron() -> void:
	var r := game(["witches", "bloody_mary"])
	hand(r, 0, [16])
	hand(r, 1, [])
	var snake: Dictionary = r.game.decks[0].pop_back()
	# Последняя карта — защита со змеёй.
	r.game.discards[0].append(snake)
	r.game.fighters[0][1].health = 4
	fight(r, "0:16", "")
	answer(r, snake.key)
	check(r._effect_request.options.has("snake_bat"), "Варево использует ингредиент только что сыгранной атаки")
	answer(r, "snake_bat")
	answer(r, Vector2i(0, 1))
	check(r.bard.cauldron.is_empty() and r.game.discards[0].size() == 2 and r.game.fighters[0][1].health == 5,
		"Заклятие лечит выбранную сестру и очищает весь котёл")
	r._damage(Vector2i(0, 0), 99)
	r._damage(Vector2i(0, 1), 99)
	r._check_victory()
	check(r.winner == -1, "Последняя живая сестра сохраняет партию")
	r._damage(Vector2i(0, 2), 99)
	r._check_victory()
	check(r.winner == 1, "Победа после поражения всех трёх сестёр")


func _end_turn() -> void:
	var r := game(["shakespeare", "hamlet"])
	hand(r, 0, [28])
	hand(r, 1, [21])
	var first: Dictionary = r.game.decks[0].pop_front()
	r.bard.poem.append(first)
	fight(r, "0:28", "1:21")
	check(r.seat == 1 and r.bard.poem == [first], "Конец хода пропускает добавление карты Шекспира и завершение строки")
	check(r.game.discards[0].any(func(card: Dictionary) -> bool: return card.key == "0:28"), "Карта Шекспира сбрасывается при завершении хода")


func _conditional_cancel() -> void:
	var r := game(["bloody_mary", "tomoe"])
	hand(r, 0, [10])
	hand(r, 1, [14])
	fight(r, "0:10", "1:14")
	check(r.last_combat.attack_canceled and not r.last_combat.defense_canceled,
		"Условная отмена защиты Томоэ предшествует атакующей Уловке")
	check(r.game.fighters[0][0].health == 15, "После восстановленной защиты Томоэ наносит 1 урон")


func _enchantments() -> void:
	var r := game(["tomoe", "titania"])
	hand(r, 0, [6])
	hand(r, 1, [14])
	fight(r, "0:06", "1:14")
	check(r.last_combat.damage == 0 and r.last_combat.attack_canceled, "Словно сон обнуляет атаку и отменяет её добор")
	check(r.game.hands[0].size() == 1 and r.game.hands[0][0].key == "0:06", "Атака вернулась ровно один раз")
	check(r.game.hands[1].size() == 1, "После Словно сон Титания берёт карту")
	r.bard.enchantment = 5
	var before: int = r.game.fighters[1][0].health
	r._damage(Vector2i(1, 0), 3)
	check(r.game.fighters[1][0].health == before, "Сон предотвращает урон эффекта")
	r.bard._combat_damage = true
	r._damage(Vector2i(1, 0), 2)
	r.bard._combat_damage = false
	check(r.game.fighters[1][0].health == before - 2, "Сон пропускает боевой урон")
	var other := game(["titania", "bloody_mary"])
	other.bard.enchantment = 0
	hand(other, 0, [28])
	hand(other, 1, [])
	fight(other, "0:28", "")
	answer(other, "discard")
	check(other.last_combat.attack_value == 5 and other.bard.enchantment == -1 and other.bard.enchantment_discard == [0],
		"Сказочная песня сбрасывает активные чары и становится пятёркой")


func _secrets() -> void:
	var r := game(["titania", "houdini"])
	hand(r, 0, [5])
	hand(r, 1, [26, 1])
	var deck_before: Array = r.game.decks[1].duplicate(true)
	check(r.play_scheme(11, 1, "0:05"), "Приём Оберона начат")
	answer(r, 1)
	check(r.effect_view(11).is_empty() and not r.effect_view(12).is_empty(), "Запрос раскрытия секрета приватен владельцу Гудини")
	answer(r, "reveal")
	check(r.game.decks[1] == deck_before and r.game.hands[1].size() == 2, "Секрет отменяет просмотр и замешивание карты")


func _team_swap() -> void:
	var r := game(["alice", "oda", "bloody_mary", "genie"])
	hand(r, 0, [4])
	hand(r, 1, [7])
	var cell := -1
	for next in r.game.board.cell_count():
		if next != 13 and r.game.board.adjacent(7, next):
			cell = next
			break
	r.game.fighters[3][0].space = cell
	fight(r, "0:04", "1:07")
	answer(r, Vector2i(3, 0))
	check(r.game.fighters[3][0].space == 7 and r.game.fighters[1][0].space == cell, "Союзник другого игрока защищает вместо Оды")
	check(r.game.discards[1].any(func(card: Dictionary) -> bool: return card.key == "1:07") and r.game.discards[3].is_empty(),
		"После командной замены карта возвращается в сброс её владельца")


func _team_follow_up() -> void:
	var r := game(["achilles", "oda", "alice", "genie"])
	hand(r, 0, [3])
	hand(r, 1, [7])
	hand(r, 3, [28])
	for cell in r.game.board.cell_count():
		if cell != 13 and r.game.board.adjacent(7, cell):
			r.game.fighters[3][0].space = cell
			break
	fight(r, "0:03", "1:07")
	answer(r, Vector2i(3, 0))
	var follow: Dictionary = r.attack_view(14).get("choice", {})
	check(follow.get("hand", -1) == 3, "В дополнительной атаке защищается рука нового союзного бойца")
	if follow.is_empty(): return
	check(r.choose_combat_card(14, {"request": follow.id, "hand": 3, "cards": ["3:28"]}) and r.resolve_combat(),
		"Защита нового владельца в дополнительной атаке разрешилась")
	check(r.game.discards[3].any(func(card: Dictionary) -> bool: return card.key == "3:28")
		and not r.game.discards[1].any(func(card: Dictionary) -> bool: return card.key == "3:28"),
		"Карта дополнительной защиты попадает в сброс её нового владельца, а не Оды")


func _tomoe() -> void:
	var r := game(["tomoe", "bloody_mary"])
	var from := -1
	var to := -1
	for a in r.game.board.cell_count():
		for b in r.game.board.cell_count():
			if a != 13 and r.game.board.same_zone(13, a) and not r.game.board.same_zone(13, b) and r.game.board.adjacent(a, b):
				from = a
				to = b
	check(from >= 0, "Найден выход из зоны Томоэ")
	r.game.fighters[1][0].space = from
	var before: int = r.game.fighters[1][0].health
	r._walk_fighter(Vector2i(1, 0), PackedInt32Array([from, to]))
	check(r.game.fighters[1][0].health == before - 1, "Выход вражеского героя из зоны наносит 1 урон")
	r.bard.rooted[Vector2i(1, 0)] = true
	check(r._movement_cells(Vector2i(1, 0), Vector2i(0, 0), {"place": "anywhere"}).is_empty(), "Неподвижного бойца нельзя поместить эффектом")


func _blind_boost() -> void:
	var r := game(["tomoe", "hamlet"])
	hand(r, 0, [12])
	hand(r, 1, [27])
	var top: Dictionary = {}
	for index in r.game.decks[1].size():
		if r.game.decks[1][index].key == "1:19":
			top = r.game.decks[1].pop_at(index)
			break
	r.game.decks[1].append(top)
	fight(r, "0:12", "1:27")
	check(r.game.hands[1].any(func(card: Dictionary) -> bool: return card.key == "1:19"), "Проигравший Гамлет возвращает именно карту слепого усиления")
	check(not r.game.discards[1].any(func(card: Dictionary) -> bool: return card.key == "1:19"), "Слепое усиление не дублируется в сбросе")


func _line_placement() -> void:
	var r := game(["shakespeare", "bloody_mary"])
	r.bard.line_effect(0, Catalog.deck_for("shakespeare", 0)[4])
	for step in 4:
		check(not r._effect_request.optional, "Поместить каждого бойца — обязательный выбор")
		var target: Vector2i = r._effect_request.options[0]
		answer(r, target)
		answer(r, r.game.fighters[target.x][target.y].space)
	check(r._effect_request.is_empty(), "Завершение строки обработало всех четырёх бойцов")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
