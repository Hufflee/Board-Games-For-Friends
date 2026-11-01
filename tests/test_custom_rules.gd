extends SceneTree
## Ядро редактора: три JSON-игры, допустимые действия, приватность, ожидания и сторож. Запуск headless.

const Rules := preload("res://games/custom/logic/cg_rules.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
var checks := 0
var errors := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)

func example(name_value: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/%s.json" % name_value))
	return parsed if parsed is Dictionary else {}

func players(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"name": "Игрок %d" % (i + 1), "team": i % 2})
	return out

func start(data: Dictionary, n: int = 2, seed_value: int = 1) -> RefCounted:
	var r := Rules.new()
	check(r.load_definition(data).is_empty(), "Описание загружается: %s" % str(data.get("meta", {}).get("title")))
	check(r.new_game(players(n), {"seed": seed_value}).is_empty(), "Партия запускается: %s" % r.last_error)
	return r

func do_action(r: RefCounted, seat: int, action: Dictionary) -> bool:
	var data := action.duplicate(true)
	data.revision = r.state.revision
	return r.act(seat, str(data.get("kind", "button")), data)

func invariant(r: RefCounted) -> void:
	var all: Array = []
	for ids: Array in r.state.zones.values():
		for id: String in ids:
			check(r.state.cards.has(id) and not all.has(id), "Карта существует ровно в одной зоне")
			all.append(id)
	check(all.size() == r.state.cards.size(), "Карты не потеряны")
	var snapshot: Dictionary = r.save_state()
	var restored := Rules.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(snapshot))).is_empty(), "JSON-снимок восстанавливается")
	check(JSON.stringify(restored.state) == JSON.stringify(JSON.parse_string(JSON.stringify(r.state))), "Полное состояние после снимка совпадает")

