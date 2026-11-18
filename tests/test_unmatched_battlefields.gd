extends SceneTree
## Проверки Робин Гуда, предметов и опасных дорожек. Запускать headless с Dummy.

const Maps := preload("res://games/unmatched/logic/um_maps.gd")
const Setup := preload("res://games/unmatched/logic/um_setup.gd")
const Rules := preload("res://games/unmatched/logic/um_rules.gd")
const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")
const Match := preload("res://games/unmatched/logic/um_match.gd")
var errors := 0
var checks := 0


func _initialize() -> void:
	_robin()
	_items()
	_item_combat()
	_danger()
	_owners()
	_faq()
	print("Unmatched, особенности: %d проверок, %d ошибок." % [checks, errors])
	quit(int(errors > 0))


func _new_rules(arena: String, heroes: PackedStringArray = ["robin_hood", "bloody_mary"]) -> RefCounted:
	var rng := RandomNumberGenerator.new()
	rng.seed = 382
	var game: RefCounted = Setup.create(arena, heroes, [11, 12], rng)
	while not game.pending().is_empty():
		var step: Dictionary = game.pending()
		game.place(game.controllers[step.seat], step.cells[0])
	var rules := Rules.new(game)
	rules.start_turn()
	return rules


func _faq() -> void:
	# Оба героя погибают в одном действии: игнорирование защиты не меняет её значение для «Вдребезги».
	var rules := _new_rules("marmoreal", ["sun_wukong", "bloody_mary"])
	var game: RefCounted = rules.game
	rules.clear_choices()
	rules.phase = Rules.Phase.ACTION
	game.fighters[0][0].space = 13
	game.fighters[0][0].health = 2
	game.fighters[1][0].space = 7
	game.fighters[1][0].health = 3
	var attack: Dictionary = Catalog.deck_for("sun_wukong", 0)[6]
	var defense: Dictionary = Catalog.deck_for("bloody_mary", 1)[14]
	game.hands[0] = [attack]
	game.hands[1] = [defense]
	check(rules.begin_attack(11, 0, 1, 0, attack.key), "FAQ: начата атака против зеркала")
	var choice: Dictionary = rules.attack_view(12).choice
	check(rules.choose_combat_card(12, {"request": choice.id, "hand": 1, "cards": [defense.key]}) and rules.resolve_combat(),
		"FAQ: защита открыта")
	_choose(rules, null)
	check(game.fighters[0][0].health == 0 and game.fighters[1][0].health == 0
		and rules.phase == Rules.Phase.FINISHED and rules.winner == 0,
		"FAQ: посмертное зеркало завершает действие, при гибели обоих побеждает активная команда")
	check(rules.last_combat.card_values == [3, 3] and rules.last_combat.damage == 3 and game.hands[1].size() == 1,
		"FAQ: игнорируемая защита сохраняет значение для зеркала, добор после смерти выполнен")
	rules.clear_choices()
	rules.phase = Rules.Phase.ACTION

	# Усиление от защиты действует раньше «Переломного момента» и заменяется его значением 5.
	rules = _new_rules("marmoreal", ["bigfoot", "sun_wukong"])
	game = rules.game
	rules.clear_choices()
	rules.phase = Rules.Phase.ACTION
	game.fighters[0][0].space = 13
	game.fighters[1][0].space = 7
	rules._turn_spaces[Vector2i(0, 0)] = 19
	attack = Catalog.deck_for("bigfoot", 0)[24]
	var boost: Dictionary = Catalog.deck_for("bigfoot", 0)[0]
	defense = Catalog.deck_for("sun_wukong", 1)[25]
	game.hands[0] = [attack, boost]
	game.hands[1] = [defense]
	check(rules.begin_attack(11, 0, 1, 0, attack.key), "FAQ: атакует переместившийся Бигфут")
	choice = rules.attack_view(12).choice
	check(rules.choose_combat_card(12, {"request": choice.id, "hand": 1, "cards": [defense.key]}) and rules.resolve_combat(),
		"FAQ: форма черепахи предлагает усиление")
	_choose(rules, boost.key)
	check(rules.last_combat.attack_value == 5 and rules.last_combat.damage == 0,
		"FAQ: значение становится 5 после усиления, прежние +3 заменены")
	rules.clear_choices()
	rules.phase = Rules.Phase.ACTION

	# Отмена атакующего не может отменить уже сработавшее «Немедленно» защиты.
	rules = _new_rules("marmoreal", ["bigfoot", "achilles"])
	game = rules.game
	game.fighters[0][0].space = 13
	game.fighters[1][0].space = 7
	game.fighters[1][1].space = 30
	attack = Catalog.deck_for("bigfoot", 0)[27]
	defense = Catalog.deck_for("achilles", 1)[22]
	game.hands[0] = [attack]
	game.hands[1] = [defense]
	check(rules.begin_attack(11, 0, 1, 0, attack.key), "FAQ: уловка атакует шлем Ахиллеса")
	choice = rules.attack_view(12).choice
	check(rules.choose_combat_card(12, {"request": choice.id, "hand": 1, "cards": [defense.key]}) and rules.resolve_combat(),
		"FAQ: шлем раскрыт против отмены")
	_choose(rules, Vector2i(1, 1))
	check(game.fighters[1][0].space == 30 and game.fighters[1][1].space == 7 and rules.last_combat.defense_canceled,
		"FAQ: Патрокл успел заменить Ахиллеса перед отменой оставшихся эффектов")
	rules.clear_choices()
	rules.phase = Rules.Phase.ACTION

	# Дополнительная атака требует живого атакующего, даже если обороняющийся выжил.
	rules = _new_rules("marmoreal", ["sun_wukong", "chupacabra"])
	game = rules.game
	rules.clear_choices()
	rules.phase = Rules.Phase.ACTION
	game.fighters[0][0].space = 13
	game.fighters[0][0].health = 1
	game.fighters[1][0].space = 7
	attack = Catalog.deck_for("sun_wukong", 0)[3]
	defense = Catalog.deck_for("chupacabra", 1)[10]
	game.hands[0] = [attack]
	game.hands[1] = [defense]
	check(rules.begin_attack(11, 0, 1, 0, attack.key), "FAQ: начат бой с дополнительной атакой")
	choice = rules.attack_view(12).choice
	check(rules.choose_combat_card(12, {"request": choice.id, "hand": 1, "cards": [defense.key]}) and rules.resolve_combat(),
		"FAQ: Чупакабра предлагает ответный урон")
	_choose(rules, Vector2i(0, 0))
	check(rules.phase == Rules.Phase.FINISHED and rules.winner == 1 and game.discards[0].has(attack),
		"FAQ: поверженный атакующий не начинает дополнительную атаку, карта сброшена")
	rules.clear_choices()
	rules.phase = Rules.Phase.ACTION

	# Неиспользованный предмет можно применить только ко второй атаке той же карты.
	rules = _new_rules("marmoreal", ["achilles", "bloody_mary"])
	game = rules.game
	game.fighters[0][0].space = 13
	game.fighters[1][0].space = 7
	rules.battlefield_items.clear()
	rules.battlefield_items.append({"id": 12, "cell": 13, "at": Vector2(0.5, 0.5)})
	attack = Catalog.deck_for("achilles", 0)[2]
	game.hands[0] = [attack]
	game.hands[1] = []
	check(rules.begin_attack(11, 0, 1, 0, attack.key), "FAQ: первая атака рядом с предметом")
	_choose(rules, null)
	choice = rules.attack_view(12).choice
	check(rules.choose_combat_card(12, {"request": choice.id, "hand": 1, "cards": []}) and rules.resolve_combat(),
		"FAQ: первая атака выполнена без предмета")
	check(rules.last_combat.attack_value == 1 and not rules.effect_view(11).is_empty(),
		"FAQ: предмет предлагается повторно для дополнительной атаки")
	_choose(rules, "use")
	choice = rules.attack_view(12).choice
	check(rules.choose_combat_card(12, {"request": choice.id, "hand": 1, "cards": []}) and rules.resolve_combat()
		and rules.last_combat.attack_value == 4 and rules.battlefield_items.is_empty(),
		"FAQ: одноразовый предмет усилил только дополнительную атаку")
	rules.clear_choices()


