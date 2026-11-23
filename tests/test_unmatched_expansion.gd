extends SceneTree
## Адресные проверки шести героев Unmatched по русским карточкам и правилам.

const Setup := preload("res://games/unmatched/logic/um_setup.gd")
const Rules := preload("res://games/unmatched/logic/um_rules.gd")
const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")
const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Match := preload("res://games/unmatched/logic/um_match.gd")

var checks := 0
var errors := 0
var active_rules: Array[RefCounted] = []


func _initialize() -> void:
	_roster()
	_dracula()
	_sherlock()
	_invisible()
	_constant_boost()
	_jekyll()
	_genie()
	_houdini()
	_arena_items()
	for rules: RefCounted in active_rules:
		rules.clear_choices()
	active_rules.clear()
	print("Unmatched, новые герои: %d проверок, %d ошибок." % [checks, errors])
	quit(int(errors > 0))


func _game(heroes: PackedStringArray, controllers: PackedInt32Array = [11, 12], arena: String = "marmoreal") -> RefCounted:
	var rng := RandomNumberGenerator.new()
	rng.seed = 725
	return Setup.create(arena, heroes, controllers, rng)


func _place_all(game: RefCounted) -> void:
	for step in 12:
		var pending: Dictionary = game.pending()
		if pending.is_empty():
			return
		if pending.get("choose_size", false):
			game.choose_size(game.controllers[pending.seat], true)
		else:
			if pending.cells.is_empty():
				break
			game.place(game.controllers[pending.seat], pending.cells[0])
	check(false, "Расстановка завершилась")


func _rules(heroes: PackedStringArray) -> RefCounted:
	var game := _game(heroes)
	_place_all(game)
	return _start(game)


func _start(game: RefCounted) -> RefCounted:
	var rules := Rules.new(game)
	active_rules.append(rules)
	return rules


func _cards(rules: RefCounted, place: int, numbers: Array) -> void:
	var deck := Catalog.deck_for(rules.game.heroes[place], place)
	var wanted: Array = numbers.map(func(number: int) -> String: return "%d:%02d" % [place, number])
	rules.game.hands[place] = deck.filter(func(card: Dictionary) -> bool: return card.key in wanted)
	rules.game.decks[place] = deck.filter(func(card: Dictionary) -> bool: return card.key not in wanted)


func _choose(rules: RefCounted, viewer: int, answer: Variant) -> void:
	var request: Dictionary = rules.effect_view(viewer)
	check(not request.is_empty(), "Игрок %d получил запрос перед ответом %s" % [viewer, str(answer)])
	if not request.is_empty():
		check(rules.choose_effect(viewer, request.id, answer), "Игрок %d применил ответ %s" % [viewer, str(answer)])


func _pick(rules: RefCounted, viewer: int, pass_optional: bool = false) -> void:
	var request: Dictionary = rules.effect_view(viewer)
	if request.is_empty():
		check(false, "Доступен запрос эффекта")
		return
	var options: Array = request.get("options", [])
	_choose(rules, viewer, null if (pass_optional and request.optional) or options.is_empty() else options[0])


func _attack(rules: RefCounted, attacker: int, defender: int, attack_key: String, defense_key: String,
		attacker_fighter: int = 0, defender_fighter: int = 0) -> bool:
	var attack_viewer: int = rules.game.controllers[attacker]
	var defense_viewer: int = rules.game.controllers[defender]
	var began: bool = rules.begin_attack(attack_viewer, attacker_fighter, defender, defender_fighter, attack_key)
	check(began, "Начата атака %s" % attack_key)
	if not began:
		return false
	var request: Dictionary = rules.attack_view(defense_viewer).get("choice", {})
	if request.is_empty():
		check(false, "Доступен запрос защиты")
		return false
	var chosen: bool = rules.choose_combat_card(defense_viewer, {"request": request.id, "hand": defender,
		"cards": [] if defense_key.is_empty() else [defense_key]})
	check(chosen, "Выбрана защита %s" % defense_key)
	return chosen


