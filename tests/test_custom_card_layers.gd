extends SceneTree
## Общий шаблон лица: разрешение привязок, строгая схема, приватность и снимок партии.
const Faces := preload("res://games/custom/logic/cg_faces.gd")
const Rules := preload("res://games/custom/logic/cg_rules.gd")
const Session := preload("res://games/custom/logic/cg_session.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
var checks := 0
var errors := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors += 1
		push_error(message)

func _initialize() -> void:
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/card_race.json"))
	var deck: Dictionary = definition.elements.decks[0]
	var old := Faces.fields(deck.rows[0], deck)
	check(not old.has("layers"), "Прежний шаблон не превращается в слои при просмотре")
	deck["face"] = {"layers": Faces.default_layers(deck)}
	check(Definition.validate(definition).errors.is_empty(), "Стартовый шаблон слоёв корректен")
	var original := JSON.stringify(deck.face.layers)
	var first := Faces.fields(deck.rows[0], deck)
	var second := Faces.fields(deck.rows[1], deck)
	check(first.canvas_size == [504, 704], "Холст равен четырём физическим размерам стандартной карты")
	check(first.layers.any(func(layer): return layer.get("text", "") == "1"), "Число первой строки подставлено без лишнего десятичного нуля")
	check(second.layers.any(func(layer): return layer.get("text", "") == "2"), "Вторая строка использует тот же шаблон со своим числом")
	check(Faces.text(3.5) == "3.5" and Faces.text(true) == "Да", "Дробные числа и флаги сохраняют смысл в тексте")
	check(Faces.text(123456.5) == "123456.5", "Большое число не теряет дробную часть из-за приближённого сравнения")
	check(JSON.stringify(deck.face.layers) == original, "Привязки не подменяют общий шаблон содержимым строки")
	var bad := definition.duplicate(true)
	bad.elements.decks[0].face.layers.append({"kind": "text", "field": "нет_свойства", "rect": [0, 0, 100, 100]})
	check(not Definition.validate(bad).errors.is_empty(), "Ссылка на удалённое свойство отклонена")
	bad = definition.duplicate(true)
	bad.elements.decks[0].face.layers.append({"kind": "image", "field": "rank", "rect": [0, 0, 100, 100]})
	check(not Definition.validate(bad).errors.is_empty(), "Рисунок не связывается с числовой колонкой")
	bad = definition.duplicate(true)
	bad.elements.decks[0].face.layers[0].rect = [0, 0, -1, 100]
	check(not Definition.validate(bad).errors.is_empty(), "Отрицательный размер слоя отклонён")
	bad = definition.duplicate(true)
	for i in 65:
		bad.elements.decks[0].face.layers.append({"kind": "fill", "rect": [0, 0, 8, 8]})
	check(not Definition.validate(bad).errors.is_empty(), "Предел слоёв проверяется до запуска")
	var g := Rules.new()
	var marker := "общий_шаблон_".repeat(50)
	deck.face.layers.append({"kind": "text", "text": marker, "rect": [0, 0, 100, 100]})
	check(g.load_definition(definition).is_empty() and g.new_game([{"name": "А"}, {"name": "Б"}], {"seed": 12}).is_empty(), "Партия со слоями запущена")
	var view := Session.view(g, 0, false)
	check(view.zones["hand@0"].all(func(card): return card.has("face") and Session.face_fields(view, card).has("layers")), "Владелец получает подставленные слои своих карт")
	check(JSON.stringify(view).count(marker) == 1, "Общий шаблон не раздувает сетевое состояние на каждую карту")
	check(view.zones["hand@1"].all(func(card): return card.get("hidden", false) and not card.has("face") and not card.has("id")), "Чужие закрытые карты не раскрывают слои и идентификаторы")
	var restored := Rules.new()
	check(restored.restore(g.save_state()).is_empty() and restored.definition.elements.decks[0].face.layers == deck.face.layers, "Снимок сохраняет шаблон лица")
	print("CUSTOM CARD LAYERS: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
