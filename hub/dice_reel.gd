extends Control
## Кубомёт: 2D-корпус, рычаг и барабан с заданной извне остановкой.
## Используется столами через TossDie и K12Die3D; сам не выполняет бросок.

const ART_SIZE := 64.0
const ART_BOUNDS := Rect2(0, 0, 66, 92)
const LEVER := Rect2(45, 24, 21, 42)
const WINDOW := Rect2(12, 14, 29, 62)
const PITCH := 20.0
const LIFT := 3.0
const GLYPH_SCALE := 4.0
const GLYPH_SIZE := 88
const SPEED := 14.0
const WIND_UP := 0.7
const BRAKE := 2.0
const ROCK := 0.32
const RESPONSE_TIMEOUT := 6.0
const BRASS := Color("bd9057")
const LIGHT := Color("f4d69a")
const INK := Color("22292a")
const MINT := Color("91f1cf")
## Щелчок трещотки на каждом ребре барабана (tools/sfx_reel_tick.py): к концу вращения ход медленнее — щелчки реже.
const TICK := preload("res://hub/audio/reel_tick.wav")
const TICK_VOICES := 4

signal pulled
signal returned_home

var active := false
var sides := 6
## Смещение от центра экрана в долях ширины крупного кубомёта, если их два.
var prompt_offset := 0.0
var required := false
var base_scale := 1.0
var _held := false
var _held_at_center := false
var _held_offset := 0.0
var _lift := 0.0
var _focus := 0.0
var _offset := 0.0
var _housing := Control.new()
var _window := Control.new()
var _elapsed := 0.0
var _brake_at := -1.0
var _start := 0.0
var _end := 0.0
var _travel := 0.0
var _anchor := 1
var _face := 1
var _spinning := false
var _lamp := 0.0
var _rib := 0  # последнее пройденное ребро (для щелчка)
var _ticks: Array[AudioStreamPlayer] = []
var _tick_voice := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_housing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_housing.show_behind_parent = true
	_housing.draw.connect(_draw_housing)
	add_child(_housing)
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_window.clip_contents = true
	_window.position = WINDOW.position
	_window.size = WINDOW.size
	_window.draw.connect(_draw_window)
	add_child(_window)
	for i in TICK_VOICES:
		var p := AudioStreamPlayer.new()
		p.stream = TICK
		p.bus = "SFX"
		add_child(p)
		_ticks.append(p)


func hit(point: Vector2) -> bool:
	return LEVER.has_point(point)


func _has_point(point: Vector2) -> bool:
	return active and hit(point) and not Net.paused and not _modal_open()


func _modal_open() -> bool:
	# Увеличенный кубомёт — верхнеуровневый узел. Окно стола должно получить ввод первым.
	var ancestor := get_parent()
	while ancestor != null and ancestor != get_viewport():
		for child in ancestor.get_children():
			if child is TopBar:
				return child._has_modal(get_tree().current_scene)
		ancestor = ancestor.get_parent()
	return false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _has_point(event.position):
		accept_event()
		pulled.emit()


func hold_local_throw() -> void:
	_held = true
	_held_at_center = required
	_held_offset = prompt_offset


func release_local_throw() -> void:
	_held = false


func _present(delta: float) -> void:
	var die := get_parent() as Control
	var die_transform := die.get_global_transform()
	var origin := die_transform * (die.size * 0.5)
	var base := die_transform.get_scale().abs() * base_scale
	var viewport := get_viewport()
	var pointer := Prefs.pointer_position if viewport == get_tree().root else viewport.get_mouse_position()
	var cursor := get_canvas_transform().affine_inverse() * pointer
	var local_point := (cursor - origin) / base + ART_BOUNDS.get_center()
	var displayed_point := get_global_transform().affine_inverse() * cursor
	var hover := active and (ART_BOUNDS.has_point(local_point) or ART_BOUNDS.has_point(displayed_point))
	var centered := _held_at_center if _held else required
	var weight := 1.0 - exp(-delta * 18.0)
	_lift = lerpf(_lift, 1.0 if centered or _held or hover else 0.0, weight)
	_focus = lerpf(_focus, 1.0 if centered else 0.0, weight)
	_offset = lerpf(_offset, _held_offset if _held else prompt_offset, weight)
	if _lift < 0.002 and _focus < 0.002:
		var returned := is_set_as_top_level()
		_lift = 0.0
		_focus = 0.0
		set_as_top_level(false)
		z_as_relative = true
		z_index = 0
		scale = Vector2.ONE * base_scale
		position = die.size * 0.5 - ART_BOUNDS.get_center() * scale
		if returned:
			returned_home.emit()
		return
	set_as_top_level(true)
	z_as_relative = false
	z_index = 75
	scale = base * lerpf(1.0, LIFT, _lift)
	var screen := get_canvas_transform().affine_inverse() * get_viewport_rect()
	var target := screen.get_center() + Vector2(_offset * ART_SIZE * LIFT * base.x, 0.0)
	var half_size := ART_BOUNDS.size * scale * 0.5
	# Парные кубомёты расходятся и на своих местах, чтобы не накрывать друг друга при броске.
	origin.x += _offset * ART_SIZE * (LIFT - 1.0) * base.x * _lift
	var center := origin.lerp(target, _focus)
	center = center.clamp(screen.position + half_size, screen.end - half_size)
	position = center - half_size