func _roster() -> void:
	var expected := {
		"dracula": [13, 2, false, 3, 1, false],
		"sherlock": [16, 2, false, 1, 8, true],
		"invisible_man": [15, 2, false, 0],
		"jekyll_hyde": [16, 2, false, 0],
		"genie": [16, 3, true, 0],
		"houdini": [14, 2, false, 1, 5, false],
	}
	for hero: String in expected:
		var cards := Catalog.deck_for(hero, 0)
		var unique := {}
		for card: Dictionary in cards:
			unique[card.key] = true
		check(cards.size() == 30 and unique.size() == 30, "У %s 30 отдельных физических карт" % hero)
		var group: Array = _game([hero, "bloody_mary"]).fighters[0]
		var stats: Array = expected[hero]
		check(group[0].health == stats[0] and Roster.HEROES[hero].move == stats[1]
			and group[0].ranged == stats[2] and group.size() == stats[3] + 1,
			"У %s совпадают здоровье, движение, тип атаки и число помощников" % hero)
		for helper: Dictionary in group.slice(1):
			check(helper.health == stats[4] and helper.ranged == stats[5], "Верные параметры помощника %s" % helper.id)


func _dracula() -> void:
	var rules := _rules(["dracula", "bloody_mary"])
	var game: RefCounted = rules.game
	game.fighters[0][0].space = 13
	game.fighters[1][0].space = 7
	var hand_size: int = game.hands[0].size()
	rules.start_turn()
	_choose(rules, 11, Vector2i(1, 0))
	check(game.fighters[1][0].health == 15 and game.hands[0].size() == hand_size + 1
		and rules.actions_left == 2, "Укус Дракулы до действия ранит соседа и даёт добор")
	rules.start_turn()
	check(rules.effect_view(11).is_empty() and game.hands[0].size() == hand_size + 1,
		"Укус доступен один раз в начале хода")

	rules = _rules(["dracula", "bloody_mary"])
	game = rules.game
	_cards(rules, 0, [14, 23])
	game.fighters[0][0].space = 13
	game.fighters[1][0].space = 0
	game.fighters[0][0].health = 9
	game.fighters[0][1].health = 0
	game.fighters[0][1].space = -1
	check(not rules.play_scheme(11, 1, "0:23") and rules.play_scheme(11, 0, "0:23"),
		"Крещение разыгрывает только Дракула")
	_pick(rules, 11)
	check(game.fighters[0][0].health == 11 and game.fighters[0][1].health == 1
		and game.board.same_zone(game.fighters[0][1].space, 13), "Крещение лечит Дракулу и возвращает Сестру в его зону")
	var sister_card: Dictionary = Catalog.deck_for("dracula", 0)[13]
	check(Catalog.can_play(sister_card, Catalog.Kind.ATTACK, false)
		and not Catalog.can_play(sister_card, Catalog.Kind.ATTACK, true), "Жажда крови принадлежит Сёстрам")

	rules = _rules(["bloody_mary", "dracula"])
	game = rules.game
	_cards(rules, 0, [1, 7, 24])
	_cards(rules, 1, [21])
	game.fighters[0][0].space = 13
	game.fighters[1][0].space = 7
	if _attack(rules, 0, 1, "0:07", "1:21"):
		check(rules.resolve_combat(), "Начато разрешение боя с приказом Дракулы")
		var reveal: Dictionary = rules.effect_view(11)
		if not reveal.is_empty():
			_pick(rules, 11)
		var order: Dictionary = rules.effect_view(12)
		check("0:07" in order.get("options", []) and "0:01" in order.get("options", [])
			and "0:24" not in order.get("options", []), "Дракула может оставить исходную атаку или выбрать другую, но не защиту")
		check(rules.effect_view(11).is_empty(), "Выбор замены атаки доступен только Дракуле")
		if "0:01" in order.get("options", []):
			_choose(rules, 12, "0:01")
			if not rules.effect_view(11).is_empty():
				_pick(rules, 11, true)
			check(rules.last_combat.get("attack", {}).get("key") == "0:01"
				and game.hands[0].any(func(card: Dictionary) -> bool: return card.key == "0:07"),
				"Новая карта разрешается в бою, заменённая остаётся в руке")

	rules = _rules(["houdini", "dracula"])
	game = rules.game
	_cards(rules, 0, [1, 3])
	_cards(rules, 1, [19, 21, 23])
	game.fighters[0][0].space = 13
	game.fighters[1][0].space = 7
	if _attack(rules, 0, 1, "0:01", "1:21"):
		check(rules.resolve_combat(), "Приказ Дракулы разрешается до немедленного эффекта атаки")
		_choose(rules, 12, "0:03")
		check("1:19" in rules.effect_view(12).get("options", []), "Новая Иллюзия предлагает Дракуле усилить защиту")
		_choose(rules, 12, "1:19")
		check(rules.effect_view(12).is_empty() and not rules.effect_view(11).is_empty(),
			"Немедленное усиление защиты не повторяется перед усилением атаки")
		_choose(rules, 11, null)
		check(rules.last_combat.get("defense_value") == 5 and rules.last_combat.get("attack_value") == 4,
			"После замены применяется только одно усиление защиты")

	for starts_canceled: bool in [true, false]:
		rules = _rules(["invisible_man", "dracula"])
		game = rules.game
		_cards(rules, 0, [24, 29])
		_cards(rules, 1, [21])
		game.fog.assign([1, 2, 3])
		game.fighters[0][0].space = 13
		game.fighters[1][0].space = 7
		var original := "0:29" if starts_canceled else "0:24"
		var replacement := "0:24" if starts_canceled else "0:29"
		if _attack(rules, 0, 1, original, "1:21"):
			check(rules.resolve_combat(), "Приказ Дракулы разрешается даже против отменяющей атаки")
			_choose(rules, 12, replacement)
			check(rules.last_combat.get("defense_canceled") == not starts_canceled,
				"Отмена защиты зависит от новой карты атаки")