func _init() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 42
	for name_value in ["card_race", "higher_lower", "dice_bid"]:
		var data := example(name_value)
		check(Definition.validate(data).errors.is_empty(), "Схема примера корректна")
		for n in [2, 4, 8]:
			for seed_value in range(8):
				var r := start(data, n, seed_value)
				var steps := 0
				while r.phase != "game_over" and steps < 200:
					steps += 1
					var legal: Array = r.legal_actions(int(r.state.current))
					check(not legal.is_empty(), "Есть допустимый ход")
					if legal.is_empty():
						break
					var picked: Dictionary = legal[random.randi_range(0, legal.size() - 1)]
					check(do_action(r, int(r.state.current), picked), "Допустимый ход выполнен: %s" % r.last_error)
					invariant(r)
				check(r.phase == "game_over" and not r.state.winners.is_empty(), "Пример доигран до победы")
	var data := example("card_race")
	var r := start(data)
	check(r.state.zones["hand@0"].size() == 3 and r.state.zones["hand@1"].size() == 3, "Раздача всем игрокам")
	var mine: Dictionary = r.get_view(0)
	var other: Dictionary = r.get_view(1)
	var spectator: Dictionary = r.get_view(-1)
	check(mine.zones["hand@0"][0].has("id"), "Своя рука содержит доступную карту")
	check(other.zones["hand@0"][0] == {"hidden": true}, "Чужая рука без id и данных вида")
	check(spectator.zones["hand@0"][0] == {"hidden": true}, "Зритель не знает руку")
	check(mine.zones.draw[0] == {"hidden": true}, "Порядок колоды скрыт")
	var before := JSON.stringify(r.save_state())
	check(not r.act(0, "button", {"id": "unknown", "revision": 0}), "Несуществующая кнопка отклоняется")
	check(not do_action(r, 1, {"kind": "card", "id": "play", "card": r.state.zones["hand@0"][0]}), "Нельзя играть чужую карту")
	check(before == JSON.stringify(r.save_state()), "Отклонённые действия не меняют состояние")
	var first: Dictionary = r.legal_actions(0)[0]
	check(do_action(r, 0, first), "Первый ход разрешён")
	check(not r.act(0, "card", {"id": "play", "card": first.card, "revision": 0}), "Старая ревизия отклоняется")
	var twin := start(data, 2, 1)
	check(twin.state.zones["hand@0"] == JSON.parse_string(before).state.zones["hand@0"], "Одинаковый seed даёт тот же расклад")
	# Пауза на выборе и сериализованное продолжение.
	data = example("card_race")
	data.rules.chains = [{"event": {"type": "start"}, "blocks": [
		{"op": "ask_number", "player": 1, "min": 2, "max": 9},
		{"op": "set", "var": "score", "player": 1, "value": {"op": "answer"}}, {"op": "win", "player": 1}]}]
	r = start(data)
	check(r.state.pending.kind == "ask_number", "Ожидание выбора сохранено")
	check(r.get_view(0).pending.is_empty() and not r.get_view(1).pending.is_empty(), "Ожидание видит только адресат")
	var resumed := Rules.new()
	check(resumed.restore(JSON.parse_string(JSON.stringify(r.save_state()))).is_empty(), "Продолжение загружено посреди ожидания")
	check(not do_action(resumed, 0, {"kind": "answer", "value": 4}), "Чужой ответ отклоняется")
	check(not do_action(resumed, 1, {"kind": "answer", "value": 10}), "Ответ вне диапазона отклоняется")
	check(do_action(resumed, 1, {"kind": "answer", "value": 7}), "Допустимый ответ возобновляет цепочку")
	check(resumed.get_var("score", 1) == 7 and resumed.phase == "game_over", "Ответ попал в следующий блок")
	data.rules.chains[0].blocks = [{"op": "wait", "seconds": 1.0}, {"op": "win", "player": "all"}]
	r = start(data)
	check(not r.tick(0.4) and r.phase != "game_over", "Ожидание не срабатывает раньше времени")
	check(r.tick(0.6) and r.phase == "game_over", "Ожидание возобновилось на хосте")
	# Результат жеста кубика клиентом не назначается.
	data.rules.chains[0].blocks = [{"op": "roll_player", "count": 3, "player": 1, "visible": "owner"}, {"op": "win", "player": 1}]
	r = start(data)
	check(do_action(r, 1, {"kind": "answer", "value": [99, 99, 99]}), "Жест броска принят")
	for face: int in r.state.dice["1"].values:
		check(face >= 1 and face <= 6, "Число кубика выбрал хост")
	check(r.get_view(0).dice["1"] == {"count": 3}, "Чужие закрытые кубики скрыты")
	# Краткий показ не открывает карту навсегда и не раскрывает приватную подсказку.
	data.rules.chains[0].blocks = [{"op": "show", "card": {"op": "top", "zone": "draw"}, "for": 0}, {"op": "hint", "player": 0, "text": "Только мне"}]
	r = start(data)
	check(r.get_view(0).zones.draw.back().has("id"), "Адресат видит временно показанную карту")
	check(r.get_view(1).zones.draw.back() == {"hidden": true}, "Краткий показ не раскрывает карту другим")
	check(r.get_view(0).show_cards.size() == 1 and r.get_view(1).show_cards.is_empty(), "Команда крупного показа приходит только адресату")
	check(r.get_view(0).hints == ["Только мне"] and r.get_view(1).hints.is_empty() and r.get_view(-1).log.is_empty(), "Подсказка видна только адресату")
	check(r.tick(2.0) and r.get_view(0).zones.draw.back() == {"hidden": true}, "Через две секунды карта снова скрыта")
	data.rules.chains[0].blocks = [{"op": "ask_card", "player": 1, "zone": "draw"}]
	r = Rules.new()
	check(r.load_definition(data).is_empty() and not r.new_game(players(2)).is_empty(), "Нельзя выбирать по id из закрытой колоды")
	data.rules.chains = [{"event": {"type": "start"}, "blocks": [{"op": "next"}]}, {"event": {"type": "turn_start"}, "blocks": [{"op": "set", "var": "score", "value": 11}]}]
	r = start(data)
	check(r.get_var("score", 1) == 11 and r.get_var("score", 0) == 0, "Событие начала хода выполняется от нового игрока")
	# Песочница: ходить можно без цепочек, доступ к чужой руке запрещён.
	data = example("card_race")
	data.rules.chains = []
	for item: Dictionary in data.layout.screens[0].items:
		if item.kind == "zone":
			item.free = true
	r = start(data)
	var choices: Array = r.legal_actions(0)
	var draw: Dictionary = {}
	for choice: Dictionary in choices:
		if choice.kind == "manual_move" and choice.to == "hand@0":
			draw = choice
		check(choice.get("to", "") != "hand@1", "Ручной режим не трогает чужую руку")
	check(not draw.is_empty() and draw.card == "", "Из закрытой колоды доступен только верх без id")
	check(do_action(r, 0, draw) and r.state.zones["hand@0"].size() == 1, "Песочница берёт верхнюю карту")
	# Перечисление UI не расходует RNG даже при случайном условии автора.
	data = example("card_race")
	data.rules.chains[1].guard = {"op": "gt", "a": {"op": "random", "a": 0, "b": 100}, "b": 30}
	r = start(data)
	var rng_before: int = r.rng.state
	r.get_view(0)
	r.get_view(1)
	check(rng_before == r.rng.state, "Просмотр и перечисление не расходуют RNG")
	# Ошибка после мутаций откатывает и карты, и генератор случайных чисел.
	data.rules.chains[1].erase("guard")
	data.rules.chains[1].blocks = [{"op": "shuffle", "zone": "draw"}, {"op": "move", "card": {"op": "card"}, "to": "table"}, {"op": "change", "var": "score", "value": {"op": "div", "a": 1, "b": 0}}]
	r = start(data)
	before = JSON.stringify(r.save_state())
	check(not do_action(r, 0, r.legal_actions(0)[0]), "Деление на ноль прекращает действие")
	check(before == JSON.stringify(r.save_state()), "Ошибка полностью откатывает действие и RNG")
	# Ошибочный тип не должен доходить до встроенного int() и ронять скрипт.
	for bad_number: Variant in ["не число", [], {"op": "literal", "value": {}}, null, true]:
		data.rules.chains = [{"event": {"type": "start"}, "blocks": [{"op": "roll", "count": bad_number}]}]
		r = Rules.new()
		check(r.load_definition(data).is_empty() and not r.new_game(players(2)).is_empty(), "Ошибочное числовое гнездо отклоняется")
	data.rules.chains = [{"event": {"type": "start"}, "blocks": [{"op": "phase", "phase": "turn"}]}, {"event": {"type": "phase_enter"}, "blocks": [{"op": "phase", "phase": "turn"}]}]
	r = Rules.new()
	check(r.load_definition(data).is_empty() and not r.new_game(players(2)).is_empty(), "Рекурсивные события остановлены сторожем глубины")
	data.rules.chains = [{"event": {"type": "start"}, "blocks": [{"op": "repeat", "count": 1000, "body": [{"op": "repeat", "count": 1000, "body": [{"op": "log", "text": "шаг"}]}]}]}]
	r = Rules.new()
	check(r.load_definition(data).is_empty() and not r.new_game(players(2)).is_empty(), "Сторож 10000 шагов останавливает вложенные циклы")
	# Событие броска получает хостовый результат; таймер вызывает только хост.
	data = example("card_race")
	data.rules.chains = [{"event": {"type": "start"}, "blocks": [{"op": "roll_player", "player": 1, "count": 2}]}, {"event": {"type": "rolled"}, "blocks": [{"op": "set", "var": "score", "value": {"op": "dice_sum", "player": {"op": "actor"}}}]}]
	r = start(data)
	check(do_action(r, 1, {"kind": "answer", "value": [99, 99]}), "Жест возобновил событие броска")
	check(r.get_var("score", 1) >= 2 and r.get_var("score", 1) <= 12, "Событие броска выполняется от бросавшего с хостовыми числами")
	data.rules.chains = [{"event": {"type": "timeout"}, "blocks": [{"op": "next"}]}]
	r = Rules.new()
	check(r.load_definition(data).is_empty() and r.new_game(players(3), {"turn_time": 1}).is_empty(), "Таймер хода включён")
	check(r.legal_actions(0).is_empty() and not r.act(0, "timeout", {"revision": 0}), "Клиент не может вызвать таймаут")
	check(not r.tick(0.4) and r.state.current == 0, "Таймер не сработал раньше времени")
	check(r.tick(0.6) and r.state.current == 1 and r.state.timer_left == 1.0, "Хост вызвал таймаут и сбросил часы нового хода")
	data.rules.chains = [{"event": {"type": "start"}, "blocks": [{"op": "skip", "player": 1}, {"op": "next"}]}]
	r = start(data, 3)
	check(r.state.current == 2 and r.state.skips.is_empty(), "Будущий ход пропущен один раз")
	data.rules.chains = [{"event": {"type": "button", "id": "role", "by": "role:author"}, "blocks": []}]
	r = Rules.new()
	check(r.load_definition(data).is_empty(), "Шапка роли загружается")
	var seats := players(2)
	seats[1].role = "author"
	check(r.new_game(seats).is_empty() and r.legal_actions(0).is_empty() and r.legal_actions(1).size() == 1, "Шапка роли разрешает действие только её владельцу")
	data = example("card_race")
	data.rules.chains = []
	data.elements.decks = []
	data.elements.dice = [{"id": "dice", "count": 4, "free": true, "visible": "owner"}]
	data.elements.tokens = [{"id": "chips", "count": 3, "value": 5, "zone": "table"}]
	data.rules.vars = [{"id": "money", "scope": "player", "type": "number", "init": 0, "free": true}]
	for item: Dictionary in data.layout.screens[0].items:
		if item.kind == "zone":
			item.free = true
	r = start(data)
	check(r.state.cards.size() == 3 and r.get_view(0).zones.table[0].data.kind == "token", "Жетоны созданы как публичные компоненты")
	check(do_action(r, 0, {"kind": "manual_resource", "id": "money", "delta": 1}), "Ресурс изменён вручную")
	check(r.get_var("money", 0) == 1 and r.get_var("money", 1) == 0, "Ручной ресурс относится к своему месту")
	check(not do_action(r, 0, {"kind": "manual_resource", "id": "money", "delta": 999}), "Подменённое изменение ресурса запрещено")
	for malformed: Variant in [[], {}, true, null]:
		check(not r.act(0, "manual_resource", {"id": malformed, "delta": 1, "revision": r.state.revision}), "Плохой тип идентификатора действия отклоняется без ошибки скрипта")
	check(do_action(r, 0, {"kind": "manual_roll", "id": "dice", "count": 999}), "Свободный набор запрашивает жест")
	check(r.state.pending.count == 4, "Количество кубиков берётся из определения, не от клиента")
	check(do_action(r, 0, {"kind": "answer", "value": [99]}), "Жест свободных кубиков подтверждён")
	check(r.state.dice["0"].values.size() == 4 and r.get_view(1).dice["0"] == {"count": 4}, "Результат закрытого набора приватен")
	data = example("card_race")
	data.rules.chains = [{"event": {"type": "start"}, "blocks": [{"op": "log", "text": "Начало"}, {"op": "wait", "seconds": 1}]}, {"event": {"type": "round_start"}, "blocks": [{"op": "log", "text": "Раунд"}]}, {"event": {"type": "turn_start"}, "blocks": [{"op": "log", "text": "Ход"}]}]
	r = start(data)
	check(r.state.log == ["Начало"], "Начало раунда/хода ждёт завершения подготовки")
	resumed = Rules.new()
	check(resumed.restore(JSON.parse_string(JSON.stringify(r.save_state()))).is_empty(), "Начальные события сохраняются в продолжении")
	check(resumed.tick(1.0) and resumed.state.log == ["Начало", "Раунд", "Ход"], "После ожидания события идут в порядке игра→раунд→ход")
	var damaged: Dictionary = r.save_state().duplicate(true)
	damaged.state.pending.frames[0].context.actor = {}
	check(not resumed.restore(damaged).is_empty(), "Повреждённый контекст снимка отклоняется")
	damaged = r.save_state().duplicate(true)
	damaged.state.vars.player = "не массив"
	check(not resumed.restore(damaged).is_empty(), "Повреждённые личные переменные отклоняются")
	damaged = r.save_state().duplicate(true)
	damaged.state.rng_state = "99999999999999999999"
	check(not resumed.restore(damaged).is_empty(), "Переполнение RNG в снимке отклоняется без приведения")
	damaged = r.save_state().duplicate(true)
	damaged.state.cards[damaged.state.cards.keys()[0]].face_up = "да"
	check(not resumed.restore(damaged).is_empty(), "Неверный тип стороны карты отклоняется")
	data = example("card_race")
	r = Rules.new()
	var steam_seats := players(2)
	steam_seats[0].steam_id = 76561198012345678
	check(r.load_definition(data).is_empty() and r.new_game(steam_seats).is_empty(), "Партия с64-битным SteamID начата")
	resumed = Rules.new()
	check(resumed.restore(JSON.parse_string(JSON.stringify(r.save_state()))).is_empty() and resumed.players[0].steam_id == "76561198012345678", "SteamID сохраняет все цифры после JSON")
	# Ограничение циклов и запрет пользовательского кода.
	data = example("card_race")
	data.rules.chains[0].blocks = [{"op": "repeat", "count": 1001, "body": []}]
	r = Rules.new()
	check(r.load_definition(data).is_empty() and not r.new_game(players(2)).is_empty(), "Сторож останавливает 1001 повтор")
	data.rules.chains[0].blocks = [{"op": "execute_gdscript", "code": "quit()"}]
	check(not Definition.validate(data).errors.is_empty(), "Неизвестный исполняемый блок запрещён")
	data = example("card_race")
	data["bad"] = RefCounted.new()
	check(not Definition.validate(data).errors.is_empty(), "Объекты ресурсов не принимаются как JSON")
	print("CUSTOM_RULES: %d проверок, ошибок %d" % [checks, errors])
	quit(1 if errors else 0)
