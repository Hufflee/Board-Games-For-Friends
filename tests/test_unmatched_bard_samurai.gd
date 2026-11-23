extends SceneTree
## Адресные проверки Шекспира и самураев по печатным данным. Запускать headless с Dummy.

const Setup := preload("res://games/unmatched/logic/um_setup.gd")
const Rules := preload("res://games/unmatched/logic/um_rules.gd")
const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")

var checked := 0
var failed := 0
var live: Array[RefCounted] = []


func _initialize() -> void:
	_catalog()
	_hamlet()
	_poem()
	_witches()
	_titania()
	_oda()
	_tomoe()
	for rules: RefCounted in live:
		rules.clear_choices()
	live.clear()
	print("Unmatched, Шекспир и самураи: %d проверок, %d ошибок." % [checked, failed])
	quit(int(failed > 0))


func _rules(heroes: PackedStringArray) -> RefCounted:
	var rng := RandomNumberGenerator.new()
	rng.seed = 725
	var game: RefCounted = Setup.create("marmoreal", heroes, [11, 12], rng)
	for i in 12:
		var step: Dictionary = game.pending()
		if step.is_empty():
			break
		game.place(game.controllers[step.seat], step.cells[0])
	var rules := Rules.new(game)
	live.append(rules)
	return rules


func _cards(rules: RefCounted, place: int, numbers: Array) -> void:
	var deck := Catalog.deck_for(rules.game.heroes[place], place)
	var wanted: Array = numbers.map(func(number: int) -> String: return "%d:%02d" % [place, number])
	rules.game.hands[place] = deck.filter(func(card: Dictionary) -> bool: return card.key in wanted)
	rules.game.decks[place] = deck.filter(func(card: Dictionary) -> bool: return card.key not in wanted)


func _choose(rules: RefCounted, viewer: int, answer: Variant) -> void:
	var request: Dictionary = rules.effect_view(viewer)
	check(not request.is_empty() and rules.choose_effect(viewer, request.id, answer),
		"Принят выбор игрока %d: %s" % [viewer, str(answer)])


func _attack(rules: RefCounted, attack_key: String, defense_key: String, attacker: int = 0, defender: int = 0) -> void:
	var began: bool = rules.begin_attack(11, attacker, 1, defender, attack_key)
	check(began, "Начата атака %s" % attack_key)
	if not began:
		return
	var request: Dictionary = rules.attack_view(12).get("choice", {})
	check(not request.is_empty() and rules.choose_combat_card(12, {"request": request.id, "hand": 1,
		"cards": [] if defense_key.is_empty() else [defense_key]}), "Принята защита %s" % defense_key)
	check(rules.resolve_combat(), "Бой разрешён")


func _physical(rules: RefCounted, place: int, extra: Array) -> void:
	var cards: Array = rules.game.decks[place] + rules.game.hands[place] + rules.game.discards[place] + extra
	var ids := {}
	for card: Dictionary in cards:
		ids[card.key] = true
	check(cards.size() == 30 and ids.size() == 30, "Тридцать физических карт, считая особую стопку")


func _catalog() -> void:
	for hero: String in EXPECTED:
		var expected: Array = EXPECTED[hero]
		var deck := Catalog.deck_for(hero, 0)
		check(deck.size() == 30, "%s: 30 физических карт" % hero)
		var unique := {}
		for card: Dictionary in deck:
			if not unique.has(card.definition):
				unique[card.definition] = [card.name, card.kind, card.fighter, card.value, card.boost, 0,
					card.get("syllables", 0), card.get("ingredient", "")]
			unique[card.definition][5] += 1
		check(unique.size() == expected.size(), "%s: число определений совпадает с PDF" % hero)
		for index in mini(unique.size(), expected.size()):
			check(unique.values()[index] == expected[index], "%s: совпадает печать «%s»" % [hero, expected[index][0]])