func _sherlock() -> void:
	var game := _game(["bloody_mary", "sherlock"], [0, 1])
	_place_all(game)
	var session := Match.new("marmoreal", game, [{"name": "А"}, {"name": "Б"}])
	var rules: RefCounted = session.rules
	active_rules.append(rules)
	_cards(rules, 0, [10])
	_cards(rules, 1, [22])
	rules.game.fighters[0][0].space = 13
	rules.game.fighters[1][0].space = 7
	if _attack(rules, 0, 1, "0:10", "1:22"):
		for viewer: int in [-1, 0, 1]:
			var view: Dictionary = session.get_view(viewer)
			check(view.combat.get("defense", {}).get("key") == "1:22",
				"Холмс открывает Элементарно сразу всем участникам и зрителю")
			check(view.combat.get("attack", {}) == {"sealed": true} and view.effect.is_empty() == (viewer != 1),
				"Атака закрыта, выбор числа доступен только Холмсу")
		_choose(rules, 1, 2)
		check(rules.resolve_combat(), "Бой разрешается после предсказания")
		check(not rules.last_combat.get("defense_canceled", true) and rules.last_combat.get("attack_canceled", false)
			and rules.last_combat.get("damage", -1) == 0,
			"Уловка не отменяет Холмса, верное предсказание отменяет атаку и игнорирует её значение")

	rules = _rules(["sherlock", "bloody_mary"])
	_cards(rules, 0, [14])
	rules.game.fighters[0][0].space = 13
	rules.game.fighters[1][0].space = 7
	check(rules.play_scheme(11, 0, "0:14"), "Разыгран Мастер маскировки")
	_choose(rules, 11, Vector2i(1, 0))
	check(rules.game.fighters[0][0].space == 7 and rules.game.fighters[1][0].space == 13
		and rules.game.fighters[1][0].health == 15, "Маскировка меняет героев местами и ранит цель")


