extends SceneTree
## Сеансы Unmatched: приватность Net и фазз из разрешённых действий. UM_GAMES задаёт число партий.

const Match := preload("res://games/unmatched/logic/um_match.gd")
const Rules := preload("res://games/unmatched/logic/um_rules.gd")
const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")

var errors := 0
var checks := 0
var rng := RandomNumberGenerator.new()
var played := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _local()
	_local_teams()
	await _local_draft()
	_combat_timing()
	var count := maxi(1, int(OS.get_environment("UM_GAMES"))) if OS.has_environment("UM_GAMES") else 24
	for seed_value in count:
		_fuzz(seed_value)
	if count >= 80:
		for hero: String in Roster.HEROES:
			for item: Array in Catalog.DECKS[hero]:
				var id := "%s:%02d" % [hero, item[0]]
				check(played.has(id), "Фазз разыграл %s" % id)
	print("Unmatched, партии: %d, сыгранных определений: %d, проверок: %d, ошибок: %d." % [count, played.size(), checks, errors])
	quit(int(errors > 0))


func _combat_timing() -> void:
	var match_game: RefCounted = Match.create("marmoreal", ["bloody_mary", "sun_wukong"], [{"name": "А"}, {"name": "Б"}], 14)
	var attack := Catalog.deck_for("bloody_mary", 0)[2]
	var discarded := Catalog.deck_for("sun_wukong", 1)[2]
	match_game.game.fighters[0][0].space = 4
	match_game.game.fighters[1][0].space = 5
	match_game.game.hands[0] = [attack]
	match_game.game.hands[1] = [discarded]
	check(match_game.act(0, "attack", {"fighter": 0, "target": Vector2i(1, 0), "key": attack.key}), "Объявлена атака с эффектом «Во время боя»")
	var request: Dictionary = match_game.get_view(1).hand.choice
	check(match_game.act(1, "combat", {"request": request.get("id", -1), "hand": 1, "cards": []}), "Защитник пропускает выбор карты")
	check(not match_game.tick(Match.REVEAL_SECONDS - 0.1) and match_game.game.discards[1].is_empty(), "Во время чтения карта ещё не сброшена")
	match_game.tick(0.11)
	var beat: Dictionary = match_game.get_view(-1).combat
	var events: Array = beat.get("during", [])
	check(events.size() == 1 and events[0].values[0] == attack.value + discarded.boost
		and match_game.game.discards[1].size() == 1, "Хост публикует сработавший эффект и изменённое значение")
	var hp: int = match_game.game.fighters[1][0].health
	check(not match_game.tick(Match.DURING_SECONDS + Match.BEFORE_IMPACT_SECONDS - 0.1)
		and match_game.game.fighters[1][0].health == hp, "Урон ждёт анимацию и двухсекундную паузу")
	check(match_game.tick(0.11) and match_game.game.fighters[1][0].health < hp, "После паузы хост применяет боевой урон")
	match_game.close()