func _hamlet() -> void:
	for not_to_be: bool in [true, false]:
		var rules := _rules(["hamlet", "bloody_mary"])
		var game: RefCounted = rules.game
		rules.start_turn()
		_choose(rules, 11, "not_to_be" if not_to_be else "to_be")
		if not_to_be:
			_choose(rules, 11, Vector2i(0, 1))
			check(game.fighters[0][1].health == 4 and game.fighters[0][0].health == 15,
				"Не быть ранит выбранного помощника и сохраняет здоровье Гамлета")
			game.fighters[0][0].space = 13
			game.fighters[1][0].space = 7
			_cards(rules, 0, [16])
			_cards(rules, 1, [])
			_attack(rules, "0:16", "")
			check(rules.last_combat.get("attack_value") == 4, "Не быть увеличивает атаку Гамлета на два")
		else:
			var before: int = game.hands[0].size()
			check(rules.begin_maneuver(11) and game.hands[0].size() == before + 2,
				"Быть даёт дополнительный добор при манёвре")


func _poem() -> void:
	for exact: bool in [true, false]:
		var rules := _rules(["shakespeare", "bloody_mary"])
		var game: RefCounted = rules.game
		_cards(rules, 0, [1, 5, 28])
		_cards(rules, 1, [10])
		game.fighters[0][0].space = 13
		game.fighters[1][0].space = 7
		_attack(rules, "0:01", "")
		while not rules.effect_view(11).is_empty():
			var request: Dictionary = rules.effect_view(11)
			_choose(rules, 11, null if request.optional else request.options[0])
		check(rules.bard.poem.size() == 1 and rules.bard.syllables() == 4,
			"После атаки карта с четырьмя слогами лежит в строке")
		_physical(rules, 0, rules.bard.poem)
		if not exact:
			var hand: Array = game.hands[0]
			for i in hand.size():
				if hand[i].key == "0:05":
					rules.bard.poem.append(hand.pop_at(i))
					break
		_attack(rules, "0:28", "1:10")
		check(rules.bard.poem.is_empty() and rules.last_combat.get("attack_canceled"),
			"Строка сбрасывается, обычный эффект карты отменён")
		check(rules.seat == (0 if exact else 1) and (not exact or rules.actions_left == 2),
			"Ровно десять слогов дают +2 действия даже после Уловки, перебор не даёт")
		_physical(rules, 0, rules.bard.poem)


func _witches() -> void:
	var rules := _rules(["witches", "bloody_mary"])
	var game: RefCounted = rules.game
	check(game.fighters[0].size() == 3 and game.fighters[0].all(func(fighter: Dictionary) -> bool:
		return fighter.is_hero and fighter.health == 6), "У сестёр три отдельных героя с шестью ОЗ")
	_cards(rules, 0, [1, 16])
	check(rules.begin_maneuver(11) and rules.boost_maneuver(11, "0:01"), "Сестра усиливает манёвр")
	check(rules.bard.cauldron.size() == 1 and rules.bard.cauldron[0].ingredient == "snake"
		and game.discards[0].is_empty(), "Сброшенная при усилении карта попадает в котёл")
	_physical(rules, 0, rules.bard.cauldron)


func _titania() -> void:
	var rules := _rules(["titania", "bloody_mary"])
	check(rules.bard.enchantment_deck.size() == 6, "Чары составляют отдельную колоду из шести карт")
	rules.start_turn()
	var opened: int = rules.bard.enchantment
	check(opened >= 0 and rules.bard.enchantment_deck.size() == 5, "Титания открывает чары в начале хода")
	rules.start_turn()
	check(rules.bard.enchantment == opened and rules.bard.enchantment_deck.size() == 5,
		"Открытые чары не заменяются повторной проверкой начала хода")


func _oda() -> void:
	var rules := _rules(["oda", "bloody_mary"])
	var game: RefCounted = rules.game
	game.fighters[0][0].space = 7
	game.fighters[0][1].space = 13
	game.fighters[1][0].space = 0
	check(game.board.same_zone(7, 13) and rules.bard.bonus(Vector2i(0, 1), true) == 1
		and rules.bard.bonus(Vector2i(0, 0), true) == 0 and rules.bard.bonus(Vector2i(1, 0), false) == 0,
		"Ода усиливает стража в зоне, но не себя и не противника")