func _invisible() -> void:
	var game := _game(["invisible_man", "bloody_mary"])
	for i in 3:
		var request: Dictionary = game.pending()
		check(request.get("fog", false) and not request.get("cells", []).is_empty(),
			"Предложен туман №%d до начала партии" % (i + 1))
		if request.get("cells", []).is_empty():
			return
		var cell: int = request.cells[0]
		check(not game.place(12, cell) and game.place(11, cell), "Туман ставит только владелец Невидимки")
	check(game.fog.size() == 3 and game.fog[0] != game.fog[1] and game.fog[1] != game.fog[2]
		and game.fog[0] != game.fog[2], "В расстановке три разных клетки тумана")
	_place_all(game)

	var rules := _start(game)
	game.fog.assign([13, 14, 25])
	game.fighters[0][0].space = 13
	game.fighters[1][0].space = 0
	check(not rules.attack_in_range(Vector2i(0, 0), 25), "Туман не делает дальнюю клетку смежной для атаки")
	check(rules.begin_maneuver(11) and 25 in rules.maneuver_cells(11, 0) and rules.move_in_maneuver(11, 0, 25),
		"Невидимка достигает далёкого тумана одним из шагов манёвра")

	rules = _rules(["bloody_mary", "invisible_man"])
	game = rules.game
	_cards(rules, 0, [5])
	_cards(rules, 1, [8])
	game.fog.assign([7, 14, 25])
	game.fighters[0][0].space = 13
	game.fighters[1][0].space = 7
	if _attack(rules, 0, 1, "0:05", "1:08"):
		check(rules.resolve_combat(), "Бой в тумане разрешён")
		check(rules.last_combat.get("defense_value") == 5, "Невидимка получает +1 к защите в тумане")

	rules = _rules(["invisible_man", "bloody_mary"])
	game = rules.game
	_cards(rules, 0, [14])
	game.fighters[0][0].health = 12
	check(rules.play_scheme(11, 0, "0:14") and game.fighters[0][0].health == 13
		and game.fighters[0][0].space == -1 and rules.seat == 1 and rules.winner < 0,
		"Исчезновение лечит, убирает фишку и завершает ход без поражения")
	for i in 2:
		check(rules.begin_maneuver(12) and rules.end_maneuver(12), "Противник завершил действие")
	var returning: Dictionary = rules.effect_view(11)
	check(rules.seat == 0 and returning.get("cells", false) and not returning.get("options", []).is_empty(),
		"В начале следующего хода Невидимка получает выбор места")
	if not returning.get("options", []).is_empty():
		var destination: int = returning.options[0]
		_choose(rules, 11, destination)
		check(game.fighters[0][0].space == destination and rules.actions_left == 2,
			"Возвращение не тратит действие")
		game.decks[0].clear()
		check(rules.begin_maneuver(11) and rules.end_maneuver(11)
			and game.fighters[0][0].health == 11, "После возвращения обязательный добор из пустой колоды наносит 2 урона")


func _constant_boost() -> void:
	for scenario: Array in [[true, false, 3, 3, 0], [false, false, 3, 2, 1], [false, true, 6, 2, 4]]:
		var fog: bool = scenario[0]
		var cancel: bool = scenario[1]
		var rules := _rules(["arthur", "bloody_mary" if cancel else "invisible_man"])
		var game: RefCounted = rules.game
		var defense_key := "1:10" if cancel else "1:20"
		_cards(rules, 0, [1, 28])
		_cards(rules, 1, [10] if cancel else [20])
		game.fighters[0][0].space = 13
		game.fighters[1][0].space = 7
		game.fog.assign([7, 14, 25] if fog else [1, 14, 25])
		check(rules.begin_attack(11, 0, 1, 0, "0:01"), "Артур начал атаку Экскалибуром")
		_choose(rules, 11, "0:28")
		var request: Dictionary = rules.attack_view(12).get("choice", {})
		check(not request.is_empty(), "После усиления доступна защита")
		if request.is_empty():
			continue
		check(rules.choose_combat_card(12, {"request": request.id, "hand": 1, "cards": [defense_key]}),
			"Выбрана защита от усиленной атаки")
		check(rules.resolve_combat(), "Бой с усиленной атакой разрешён")
		var result: Dictionary = rules.last_combat
		check(result.get("attack_value") == scenario[2] and result.get("defense_value") == scenario[3]
			and result.get("damage") == scenario[4] and result.get("attack_canceled") == cancel,
			"Значения и урон учитывают постоянное усиление: туман %s, отмена %s" % [fog, cancel])
		check(game.discards[0].any(func(card: Dictionary) -> bool: return card.key == "0:28"),
			"Карта усиления сброшена даже при отмене")


