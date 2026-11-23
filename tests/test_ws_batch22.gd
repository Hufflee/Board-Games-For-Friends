extends SceneTree
## Словарь ответов, круги рассказчиков, подставки 4×4 и прокрутка каталога «Ворд Слэма».
## godot --headless --audio-driver Dummy --path . --script res://tests/test_ws_batch22.gd

const PLAYERS := [
	{"name": "Аня", "team": 0}, {"name": "Боря", "team": 1},
	{"name": "Вера", "team": 0}, {"name": "Глеб", "team": 1},
	{"name": "Даша", "team": 0}, {"name": "Егор", "team": 1},
]

var checks := 0
var failures := 0


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	_check_dictionaries()
	_check_storytellers()
	_check_simplified_replacement()
	await _check_table()
	print("ВОРД СЛЭМ 22.11: %d проверок, %d ошибок" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_simplified_replacement() -> void:
	var rules := WSRules.new()
	rules.new_game(PLAYERS, true, 3, false, false, 22, "simplified")
	rules.word = "игра"
	rules._fix_catalog()
	_check(not rules.catalog_order.noun.has("noun:49"), "Однокоренная текущему ответу подсказка скрыта")
	rules.word = "город"
	rules._fix_catalog()
	_check(rules.catalog_order.noun.has("noun:49"), "Подсказка прошлого ответа возвращается после смены слова")
	_check(not rules.catalog_order.noun.has("noun:29"), "Фильтр относится только к новому ответу")


func _check_dictionaries() -> void:
	var shared := SharedWords.all()
	var standard := WSRules.new()
	standard.new_game(PLAYERS, true, 21, false, false, 21)
	_check(standard.answer_dictionary == "shared" and shared.has(standard.word), "По умолчанию используется общий словарь")
	var simple := WSRules.new()
	var simple_catalog := WSRules.new()
	simple.new_game(PLAYERS, true, 21, false, false, 21, "basic", "simple")
	simple_catalog.new_game(PLAYERS, true, 21, false, false, 21, "simplified", "simple")
	_check(simple.deck == simple_catalog.deck and simple.card == simple_catalog.card, "Режим подсказок не меняет колоду ответов")
	var seen := {}
	for card: Dictionary in simple.deck + [simple.card]:
		var answer: String = card["words"][0]
		_check(IBSWords.SIMPLE.has(answer) and not seen.has(answer), "Колода из простых слов собрана без повторов")
		seen[answer] = true
	_check(simple.get_view(simple.drawer())["answer_dictionary"] == "simple", "Выбранный словарь передаётся игрокам")
	for rules: WSRules in [simple, simple_catalog]:
		var previous := rules.word
		_check(rules.vote_skip(rules.drawer()) and rules.word != previous and IBSWords.SIMPLE.has(rules.word), "После голосования приходит другое простое слово")
		_check(rules.host_new_theme() and IBSWords.SIMPLE.has(rules.word), "Хост берёт простое слово из колоды")
		rules.deck.clear()
		previous = rules.word
		_check(rules.host_new_theme() and rules.word != previous and IBSWords.SIMPLE.has(rules.word), "Хост берёт другое простое слово при пустой колоде")
		rules.set_ready(rules.drawer())
		rules.time_up()
		rules.advance()
		_check(rules.tiebreak and IBSWords.SIMPLE.has(rules.word), "Дополнительная карта берётся из простого словаря")


func _check_storytellers() -> void:
	for solo: bool in [true, false]:
		var first_by_seed := {}
		for seed_value: int in [3, 17, 91, 103, 210, 221]:
			var rules := WSRules.new()
			rules.new_game(PLAYERS, solo, 25, false, false, seed_value)
			first_by_seed[rules.storytellers[0]] = true
			for cycle in 2:
				var told := [[], []]
				for turn in (6 if solo else 3):
					for side in rules.storytellers.size():
						var seat: int = rules.storytellers[side]
						_check(not told[side].has(seat), "В каждом круге рассказчик выступает по одному разу")
						told[side].append(seat)
						rules.set_ready(seat)
					rules.time_up()
					rules.advance()
		_check(first_by_seed.size() > 1, "Выбор первого рассказчика зависит от случайной последовательности")


func _check_table() -> void:
	root.size = Vector2i(1280, 720)
	var table: Control = load("res://games/word_slam/ui/ws_table.gd").new()
	root.add_child(table)
	var rules := WSRules.new()
	var initial := {}
	var changed_seed := 0
	for seed_value in range(1, 200):
		rules.new_game(PLAYERS, true, 21, false, false, seed_value, "basic", "simple")
		initial = rules.get_view(rules.drawer(), true)
		rules.vote_skip(rules.drawer())
		if rules.catalog_order != initial["catalog_order"]:
			changed_seed = seed_value
			break
	_check(changed_seed != 0, "Найдена смена слова с заменой однокоренной подсказки")
	if changed_seed == 0:
		table.queue_free()
		return
	table._on_state(initial)
	await _settle()
	_check_catalog(table, initial["catalog_order"])
	var offsets := {}
	var scrolled_categories := 0
	for cat: String in WSData.CATEGORIES:
		var flow: HFlowContainer = table._catalog_flows[cat]
		var scroll := flow.get_parent() as ScrollContainer
		scroll.scroll_vertical = 8 + offsets.size() * 7
		offsets[cat] = scroll.scroll_vertical
		if scroll.scroll_vertical > 0:
			scrolled_categories += 1
	_check(scrolled_categories > 1, "Позиции прокрутки проверяются в нескольких категориях")
	table._on_state(rules.get_view(rules.drawer(), true))
	await _settle()
	_check(rules.phase == "word", "Состав обновляется уже в фазе просмотра")
	_check_catalog(table, rules.catalog_order)
	_check_offsets(table, offsets)
	var before := rules.catalog_order.duplicate(true)
	rules.set_ready(rules.drawer())
	table._on_state(rules.get_view(rules.drawer(), true))
	await _settle()
	_check_catalog(table, rules.catalog_order)
	_check_offsets(table, offsets)
	for cat: String in WSData.CATEGORIES:
		var old: Array = before[cat].duplicate()
		var current: Array = rules.catalog_order[cat].duplicate()
		_check(old != current, "При старте меняется порядок категории «%s»" % cat)
		old.sort()
		current.sort()
		_check(old == current, "При старте сохраняется состав категории «%s»" % cat)
		await _check_catalog_scroll_range(table._catalog_flows[cat])
		var flow: HFlowContainer = table._catalog_flows[cat]
		(flow.get_parent() as ScrollContainer).scroll_vertical = offsets[cat]

	table._as = (rules.drawer() + 1) % PLAYERS.size()
	table._on_state(rules.get_view(rules.drawer(), true))
	await _settle()
	_check(not table._catalog_cols.visible and table._guess_edit != null, "Отгадывающий видит поле догадки")
	table._as = rules.drawer()
	table._on_state(rules.get_view(rules.drawer(), true))
	await _settle()
	_check(table._catalog_cols.visible, "При возвращении рассказчика снова виден каталог")
	_check_offsets(table, offsets)
	_check_holders(table, rules)
	await _settle()
	table.queue_free()


func _settle() -> void:
	for frame in 4:
		await process_frame


func _check_catalog(table: Control, expected: Dictionary) -> void:
	for cat: String in WSData.CATEGORIES:
		var ids := []
		var flow: HFlowContainer = table._catalog_flows[cat]
		for button: Button in flow.get_children():
			ids.append(button.get_meta("clue_id"))
		_check(ids == expected[cat], "На экране полный состав и нужный порядок категории «%s»" % cat)


func _check_offsets(table: Control, offsets: Dictionary) -> void:
	for cat: String in WSData.CATEGORIES:
		var flow: HFlowContainer = table._catalog_flows[cat]
		var scroll := flow.get_parent() as ScrollContainer
		_check(scroll.scroll_vertical == offsets[cat], "Прокрутка категории «%s» сохранилась" % cat)


func _check_catalog_scroll_range(flow: HFlowContainer) -> void:
	var scroll := flow.get_parent() as ScrollContainer
	var bar := scroll.get_v_scroll_bar()
	var all_reachable := true
	for button: Button in flow.get_children():
		scroll.scroll_vertical = roundi(button.position.y)
		await process_frame
		var visible := scroll.get_global_rect()
		visible.size.x -= bar.size.x if bar.visible else 0.0
		all_reachable = all_reachable and visible.grow(1.0).encloses(button.get_global_rect())
	_check(all_reachable, "Каждая подсказка целиком видна при прокрутке категории")


func _check_holders(table: Control, rules: WSRules) -> void:
	var ids: Array = rules.catalog_order["noun"].slice(0, 16)
	_check(rules.set_holders(rules.drawer(), [ids, []]), "Хост принимает все шестнадцать карт подставки")
	var overflow: Array = ids + [rules.catalog_order["noun"][16]]
	_check(not rules.set_holders(rules.drawer(), [overflow, []]), "Хост отклоняет семнадцатую карту")
	table._on_state(rules.get_view(rules.drawer(), true))
	var unique_rows := {}
	var unique_cols := {}
	var shelf_area := Rect2(Vector2.ZERO, Vector2(table._shelves.size.x / 2.0, table._shelves.size.y))
	for index in ids.size():
		var slot: Vector2 = table._slot(0, index)
		var card: Control = table._cards.get("0|" + ids[index])
		unique_rows[slot.y] = true
		unique_cols[slot.x] = true
		_check(table._where(slot) == [0, index], "Зона броска соответствует ячейке %d" % index)
		_check(card != null and shelf_area.encloses(Rect2(slot - card.size / 2.0, card.size)), "Карточка %d целиком в пределах подставки" % index)
	_check(unique_rows.size() == 4 and unique_cols.size() == 4, "Все карточки разложены по сетке 4×4")