func _tomoe() -> void:
	var rules := _rules(["tomoe", "bloody_mary"])
	var game: RefCounted = rules.game
	_cards(rules, 0, [12])
	_cards(rules, 1, [])
	game.fighters[0][0].space = 13
	for cell in game.board.cell_count():
		if game.board.same_zone(13, cell) and not game.board.adjacent(13, cell) and cell != 13:
			game.fighters[1][0].space = cell
			check(not rules.begin_attack(11, 0, 1, 0, "0:12"), "Последний бой запрещён по дальней цели")
			break
	game.fighters[1][0].space = 7
	check(rules.begin_attack(11, 0, 1, 0, "0:12"), "Последний бой разрешён по смежной цели")
	var before: Dictionary = rules.attack_view(12)
	check(before.get("cards", {}).get("attack", {}).get("key") == "0:12", "Последний бой объявляется открыто")
	var choice: Dictionary = before.get("choice", {})
	if not choice.is_empty():
		rules.choose_combat_card(12, {"request": choice.id, "hand": 1, "cards": []})
	check(rules.resolve_combat() and rules.seat == 1, "Последний бой заканчивает ход")


func check(condition: bool, message: String) -> void:
	checked += 1
	if not condition:
		failed += 1
		push_error(message)


# Значения независимо сверены по полноразмерным страницам двух PDF.
const EXPECTED := {
	"tomoe": [
		["Впятером против тысячи", 0, 0, 4, 1, 2, 0, ""],
		["Достойный противник", 2, 0, 3, 3, 3, 0, ""],
		["Пронзающий выстрел", 0, 0, 2, 1, 3, 0, ""],
		["Стычка", 2, 0, 4, 1, 3, 0, ""],
		["Узрите мой последний бой", 0, 0, 7, 4, 2, 0, ""],
		["Блеск стали", 2, 0, 2, 1, 3, 0, ""],
		["До последнего вздоха", 1, 0, 3, 2, 2, 0, ""],
		["Устрашающая мощь", 0, 0, 3, 1, 2, 0, ""],
		["Усмирить любого демона", 2, 0, 3, 3, 2, 0, ""],
		["Последний рубеж лорда Кисо", 3, 0, 0, 2, 3, 0, ""],
		["Путь самурая", 0, 0, 2, 1, 2, 0, ""],
		["Подвиги храбрости", 1, 0, 2, 2, 3, 0, ""],
	],
	"oda": [
		["Гром и молнии", 0, 1, 4, 1, 3, 0, ""],
		["Подкрепление", 3, 2, 0, 2, 3, 0, ""],
		["Поймать в ловушку", 1, 2, 2, 2, 3, 0, ""],
		["Боевые маневры", 2, 2, 2, 2, 4, 0, ""],
		["Проверка на практике", 1, 0, 3, 1, 3, 0, ""],
		["Покой и стратегия", 2, 2, 1, 1, 3, 0, ""],
		["Огонь и пламя", 0, 2, 3, 3, 3, 0, ""],
		["Переломный момент", 2, 2, 3, 2, 2, 0, ""],
		["Демон-повелитель шестого неба", 3, 0, 0, 3, 2, 0, ""],
		["Солнце и луна", 0, 1, 2, 1, 2, 0, ""],
		["Закалённый войной", 0, 0, 5, 2, 2, 0, ""],
	],
	"witches": [
		["Таинственное лекарство", 1, 2, 1, 2, 2, 0, "snake"],
		["Пророчество", 3, 2, 0, 2, 2, 0, "lizard_leg"],
		["Всевидящий фамильяр", 0, 2, 4, 2, 2, 0, "lizard_leg"],
		["Зелье, прей!", 1, 2, 2, 3, 3, 0, "snake"],
		["Звёзды сходятся", 2, 2, 0, 1, 3, 0, "lizard_leg"],
		["Пресечь", 2, 2, 3, 2, 3, 0, "bat"],
		["Котёл, урчи!", 2, 2, 3, 2, 3, 0, "bat"],
		["Шум и гам", 0, 2, 3, 1, 3, 0, "snake"],
		["Пламя, прядай, клокочи!", 0, 2, 3, 2, 3, 0, "lizard_leg"],
		["Что-то грешное к нам спешит", 3, 2, 0, 3, 2, 0, "bat"],
		["Любопытный фамильяр", 2, 2, 2, 3, 2, 0, "bat"],
		["Щёлкни пальцем только раз", 1, 2, 2, 1, 2, 0, "snake"],
	],
	"shakespeare": [
		["Места, места!", 0, 2, 3, 1, 2, 4, ""],
		["Познав кару", 0, 2, 4, 2, 2, 4, ""],
		["И ты, Брут?", 2, 2, 3, 3, 2, 4, ""],
		["Сласть печали", 2, 1, 4, 2, 2, 4, ""],
		["Вновь ринемся в пролом", 2, 0, 3, 2, 2, 6, ""],
		["Сверка", 2, 2, 1, 2, 2, 2, ""],
		["Увы", 2, 0, 2, 2, 2, 2, ""],
		["Мартовские иды", 2, 0, 2, 2, 2, 4, ""],
		["Ужас", 0, 0, 4, 3, 5, 2, ""],
		["Обман", 2, 2, 2, 1, 3, 2, ""],
		["Снова", 2, 1, 3, 2, 3, 2, ""],
		["Полцарства за коня", 0, 0, 5, 3, 3, 6, ""],
	],
	"hamlet": [
		["Последовательность в безумии", 3, 0, 0, 3, 3, 0, ""],
		["Вещи не бывают ни хорошими, ни дурными", 1, 2, 2, 1, 3, 0, ""],
		["Зрелище… петля!", 2, 2, 3, 2, 3, 0, ""],
		["За эту кровь я сам отвечу", 2, 0, 2, 1, 3, 0, ""],
		["Уснуть… и может видеть сны?", 0, 2, 3, 2, 3, 0, ""],
		["Загадочная участь", 0, 2, 2, 3, 3, 0, ""],
		["Из жалости я должен быть суровым", 0, 0, 2, 4, 2, 0, ""],
		["Дальше… тишина", 1, 0, 2, 3, 2, 0, ""],
		["Главное — всегда быть наготове", 2, 2, 2, 1, 2, 0, ""],
		["Сумасшедшее озарение", 1, 2, 0, 1, 2, 0, ""],
		["Смирившись с судьбой", 2, 0, 1, 2, 2, 0, ""],
		["Призрак", 3, 0, 0, 1, 2, 0, ""],
	],
	"titania": [
		["Прощальный подарок", 2, 2, 2, 1, 2, 0, ""],
		["Земля при лунном свете", 2, 0, 3, 2, 2, 0, ""],
		["Какими глупцами бывают эти смертные", 3, 1, 0, 2, 2, 0, ""],
		["Мимолётный взгляд", 3, 0, 0, 4, 2, 0, ""],
		["Царица фей", 0, 0, 2, 3, 2, 0, ""],
		["Встреча при лунном сиянии", 0, 1, 5, 2, 3, 0, ""],
		["Словно сон", 1, 0, 0, 2, 2, 0, ""],
		["Неприкосновенность волшебных лесов", 1, 2, 2, 1, 3, 0, ""],
		["Унесённый ветром", 2, 2, 4, 1, 3, 0, ""],
		["Дары фей", 3, 2, 0, 2, 3, 0, ""],
		["Столь же мудра, как и прекрасна", 2, 0, 2, 2, 3, 0, ""],
		["Сказочная песня", 2, 2, 3, 2, 3, 0, ""],
	],
}