func _jekyll() -> void:
	var rules := _rules(["jekyll_hyde", "bloody_mary"])
	_cards(rules, 0, [9, 12, 23])
	rules.start_turn()
	_choose(rules, 11, "hyde")
	check(not rules.play_scheme(11, 0, "0:23"), "Хайд не может разыграть исследования Джекилла")
	check(rules.begin_maneuver(11) and rules.end_maneuver(11)
		and rules.game.fighters[0][0].health == 15, "Хайд теряет 1 ОЗ даже при манёвре без движения")
	check(rules.begin_maneuver(11) and rules.end_maneuver(11), "Второй манёвр Хайда завершён")
	for i in 2:
		check(rules.begin_maneuver(12) and rules.end_maneuver(12), "Противник завершил действие")
	_choose(rules, 11, "jekyll")
	check(not rules.play_scheme(11, 0, "0:09"), "Джекилл не может разыграть Чистое зло Хайда")
	check(rules.begin_maneuver(11) and rules.end_maneuver(11)
		and rules.game.fighters[0][0].health == 14, "Манёвр Джекилла не ранит героя")


func _genie() -> void:
	for wish: String in ["wish_draw", "wish_four", "wish_discard"]:
		var rules := _rules(["genie", "bloody_mary"])
		var game: RefCounted = rules.game
		_cards(rules, 0, [1, 3, 13, 19, 28])
		_cards(rules, 1, [1, 5, 10, 24])
		rules.start_turn()
		_choose(rules, 11, "0:01")
		check(rules.actions_left == 3 and game.discards[0].size() == 1,
			"Сброс Джинна в начале хода даёт одно действие")
		var before: int = game.hands[0].size()
		check(rules.play_scheme(11, 0, "0:13"), "Разыграны Три желания")
		_choose(rules, 11, wish)
		if wish == "wish_discard":
			_choose(rules, 12, "1:01")
			_choose(rules, 12, "1:10")
			check(game.hands[1].size() == 2, "Желание вынуждает противника сбросить ровно две карты")
		check(rules.actions_left == 3, "Три желания возвращают потраченное действие")
		if wish == "wish_draw":
			check(game.hands[0].size() == before + 4, "Добор даёт ровно пять карт после розыгрыша")
		elif wish == "wish_four":
			game.fighters[0][0].space = 13
			game.fighters[1][0].space = 7
			if _attack(rules, 0, 1, "0:19", "1:24"):
				check(rules.resolve_combat() and rules.last_combat.get("attack_value") == 4,
					"Печатная атака 3 становится 4 в ход желания")
			for i in 2:
				check(rules.begin_maneuver(11) and rules.end_maneuver(11), "Джинн завершил действие")
			if _attack(rules, 1, 0, "1:05", "0:03"):
				check(rules.resolve_combat() and rules.last_combat.get("defense_value") == 1,
					"На чужом ходу защита Джинна снова равна напечатанной единице")


