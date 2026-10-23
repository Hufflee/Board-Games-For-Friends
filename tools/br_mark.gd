## Разметка поля «Большой бродилки»: клики по клеткам MapFull.jpg по порядку дорожки (от старта к финишу).
## Запуск: godot --path . --script res://tools/br_mark.gd
## Перед кликом нажми клавишу кода клетки (как в BRBoard.CODES: . r g C O $ T Y G P B L W D X V M N K J + F S),
## Shift+1/2/3 — оттенок l/g/b. Z — отменить последнюю, Enter — вывести TRACK, SHADE и POS в консоль.
extends SceneTree

var _img: TextureRect
var _code := "."
var _shade := "l"
var _cells: Array = []  # [{c, s, p: Vector2 доли}]
var _dots: Control
var _info: Label


func _init() -> void:
	var tex: Texture2D = load("res://games/brodilka/art/src/MapFull.jpg")
	root.size = Vector2i(1600, 1000)
	_img = TextureRect.new()
	_img.texture = tex
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_img.size = Vector2(1600, 1000)
	_img.gui_input.connect(_on_input)
	root.add_child(_img)
	_dots = Control.new()
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.draw.connect(_draw_dots)
	_img.add_child(_dots)
	_dots.size = _img.size
	_info = Label.new()
	_info.add_theme_color_override("font_color", Color.YELLOW)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 6)
	root.add_child(_info)
	_upd()


func _rect() -> Rect2:
	var ts := _img.texture.get_size()
	var k: float = min(_img.size.x / ts.x, _img.size.y / ts.y)
	var s := ts * k
	return Rect2((_img.size - s) / 2, s)


func _on_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var r := _rect()
		_cells.append({c = _code, s = _shade, p = (e.position - r.position) / r.size})
		_upd()
	elif e is InputEventKey and e.pressed:
		if e.keycode == KEY_Z:
			_cells.pop_back()
		elif e.keycode == KEY_ENTER:
			_dump()
		elif e.shift_pressed and e.keycode in [KEY_1, KEY_2, KEY_3]:
			_shade = ["l", "g", "b"][e.keycode - KEY_1]
		elif e.unicode > 0:
			var ch := char(e.unicode)
			if BRBoard.CODES.has(ch):
				_code = ch
		_upd()


func _upd() -> void:
	_info.text = "клеток: %d   код: «%s» (%s)   оттенок: %s   [Z — отмена, Enter — вывод]" % [_cells.size(), _code, BRData.CELL_NAMES.get(BRBoard.CODES[_code], ""), _shade]
	_dots.queue_redraw()


func _draw_dots() -> void:
	var r := _rect()
	for i in _cells.size():
		var p: Vector2 = r.position + _cells[i].p * r.size
		_dots.draw_circle(p, 7, Color(1, 0.2, 0.2, 0.8))
		_dots.draw_string(ThemeDB.fallback_font, p + Vector2(8, -6), "%d%s" % [i, _cells[i].c], HORIZONTAL_ALIGNMENT_LEFT, -1, 12)


func _dump() -> void:
	var t := ""
	var s := ""
	var ps := []
	for c in _cells:
		t += c.c
		s += c.s
		ps.append("Vector2(%.4f, %.4f)" % [c.p.x, c.p.y])
	print('const TRACK := "%s"' % t)
	print('const SHADE := "%s"' % s)
	print("const POS := [%s]" % ", ".join(PackedStringArray(ps)))