func timed_out() -> bool:
	return _elapsed >= RESPONSE_TIMEOUT


func show_face(value: int) -> void:
	_spinning = false
	_face = clampi(value, 0, sides)
	_travel = 0.0
	_window.queue_redraw()
	queue_redraw()


func spin() -> void:
	_spinning = true
	_anchor = clampi(_face, 1, sides)
	_elapsed = 0.0
	_brake_at = -1.0
	_travel = 0.0
	_rib = 0


## Сначала равномерный ход вниз, затем замедление до соседней подходящей метки и отскок.
## При позднем ответе барабан продолжает идти до получения грани.
func advance(delta: float, result: int) -> bool:
	_elapsed += delta
	if _brake_at < 0.0:
		_travel = _elapsed * SPEED
		if result > 0 and _elapsed >= WIND_UP:
			_start = _travel
			var mark := float(posmod(_anchor - result, sides))
			_end = mark + roundf((_start + SPEED * BRAKE * 0.5 - mark) / sides) * sides
			_brake_at = _elapsed
	else:
		var t := (_elapsed - _brake_at) / BRAKE
		if t < 1.0:
			# Кубическая интерполяция сохраняет скорость входа и гасит её до нуля у метки.
			var distance := _end - _start
			var tangent := minf(SPEED * BRAKE, 2.8 * distance)
			_travel = _start + (3.0 * t * t - 2.0 * t * t * t) * distance + t * (1.0 - t) ** 2 * tangent
		else:
			var rock := (_elapsed - _brake_at - BRAKE) / ROCK
			if rock >= 1.0:
				show_face(result)
				return true
			_travel = _end + sin(rock * TAU) * (1.0 - rock) * 0.17
	_click_ribs(delta)
	_window.queue_redraw()
	queue_redraw()
	return false


## Барабан прошёл ребро (середину между цифрами) — щелчок; чем медленнее ход, тем тише и ниже.
func _click_ribs(delta: float) -> void:
	var rib := floori(_travel + 0.5)
	if rib == _rib:
		return
	var passed := absi(rib - _rib)
	_rib = rib
	if not is_visible_in_tree() or _ticks.is_empty():
		return
	var speed := clampf(float(passed) / maxf(delta, 0.001) / SPEED, 0.0, 1.0)
	var p := _ticks[_tick_voice]
	_tick_voice = (_tick_voice + 1) % _ticks.size()
	p.volume_db = lerpf(-15.0, -9.0, speed)
	p.pitch_scale = lerpf(0.88, 1.04, speed) * randf_range(0.97, 1.03)
	p.play()


func _process(delta: float) -> void:
	_present(delta)
	if active and is_visible_in_tree():
		_lamp = fposmod(_lamp + delta * 4.0, TAU)
		queue_redraw()


func _plate(rect: Rect2, fill: Color, edge: Color, radius: int, border: int = 1) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(border)
	style.set_corner_radius_all(radius)
	style.corner_detail = 20
	style.anti_aliasing_size = 0.6
	_housing.draw_style_box(style, rect)