func _choose(rules: RefCounted, answer: Variant) -> void:
	var actor: int = rules.game.controllers[rules.choosing_seat()]
	var request: Dictionary = rules.effect_view(actor)
	check(not request.is_empty() and rules.choose_effect(actor, request.get("id", -1), answer), "Принят выбор %s" % str(answer))


func _item_rules(id: int, arena: String = "hell_s_kitchen") -> RefCounted:
	var rules := _new_rules(arena)
	rules.battlefield_items.clear()
	rules.battlefield_items.append({"id": id, "cell": rules.game.fighters[0][0].space, "at": Vector2(0.5, 0.5)})
	return rules


func _robin() -> void:
	var rules := _new_rules("marmoreal")
	var game: RefCounted = rules.game
	game.fighters[0][0].space = 4
	game.fighters[0][1].space = 5
	game.fighters[1][0].space = 6
	var deck: Array = Catalog.deck_for("robin_hood", 0)
	game.hands[0] = [deck[12]]
	game.hands[1] = [Catalog.deck_for("bloody_mary", 1)[11]]
	check(not rules.begin_attack(11, 0, 1, 0, deck[12].key), "Герой не может использовать карту разбойника")
	check(rules.begin_attack(11, 1, 1, 0, deck[12].key), "Разбойник начинает атаку")
	var request: Dictionary = rules.attack_view(12).choice
	check(rules.choose_combat_card(12, {"request": request.id, "hand": 1, "cards": [game.hands[1][0].key]}), "Выбрана защита от разбойника")
	check(rules.resolve_combat() and rules.last_combat.defense_value == 0 and rules.last_combat.damage == 2,
		"Разбой отменяет эффекты защиты и игнорирует значение")
	check(rules.effect_view(11).get("cells", false), "Отход на две клетки доступен разбойнику после атаки")
	_choose(rules, null)
	rules.clear_choices()
	rules = _new_rules("marmoreal")
	game = rules.game
	game.hands[0] = [deck[3]]
	var before: int = game.decks[0].size()
	check(rules.play_scheme(11, 0, deck[3].key), "Сыграно ограбление богачей")
	_choose(rules, 1)
	check(rules.effect_view(12).get("options", []) == ["discard", "draw"], "Противник выбирает, сбрасывать ли карту")
	_choose(rules, "draw")
	check(game.decks[0].size() == before - 2 and game.hands[0].size() == 2, "При отказе противника Робин получает ровно две карты")
	rules.clear_choices()
	rules = _new_rules("marmoreal", ["robin_hood", "medusa"])
	game = rules.game
	game.fighters[0][0].space = 4
	game.fighters[1][1].space = 5
	game.hands[0] = [deck[6]]
	game.hands[1] = []
	rules.begin_attack(11, 0, 1, 1, deck[6].key)
	request = rules.attack_view(12).choice
	rules.choose_combat_card(12, {"request": request.id, "hand": 1, "cards": []})
	check(rules.resolve_combat() and game.fighters[1][1].space == -1 and game.hands[0].size() == 4,
		"Обезоруживающий выстрел добирает четыре карты даже против помощника с одним здоровьем")
	rules.clear_choices()


