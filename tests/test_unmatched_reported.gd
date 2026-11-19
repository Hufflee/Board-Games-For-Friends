extends SceneTree
## Регрессии из партии: Надежда, кольчуга, ограбление, замена защиты и гибель героев.

const Setup := preload("res://games/unmatched/logic/um_setup.gd")
const Rules := preload("res://games/unmatched/logic/um_rules.gd")
const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")
const Match := preload("res://games/unmatched/logic/um_match.gd")
var checks := 0
var errors := 0

func _initialize() -> void:
	_hope()
	_reflect()
	_robin()
	_loki()
	_defeated()
	print("Unmatched, сообщения игроков: %d проверок, %d ошибок." % [checks, errors])
	quit(int(errors > 0))

func _rules(heroes: PackedStringArray) -> RefCounted:
	var rng := RandomNumberGenerator.new()
	rng.seed = 725
	var controllers: PackedInt32Array = [11, 12] if heroes.size() == 2 else [11, 12, 13, 14]
	var game: RefCounted = Setup.create("marmoreal", heroes, controllers, rng)
	while not game.pending().is_empty():
		var step: Dictionary = game.pending()
		game.place(game.controllers[step.seat], step.cells[0])
	return Rules.new(game)

func _choose(rules: RefCounted, answer: Variant) -> void:
	var request: Dictionary = rules._effect_request
	check(not request.is_empty(), "Есть запрос эффекта перед ответом")
	if not request.is_empty():
		check(rules.choose_effect(rules.game.controllers[request.seat], request.id, answer), "Допустимый ответ применён")

func _hope() -> void:
	for reveal in [false, true]:
		var rules := _rules(["pandora", "bloody_mary"])
		rules.misery_pile = [2, 4]
		rules.start_turn()
		var request: Dictionary = rules.effect_view(11)
		check(request.get("misery_peek", false) and request.get("shown", [{}])[0].key == "misery:2",
			"Надежда показывает следующую Боль до решения")
		check(rules.effect_view(12).is_empty() and rules.miseries == [4] and rules.misery_pile == [2],
			"Чужому игроку закрытое бедствие не раскрыто, просмотр не извлекает карту")
		_choose(rules, "reveal" if reveal else null)
		check(rules.miseries == ([4, 2] if reveal else [4]), "Надежда открывает именно просмотренную карту либо оставляет её закрытой")
		if not rules._effect_request.is_empty():
			_choose(rules, null)
		check(rules.phase == Rules.Phase.ACTION, "После Надежды начинается обычный ход")

func _combat(rules: RefCounted, attack: Dictionary, defense: Dictionary) -> void:
	rules.game.fighters[0][0].space = 13
	rules.game.fighters[1][0].space = 7
	rules.game.hands[0].push_front(attack)
	rules.game.hands[1].push_front(defense)
	check(rules.begin_attack(11, 0, 1, 0, attack.key), "Атака начата")
	var request: Dictionary = rules.attack_view(12).choice
	check(rules.choose_combat_card(12, {"request": request.id, "hand": 1, "cards": [defense.key]}), "Защита выбрана")
	check(rules.resolve_combat(), "Бой запущен")

func _reflect() -> void:
	var rules := _rules(["bloody_mary", "sun_wukong"])
	var attack: Dictionary = Catalog.deck_for("bloody_mary", 0)[4]
	var defense: Dictionary = Catalog.deck_for("sun_wukong", 1)[23]
	rules.game.hands[0] = []
	rules.game.hands[1] = []
	_combat(rules, attack, defense)
	check(rules.effect_view(12).options == ["reflect"], "Золотая кольчуга предлагает перенаправление")
	_choose(rules, "reflect")
	check(rules.last_combat.reflected and rules.game.fighters[1][0].health == 17,
		"Кольчуга перенаправляет урон и сохраняет здоровье Сунь Укуна")

func _robin() -> void:
	for discard in [false, true]:
		var rules := _rules(["robin_hood", "bloody_mary"])
		var before: int = rules.game.hands[0].size()
		var key: String = rules.game.hands[1][0].key
		rules.phase = Rules.Phase.EFFECT_CHOICE
		rules._scheme_choice(Vector2i(0, 0), {"steal_rich": true})
		_choose(rules, 1)
		check(rules.effect_view(12).get("labels", {}).get("draw") == "Робин Гуд берёт ещё 1 карту",
			"Воровство подписывает, кто получает карту")
		_choose(rules, "discard" if discard else "draw")
		if discard:
			_choose(rules, key)
		check(rules.game.hands[0].size() == before + (1 if discard else 2), "Обе ветки Воровства дают верный добор")

