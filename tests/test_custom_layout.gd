extends SceneTree
## Якоря: точная базовая геометрия, широкое/высокое поле и строгая схема.
const Layout := preload("res://games/custom/logic/cg_layout.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _initialize() -> void:
	var base := Rect2(128, 112, 240, 80)
	for x: String in Layout.X:
		for y: String in Layout.Y:
			var item := {"anchors": {"x": x, "y": y}}
			check(Layout.rect(base, item, Layout.BASE) == base, "Базовая геометрия неизменна для %s/%s" % [x, y])
	check(Layout.rect(base, {}, Vector2(1920, 672)).position == Vector2(448, 112), "Без собственного якоря элемент сохраняет положение относительно центра прежнего стола")
	check(Layout.rect(base, {"anchors": {"x": "right", "y": "bottom"}}, Vector2(1920, 912)) == Rect2(768, 352, 240, 80), "Правый/нижний отступ сохраняется")
	check(Layout.rect(base, {"anchors": {"x": "stretch", "y": "stretch"}}, Vector2(1920, 912)) == Rect2(128, 112, 880, 320), "Растяжение добавляет свободное место к размеру")
	check(Layout.rect(base, {"anchors": {"x": "left", "y": "center"}}, Vector2(1920, 912)) == Rect2(128, 232, 240, 80), "Левый край и вертикальный центр независимы")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/card_race.json"))
	check(not Layout.adaptive(data.layout), "Прежний проект не включает адаптацию сам")
	data.layout.screens[0].items[0]["anchors"] = {"x": "stretch", "y": "bottom"}
	check(Layout.adaptive(data.layout) and Definition.validate(data).errors.is_empty(), "Допустимые якоря включают адаптацию и проходят схему")
	for bad: Variant in [null, [], "right", {"x": "bottom"}, {"y": "right"}, {"x": 1}]:
		data.layout.screens[0].items[0].anchors = bad
		check(not Definition.validate(data).errors.is_empty(), "Неверный тип/ось якоря отклонён")
	print("CUSTOM LAYOUT: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