func _items() -> void:
	for arena: String in Maps.Battlefields.POOLS:
		var rules := _new_rules(arena)
		var cells := {}
		for item: Dictionary in rules.battlefield_items:
			cells[item.cell] = true
			check(item.id in Maps.Battlefields.POOLS[arena], "На поле %s предмет из соответствующего набора" % arena)
		check(cells.size() == 6, "На поле %s шесть разных ячеек предметов" % arena)
		rules.clear_choices()
	var rules := _item_rules(11)
	var game: RefCounted = rules.game
	game.fighters[0][0].health = 8
	var hand: int = game.hands[0].size()
	check(not rules.use_battlefield_item(12, 0, 11) and not rules.use_battlefield_item(11, 1, 11), "Предмет требует своего хода и бойца на его клетке")
	check(rules.use_battlefield_item(11, 0, 11) and game.fighters[0][0].health == 10
		and game.hands[0].size() == hand + 1 and rules.actions_left == 1, "Аптечка лечит, даёт карту и тратит действие")
	check(not rules.use_battlefield_item(11, 0, 11) and rules.used_items.size() == 1, "Использованный предмет расходуется ровно один раз")
	rules.clear_choices()
	rules = _item_rules(29)
	rules.game.fighters[0][0].health = 12
	rules.use_battlefield_item(11, 0, 29)
	check(rules.game.fighters[0][0].health == 13, "Лечение слаша ограничено максимумом здоровья")
	rules.clear_choices()
	rules = _item_rules(22)
	var card: Dictionary = rules.game.hands[0].pop_back()
	rules.game.discards[0].append(card)
	rules.use_battlefield_item(11, 0, 22)
	_choose(rules, card.key)
	check(card in rules.game.hands[0] and rules.game.discards[0].is_empty(), "Телефон возвращает выбранный экземпляр из сброса")
	rules.clear_choices()
	rules = _item_rules(25)
	hand = rules.game.decks[0].size()
	rules.use_battlefield_item(11, 0, 25)
	check(rules.game.discards[0].size() == 5 and rules.game.hands[0].size() == 3
		and rules.game.decks[0].size() == hand - 3, "Документы сначала сбрасывают всю руку и добирают три карты")
	rules.clear_choices()
	rules = _item_rules(24)
	rules.use_battlefield_item(11, 0, 24)
	var target: int = rules.effect_view(11).options.back()
	_choose(rules, target)
	check(rules.game.fighters[0][0].space == target and rules.game.fighters[0][0].walk.is_empty(), "Ранец помещает бойца без прохождения промежуточных клеток")
	rules.clear_choices()
	rules = _item_rules(15)
	rules.use_battlefield_item(11, 0, 15)
	_choose(rules, null)
	check(rules.actions_left == 2, "Шары дают дополнительное действие даже при отказе от перемещения")
	rules.clear_choices()
	rules = _item_rules(9)
	rules.use_battlefield_item(11, 0, 9)
	for i in 4:
		var place: int = rules.choosing_seat()
		_choose(rules, rules.game.hands[place][0].key)
	check(rules.game.discards[0].size() == 2 and rules.game.discards[1].size() == 2, "Генератор ЭМИ сбрасывает две выбранные карты каждой руки")
	rules.clear_choices()
	rules = _item_rules(5)
	rules.use_battlefield_item(11, 0, 5)
	card = rules.game.hands[0][-1]
	_choose(rules, card.key)
	check(rules.game.hands[0].size() == 7 and rules.game.decks[0][0] == card, "Газета добирает три и кладёт выбранную карту под колоду")
	rules.clear_choices()
	rules = _item_rules(26)
	rules.use_battlefield_item(11, 0, 26)
	check(rules.effect_view(11).get("labels", {}).get(1) == "Кровавая Мэри", "Выбор противника содержит имя героя")
	_choose(rules, 1)
	check(rules.effect_view(11).shown.size() == 5 and rules.effect_view(12).is_empty(), "Камера показывает чужую руку только применившему предмет")
	_choose(rules, "confirm")
	check(rules.game.hands[0].size() == 6, "После просмотра камеры взята одна карта")
	rules.clear_choices()
	rules = _item_rules(30)
	var top: Array = rules.game.decks[1].slice(-3)
	rules.use_battlefield_item(11, 0, 30)
	_choose(rules, 1)
	for selected: Dictionary in top:
		check(rules.effect_view(12).is_empty(), "Чужой порядок колоды остаётся закрыт от её владельца")
		_choose(rules, selected.key)
	check(rules.game.decks[1][-1] == top[0] and rules.game.decks[1][-3] == top[2], "Зазум возвращает выбранную последовательность сверху")
	rules.clear_choices()
	for id: int in [7, 17]:
		rules = _item_rules(id)
		rules.game.fighters[0][0].space = 4
		rules.game.fighters[0][1].space = 3
		rules.game.fighters[1][0].space = 5
		rules.battlefield_items[0].cell = 4
		rules.use_battlefield_item(11, 0, id)
		if id == 17:
			_choose(rules, Vector2i(1, 0))
		check(rules.game.fighters[1][0].health == (15 if id == 7 else 14), "Предмет %d нанёс урон противнику" % id)
		if id == 7:
			check(rules.game.fighters[0][0].health == 12 and rules.game.fighters[0][1].health == 0,
				"Электрифицированный пол повреждает также своих бойцов в зоне")
		rules.clear_choices()
	rules = _item_rules(4)
	game = rules.game
	var scheme: Dictionary = Catalog.deck_for("robin_hood", 0)[3]
	game.decks[0] = [scheme]
	game.hands[1] = []
	rules.use_battlefield_item(11, 0, 4)
	_choose(rules, scheme.key)
	_choose(rules, Vector2i(0, 0))
	_choose(rules, 1)
	check(rules.actions_left == 1 and rules._action_count == 1 and scheme in game.discards[0]
		and rules.phase == Rules.Phase.ACTION, "Жаровня разыгрывает приём без расхода второго действия")
	rules.clear_choices()
	rules = _item_rules(1)
	rules.use_battlefield_item(11, 0, 1)
	var request: Dictionary = rules.effect_view(11)
	check(request.options.any(func(target: Vector2i) -> bool: return target.x == 1), "Астральное кольцо разрешает двигать также противника")
	_choose(rules, null)
	check(rules.actions_left == 1, "Перемещения кольца можно пропустить")
	rules.clear_choices()