func _loki() -> void:
	var rules := _rules(["loki", "yennenga"])
	var attack: Dictionary = Catalog.deck_for("loki", 0)[22]
	var formation: Dictionary = Catalog.deck_for("yennenga", 1)[23]
	var feint: Dictionary = Catalog.deck_for("medusa", 1)[3]
	var discard: Dictionary = Catalog.deck_for("loki", 0)[0]
	rules.game.fighters[1][1].space = -1
	rules.game.fighters[1][1].health = 0
	rules.game.hands[0] = [discard]
	rules.game.hands[1] = [feint]
	_combat(rules, attack, formation)
	check(rules.effect_view(11).get("hand_discard", false), "Защитное построение первым предлагает Локи сбросить карту")
	check(formation not in rules.game.hands[1], "Исходная защита ещё не возвращена до её эффекта")
	_choose(rules, discard.key)
	check(rules.effect_view(11).prompt.begins_with("Поиск неприятностей") and formation in rules.game.hands[1],
		"После эффекта защиты Локи получает выбор с возвращённой картой")
	_choose(rules, feint.key)
	while not rules._effect_request.is_empty() and rules._effect_request.prompt == "Сколько урона перенести на лучника?":
		_choose(rules, 0)
	check(not rules.last_combat.attack_canceled and rules.last_combat.defense.key == feint.key,
		"Новая Уловка не запускает пропущенное Немедленно и не отменяет атаку")
	check(formation in rules.game.hands[1] and feint not in rules.game.hands[1] and rules.game.discards[1].back().key == feint.key,
		"Старая защита в руке, новая сброшена ровно один раз")
	rules = _rules(["loki", "yennenga"])
	var shift: Dictionary = Catalog.deck_for("yennenga", 1)[15]
	rules.game.fighters[1][1].space = -1
	rules.game.fighters[1][1].health = 0
	rules.game.hands[0] = []
	rules.game.hands[1] = [shift]
	_combat(rules, attack, formation)
	check(rules.effect_view(12).get("cells", false), "Без сброса Йенненга сначала выбирает клетку возврата лучника")
	var cell: int = rules.effect_view(12).options[0]
	_choose(rules, cell)
	check(rules._attack_pair[1] == Vector2i(1, 0) and rules.game.fighters[1][1].space == cell
		and rules.effect_view(11).prompt.begins_with("Поиск неприятностей"),
		"Лучник возвращён до выбора Локи, цель атаки остаётся Йенненгой")
	check(formation.key in rules.effect_view(11).options and shift.key in rules.effect_view(11).options,
		"Локи видит новую и возвращённую защиту")
	_choose(rules, formation.key)
	while not rules._effect_request.is_empty() and rules._effect_request.prompt == "Сколько урона перенести на лучника?":
		_choose(rules, 0)
	check(not rules.last_combat.is_empty() and rules.last_combat.defense.key == formation.key
		and shift in rules.game.hands[1], "Повторный выбор Построения не повторяет его Немедленно")
	rules = _rules(["loki", "medusa"])
	rules.game.hands[0] = []
	rules.game.hands[1] = []
	_combat(rules, attack, feint)
	check(rules._effect_request.is_empty() and rules.last_combat.attack_canceled,
		"Уловка первоначальной защиты отменяет Поиск неприятностей")
	rules = _rules(["loki", "achilles"])
	var helmet: Dictionary = Catalog.deck_for("achilles", 1)[22]
	rules.game.hands[0] = []
	rules.game.hands[1] = []
	rules.game.fighters[1][1].space = 30
	_combat(rules, attack, helmet)
	_choose(rules, Vector2i(1, 1))
	check(rules.last_combat.defense.is_empty() and rules.game.hands[1].size() == 1
		and rules.game.hands[1][0].key == helmet.key,
		"После обмена с Патроклом при отсутствии пригодной защиты шлем возвращён без дублирования")

func _defeated() -> void:
	for hero: String in ["sun_wukong", "pandora", "arthur"]:
		var rules := _rules([hero, "medusa"])
		rules.game.fighters[0][1].space = 20
		rules.game.fighters[0][1].health = 1
		rules._damage(Vector2i(0, 0), 100)
		rules._end_action()
		check(rules.phase == Rules.Phase.FINISHED and rules.winner == 1 and rules.game.fighters[0][1].space == 20,
			"Дуэль: %s проигрывает после гибели героя, живой помощник не спасает" % hero)
		var team := _rules([hero, "medusa", "robin_hood", "bigfoot"])
		team.game.fighters[0][1].space = 20
		team.game.fighters[0][1].health = 1
		team._damage(Vector2i(0, 0), 100)
		team._end_action()
		check(team.phase != Rules.Phase.FINISHED and team._has_fighters(0), "Команды: помощник %s остаётся в партии с живым союзным героем" % hero)
		team._damage(Vector2i(2, 0), 100)
		team._end_action()
		check(team.phase == Rules.Phase.FINISHED and team.winner == 1, "Оба героя команды погибли: помощники не предотвращают поражение")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