func _houdini() -> void:
	var deck := Catalog.deck_for("houdini", 0)
	check(Catalog.can_play(deck[6], Catalog.Kind.SCHEME, false)
		and not Catalog.can_play(deck[6], Catalog.Kind.SCHEME, true), "Подготовить сцену может только Бесс")
	check(Catalog.can_play(deck[8], Catalog.Kind.DEFENSE, false)
		and not Catalog.can_play(deck[8], Catalog.Kind.DEFENSE, true), "Прекрасную Бесс в бой берёт только Бесс")
	check(Catalog.can_play(deck[14], Catalog.Kind.ATTACK, false)
		and Catalog.can_play(deck[14], Catalog.Kind.ATTACK, true), "Очередной трюк могут разыграть оба бойца")

	var rules := _rules(["houdini", "bloody_mary"])
	var game: RefCounted = rules.game
	_cards(rules, 0, [5, 9])
	game.fighters[0][0].health = 10
	game.fighters[0][0].space = 13
	game.fighters[1][0].space = 7
	check(rules.begin_maneuver(11) and rules.boost_maneuver(11, "0:05"), "Гудини усилил манёвр")
	var placement: Dictionary = rules.effect_view(11)
	check(game.fighters[0][0].health == 12, "Усиление картой Вся часть представления лечит Гудини на 2")
	check(25 in placement.get("options", []) and 7 not in placement.get("options", []),
		"Мастер побега предлагает дальнюю свободную клетку и исключает занятую")
	if 25 in placement.get("options", []):
		_choose(rules, 11, 25)
		check(game.fighters[0][0].space == 25 and rules.maneuver_cells(11, 0).is_empty()
			and rules.end_maneuver(11), "Телепортация заменяет движение Гудини во время манёвра")
		check(rules.begin_maneuver(11), "Начинается следующий манёвр Гудини")
		var before: int = game.decks[0].size()
		check(rules.boost_maneuver(11, "0:09") and game.decks[0].size() == before,
			"Следующий манёвр можно усилить Прекрасной Бесс")
		_pick(rules, 11, true)
		check(rules.end_maneuver(11) and rules.actions_left == 1,
			"Напечатанное усиление Прекрасной Бесс даёт дополнительное действие")

	for defender_fighter in [0, 1]:
		rules = _rules(["bloody_mary", "houdini"])
		game = rules.game
		_cards(rules, 0, [7])
		_cards(rules, 1, [5])
		game.fighters[0][0].space = 13
		game.fighters[1][defender_fighter].space = 7
		game.fighters[1][defender_fighter].health = 1
		if _attack(rules, 0, 1, "0:07", "1:05", 0, defender_fighter):
			check(rules.resolve_combat(), "Разрешён бой с частью представления")
			var revive: Dictionary = rules.effect_view(12)
			check(revive.get("cells", false) and game.fighters[1][defender_fighter].health == 4,
				"Часть представления возвращает Гудини или Бесс с четырьмя ОЗ")
			if revive.get("cells", false):
				var cell: int = revive.options[0]
				_choose(rules, 12, cell)
				check(game.fighters[1][defender_fighter].space == cell and rules.winner < 0,
					"Возвращение на поле завершилось до проверки победы")

	for reveal: bool in [true, false]:
		rules = _rules(["sherlock", "houdini"])
		game = rules.game
		_cards(rules, 0, [27])
		_cards(rules, 1, [9, 26])
		check(rules.play_scheme(11, 0, "0:27"), "Холмс начинает просмотр чужой руки")
		_choose(rules, 11, 1)
		check(rules.effect_view(11).is_empty() and rules.effect_view(12).get("options") == ["reveal"],
			"Чужая рука скрыта, пока Гудини может показать секрет")
		_choose(rules, 12, "reveal" if reveal else null)
		if reveal:
			check(rules.effect_view(11).is_empty() and game.hands[1].size() == 2,
				"Показ секрета отменяет просмотр и сброс, обе карты остаются в руке")
			check(rules.public_card_notice.get("card", {}).get("key") == "1:26",
				"Открыт секрет, остальные карты не опубликованы")
		else:
			var request: Dictionary = rules.effect_view(11)
			check("1:09" in request.get("options", []), "Холмс может сбросить увиденную карту Бесс")
			if "1:09" in request.get("options", []):
				var before: int = game.decks[1].size()
				_choose(rules, 11, "1:09")
				check(game.hands[1].size() == 2 and game.decks[1].size() == before - 1
					and game.discards[1].back().key == "1:09", "Сброшенная противником Бесс даёт владельцу карту")

	rules = _rules(["sinbad", "houdini"])
	game = rules.game
	_cards(rules, 0, [20])
	_cards(rules, 1, [9])
	game.fighters[0][0].space = 13
	game.fighters[1][0].space = 7
	if _attack(rules, 0, 1, "0:20", ""):
		var before: int = game.decks[1].size()
		check(rules.resolve_combat() and game.hands[1].size() == 1 and game.decks[1].size() == before - 1
			and game.discards[1].back().key == "1:09", "Случайный сброс противником тоже даёт карту за Бесс")

	rules = _rules(["houdini", "bloody_mary"])
	game = rules.game
	_cards(rules, 0, [1, 2, 3, 4, 5, 9])
	for i in 2:
		check(rules.begin_maneuver(11) and rules.end_maneuver(11), "Гудини добирает картой манёвра")
	var before: int = game.decks[0].size()
	check(rules.discard_to_limit(11, "0:09") and game.hands[0].size() == 7
		and game.decks[0].size() == before, "Свой сброс Бесс до лимита не даёт добора")