func _item_combat() -> void:
	for cancel: bool in [false, true]:
		var rules := _item_rules(10)
		var game: RefCounted = rules.game
		game.fighters[0][0].space = 4
		game.fighters[1][0].space = 5
		rules.battlefield_items[0].cell = 4
		var card: Dictionary = Catalog.deck_for("robin_hood", 0)[0]
		game.hands[0] = [card]
		game.hands[1] = [Catalog.deck_for("bloody_mary", 1)[9]] if cancel else []
		check(rules.begin_attack(11, 0, 1, 0, card.key), "Атака с доступным боевым предметом")
		check(rules.attack_view(12).get("choice", {}).is_empty(), "Предмет атакующего выбирается до решения защитника")
		_choose(rules, "use")
		var request: Dictionary = rules.attack_view(12).choice
		rules.choose_combat_card(12, {"request": request.id, "hand": 1,
			"cards": [game.hands[1][0].key] if cancel else []})
		check(rules.resolve_combat() and rules.last_combat.attack_value == (5 if cancel else 7),
			"Боевой предмет %s" % ("отменяется Уловкой" if cancel else "усиливает значение карты"))
		check(rules.used_items.size() == 1 and rules.battlefield_items.is_empty(), "Боевой предмет потрачен даже при отмене")
		rules.clear_choices()
	for first: bool in [true, false]:
		var rules := _item_rules(10)
		var game: RefCounted = rules.game
		game.fighters[0][0].space = 4
		game.fighters[1][0].space = 5
		rules.battlefield_items[0].cell = 4
		var card: Dictionary = Catalog.deck_for("bigfoot", 0)[24]
		game.hands[0] = [card]
		game.hands[1] = []
		rules._turn_spaces[Vector2i(0, 0)] = 3
		rules.begin_attack(11, 0, 1, 0, card.key)
		_choose(rules, "use")
		_choose(rules, "item_first" if first else "item_last")
		var request: Dictionary = rules.attack_view(12).choice
		rules.choose_combat_card(12, {"request": request.id, "hand": 1, "cards": []})
		check(rules.resolve_combat() and rules.last_combat.attack_value == (5 if first else 7),
			"Порядок предмета и замены значения карты влияет на результат")
		rules.clear_choices()
	var rules := _item_rules(20)
	var game: RefCounted = rules.game
	game.fighters[0][0].space = 4
	game.fighters[1][0].space = 30
	rules.battlefield_items[0].cell = 4
	rules.use_battlefield_item(11, 0, 20)
	check(rules.attack_in_range(Vector2i(0, 0), 30) and not rules.attack_in_range(Vector2i(0, 1), 30),
		"Карта местности даёт дальность только применившему её бойцу")
	var card: Dictionary = Catalog.deck_for("robin_hood", 0)[0]
	game.hands[0] = [card]
	check(rules.begin_attack(11, 0, 1, 0, card.key) and rules._map_target == Vector2i(-1, -1),
		"Дальность карты местности расходуется следующей атакой")
	rules.clear_choices()


