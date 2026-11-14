extends SceneTree
## Шаблоны редактора (ТЗ 3.5): раскладки стола переставляют элементы, сохраняя ссылки колод/правил на зоны,
## недостающее добавляют, проект остаётся без ошибок и без перекрытий; плитки готовых фонов бесшовные.
## Запуск: APPDATA=<папка в build> godot --headless --audio-driver Dummy --path . --script res://tests/test_editor_templates.gd
const Definition := preload("res://games/custom/logic/cg_def.gd")
const Templates := preload("res://editor/ed_templates.gd")
var checks := 0
var errors := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func example() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/card_race.json"))

func _run() -> void:
	# Сами шаблоны: внутри стола, без перекрытий, одна главная кнопка.
	for template: Dictionary in Templates.LAYOUTS:
		var items: Array = []
		for slot: Dictionary in template.slots:
			items.append(slot.duplicate(true))
		var found: Dictionary = Definition.layout_conflicts(items)
		check(found.bad.is_empty(), "Шаблон «%s» без перекрытий и выхода за стол: %s %s" % [template.title, str(found.pairs), str(found.outside)])
		check(found.mains.size() == 1, "В шаблоне «%s» одна главная кнопка" % template.title)
	# Применение к проекту: зоны колоды сохраняются, ошибок нет.
	for template: Dictionary in Templates.LAYOUTS:
		var data := example()
		var before: Array = data.layout.screens[0].items.map(func(item: Dictionary): return str(item.id))
		var result: Dictionary = Templates.apply_layout(data, str(template.id))
		var ids: Array = result.layout.screens[0].items.map(func(item: Dictionary): return str(item.get("id", "")))
		check(before.all(func(id: String): return ids.has(id)), "«%s»: прежние элементы на месте (ссылки целы)" % template.title)
		var report: Dictionary = Definition.validate(result)
		check(report.errors.is_empty(), "«%s»: проект без ошибок: %s" % [template.title, str(report.errors)])
		check(result.layout.custom == true, "«%s»: раскладка помечена своей" % template.title)
		check(data.layout.screens[0].items.size() == before.size(), "Исходные данные не изменены")
		var left: Dictionary = Definition.layout_conflicts(result.layout.screens[0].items)
		check(left.pairs.is_empty() and left.outside.is_empty(), "«%s»: после применения нет перекрытий: %s" % [template.title, str(left.pairs)])
	var cards: Dictionary = Templates.apply_layout(example(), "cards")
	var hand: Dictionary = cards.layout.screens[0].items.filter(func(item: Dictionary): return item.get("id") == "hand")[0]
	check(hand.rect == [208, 424, 864, 200], "Рука встала на место руки шаблона: %s" % str(hand.get("rect")))
	var draw: Dictionary = cards.layout.screens[0].items.filter(func(item: Dictionary): return item.get("id") == "draw")[0]
	check(draw.rect == [384, 176, 184, 216], "Колода встала в слот колоды")
	var conflicts: Dictionary = Definition.layout_conflicts(cards.layout.screens[0].items)
	check(conflicts.pairs.is_empty(), "После «Карточной» у шаблона-примера нет перекрытий: %s" % str(conflicts.pairs))
	check(cards.layout.screens[0].items.any(func(item: Dictionary): return item.kind == "button" and item.get("main", false)), "Добавлена главная кнопка")
	# Повторное применение не плодит элементы.
	var twice: Dictionary = Templates.apply_layout(cards, "cards")
	check(twice.layout.screens[0].items.size() == cards.layout.screens[0].items.size(), "Повторный шаблон не добавляет лишнего")
	# Фоны: размер и бесшовность (края совпадают по яркости в пределах шума).
	for look: Dictionary in Templates.BACKGROUNDS:
		var image: Image = Templates.background_image(str(look.id))
		check(image.get_size() == Vector2i(256, 256), "Плитка «%s» 256×256" % look.title)
		check(Templates.background_image(str(look.id)) == image, "Плитка «%s» кэшируется" % look.title)
	# Лица карт: колонки добавлены, слои допустимы, проект без ошибок, фон карты сохранён.
	for template: Dictionary in Templates.FACES:
		var data := example()
		var deck: Dictionary = Templates.apply_face(data.elements.decks[0], str(template.id))
		var ids: Array = deck.columns.map(func(column: Dictionary): return str(column.id))
		check(template.columns.keys().all(func(key: String): return ids.has(key)), "Лицо «%s»: колонки %s" % [template.title, str(template.columns.keys())])
		check(deck.face.layers[0].get("role") == "card", "Лицо «%s»: первым — фон карты" % template.title)
		check(Definition.box_valid({"faces": {"front": deck.face.layers}}, Definition.CARD_LAYER_KINDS), "Лицо «%s»: слои допустимы" % template.title)
		check(deck.rows.all(func(row: Dictionary): return template.columns.keys().all(func(key: String): return row.has(key))), "Лицо «%s»: строки получили новые свойства" % template.title)
		data.elements.decks[0] = deck
		check(Definition.validate(data).errors.is_empty(), "Лицо «%s»: проект без ошибок: %s" % [template.title, str(Definition.validate(data).errors)])
	# Наборы: игральные колоды.
	for count: int in [36, 52]:
		var data := example()
		data.elements.decks[0] = Templates.playing_deck(data.elements.decks[0], count)
		var deck: Dictionary = data.elements.decks[0]
		check(deck.rows.size() == count, "Колода %d: %d карт" % [count, deck.rows.size()])
		check(deck.rows.filter(func(row: Dictionary): return row.suit == "Червы").all(func(row: Dictionary): return row.suit_color == "#b3261e"), "Колода %d: червы красные" % count)
		check(deck.rows.back().value == 14 and deck.rows[0].value == 15 - count / 4, "Колода %d: числа для правил" % count)
		check(Definition.validate(data).errors.is_empty(), "Колода %d без ошибок: %s" % [count, str(Definition.validate(data).errors)])
	# Из игр сборника: файлы на месте, картинки читаются, ссылки раскладок на фоны верны.
	for entry: Dictionary in Templates.GAME_BACKGROUNDS + Templates.GAME_BACKS:
		check(ResourceLoader.exists(str(entry.path)), "Ресурс есть: %s" % entry.path)
	for entry: Dictionary in Templates.available(Templates.GAME_BACKS).slice(0, 3):
		var image: Image = Templates.project_image(str(entry.path))
		check(image != null and image.get_width() > 0 and not image.is_compressed(), "Рубашка «%s» читается" % entry.title)
	var big: Image = Templates.project_image("res://games/brodilka/art/board.webp")
	check(big != null and maxi(big.get_width(), big.get_height()) <= 2048, "Большой фон ужат до 2048")
	for key: String in Templates.LAYOUT_GAMES:
		check(not Templates.layout(key).is_empty() and not Templates.entry_of(Templates.GAME_BACKGROUNDS, str(Templates.LAYOUT_GAMES[key].bg)).is_empty(), "Раскладка «%s» связана с фоном игры" % key)
	for look: Dictionary in Templates.DRAWN_BACKS:
		check(Templates.drawn_back_image(str(look.id)).get_size() == Vector2i(252, 352), "Узор «%s» 252×352" % look.title)
	# Шаблоны правил: проект без ошибок, партия начинается, первый ход по шаблону проходит.
	const Rules := preload("res://games/custom/logic/cg_rules.gd")
	var players: Array = [{"name": "А", "team": 0}, {"name": "Б", "team": 1}]
	for template: Dictionary in Templates.RULES:
		var data := example()
		data.rules.chains = []
		data = Templates.apply_rules(data, str(template.id))
		check(Definition.validate(data).errors.is_empty(), "Правила «%s» без ошибок: %s" % [template.title, str(Definition.validate(data).errors)])
		var r := Rules.new()
		check(r.load_definition(data).is_empty() and r.new_game(players, {"seed": 4}).is_empty(), "Правила «%s»: партия начинается (%s)" % [template.title, r.last_error])
		var again := Templates.apply_rules(data, str(template.id))
		check(again.layout.screens[0].items.size() == data.layout.screens[0].items.size(), "Правила «%s»: повтор не плодит элементы стола" % template.title)
		var legal: Array = r.legal_actions(int(r.state.current))
		match str(template.id):
			"draw_play":
				check(r.state.zones["hand@0"].size() == 5 and r.state.zones["hand@1"].size() == 5, "Раздано по 5")
				var play: Array = legal.filter(func(action: Dictionary): return action.kind == "card")
				check(not play.is_empty() and r.act(int(r.state.current), "card", {"id": play[0].id, "card": play[0].card, "zone": play[0].get("zone", ""), "revision": r.state.revision}), "Карта сыграна: %s" % r.last_error)
				check(r.state.zones["table"].size() == 1 and int(r.state.current) == 1, "Карта на столе, ход перешёл")
				check(r.act(1, "button", {"id": "take_card", "revision": r.state.revision}) and r.state.zones["hand@1"].size() == 6, "Кнопка «Взять карту»: %s" % r.last_error)
			"dice_points":
				check(r.act(0, "button", {"id": "roll_dice", "revision": r.state.revision}), "Бросок: %s" % r.last_error)
				var score: int = int(r.state.vars.player[0].get("score", 0))
				check(score >= 2 and score <= 12 and int(r.state.current) == 1, "Сумма кубиков в очках (%d), ход дальше" % score)
			"leader_out":
				check(legal.any(func(action: Dictionary): return action.kind == "button" and action.id == "leader_choose") or int(r.state.leader) != int(r.state.current), "Ведущему доступна «Выбрать»")
	# Новая игра из шаблона: без сохранённого проекта картинки не кладутся (ошибка-пометка), остальное собирается.
	var Document: GDScript = load("res://editor/ed_document.gd")
	for spec: Dictionary in Templates.KITS:
		var result: Dictionary = Templates.apply_kit(Document.blank(), str(spec.id))
		var data: Dictionary = result.data
		check(Definition.validate(data).errors.is_empty(), "Набор «%s» без ошибок: %s" % [spec.title, str(Definition.validate(data).errors)])
		check(data.meta.title == spec.title and data.meta.look.has("buttons"), "Набор «%s»: название, цвета и кнопки" % spec.title)
		check(not spec.has("deck") or data.elements.decks.size() == 1, "Набор «%s»: колода" % spec.title)
		var r := Rules.new()
		check(r.load_definition(data).is_empty() and r.new_game(players, {"seed": 9}).is_empty(), "Набор «%s»: партия начинается (%s)" % [spec.title, r.last_error])
		check(not r.legal_actions(int(r.state.current)).is_empty(), "Набор «%s»: у ходящего есть действия" % spec.title)
	print("EDITOR TEMPLATES: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors > 0 else 0)