func _arena_item_rules(heroes: PackedStringArray, id: int) -> RefCounted:
	var game := _game(heroes, [11, 12], "hell_s_kitchen")
	_place_all(game)
	var rules := _start(game)
	rules.battlefield_items.clear()
	rules.battlefield_items.append({"id": id, "cell": game.fighters[0][0].space, "at": Vector2(0.5, 0.5)})
	return rules


func _arena_items() -> void:
	for secret: bool in [true, false]:
		var rules := _arena_item_rules(["bloody_mary", "houdini"], 26)
		var game: RefCounted = rules.game
		_cards(rules, 0, [1, 2, 3])
		_cards(rules, 1, [9, 26] if secret else [9, 15])
		check(rules.use_battlefield_item(11, 0, 26), "Использована Камера")
		_choose(rules, 11, 1)
		var hand_count: int = game.hands[0].size()
		if secret:
			check(rules.effect_view(11).is_empty() and rules.effect_view(12).get("options") == ["reveal"],
				"Камера ещё не раскрыла руку, Гудини может показать секрет")
			_choose(rules, 12, "reveal")
			check(rules.effect_view(11).is_empty() and game.hands[0].size() == hand_count
				and rules.public_card_notice.get("card", {}).get("key") == "1:26",
				"Секрет отменяет просмотр и добор Камеры, публикуется только сам секрет")
		else:
			var request: Dictionary = rules.effect_view(11)
			check(request.get("shown", []).size() == 2 and rules.effect_view(12).is_empty(),
				"Камера показывает две карты только использовавшему предмет игроку")
			_choose(rules, 11, "confirm")
			check(game.hands[0].size() == hand_count + 1, "После просмотра Камера даёт одну карту")

	for houdini: int in [0, 1]:
		var rules := _arena_item_rules(["houdini", "bloody_mary"] if houdini == 0 else ["bloody_mary", "houdini"], 9)
		var game: RefCounted = rules.game
		_cards(rules, houdini, [9, 15, 23])
		_cards(rules, 1 - houdini, [1, 2, 3])
		var deck_count: int = game.decks[houdini].size()
		check(rules.use_battlefield_item(11, 0, 9), "Использован Генератор ЭМИ")
		for i in 4:
			var place: int = rules.choosing_seat()
			if place not in [0, 1]:
				check(false, "Генератор предложил все четыре сброса")
				break
			_pick(rules, game.controllers[place])
		check(game.discards[houdini].size() == 2 and game.discards[houdini][0].definition == "houdini:09",
			"Под ЭМИ сброшена Бесс и ещё одна карта")
		check(game.hands[houdini].size() == 1 + houdini and game.decks[houdini].size() == deck_count - houdini,
			"Бесс даёт карту только после сброса чужим ЭМИ")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		errors += 1
		push_error(message)