func _local() -> void:
	var net := root.get_node("Net")
	net.host_offline("unmatched")
	net.set_setting("um_heroes", ["bloody_mary", "sun_wukong"])
	net.set_unmatched_hero(0, "achilles")
	check(net.settings.um_heroes == ["achilles", "sun_wukong"], "В свободном режиме участник меняет героя до старта")
	net.set_unmatched_hero(1, "achilles")
	check(net.settings.um_heroes == ["achilles", "sun_wukong"], "Один герой не может занять два места")
	net.set_unmatched_hero(0, "bloody_mary")
	net.set_setting("um_arena", OS.get_environment("UM_MATCH_ARENA") if OS.has_environment("UM_MATCH_ARENA") else "marmoreal")
	var app: Control = load("res://games/unmatched/ui/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var why: String = net.start_game()
	check(why.is_empty(), "Запуск через Net: %s" % why)
	if not why.is_empty():
		app.queue_free()
		net.leave()
		return
	check(net.view.handoff and net.view.hand.cards.is_empty(), "Перед передачей компьютер скрывает руку")
	net.send_action("maneuver", {})
	check(net.unmatched.rules.actions_left == 2, "До передачи нельзя выполнять действия")
	net.send_action("handoff", {})
	check(net.view.viewer == 0 and net.view.hand.cards.size() == 5, "Мэри видит только свою руку")
	var table: Control = app.get("_screen")
	check(table._hand._fan.order.size() == 5, "Компактный веер показывает пять настоящих карт")
	if not DisplayServer.get_name() == "headless" and OS.has_environment("UM_MATCH_SHOTS"):
		await _capture(table)
	check(net._seat_view(-1, [], 0, false).hand.cards.is_empty(), "Зритель не получает частную руку")
	for i in 2:
		net.send_action("maneuver", {})
		net.send_action("end_maneuver", {})
	check(net.view.handoff and net.view.actor == 1 and net.view.hand.cards.is_empty(), "При смене хода прежняя рука скрывается")
	net.send_action("handoff", {})
	check(net.view.hand.hand == 1 and net.view.hand.cards.size() == 5, "Второй контроллер видит только свою руку")
	check(net.view.piles.size() == 2 and net.view.piles[0].deck_count == 23, "Соперник видит счётчики обеих колод")
	net.end_game()
	check(net.unmatched == null and not net.in_game, "Возврат в лобби очищает правила")
	app.queue_free()
	await process_frame
	net.leave()


func _capture(table: Control) -> void:
	root.size = Vector2i(1280, 720)
	var prefs := root.get_node("Prefs")
	var folder := ProjectSettings.globalize_path("res://build/shots/unmatched_match")
	DirAccess.make_dir_recursive_absolute(folder)
	for theme_mode: String in ["light", "dark"]:
		prefs.theme_mode = theme_mode
		table.present(table._state)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := "%s/%s_%s.png" % [folder, table._state.arena, theme_mode]
		check(image != null and image.save_png(path) == OK, "Кадр %s записан" % theme_mode)
		check(table._actions.get_global_rect().end.x < 1280 and table._board.size.y > 200, "Управление и поле помещаются при 1280×720")


func _local_teams() -> void:
	var net := root.get_node("Net")
	for players in [3, 4]:
		net.host_offline("unmatched")
		net.set_bots(players - 1)
		net.set_setting("um_heroes", ["medusa", "arthur", "yennenga", "achilles"])
		var error: String = net.start_game()
		check(error.is_empty(), "Командный запуск для %d контроллеров" % players)
		if not error.is_empty():
			continue
		var switched := false
		for i in 7:
			if net.view.handoff:
				net.send_action("handoff", {})
			var placement: Dictionary = net.view.setup
			if placement.get("cells", []).is_empty():
				check(false, "Хост прислал допустимые клетки помощника")
				break
			if players == 3 and placement.seat == 1 and not switched:
				check(net.view.hand.owned == [1, 3], "У одного контроллера две руки своей команды")
				net.send_action("view_hand", {"seat": 0})
				check(net.view.hand.hand == 1, "Чужую руку открыть нельзя")
				net.send_action("view_hand", {"seat": 3})
				check(net.view.hand.hand == 3 and net.view.setup.seat == 1, "Рука переключается отдельно от места расстановки")
				switched = true
			net.send_action("place", {"cell": placement.cells[0]})
		check(net.unmatched.game.pending().is_empty(), "Командное поле расставлено")
		net.end_game()
		net.leave()


func _local_draft() -> void:
	var net := root.get_node("Net")
	net.host_offline("unmatched")
	net.set_setting("um_hero_mode", "pick3")
	var app: Control = load("res://games/unmatched/ui/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var shots := DisplayServer.get_name() != "headless" and OS.has_environment("UM_MATCH_SHOTS")
	if shots:
		await _named_capture("lobby")
	check(net.start_game().is_empty(), "Стартовый выбор из трёх открывается")
	check(net.view.handoff and net.view.draft.offers.is_empty(), "Варианты закрыты до передачи экрана")
	net.send_action("handoff", {})
	var choices: Array = net.view.draft.offers
	var table: Control = app.get("_screen")
	check(choices.size() == 3 and table._hero_choice._tiles.size() == 3, "Три карточки доступны текущему игроку")
	check(net.view.fighters.is_empty() and table._board._figures.is_empty() and net.view.hand.cards.is_empty(),
		"До выбора экран не показывает предварительные фигуры и руки: проекция %d, поле %d, рука %d"
		% [net.view.fighters.size(), table._board._figures.size(), net.view.hand.cards.size()])
	if shots:
		await _named_capture("hero_choice")
	if choices.size() == 3:
		table._hero_choice._tiles[0].pressed.emit()
		check(net.view.handoff and net.view.draft.offers.is_empty(), "После выбора экран передаётся сопернику")
		net.send_action("handoff", {})
		var next: Array = net.view.draft.offers
		check(next.size() == 3 and choices[0] not in next, "Выбранный герой исключён из следующего предложения")
		if not next.is_empty():
			net.send_action("draft_hero", {"hero": next[0]})
			check(net.unmatched.game.heroes == PackedStringArray([choices[0], next[0]]), "Герои назначены отдельным местам до раздачи")
	net.end_game()
	app.queue_free()
	await process_frame
	net.leave()
	var participants := [{"name": "А"}, {"name": "Б"}]
	var pair: RefCounted = Match.create("marmoreal", [], participants, 15, "pick2")
	check(pair.get_view(0).draft.offers.size() == 2 and pair.get_view(1).draft.offers.is_empty(), "Выбор из двух приватен")
	check(not pair.act(1, "draft_hero", {"hero": pair.get_view(0).draft.offers[0]}), "Хост проверяет владельца выбора")
	pair.close()
	var random_game: RefCounted = Match.create("marmoreal", [], participants, 15, "random")
	check(random_game.game.heroes[0] != random_game.game.heroes[1] and not random_game.get_view(0).has("draft"),
		"Случайный режим раздаёт разных героев без экрана выбора")
	random_game.close()


func _named_capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://build/shots/unmatched_match")
	DirAccess.make_dir_recursive_absolute(folder)
	var image := root.get_texture().get_image()
	check(image != null and image.save_png("%s/%s.png" % [folder, name]) == OK, "Кадр %s сохранён" % name)


func _fuzz(seed_value: int) -> void:
	rng.seed = seed_value
	var heroes: Array = Roster.HEROES.keys()
	for index in range(heroes.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var saved: String = heroes[index]
		heroes[index] = heroes[other]
		heroes[other] = saved
	var total := 2 + seed_value % 3
	var players: Array = []
	for person in total:
		players.append({"name": "Игрок %d" % person})
	var arena: String = ["marmoreal", "sarpedon", "gardens"][floori(seed_value / 3.0) % 3]
	var match_game: RefCounted = Match.create(arena, PackedStringArray(heroes.slice(0, 2 if total == 2 else 4)), players, seed_value)
	if match_game == null:
		check(false, "Создание партии %d" % seed_value)
		return
	for step in 800:
		if match_game.rules.phase == Rules.Phase.FINISHED:
			for place in match_game.game.heroes.size():
				var cards: Array = match_game.game.hands[place] + match_game.game.decks[place] + match_game.game.discards[place]
				var keys := {}
				for card: Dictionary in cards:
					keys[card.key] = true
				check(cards.size() == 30 and keys.size() == 30, "У каждого героя 30 уникальных экземпляров")
			check(true, "Партия %d дошла до победы за %d действий" % [seed_value, step])
			var final: Dictionary = preload("res://hub/victory_result.gd").resolve("unmatched", match_game.get_view(-1))
			check(final.finished and not final.winners.is_empty(), "Финал показывает победителей")
			return
		if match_game.rules.pending_impact.is_valid() or match_game.rules.combat_pause > 0.0:
			match_game.tick(10.0)
			continue
		if match_game.rules.phase == Rules.Phase.COMBAT_REVEAL:
			var cards: Dictionary = match_game.rules.attack_view(-1).cards
			for name: String in ["attack", "defense"]:
				if not cards[name].is_empty():
					played[cards[name].definition] = true
			if match_game.tick(Match.REVEAL_SECONDS):
				continue
			check(false, "Партия %d: раскрытые карты не разрешились %s" % [seed_value, cards])
			return
		var actor: int = match_game.actor()
		var view: Dictionary = match_game.get_view(actor)
		var commands := _commands(view)
		if commands.is_empty():
			check(false, "Партия %d: нет действий в фазе %s" % [seed_value, view.phase])
			return
		var action: Array = commands[rng.randi_range(0, commands.size() - 1)]
		if not match_game.act(actor, action[0], action[1]):
			check(false, "Партия %d: отклонён разрешённый ход %s %s" % [seed_value, view.phase, action])
			return
		if action[0] == "scheme":
			for card: Dictionary in view.hand.cards:
				if card.key == action[1].key:
					played[card.definition] = true
	check(false, "Партия %d не завершилась за 800 действий" % seed_value)


func _commands(view: Dictionary) -> Array:
	var effect: Dictionary = view.effect
	if not effect.is_empty():
		var args: Array = effect.options.map(func(answer: Variant) -> Array: return ["effect", {"request": effect.id, "answer": answer}])
		if effect.optional:
			args.append(["effect", {"request": effect.id, "answer": null}])
		return args
	var setup: Dictionary = view.setup
	if not setup.is_empty():
		if setup.get("choose_size", false):
			return [["size", {"large": true}], ["size", {"large": false}]]
		return Array(setup.cells).map(func(cell: int) -> Array: return ["place", {"cell": cell}])
	var hand: Dictionary = view.hand
	var request: Dictionary = hand.choice
	if not request.is_empty():
		var args: Array = request.allowed.map(func(key: String) -> Array: return ["combat", {"request": request.id, "hand": hand.hand, "cards": [key]}])
		if request.min == 0:
			args.append(["combat", {"request": request.id, "hand": hand.hand, "cards": []}])
		return args
	match view.phase_id:
		Rules.Phase.ACTION:
			var args: Array = [["maneuver", {}]]
			for fighter: int in view.attacks:
				for figure: Dictionary in view.fighters:
					if figure.cell in view.attacks[fighter]:
						args.append(["attack", {"fighter": fighter, "target": Vector2i(figure.seat, figure.fighter)}])
				for card: Dictionary in view.schemes[fighter]:
					args.append(["scheme", {"fighter": fighter, "key": card.key}])
			return args
		Rules.Phase.MANEUVER:
			var args: Array = [["end_maneuver", {}]]
			for fighter: int in view.moves:
				for cell: int in view.moves[fighter]:
					args.append(["move", {"fighter": fighter, "cell": cell}])
			if view.boost_allowed:
				for card: Dictionary in hand.cards:
					if card.boost >= 0:
						args.append(["boost", {"key": card.key}])
			return args
		Rules.Phase.DISCARD:
			return hand.cards.map(func(card: Dictionary) -> Array: return ["discard", {"key": card.key}])
	return []


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		errors += 1
		push_error(message)
