extends SceneTree
## Первые проверки общих стопок и графа Unmatched: --headless --script res://tests/test_unmatched.gd.

const Board := preload("res://games/unmatched/logic/um_board.gd")
const Maps := preload("res://games/unmatched/logic/um_maps.gd")
const Piles := preload("res://hub/card_piles.gd")
const Reveal := preload("res://hub/card_reveal.gd")
const Choice := preload("res://hub/player_choice.gd")
const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")
const Setup := preload("res://games/unmatched/logic/um_setup.gd")
const Rules := preload("res://games/unmatched/logic/um_rules.gd")
const Effects := preload("res://games/unmatched/logic/um_effects.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	var deck := [1, 2, 3]
	var hand := [1, 3]
	var discard: Array = []
	check(Piles.draw(deck, hand) and deck == [1, 2] and hand == [1, 3, 3], "Добор с вершины")
	check(Piles.discard(hand, 1, discard) and hand == [1, 3] and discard == [3], "Сброс выбранного экземпляра")
	check(not Piles.draw([], hand) and hand == [1, 3], "Пустой добор не меняет руку")
	check(not Piles.transfer(deck, 0, discard, 2) and deck == [1, 2], "Неверная цель не двигает карту")
	check(Piles.transfer(deck, 1, deck, 0) and deck == [2, 1], "Перенос на дно той же стопки")
	check_common_actions()

	var spaces: Array[Dictionary] = [{"zones": ["a"]}, {"zones": ["a", "b"]}, {"zones": ["b"]}, {"zones": ["a"]}]
	var links: Array[PackedInt32Array] = [PackedInt32Array([1]), PackedInt32Array([0, 2]), PackedInt32Array([1, 3]), PackedInt32Array([2])]
	var board := Board.new(spaces, links, PackedInt32Array([0, 3]), [Vector2i(1, 2)])
	check(board.valid() and board.start_for(1) == 3 and board.start_for(2) == -1, "Стартовые клетки дуэли")
	check(board.reachable(0, 3, 0, {1: 0}) == PackedInt32Array([2, 3]), "Проход через союзника без остановки на нём")
	check(board.route(0, 3, 3, 0, {1: 0}) == PackedInt32Array([0, 1, 2, 3]), "Анимация получает каждую клетку хостового маршрута")
	check(board.route(0, 3, 3, 0, {1: 1}).is_empty(), "Маршрут не пересекает заблокированный проход")
	check(board.reachable(0, 3, 0, {1: 1}).is_empty(), "Противник преграждает путь")
	check(board.reachable(0, 2, 0, {1: 1}, true) == PackedInt32Array([2]), "Особый проход через противника")
	check(board.in_attack_range(0, 3, true) and not board.in_attack_range(0, 3, false), "Дальняя атака в зоне")
	check(board.in_attack_range(2, 3, true), "Дальняя атака по соседу из другой зоны")
	check(board.attack_bonus(1, 2) == 1 and board.attack_bonus(2, 1) == 0, "Возвышенность действует по стрелке")
	check_art()
	check_workshop_maps()
	check_catalog()
	check_setup()
	check_turn()
	check_combat()
	check_reported_cards()
	check_volume_three()
	check_heorot()
	check_bigfoot()
	check_follow_up()
	check_scheme()
	check_private_effects()
	check_archers()
	check_high_ground()
	check_maps()
	print("Unmatched: %d проверок, %d ошибок." % [checks, failures])
	quit(int(failures > 0))


func check_catalog() -> void:
	var definitions := {}
	var follow_ups := {}
	for hero: String in Roster.HEROES:
		var deck := Catalog.deck_for(hero, 2)
		check(deck.size() == 30, "Тридцать экземпляров %s" % hero)
		for index in deck.size():
			var card: Dictionary = deck[index]
			check(card.key == "2:%02d" % (index + 1) and FileAccess.file_exists(card.face),
				"Экземпляр %s %d связан с нужным изображением" % [hero, index + 1])
			check(card.hero == hero and not card.name.is_empty() and card.kind in [0, 1, 2, 3]
				and card.fighter in [0, 1, 2] and card.value >= 0 and card.boost >= -1,
				"Характеристики %s" % card.key)
			definitions[card.definition] = true
			if card.has("follow_up"):
				follow_ups[card.definition] = true
		check(Catalog.deck_for(hero, 3)[0].key != deck[0].key, "Ключ включает место")
	check(definitions.size() == 175 and follow_ups.size() == 4, "Уникальные записи и дополнительные атаки")
	for id: String in definitions:
		check(Effects.COMBAT.has(id) != Effects.SCHEMES.has(id), "Одно определение эффекта для %s" % id)
	check(Catalog.deck_for("unknown", 0).is_empty(), "Неизвестный герой не получает карты")
	check(Catalog.deck_for("sinbad", 0)[14].boost == -1 and Catalog.deck_for("sinbad", 0)[25].boost == 1,
		"Путешествия без напечатанного усиления и возвращение")
	var medusa := Catalog.deck_for("medusa", 0)
	check(Catalog.can_play(medusa[0], Catalog.Kind.ATTACK, true)
		and Catalog.can_play(medusa[0], Catalog.Kind.DEFENSE, false)
		and not Catalog.can_play(medusa[0], Catalog.Kind.SCHEME, false), "Универсальная карта подходит для атаки и защиты")
	check(Catalog.can_play(medusa[14], Catalog.Kind.DEFENSE, false)
		and not Catalog.can_play(medusa[14], Catalog.Kind.DEFENSE, true), "Карта Гарпии недоступна Медузе")


func check_setup() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var duel: RefCounted = Setup.create("marmoreal", ["alice", "sun_wukong"], [71, 82], rng)
	check(duel != null, "Дуэль между томами создаётся")
	if duel == null:
		return
	rng.seed = 31
	var replay: RefCounted = Setup.create("marmoreal", ["alice", "sun_wukong"], [71, 82], rng)
	check(duel.hands == replay.hands and duel.decks == replay.decks, "Раздача воспроизводится по seed хоста")
	check(duel.hands[0].size() == 5 and duel.decks[0].size() == 25 and duel.discards[0].is_empty(), "Стартовая раздача")
	var request: Dictionary = duel.pending()
	if not request.has("cells") or request.cells.is_empty():
		check(false, "У Бармаглота есть клетки расстановки")
		return
	var cell: int = request.cells[0]
	check(not duel.place(82, cell) and not duel.place(71, duel.board.start_for(1)), "Чужое место и старт соперника недопустимы")
	check(duel.place(71, cell) and duel.pending().has("choose_size"), "После Бармаглота выбирает Алиса")
	check(not duel.choose_size(82, true) and duel.choose_size(71, true) and duel.alice_large, "Только Алиса задаёт размер")
	check(Rules.new(duel).hero_status(0) == "Большая", "Размер Алисы готов для публичного отображения")
	check(duel.pending().is_empty() and duel.fighters[1][0].space == duel.board.start_for(1)
		and duel.fighters[1][1].space == -1, "Двойники остаются в запасе")
	check(Setup.create("sarpedon", ["medusa", "arthur"], [1, 1], rng) == null, "Нельзя управлять противниками")
	for arena: String in ["marmoreal", "sarpedon"]:
		for owners: Array in [[1, 2, 1, 3], [1, 2, 3, 4]]:
			var teams: RefCounted = Setup.create(arena, ["medusa", "arthur", "yennenga", "achilles"], PackedInt32Array(owners), rng)
			check(teams != null, "Командная партия с %d игроками" % (3 if owners[0] == owners[2] else 4))
			if teams == null:
				continue
			for expected_seat in [0, 0, 0, 1, 2, 2, 3]:
				var next: Dictionary = teams.pending()
				check(next.get("seat", -1) == expected_seat and not next.get("cells", []).is_empty(), "Расстановка помощников в порядке А–Б–А–Б")
				if next.get("cells", []).is_empty():
					break
				check(teams.place(owners[expected_seat], next.cells[0]), "Выбор контролирующего игрока принят")
			check(teams.pending().is_empty(), "Командная расстановка завершена")
	var narrow: RefCounted = Setup.create("sarpedon", ["achilles", "yennenga", "sinbad", "medusa"], [1, 2, 3, 4], rng)
	check(narrow.place(1, 16) and narrow.place(2, 20) and narrow.place(2, 26) and narrow.place(3, 1),
		"Предыдущая команда может занять общую зону при расстановке")
	check(narrow.place(4, 5) and narrow.place(4, 6) and not narrow.pending().cells.is_empty()
		and not narrow.board.same_zone(narrow.board.start_for(3), narrow.pending().cells[0]),
		"При заполнении зоны последний помощник ставится рядом с уже размещёнными")


func check_turn() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 18
	var setup: RefCounted = Setup.create("sarpedon", ["bloody_mary", "sun_wukong"], [11, 12], rng)
	var rules := Rules.new(setup)
	check(not rules.begin_maneuver(12) and rules.begin_maneuver(11), "Манёвр разрешён только активному контроллеру")
	check(setup.hands[0].size() == 6 and rules.actions_left == 1, "Обязательный добор и расход действия")
	var key: String = setup.hands[0][0].key
	check(rules.boost_maneuver(11, key) and not rules.boost_maneuver(11, setup.hands[0][0].key)
		and setup.discards[0][-1].key == key, "Единственное усиление переносит карту в открытый сброс")
	var cells := rules.maneuver_cells(11, 0)
	check(not cells.is_empty() and not rules.move_in_maneuver(11, 0, setup.board.start_for(1)), "Противник блокирует остановку")
	if not cells.is_empty():
		check(rules.move_in_maneuver(11, 0, cells[0]) and rules.maneuver_cells(11, 0).is_empty(), "Боец движется один раз за манёвр")
	check(rules.end_maneuver(11) and rules.phase == Rules.Phase.ACTION, "После первого действия можно начать второе")
	Piles.draw_many(setup.decks[0], setup.hands[0], 3)
	check(rules.begin_maneuver(11) and rules.end_maneuver(11)
		and rules.phase == Rules.Phase.DISCARD and rules.seat == 0, "Лишние карты блокируют передачу хода")
	while setup.hands[0].size() > Rules.HAND_LIMIT:
		if not rules.discard_to_limit(11, setup.hands[0][0].key):
			check(false, "Лишнюю карту можно сбросить")
			break
	check(rules.seat == 1 and rules.actions_left == 2, "После сброса ход получает соперник")
	var summon: Dictionary = rules.effect_view(12)
	check(not summon.is_empty() and rules.choose_effect(12, summon.id, null), "Сунь Укун может пропустить призыв")
	setup.decks[1].clear()
	setup.fighters[1][0].health = 2
	check(rules.begin_maneuver(12) and setup.fighters[1][0].space == -1
		and rules.phase == Rules.Phase.FINISHED and rules.winner == 0, "Истощение может завершить дуэль до движения")
	var voyage: RefCounted = Setup.create("marmoreal", ["sinbad", "bloody_mary"], [11, 12], rng)
	voyage.place(11, voyage.pending().cells[0])
	var sinbad := Rules.new(voyage)
	var cards := Catalog.deck_for("sinbad", 0)
	voyage.decks[0] = [cards[0]]
	voyage.hands[0] = [cards[14], cards[25]]
	voyage.discards[0] = [cards[15]]
	check(sinbad.begin_maneuver(11) and not sinbad.boost_maneuver(11, cards[14].key),
		"У обычного Путешествия нет значения усиления")
	check(sinbad.boost_maneuver(11, cards[25].key), "Путешествие домой можно сбросить для усиления")
	var spaces := {}
	for place in voyage.fighters.size():
		for figure: Dictionary in voyage.fighters[place]:
			spaces[figure.space] = place % 2
	check(sinbad.maneuver_cells(11, 0) == voyage.board.reachable(voyage.board.start_for(0), 5, 0, spaces),
		"Синдбад прибавляет усиление и оба Путешествия в сбросе")


func check_combat() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var setup: RefCounted = Setup.create("sarpedon", ["medusa", "arthur"], [11, 12], rng)
	while not setup.pending().is_empty():
		var request: Dictionary = setup.pending()
		if request.cells.is_empty() or not setup.place(setup.controllers[request.seat], request.cells[0]):
			check(false, "Расстановка для проверки боя")
			return
	# Смежные клетки с обеими фигурами, вне зон расстановки помощников.
	setup.fighters[0][0].space = 32
	setup.fighters[1][0].space = 33
	var medusa := Catalog.deck_for("medusa", 0)
	var arthur := Catalog.deck_for("arthur", 1)
	setup.hands[0] = [medusa[27], medusa[0], medusa[12]]
	setup.hands[1] = [arthur[4], arthur[1]]
	var rules := Rules.new(setup)
	check(not rules.begin_attack(12, 0, 1, 0) and not rules.begin_attack(11, 0, 1, -1)
		and not rules.begin_attack(11, 0, 0, 1), "Хост отклоняет чужую атаку и недопустимую цель")
	var start: Dictionary = rules.effect_view(11)
	if not start.is_empty():
		rules.choose_effect(11, start.id, null)
	check(rules.begin_attack(11, 0, 1, 0), "Смежная атака возможна")
	var request: Dictionary = rules.attack_view(11).get("choice", {})
	check(request.get("allowed", []) == [medusa[27].key, medusa[0].key] and not rules.attack_view(12).has("choice"),
		"Герой не может выбрать приём, чужой запрос скрыт")
	check(rules.choose_combat_card(11, {"request": request.id, "hand": 0, "cards": [medusa[27].key]}), "Атака запечатана")
	check(rules.attack_view(12).cards.is_empty() and not rules.resolve_combat(), "До ответа защиты обе карты закрыты")
	request = rules.attack_view(12).choice
	var answer := {"request": request.id, "hand": 1, "cards": [arthur[4].key]}
	check(not rules.choose_combat_card(11, answer) and rules.choose_combat_card(12, answer), "Защита принадлежит контроллеру цели")
	check(rules.attack_view(99).cards.attack.key == medusa[27].key and not rules.choose_combat_card(12, answer),
		"После выбора обе карты открыты, повторный ответ отклоняется")
	check(rules.resolve_combat() and rules.last_combat.attack_canceled and rules.last_combat.damage == 0
		and setup.fighters[1][0].health == 18, "Уловка отменяет эффект атаки, печатная защита блокирует урон")
	check(setup.discards[0][-1].key == medusa[27].key and setup.discards[1][-1].key == arthur[4].key
		and not rules.resolve_combat(), "Разыгранные карты сбрасываются ровно один раз")
	check(rules.begin_attack(11, 0, 1, 0), "Второе действие может быть атакой")
	request = rules.attack_view(11).choice
	rules.choose_combat_card(11, {"request": request.id, "hand": 0, "cards": [medusa[0].key]})
	request = rules.attack_view(12).choice
	rules.choose_combat_card(12, {"request": request.id, "hand": 1, "cards": []})
	check(rules.resolve_combat() and setup.fighters[1][0].health == 15 and setup.hands[0].size() == 2
		and rules.seat == 1, "Атака без защиты наносит урон, эффект берёт карту до передачи хода")


func check_volume_three() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 63
	var setup: RefCounted = Setup.create("marmoreal", ["pandora", "bloody_mary"], [11, 12], rng)
	var rules := Rules.new(setup)
	rules.misery_pile = [3, 0]
	rules.start_turn()
	var request: Dictionary = rules.effect_view(11)
	check(rules.miseries == [0] and request.get("options", []) == ["reveal"], "Ящик открывает одно несчастье обязательно")
	check(rules.choose_effect(11, request.get("id", -1), "reveal") and rules.miseries == [0, 3]
		and setup.fighters[0][0].health == 12, "Три пера закрывают ящик и наносят урон по числу открытых карт")
	rules._finish_turn()
	check(rules.miseries.is_empty() and rules.misery_pile.size() == 2, "Открытые несчастья возвращаются в колоду в конце хода")
	rules.clear_choices()
	setup = Setup.create("marmoreal", ["blackbeard", "bloody_mary"], [11, 12], rng)
	while not setup.pending().is_empty():
		var step: Dictionary = setup.pending()
		setup.place(11, step.cells[0])
	rules = Rules.new(setup)
	rules.start_turn()
	request = rules.effect_view(11)
	check(rules.choose_effect(11, request.get("id", -1), "pay") and rules.doubloons == 1 and rules.actions_left == 3,
		"Чёрная Борода обменивает дублон на дополнительное действие")
	rules.clear_choices()
	setup = Setup.create("marmoreal", ["loki", "bloody_mary"], [11, 12], rng)
	setup.fighters[0][0].space = 4
	setup.fighters[1][0].space = 5
	var trick := Catalog.deck_for("loki", 0)[25]
	setup.hands[0] = [trick]
	setup.hands[1] = []
	rules = Rules.new(setup)
	rules.begin_attack(11, 0, 1, 0, trick.key)
	request = rules.attack_view(12).get("choice", {})
	rules.choose_combat_card(12, {"request": request.get("id", -1), "hand": 1, "cards": []})
	check(rules.resolve_combat() and trick in setup.hands[1] and trick not in setup.discards[0],
		"Разыгранная Хитрость Локи переходит в руку противника")
	rules._discard_key(1, trick.key)
	rules._run_effects()
	request = rules.effect_view(11)
	check(rules.choose_effect(11, request.get("id", -1), "deck") and setup.decks[0].back() == trick,
		"Локи возвращает сброшенную Хитрость на верх своей колоды")
	rules.clear_choices()
	setup = Setup.create("marmoreal", ["chupacabra", "bloody_mary"], [11, 12], rng)
	setup.fighters[0][0].space = 4
	setup.fighters[1][0].space = 5
	setup.hands[0] = [Catalog.deck_for("chupacabra", 0)[27]]
	setup.hands[1] = []
	rules = Rules.new(setup)
	check(rules.begin_attack(11, 0, 1, 0, setup.hands[0][0].key), "Чупакабра начинает атаку")
	request = rules.attack_view(12).get("choice", {})
	rules.choose_combat_card(12, {"request": request.get("id", -1), "hand": 1, "cards": []})
	check(rules.resolve_combat() and rules.last_combat.damage == 0, "Неудачная атака Чупакабры завершена")
	request = rules.effect_view(11)
	check(request.get("options", []) == ["draw"] and request.optional and rules.effect_view(12).is_empty(),
		"Голод Чупакабры предлагает добор даже после атаки без урона")
	check(rules.choose_effect(11, request.get("id", -1), null) and setup.hands[0].is_empty()
		and rules.phase == Rules.Phase.ACTION, "Добор Чупакабры можно пропустить")
	rules.clear_choices()


func check_workshop_maps() -> void:
	check(Maps.MAPS.size() == 39, "Загружены все 39 полей Workshop")
	for key: String in Maps.MAPS:
		var field: RefCounted = Maps.create(key)
		check(field != null and field.valid() and Maps.supports(key, 2) == (key not in Maps.HIDDEN_ARENAS),
			"Поле %s содержит связанный набор клеток и правильно доступно" % key)
		var image_name: String = Maps.IMAGES.get(key, key)
		check(FileAccess.file_exists("res://games/unmatched/art/boards/%s.webp" % image_name), "Изображение поля %s доступно" % key)
	check(not Maps.supports("sherwood", 4) and Maps.supports("venice", 4), "Ограничения полей учитывают стартовые клетки")
	var santa: RefCounted = Maps.create("santa_s_workshop")
	check(santa.adjacent(19, 0) and 19 in santa.reachable(0, 1, 0, {})
		and 0 not in santa.reachable(19, 1, 0, {}), "Оранжевые стрелки Санты ограничивают движение, но не смежность")
	var manor: RefCounted = Maps.create("baskerville_manor")
	check(16 in manor.reachable(0, 1, 0, {}) and not manor.adjacent(0, 16), "Тайный ход доступен для движения, но не атаки")
	var rng := RandomNumberGenerator.new()
	rng.seed = 562
	var setup: RefCounted = Setup.create("santa_s_workshop", ["bloody_mary", "sun_wukong"], [11, 12], rng)
	setup.fighters[0][0].space = 11
	setup.fighters[1][0].space = 10
	var rules := Rules.new(setup)
	rules._finish_turn()
	var request: Dictionary = rules.effect_view(12)
	var options: Array = request.get("options", [])
	check(not options.is_empty() and rules.seat == 0, "Владелец последнего бойца выбирает свободное место до смены хода")
	if not options.is_empty():
		check(rules.choose_effect(12, request.id, options.front()) and setup.fighters[0][0].space == 10
			and setup.fighters[1][0].space == options.front() and rules.seat == 1, "Конвейер двигает всю очередь на одну клетку")
	rules.clear_choices()


func check_heorot() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var setup: RefCounted = Setup.create("heorot", ["bigfoot", "bloody_mary"], [11, 12], rng)
	setup.place(11, setup.pending().cells[0])
	var field: RefCounted = setup.board
	check(field.doors.size() == 3 and field.closed_doors.is_empty(), "Три двери Хеорота начинают открытыми")
	setup.fighters[0][0].space = 3
	setup.fighters[0][1].space = 20
	setup.fighters[1][0].space = 16
	var rules := Rules.new(setup)
	check(not rules.toggle_maneuver_door(11, 0, 1), "Дверь нельзя переключать вне манёвра")
	check(rules.begin_maneuver(11) and not rules.toggle_maneuver_door(12, 0, 1), "Чужой манёвр не даёт управления дверью")
	check(rules.move_in_maneuver(11, 0, 20) and not rules.end_maneuver(11), "Боец взаимодействует с дверью на проходе через союзника")
	check(rules.toggle_maneuver_door(11, 0, 1) and not field.adjacent(3, 20)
		and not field.adjacent(3, 21) and not field.same_zone(3, 20) and not field.in_attack_range(3, 20, true),
		"Закрытая дверь разрывает обе дорожки, смежность, зону и дальнюю атаку")
	check(rules.toggle_maneuver_door(11, 0, 1) and field.adjacent(3, 20) and field.same_zone(3, 20)
		and 28 in rules.maneuver_cells(11, 0) and rules._maneuver_remaining(0) == 1,
		"Открывание тратит один шаг и восстанавливает обе дорожки")
	check(rules.move_in_maneuver(11, 0, 28) and rules.maneuver_cells(11, 0).is_empty()
		and rules.end_maneuver(11), "Манёвр заканчивается на свободной клетке после расхода шагов")
	rules.clear_choices()


func check_bigfoot() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	var setup: RefCounted = Setup.create("heorot", ["bigfoot", "bloody_mary"], [11, 12], rng)
	setup.place(11, setup.pending().cells[0])
	var rules := Rules.new(setup)
	var deck := Catalog.deck_for("bigfoot", 0)
	setup.fighters[0][0].space = 24
	setup.fighters[0][1].space = 25
	setup.fighters[1][0].space = 18
	setup.hands[0] = deck.slice(0, 7)
	rules.actions_left = 0
	rules._end_action()
	var request := rules.effect_view(11)
	check(request.get("options", []) == ["draw"] and request.optional and rules.effect_view(12).is_empty(),
		"Бигфут выбирает добор за чистую зону в конце своего хода")
	check(rules.choose_effect(11, request.get("id", -1), "draw") and setup.hands[0].size() == 8
		and rules.phase == Rules.Phase.DISCARD, "Добор Бигфута происходит перед сбросом до семи")
	check(rules.discard_to_limit(11, setup.hands[0][0].key) and rules.seat == 1,
		"Добор срабатывает один раз, после сброса ход передаётся")
	rules.clear_choices()
	setup.fighters[0][0].space = 3
	setup.fighters[0][1].space = 20
	setup.fighters[1][0].space = 21
	setup.hands[0] = [deck[16]]
	rules = Rules.new(setup)
	check(not rules.play_scheme(11, 0, deck[16].key) and rules.play_scheme(11, 1, deck[16].key),
		"Приём «Рога Шакалопа» доступен только помощнику")
	request = rules.effect_view(11)
	check(29 in request.get("options", []) and 21 not in request.get("options", []),
		"Шакалоп проходит сквозь врага и заканчивает движение на свободной клетке")
	check(rules.choose_effect(11, request.get("id", -1), 29)
		and setup.fighters[0][1].walk == PackedInt32Array([20, 21, 29]), "Маршрут Шакалопа действительно проходит через противника")
	request = rules.effect_view(11)
	check(Vector2i(1, 0) in request.get("options", []) and Vector2i(0, 0) not in request.get("options", []),
		"Рога выбирают бойца, смежного с новой клеткой Шакалопа")
	check(rules.choose_effect(11, request.get("id", -1), Vector2i(1, 0)) and setup.fighters[1][0].health == 14,
		"Рога нанесли два урона выбранному бойцу")
	rules.clear_choices()
	setup.fighters[0][0].space = 3
	setup.fighters[1][0].space = 20
	rules = Rules.new(setup)
	rules.actions_left = 0
	rules._end_action()
	check(rules.effect_view(11).is_empty() and rules.seat == 1, "Враг в зоне блокирует способность Бигфута")
	rules.clear_choices()
	setup.fighters[0][0].space = 20
	setup.fighters[0][1].space = 27
	setup.fighters[1][0].space = 21
	setup.hands[0] = [deck[10]]
	setup.hands[1] = []
	rules = Rules.new(setup)
	check(rules.begin_attack(11, 0, 1, 0, deck[10].key), "Бигфут разыгрывает «Свирепость»")
	request = rules.attack_view(12).get("choice", {})
	rules.choose_combat_card(12, {"request": request.get("id", -1), "hand": 1, "cards": []})
	check(rules.resolve_combat() and setup.fighters[0][1].health == 5 and setup.fighters[1][0].health == 9,
		"Победная «Свирепость» наносит дополнительный урон и противнику, и соседнему Шакалопу")
	rules.clear_choices()


func check_reported_cards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 27
	var setup: RefCounted = Setup.create("marmoreal", ["alice", "bloody_mary"], [11, 12], rng)
	setup.place(11, setup.pending().cells[0])
	setup.choose_size(11, false)
	setup.fighters[0][0].space = 4
	setup.fighters[1][0].space = 5
	var alice := Catalog.deck_for("alice", 0)
	var mary := Catalog.deck_for("bloody_mary", 1)
	var gates := alice[22]
	var top := alice[2]
	var mirror := mary[14]
	setup.hands[0] = [gates]
	setup.hands[1] = [mirror]
	setup.decks[0] = [top]
	var rules := Rules.new(setup)
	check(rules.begin_attack(11, 0, 1, 0, gates.key), "Враг у ворот разыгрывается атакой")
	var request: Dictionary = rules.attack_view(12).choice
	rules.choose_combat_card(12, {"request": request.get("id", -1), "hand": 1, "cards": [mirror.key]})
	rules.resolve_combat()
	request = rules.effect_view(12)
	check(request.get("modifier_choice", false) and request.get("options", []) == [-1, 1],
		"Разбитое зеркало предлагает уменьшение и увеличение")
	check(rules.choose_effect(12, request.get("id", -1), -1)
		and rules.last_combat.get("defense_value") == mirror.value - 1, "Разбитое зеркало принимает уменьшение")
	check(setup.decks[0].is_empty() and setup.discards[0].has(top)
		and rules.last_combat.get("attack_value") == gates.value + top.boost, "Враг у ворот сбрасывает вершину и добавляет усиление")
	setup = Setup.create("marmoreal", ["arthur", "bloody_mary"], [11, 12], rng)
	setup.place(11, setup.pending().cells[0])
	setup.fighters[0][0].space = 4
	setup.fighters[0][1].space = 5
	setup.fighters[1][0].space = 6
	var storm := Catalog.deck_for("arthur", 0)[15]
	setup.hands[0] = [storm]
	rules = Rules.new(setup)
	check(rules.play_scheme(11, 1, storm.key), "Мерлин разыгрывает Управляя штормом")
	for target: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
		request = rules.effect_view(11)
		var previous: int = setup.fighters[target.x][target.y].space
		check(target in request.get("options", []) and rules.choose_effect(11, request.get("id", -1), target),
			"Одним приёмом можно выбрать бойца каждой стороны")
		request = rules.effect_view(11)
		var cells: Array = request.get("options", [])
		check(not cells.is_empty() and rules.choose_effect(11, request.get("id", -1), cells.front())
			and setup.fighters[target.x][target.y].space != previous, "Боец перемещается на выбранную клетку")
	rules.clear_choices()


func check_follow_up() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 182
	var setup: RefCounted = Setup.create("sarpedon", ["bloody_mary", "arthur"], [11, 12], rng)
	var placement: Dictionary = setup.pending()
	check(setup.place(12, placement.cells[0]), "Мерлин расставлен")
	setup.fighters[0][0].space = 32
	setup.fighters[1][0].space = 33
	var mary := Catalog.deck_for("bloody_mary", 0)
	var arthur := Catalog.deck_for("arthur", 1)
	setup.hands[0] = [mary[6]]
	setup.hands[1] = [arthur[7], arthur[4]]
	var rules := Rules.new(setup)
	check(rules.begin_attack(11, 0, 1, 0), "Основная атака Мэри начата")
	var request: Dictionary = rules.attack_view(11).choice
	rules.choose_combat_card(11, {"request": request.id, "hand": 0, "cards": [mary[6].key]})
	request = rules.attack_view(12).choice
	rules.choose_combat_card(12, {"request": request.id, "hand": 1, "cards": [arthur[7].key]})
	check(rules.resolve_combat() and setup.discards[1][-1].key == arthur[7].key
		and setup.discards[0].is_empty() and rules.actions_left == 1, "Первая защита сброшена, вторая атака без расхода действия")
	var second: Dictionary = rules.attack_view(12).choice
	check(second.id != request.id and second.allowed == [arthur[4].key] and rules.attack_view(11).cards.is_empty(),
		"Новый закрытый выбор защиты исключает старую карту")
	rules.choose_combat_card(12, {"request": second.id, "hand": 1, "cards": [arthur[4].key]})
	check(rules.attack_view(12).cards.attack.name == "Кровавая реприза"
		and rules.attack_view(12).cards.attack.boost == 4, "У второй атаки своё имя и исходное усиление")
	check(rules.resolve_combat() and rules.last_combat.attack_canceled and rules.last_combat.damage == 0
		and setup.discards[0].size() == 1 and setup.discards[0][0].key == mary[6].key,
		"Уловка отменяет подстановку значения, карта атаки сбрасывается один раз")


func check_scheme() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var setup: RefCounted = Setup.create("marmoreal", ["alice", "bloody_mary"], [11, 12], rng)
	setup.place(11, setup.pending().cells[0])
	setup.choose_size(11, false)
	var card := Catalog.deck_for("alice", 0)[10]
	setup.hands[0] = [card]
	var rules := Rules.new(setup)
	check(not rules.play_scheme(12, 0, card.key) and not rules.play_scheme(11, 1, card.key),
		"Приём Алисы недоступен Бармаглоту и другому контроллеру")
	check(rules.play_scheme(11, 0, card.key) and setup.alice_large and setup.hands[0].size() == 2
		and setup.discards[0][-1].key == card.key and rules.actions_left == 1, "Выпей меня берёт две карты, меняет размер и отправляется в сброс")


func check_private_effects() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var setup: RefCounted = Setup.create("sarpedon", ["arthur", "bloody_mary"], [11, 12], rng)
	setup.place(11, setup.pending().cells[0])
	setup.fighters[0][0].space = 32
	setup.fighters[0][1].space = 10
	setup.fighters[1][0].space = 33
	var arthur := Catalog.deck_for("arthur", 0)
	var mary := Catalog.deck_for("bloody_mary", 1)
	setup.hands[0] = [arthur[0], arthur[1], arthur[21]]
	setup.hands[1] = [mary[9]]
	var rules := Rules.new(setup)
	check(rules.begin_attack(11, 0, 1, 0), "Артур начал атаку")
	var request: Dictionary = rules.attack_view(11).choice
	rules.choose_combat_card(11, {"request": request.id, "hand": 0, "cards": [arthur[0].key]})
	request = rules.effect_view(11)
	check(not request.is_empty() and rules.effect_view(12).is_empty()
		and not rules.attack_view(12).has("choice"), "Усиление Артура закрыто до выбора защиты")
	check(not rules.choose_effect(12, request.id, arthur[1].key)
		and rules.choose_effect(11, request.id, arthur[1].key), "Усиление принимает ответ только Артура")
	request = rules.attack_view(12).choice
	rules.choose_combat_card(12, {"request": request.id, "hand": 1, "cards": [mary[9].key]})
	check(rules.resolve_combat() and rules.last_combat.damage == 4 and setup.discards[0].size() == 2,
		"Уловка отменяет скрытое усиление и не мешает сбросу карты")
	setup.decks[0] = [arthur[2], arthur[3], arthur[4], arthur[5], arthur[6]]
	check(rules.play_scheme(11, 1, arthur[21].key), "Мерлин начинает Пророчество")
	request = rules.effect_view(11)
	check(request.shown.size() == 4 and request.options == [arthur[6].key, arthur[5].key, arthur[4].key, arthur[3].key]
		and rules.effect_view(12).is_empty(), "Только Мерлин видит четыре верхние карты")
	rules.choose_effect(11, request.id, arthur[3].key)
	request = rules.effect_view(11)
	rules.choose_effect(11, request.id, arthur[6].key)
	request = rules.effect_view(11)
	rules.choose_effect(11, request.id, arthur[4].key)
	check(setup.hands[0] == [arthur[3], arthur[6]] and setup.decks[0] == [arthur[2], arthur[5], arthur[4]],
		"Пророчество забирает две карты и меняет порядок вершины")


func check_archers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var setup: RefCounted = Setup.create("sarpedon", ["bloody_mary", "yennenga"], [11, 12], rng)
	for i in 2:
		setup.place(12, setup.pending().cells[0])
	setup.fighters[0][0].space = 32
	setup.fighters[1][0].space = 33
	setup.fighters[1][1].space = 34
	setup.fighters[1][2].space = 25
	var mary := Catalog.deck_for("bloody_mary", 0)
	setup.hands[0] = [mary[4]]
	var rules := Rules.new(setup)
	check(rules.begin_attack(11, 0, 1, 0), "Атака Йенненги началась")
	var request: Dictionary = rules.attack_view(11).choice
	rules.choose_combat_card(11, {"request": request.id, "hand": 0, "cards": [mary[4].key]})
	request = rules.attack_view(12).choice
	rules.choose_combat_card(12, {"request": request.id, "hand": 1, "cards": []})
	check(rules.resolve_combat() and setup.fighters[1][0].health == 15, "Йенненга выбирает перенос до применения урона")
	request = rules.effect_view(12)
	check(request.options == [0, 1, 2] and rules.choose_effect(12, request.id, 2), "Первый лучник принимает урон в пределах здоровья")
	request = rules.effect_view(12)
	check(request.options == [0, 1] and rules.choose_effect(12, request.id, 1), "Второй лучник принимает остаток")
	check(setup.fighters[1][0].health == 15 and setup.fighters[1][1].space == -1
		and setup.fighters[1][2].health == 1 and rules.last_combat.attacker_won,
		"Перенос всего урона сохраняет победу атакующего")


func check_high_ground() -> void:
	for descending in [true, false]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 12
		var setup: RefCounted = Setup.create("gardens", ["medusa", "bloody_mary"], [11, 12], rng)
		for i in 3:
			setup.place(11, setup.pending().cells[0])
		setup.fighters[0][0].space = 13 if descending else 12
		setup.fighters[1][0].space = 12 if descending else 13
		for helper in range(1, setup.fighters[0].size()):
			setup.fighters[0][helper].space = 25 + helper
		var shot := Catalog.deck_for("medusa", 0)[27]
		var feint := Catalog.deck_for("bloody_mary", 1)[9]
		setup.hands[0] = [shot]
		setup.hands[1] = [feint]
		var rules := Rules.new(setup)
		rules.start_turn()
		var choice: Dictionary = rules.effect_view(11)
		if not choice.is_empty():
			rules.choose_effect(11, choice.id, null)
		check(rules.begin_attack(11, 0, 1, 0), "Атака на ступенях Висячих садов")
		choice = rules.attack_view(11).choice
		rules.choose_combat_card(11, {"request": choice.id, "hand": 0, "cards": [shot.key]})
		choice = rules.attack_view(12).choice
		rules.choose_combat_card(12, {"request": choice.id, "hand": 1, "cards": [feint.key]})
		check(rules.resolve_combat() and rules.last_combat.attack_canceled
			and rules.last_combat.damage == int(descending), "Высота направленная и сохраняется при Уловке")


func check_common_actions() -> void:
	var deck := [1, 2, 3]
	var hand := [4]
	check(Piles.peek(deck, 2) == [3, 2] and deck == [1, 2, 3], "Просмотр вершины не меняет колоду")
	check(Piles.peek(deck, -1).is_empty(), "Отрицательный объём просмотра")
	check(Piles.draw_many(deck, hand, 4) == [3, 2, 1] and deck.is_empty() and hand == [4, 3, 2, 1], "Добор сохраняет порядок и останавливается при истощении")
	var rng := RandomNumberGenerator.new()
	rng.seed = 81
	var duplicate_cards := [7, 7, 7]
	var discard: Array = []
	check(Piles.discard_random(duplicate_cards, discard, 2, rng) == [7, 7] and duplicate_cards == [7] and discard == [7, 7], "Случайный сброс различает экземпляры")
	rng.seed = 64
	var first_pick := Piles.random_indices(hand, 3, rng)
	rng.seed = 64
	check(first_pick == Piles.random_indices(hand, 3, rng) and first_pick.size() == 3, "Случайность воспроизводится на хосте")
	var is_even := func(card: int) -> bool: return card % 2 == 0
	check(Piles.matching(hand, is_even) == [4, 2] and Piles.count_matching(hand, is_even) == 2, "Отбор и подсчёт сохраняют порядок исходной руки")

	var reveals := {}
	Reveal.show(reveals, [1, 2], -1, 2.0)
	Reveal.show(reveals, [3], 0, 1.0)
	check(Reveal.visible_to(reveals[1], -1) and Reveal.visible_to(reveals[2], 1), "Публичный показ открывает обе карты")
	check(Reveal.visible_to(reveals[3], 0) and not Reveal.visible_to(reveals[3], 1) and not Reveal.visible_to(reveals[3], -1), "Частный показ только адресату")
	check(Reveal.tick(reveals, 1.0) and not reveals.has(3) and reveals.has(2), "Временный просмотр закрывается в срок")

	var options := [1, 2]
	var optional := Choice.request(0, options, true)
	options.clear()
	check(Choice.accepts(optional, 0, 1) and Choice.accepts(optional, 0, null), "Варианты хранятся на хосте, необязательный выбор можно пропустить")
	check(not Choice.accepts(optional, 1, 1) and not Choice.accepts(optional, 0, 3), "Чужое место и скрытый вариант отклоняются")
	check(not Choice.accepts(Choice.request(0, [1]), 0, null), "Обязательный выбор нельзя пропустить")


func check_art() -> void:
	var text := FileAccess.get_file_as_string("res://games/unmatched/art/cards/sources.json")
	var catalog: Variant = JSON.parse_string(text)
	check(catalog is Dictionary and catalog.size() == Roster.HEROES.size(), "В каталоге есть колода каждого героя")
	if not catalog is Dictionary:
		return
	for hero: String in Roster.HEROES:
		var deck: Array = catalog.get(hero, [])
		check(deck.size() == 30, "У %s тридцать карт" % hero)
		for entry: Dictionary in deck:
			var path := "res://games/unmatched/art/cards/%s/%s" % [hero, entry.file]
			check(FileAccess.file_exists(path), "Найдено изображение карты %s" % path)
	check(Roster.HEROES.sun_wukong.sidekick.reserve, "Двойники начинают вне поля")
	check(not Roster.HEROES.bloody_mary.has("sidekick"), "У Кровавой Мэри нет помощника")
	check(Roster.HEROES.yennenga.sidekick.health == 2, "У лучников по два здоровья")


func check_maps() -> void:
	var expectations := {
		"marmoreal": {"count": 31, "starts": [13, 30, 2, 11], "links": 42, "zones": 8},
		"sarpedon": {"count": 38, "starts": [18, 34, 2, 14], "links": 61, "zones": 6},
		"gardens": {"count": 33, "starts": [3, 13, 18, 9], "links": 50, "zones": 8},
	}
	for arena: String in expectations:
		var map := Maps.create(arena)
		var expected: Dictionary = expectations[arena]
		check(map != null and map.valid(), "Собран граф %s" % arena)
		check(map.cell_count() == expected.count, "Число клеток %s" % arena)
		check(map.reachable(0, expected.count, 0, {}).size() == expected.count - 1, "Все клетки связаны %s" % arena)
		for i in expected.starts.size():
			check(map.start_for(i) == expected.starts[i], "Старт %d на %s" % [i + 1, arena])
		var zones := {}
		var links := 0
		for cell: int in expected.count:
			check(Rect2(0, 0, 1, 1).has_point(map.position_for(cell)), "Центр клетки внутри %s" % arena)
			for zone: String in map.zones_for(cell):
				zones[zone] = true
			for other: int in range(cell + 1, expected.count):
				var connected: bool = map.adjacent(cell, other)
				check(connected == map.adjacent(other, cell), "Обычная связь действует в обе стороны")
				links += int(connected)
		check(zones.size() == expected.zones and links == expected.links, "Количество зон и связей %s" % arena)
	var marble := Maps.create("marmoreal")
	check(not marble.adjacent(12, 15) and marble.same_zone(12, 15), "Созвучные зоны не означают соседство")
	var coast := Maps.create("sarpedon")
	check(coast.adjacent(23, 31) and not coast.adjacent(17, 23), "Связи побережья соответствуют печатному полю")
	var gardens := Maps.create("gardens")
	var heights := 0
	var valid_heights := true
	for start in gardens.cell_count():
		for finish in gardens.cell_count():
			var bonus: int = gardens.attack_bonus(start, finish)
			heights += bonus
			valid_heights = valid_heights and (bonus == 0 or (
				gardens.adjacent(start, finish) and gardens.attack_bonus(finish, start) == 0))
	check(valid_heights and heights == 20, "На Висячих садах 20 направленных бонусов")
	check(gardens.attack_bonus(32, 29) == 1 and gardens.attack_bonus(29, 13) == 1
		and gardens.attack_bonus(13, 12) == 1, "Стрелки от центральных ступеней направлены вниз")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