func _danger() -> void:
	var rules := _new_rules("pandemonium")
	var game: RefCounted = rules.game
	game.fighters[0][0].space = 4
	game.fighters[1][0].space = 15
	check(rules.begin_maneuver(11) and rules.move_in_maneuver(11, 0, 5), "Боец пересёк опасный путь")
	rules._run_effects()
	check(game.fighters[0][0].health == 12 and game.fighters[0][0].space == 5, "Опасный путь наносит один урон на пути движения")
	check(rules.move_in_maneuver(11, 0, 4), "Боец пересёк опасный путь обратно")
	rules._run_effects()
	check(game.fighters[0][0].health == 12, "Повторное пересечение в том же ходу не наносит урон")
	rules.clear_choices()
	game.fighters[0][1].space = 4
	game.fighters[0][0].space = 3
	rules._offer_move(Vector2i(0, 1), 0, Vector2i(-1, -1), {"distance": 2})
	_choose(rules, 5)
	check(game.fighters[0][1].space == -1 and game.fighters[0][1].health == 0,
		"Разбойник с одним здоровьем погибает при пересечении и прекращает движение")
	rules.clear_choices()
	rules._door_fighter = 1
	check(not rules._maneuver_in_transit(), "Поверженный боец не блокирует окончание манёвра как проходящий через союзника")


func _owners() -> void:
	for owner in 3:
		var controllers: PackedInt32Array = Match.controllers_for(3, owner)
		check(controllers.count(owner) == 2 and controllers[1] == owner and controllers[3] == owner,
			"Участник %d управляет двумя героями одной команды" % owner)
		var match_game: RefCounted = Match.create("marmoreal", ["robin_hood", "bigfoot", "pandora", "loki"],
			[{"name": "А"}, {"name": "Б"}, {"name": "В"}], 18, "free", owner)
		check(match_game != null and match_game.game.controllers == controllers, "Владелец двух героев применяется при создании партии")
		if match_game != null:
			match_game.close()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		errors += 1
		push_error(message)
