extends SceneTree
## Вид кубиков пользовательской игры: цвет корпуса/точек, грани точками/цифрами/картинками,
## набор у броска и в view, ссылка блока на набор, кость PerudoDie по умолчанию прежняя.
## Запуск: APPDATA=<папка в build> godot --headless --audio-driver Dummy --path . --script res://tests/test_editor_dice.gd
const Rules := preload("res://games/custom/logic/cg_rules.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
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
	var data := example()
	data.rules.chains = []
	data.elements.decks = []
	data.elements.dice = [
		{"id": "white", "title": "Белые", "count": 2, "free": true, "color": "#ffffff", "pips": "#202020", "faces": "numbers"},
		{"id": "red", "title": "Красный", "count": 1, "free": true, "color": "#c0392b", "faces": "dots"},
	]
	for item: Dictionary in data.layout.screens[0].items:
		if item.kind == "zone":
			item.free = true
	check(Definition.validate(data).errors.is_empty(), "Вид кубиков допустим: %s" % str(Definition.validate(data).errors))
	var r := Rules.new()
	check(r.load_definition(data).is_empty() and r.new_game([{"name": "А", "team": 0}, {"name": "Б", "team": 1}], {"seed": 3}).is_empty(), "Партия с двумя наборами")
	check(r.act(0, "manual_roll", {"id": "red", "revision": r.state.revision}), "Ручной бросок красного набора")
	check(r.act(0, "answer", {"value": [1], "revision": r.state.revision}), "Жест подтверждён")
	check(r.state.dice["0"].get("set") == "red" and r.state.dice["0"].values.size() == 1, "Бросок помнит свой набор и его количество")
	check(r.get_view(1).dice_sets.get("0") == "red", "Во view видно, какой набор бросили")
	var saved := r.save_state()
	var restored := Rules.new()
	restored.load_definition(data)
	check(restored.restore(saved).is_empty() and restored.state.dice["0"].set == "red", "Набор броска сохраняется и восстанавливается")

	var broken := example()
	broken.elements.dice = [{"id": "d", "title": "Мой d6", "count": 1, "color": "не цвет", "faces": "кляксы", "images": [1, 2]}]
	var report: Array = Definition.validate(broken).errors
	check(report.any(func(text: String): return text.contains("«Мой d6»") and text.contains("цвет")), "Неверный цвет назван с набором: %s" % str(report))
	check(report.any(func(text: String): return text.contains("вид граней")), "Неизвестный вид граней — ошибка")
	check(report.any(func(text: String): return text.contains("картинки граней")), "Неверные картинки граней — ошибка")
	broken = example()
	broken.elements.dice = [{"id": "d", "count": 1}]
	broken.rules.chains = [{"event": {"type": "start"}, "blocks": [{"op": "roll", "count": 1, "dice": "gone"}]}]
	report = Definition.validate(broken).errors
	check(report.any(func(text: String): return text.contains("«gone»") and text.contains("цепочка №1")), "Блок броска с удалённым набором — ошибка с местом: %s" % str(report))

	# d4–d20: бросок набора даёт числа до числа граней; у d20 грани только цифрами.
	var poly := example()
	poly.rules.chains = []
	poly.elements.decks = []
	poly.elements.dice = [{"id": "big", "title": "d20", "count": 6, "free": true, "sides": 20, "faces": "numbers"}, {"id": "small", "title": "d4", "count": 6, "free": true, "sides": 4, "faces": "numbers"}]
	for item: Dictionary in poly.layout.screens[0].items:
		if item.kind == "zone":
			item.free = true
	check(Definition.validate(poly).errors.is_empty(), "d20 и d4 допустимы: %s" % str(Definition.validate(poly).errors))
	var seen_big := 0
	var seen_small := 0
	for attempt in 6:
		var pr := Rules.new()
		pr.load_definition(poly)
		pr.new_game([{"name": "А", "team": 0}, {"name": "Б", "team": 1}], {"seed": 10 + attempt})
		pr.act(0, "manual_roll", {"id": "big", "revision": pr.state.revision})
		pr.act(0, "answer", {"value": [], "revision": pr.state.revision})
		for value: int in pr.state.dice["0"].values:
			seen_big = maxi(seen_big, value)
			check(value >= 1 and value <= 20, "d20 в границах: %d" % value)
		pr.act(0, "manual_roll", {"id": "small", "revision": pr.state.revision})
		pr.act(0, "answer", {"value": [], "revision": pr.state.revision})
		for value: int in pr.state.dice["0"].values:
			seen_small = maxi(seen_small, value)
	check(seen_big > 6, "d20 выбрасывает больше 6 (максимум %d)" % seen_big)
	check(seen_small <= 4, "d4 не больше 4 (максимум %d)" % seen_small)
	poly.elements.dice = [{"id": "x", "title": "Кривой", "count": 1, "sides": 7}, {"id": "y", "title": "Точечный", "count": 1, "sides": 12, "faces": "dots"}]
	var poly_report: Array = Definition.validate(poly).errors
	check(poly_report.any(func(text: String): return text.contains("«Кривой»") and text.contains("4, 6, 8, 10, 12 или 20")), "7 граней — ошибка")
	check(poly_report.any(func(text: String): return text.contains("«Точечный»") and text.contains("только цифрами")), "d12 точками — ошибка")
	# UI-стиль зависит от автозагрузок: грузим после запуска дерева (rulebook).
	var style: GDScript = load("res://games/custom/ui/cg_style.gd")
	var die: Control = load("res://games/perudo/ui/d6_view.gd").new(3, 64)
	check(die.pip_color.a == 0.0 and not die.number_faces and die.face_textures.is_empty(), "Кость по умолчанию прежняя (Перудо и другие игры)")
	style.style_die(die, data.elements.dice[0], null)
	check(die.color == Color("ffffff") and die.pip_color == Color("202020") and die.number_faces, "Стиль набора применяется к кости")
	style.style_die(die, {}, null)
	check(die.color == Color("f3ead2") and die.pip_color.a == 0.0 and not die.number_faces, "Набор без вида — обычная кость")
	style.style_die(die, {"color": "player"}, null, Color("e6194b"))
	check(die.color == Color("e6194b"), "Цвет игрока подставляется в кость")
	style.style_die(die, {"color": "team"}, null)
	check(die.color == Color("f3ead2"), "Без цвета места — обычная кость")
	var owner_dice := example()
	owner_dice.elements.dice = [{"id": "p", "count": 1, "color": "player"}, {"id": "t", "count": 1, "color": "team"}]
	check(Definition.validate(owner_dice).errors.is_empty(), "«Цвет игрока/команды» допустим в наборе")
	die.free()

	print("EDITOR DICE: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors > 0 else 0)
