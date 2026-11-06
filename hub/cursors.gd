extends Node
## Свой курсор игры (все экраны): белые формы с тёмным контуром и мягкой тенью, арт — tools/hub_cursors.py
## (hub/art/cursors/<32|48>/). Ожидание (WAIT) — крутящееся кольцо, «занято» (BUSY) — стрелка с бегущим по
## контуру светом: кадры листов подменяются, только пока такой курсор на экране.
## Подключает Prefs (автозагрузка) в _ready; на мониторах от 1440 px по высоте — крупный набор 48 px.

const DIR := "res://hub/art/cursors/"
const FPS := 16.0
## Форма Godot → [файл, горячая точка в сетке 32 px].
const SHAPES := {
	Input.CURSOR_ARROW: ["arrow", Vector2(4, 3)],
	Input.CURSOR_IBEAM: ["ibeam", Vector2(16, 16)],
	Input.CURSOR_POINTING_HAND: ["hand", Vector2(12.6, 7.2)],
	Input.CURSOR_CROSS: ["cross", Vector2(16, 16)],
	Input.CURSOR_DRAG: ["hand", Vector2(12.6, 7.2)],
	Input.CURSOR_CAN_DROP: ["hand", Vector2(12.6, 7.2)],
	Input.CURSOR_FORBIDDEN: ["forbidden", Vector2(4, 3)],
	Input.CURSOR_VSIZE: ["vsize", Vector2(16, 16)],
	Input.CURSOR_HSIZE: ["hsize", Vector2(16, 16)],
	Input.CURSOR_BDIAGSIZE: ["bdiag", Vector2(16, 16)],
	Input.CURSOR_FDIAGSIZE: ["fdiag", Vector2(16, 16)],
	Input.CURSOR_MOVE: ["move", Vector2(16, 16)],
	Input.CURSOR_VSPLIT: ["vsize", Vector2(16, 16)],
	Input.CURSOR_HSPLIT: ["hsize", Vector2(16, 16)],
	Input.CURSOR_HELP: ["help", Vector2(4, 3)],
}
## Анимации: форма → [лист кадров, горячая точка].
const ANIMATED := {
	Input.CURSOR_WAIT: ["wait", Vector2(16, 16)],
	Input.CURSOR_BUSY: ["busy", Vector2(4, 3)],
}

var size := 32
var _frames := {}  # форма → Array[Image]
var _clock := 0.0
var _shown := {}  # форма → номер показанного кадра


func _ready() -> void:
	name = "Cursors"
	process_mode = Node.PROCESS_MODE_ALWAYS  # и на паузе
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	size = 48 if DisplayServer.screen_get_size().y >= 1400 else 32
	var k := size / 32.0
	for shape: int in SHAPES:
		var entry: Array = SHAPES[shape]
		var texture := load("%s%d/%s.png" % [DIR, size, entry[0]]) as Texture2D
		if texture != null:
			Input.set_custom_mouse_cursor(texture.get_image(), shape, (entry[1] as Vector2) * k)
	for shape: int in ANIMATED:
		var sheet := load("%s%d/%s.png" % [DIR, size, ANIMATED[shape][0]]) as Texture2D
		if sheet == null:
			continue
		var image := sheet.get_image()
		var list: Array[Image] = []
		for i in image.get_width() / size:
			list.append(image.get_region(Rect2i(i * size, 0, size, size)))
		_frames[shape] = list
		_show(shape, 0)


func _show(shape: int, frame: int) -> void:
	var list: Array = _frames.get(shape, [])
	if list.is_empty() or _shown.get(shape, -1) == frame:
		return
	_shown[shape] = frame
	Input.set_custom_mouse_cursor(list[frame], shape, (ANIMATED[shape][1] as Vector2) * (size / 32.0))


## Кадры подменяются только у курсора, который сейчас на экране.
func _process(delta: float) -> void:
	var shape := Input.get_current_cursor_shape()
	if not _frames.has(shape):
		return
	_clock += delta
	var list: Array = _frames[shape]
	_show(shape, int(_clock * FPS) % list.size())