func _draw_housing() -> void:
	var metal := Color("4f6866")
	var side := Color("283a3b")
	# Ножки, отливка, выступающий латунный обод и утопленное окно.
	_plate(Rect2(3, 8, 46, 82), Color(0.04, 0.06, 0.06, 0.55), Color.TRANSPARENT, 10, 0)
	_plate(Rect2(6, 81, 12, 9), side, INK, 3)
	_plate(Rect2(35, 81, 12, 9), side, INK, 3)
	_plate(Rect2(3, 6, 47, 80), side, INK, 10, 2)
	_plate(Rect2(3, 3, 46, 79), metal, BRASS, 10, 2)
	_plate(Rect2(7, 7, 38, 72), side, Color("728883"), 8)
	_plate(Rect2(9, 11, 35, 68), INK, BRASS, 5, 2)
	_housing.draw_line(Vector2(13, 12), Vector2(40, 12), LIGHT, 1.0, true)
	for x in [10.0, 42.0]:
		_housing.draw_circle(Vector2(x, 8), 2.4, INK, true, -1.0, true)
		_housing.draw_circle(Vector2(x, 7.6), 1.5, LIGHT, true, -1.0, true)
	for x in [22.0, 26.0, 30.0]:
		_housing.draw_line(Vector2(x, 82), Vector2(x, 85), BRASS, 1.0, true)


func _draw() -> void:
	# Рукоять уходит вниз в начале вращения и возвращается пружиной.
	var pivot := Vector2(49, 58)
	var pull := sin(clampf(_elapsed / 0.36, 0.0, 1.0) * PI) if _spinning else 0.0
	var knob := Vector2(56 + pull * 1.6, 35 + pull * 19.0)
	draw_line(pivot, knob, INK, 6.0, true)
	draw_line(pivot, knob, BRASS, 3.0, true)
	draw_circle(pivot, 5.0, INK, true, -1.0, true)
	draw_circle(pivot, 3.0, BRASS, true, -1.0, true)
	var glow := 0.5 + sin(_lamp) * 0.5
	if active:
		draw_circle(knob, 10.0, Color(MINT, 0.11 + 0.18 * glow), true, -1.0, true)
	draw_circle(knob, 6.6, INK, true, -1.0, true)
	draw_circle(knob, 5.0, Color("578577").lerp(MINT, 0.55 + glow * 0.45) if active else BRASS, true, -1.0, true)
	draw_circle(knob - Vector2(1.3, 1.5), 1.7, LIGHT, true, -1.0, true)


func _draw_window() -> void:
	var font := ThemeDB.fallback_font
	var bounds := Rect2(Vector2.ZERO, WINDOW.size)
	_window.draw_rect(bounds, INK)
	var middle := WINDOW.size.y * 0.5
	_window.draw_rect(Rect2(0, middle - 10, WINDOW.size.x, 20), Color("414c40"))
	var step := floori(_travel)
	var fraction := _travel - float(step)
	# Растеризуем цифры с запасом под крупный вид и масштаб интерфейса.
	_window.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / GLYPH_SCALE)
	for slot in range(-2, 3):
		if not _spinning and absi(slot) > 1:
			continue
		var base_face := _anchor - step if _spinning else maxi(1, _face)
		var value := 0 if not _spinning and _face == 0 and slot == 0 else posmod(base_face + slot - 1, sides) + 1
		var text := str(value) if value > 0 else "–"
		var y := middle + (float(slot) + fraction) * PITCH
		var ink := LIGHT.lerp(Color("8c856d"), smoothstep(5.0, 18.0, absf(y - middle)))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, GLYPH_SIZE).x / GLYPH_SCALE
		var pos := Vector2((WINDOW.size.x - width) * 0.5, y + 7.0)
		_window.draw_string(font, (pos + Vector2(0, 1)) * GLYPH_SCALE, text, HORIZONTAL_ALIGNMENT_LEFT, -1, GLYPH_SIZE, INK)
		_window.draw_string(font, pos * GLYPH_SCALE, text, HORIZONTAL_ALIGNMENT_LEFT, -1, GLYPH_SIZE, ink)
	_window.draw_set_transform(Vector2.ZERO)
	_window.draw_rect(Rect2(0, 0, WINDOW.size.x, 5), Color(INK, 0.65))
	_window.draw_rect(Rect2(0, WINDOW.size.y - 5, WINDOW.size.x, 5), Color(INK, 0.6))
	for x in [1.0, WINDOW.size.x - 3.0]:
		_window.draw_rect(Rect2(x, middle - 1, 2, 3), BRASS)
