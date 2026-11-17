extends Control
## Рисует поле и 2D-фишки. Зум и панорама меняют только координаты отрисовки.

signal target_pressed(cell: int)
signal character_hovered(hero: String)

const Art := preload("res://games/unmatched/ui/um_card_art.gd")
const Style := preload("res://games/unmatched/ui/um_style.gd")
const Maps := preload("res://games/unmatched/logic/um_maps.gd")
const IMAGES := {"marmoreal": "vol1_a", "sarpedon": "vol1_b", "gardens": "gardens"}

var _arena := ""
var _board: Texture2D
var _figures: Array = []
var _targets: Dictionary = {}
var _portraits: Dictionary = {}
var _zoom := 1.0
var _offset := Vector2.ZERO
var _pressed := false
var _moved := false
var _motions := {}
var _effect_losses: Array[Dictionary] = []
var _hovered := ""
var drop_highlight := false:
	set(value):
		drop_highlight = value
		queue_redraw()
var outline_color := Color("c39676"):
	set(value):
		outline_color = value
		queue_redraw()


func _ready() -> void:
	clip_contents = true
	set_process(false)
	mouse_exited.connect(_show_character.bind(""))
	resized.connect(func():
		clamp_offset()
		queue_redraw())


func present(arena: String, figures: Array, targets: Dictionary, show_effect_losses: bool = false) -> void:
	if arena != _arena:
		_arena = arena
		_motions.clear()
		_effect_losses.clear()
		_figures = []
		_zoom = 1.0
		_offset = Vector2.ZERO
		_board = null
		if IMAGES.has(arena):
			var source := Art.texture("res://games/unmatched/art/boards/%s.webp" % IMAGES[arena])
			if arena == "gardens":
				_board = source
			elif source != null:
				var atlas := AtlasTexture.new()
				atlas.atlas = source
				var source_size := source.get_size()
				atlas.region = Rect2(Maps.PRINT_AREA.position / Maps.PRINT_SIZE * source_size,
					Maps.PRINT_AREA.size / Maps.PRINT_SIZE * source_size)
				atlas.filter_clip = true
				_board = atlas
	var previous := {}
	for fighter: Dictionary in _figures:
		if fighter.has("fighter"):
			previous[Vector2i(fighter.seat, fighter.fighter)] = fighter
	var present_keys := {}
	for fighter: Dictionary in figures:
		if not fighter.has("fighter"):
			continue
		var key := Vector2i(fighter.seat, fighter.fighter)
		present_keys[key] = true
		if not previous.has(key):
			continue
		var old: Dictionary = previous[key]
		if show_effect_losses and old.hp > fighter.hp:
			_effect_losses.append({"at": fighter.at, "amount": old.hp - fighter.hp, "elapsed": 0.0})
		var path: Array = fighter.get("walk", []).duplicate() if fighter.get("walk_serial", 0) != old.get("walk_serial", 0) else []
		if path.size() < 2 or path[0] != old.at or path[-1] != fighter.at:
			if old.at == fighter.at:
				continue
			path = [old.at, fighter.at]
		if _motions.has(key):
			_motions[key].path.append_array(path.slice(1))
		else:
			_motions[key] = {"path": path, "elapsed": 0.0}
	for key: Vector2i in _motions.keys():
		if not present_keys.has(key):
			_motions.erase(key)
	if show_effect_losses:
		for key: Vector2i in previous:
			var old: Dictionary = previous[key]
			if not present_keys.has(key) and old.hp > 0:
				_effect_losses.append({"at": old.at, "amount": old.hp, "elapsed": 0.0})
	set_process(not _motions.is_empty() or not _effect_losses.is_empty())
	_figures = figures
	_targets = targets
	queue_redraw()


func _process(delta: float) -> void:
	for key: Vector2i in _motions.keys():
		var motion: Dictionary = _motions[key]
		motion.elapsed += delta
		while motion.elapsed >= 0.19 and motion.path.size() > 1:
			motion.elapsed -= 0.19
			motion.path.pop_front()
		if motion.path.size() < 2:
			_motions.erase(key)
	for loss in _effect_losses:
		loss.elapsed += delta
	_effect_losses = _effect_losses.filter(func(loss: Dictionary) -> bool: return loss.elapsed < 1.10)
	set_process(not _motions.is_empty() or not _effect_losses.is_empty())
	queue_redraw()


func zoom_by(factor: float, at: Vector2) -> void:
	var previous := _zoom
	_zoom = clampf(previous * factor, 1.0, 3.0)
	_offset = at - size * 0.5 - (at - size * 0.5 - _offset) * (_zoom / previous)
	clamp_offset()
	queue_redraw()


func clamp_offset() -> void:
	var limit := ((_field_size() - size) * 0.5).max(Vector2.ZERO)
	_offset = _offset.clamp(-limit, limit)


func _field_size() -> Vector2:
	if _board == null:
		return Vector2.ZERO
	var original := _board.get_size()
	var fit := (size - Vector2(4, 4)).max(Vector2.ZERO)
	return original * minf(fit.x / original.x, fit.y / original.y) * _zoom


func _field_rect() -> Rect2:
	var field := _field_size()
	return Rect2((size - field) * 0.5 + _offset, field)


func _draw() -> void:
	if _board == null:
		return
	var field := _field_rect()
	draw_texture_rect(_board, field, false)
	draw_rect(field.grow(0.75), outline_color, false, 1.5, true)
	if drop_highlight:
		draw_rect(field, Color(0.28, 0.77, 0.37, 0.30))
		draw_rect(field, Color(0.63, 0.94, 0.63, 0.85), false, 2.0, true)
	for position: Vector2 in _targets.values():
		if _figures.any(func(fighter: Dictionary) -> bool:
			return fighter.get("attackable", false) and fighter.at == position):
			continue
		draw_arc(field.position + position * field.size, field.size.x * 0.035, 0.0, TAU, 40, Color("ffedaa"), 3.0, true)
	for fighter: Dictionary in _figures:
		var key := Vector2i(fighter.seat, fighter.get("fighter", -1))
		if not _motions.has(key):
			_draw_fighter(field.position + (fighter.at as Vector2) * field.size, field.size.x, fighter)
	for fighter: Dictionary in _figures:
		var key := Vector2i(fighter.seat, fighter.get("fighter", -1))
		if _motions.has(key):
			var motion: Dictionary = _motions[key]
			var fraction: float = motion.elapsed / 0.19
			var position: Vector2 = (motion.path[0] as Vector2).lerp(motion.path[1], fraction)
			var lift := 0.0 if Prefs.reduce_motion else sin(PI * fraction)
			_draw_fighter(field.position + position * field.size, field.size.x, fighter, lift)
	for loss in _effect_losses:
		var text := "−%d ОЗ" % loss.amount
		var point: Vector2 = field.position + loss.at * field.size
		point -= Vector2(18, 25 + (0.0 if Prefs.reduce_motion else loss.elapsed * 18.0))
		point.y = maxf(20.0, point.y)
		var font := Style.body_font()
		var alpha := clampf((1.10 - loss.elapsed) * 3.0, 0.0, 1.0)
		draw_string_outline(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, 5, Color(Color("301c23"), alpha))
		draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(Color("ffb39f"), alpha))


func _draw_fighter(center: Vector2, width: float, fighter: Dictionary, lift: float = 0.0) -> void:
	var radius := width * (0.038 if fighter.get("hero", false) else 0.027)
	var tint: Color = Style.TOKENS[posmod(int(fighter.seat), Style.TOKENS.size())]
	draw_circle(center + Vector2(1, 3), radius + 1, Color(0.09, 0.06, 0.1, 0.55), true, -1, true)
	center.y -= radius * 0.35 * lift
	radius *= 1.0 + lift * 0.16
	if fighter.get("attackable", false):
		draw_circle(center, radius + 6.0, Color(0.91, 0.20, 0.27, 0.35), true, -1, true)
		draw_arc(center, radius + 4.0, 0.0, TAU, 40, Color("ff626e"), 3.0, true)
	if fighter.get("selected", false):
		draw_arc(center, radius + 5.0, 0.0, TAU, 40, Color("f8e2a7"), 3.0, true)
	draw_circle(center, radius, tint, true, -1, true)
	var key := str(fighter.token)
	if not _portraits.has(key):
		_portraits[key] = _round_portrait(key)
	var portrait: Texture2D = _portraits[key]
	if portrait != null:
		draw_texture_rect(portrait, Rect2(center - Vector2.ONE * (radius - 3), Vector2.ONE * (radius - 3) * 2), false)
	var badge := center + Vector2(radius * 0.68, radius * 0.72)
	draw_circle(badge, 10.0, Color("241c27"), true, -1, true)
	var health := str(fighter.hp)
	var font := Style.body_font()
	var measure := font.get_string_size(health, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(font, badge + Vector2(-measure.x * 0.5, 4), health, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	var status := str(fighter.get("status", ""))
	if not status.is_empty():
		var text_width := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var left := clampf(center.x - text_width * 0.5, 7.0, maxf(7.0, size.x - text_width - 7.0))
		var top := clampf(center.y + radius + 4.0, 1.0, maxf(1.0, size.y - 20.0))
		var plate := Style.stone(Color(0.12, 0.09, 0.13, 0.93), Color("bd8e68"), 0)
		plate.shadow_size = 0
		draw_style_box(plate, Rect2(left - 5.0, top, text_width + 10.0, 18.0))
		draw_string(font, Vector2(left, top + 13), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("fff2df"))


func _round_portrait(key: String) -> Texture2D:
	var source := Art.texture("res://games/unmatched/art/tokens/%s.webp" % key)
	if source == null:
		return null
	var image := source.get_image()
	var side := mini(image.get_width(), image.get_height())
	var origin := (image.get_size() - Vector2i(side, side)) / 2
	image = image.get_region(Rect2i(origin, Vector2i(side, side)))
	image.resize(64, 64, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var alpha := clampf(32.0 - Vector2(x - 31.5, y - 31.5).length(), 0.0, 1.0)
			var pixel := image.get_pixel(x, y)
			pixel.a = alpha
			image.set_pixel(x, y, pixel)
	return ImageTexture.create_from_image(image)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_by(1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15, event.position)
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				_pressed = true
				_moved = false
			else:
				if _pressed and not _moved and event.button_index == MOUSE_BUTTON_LEFT:
					_pick(event.position)
				_pressed = false
	elif event is InputEventMouseMotion and _pressed:
		if event.relative.length_squared() >= 1.0:
			_moved = true
		_offset += event.relative
		clamp_offset()
		queue_redraw()
	elif event is InputEventMouseMotion:
		var field := _field_rect()
		for fighter: Dictionary in _figures:
			var center := field.position + (fighter.at as Vector2) * field.size
			var radius := field.size.x * (0.038 if fighter.get("hero", false) else 0.027)
			if event.position.distance_to(center) <= radius:
				_show_character(str(fighter.get("character", "")))
				return
		_show_character("")


func _show_character(hero: String) -> void:
	if hero != _hovered:
		_hovered = hero
		character_hovered.emit(hero)


func _pick(at: Vector2) -> void:
	var field := _field_rect()
	for cell: int in _targets:
		var center := field.position + (_targets[cell] as Vector2) * field.size
		if at.distance_to(center) < field.size.x * 0.037:
			target_pressed.emit(cell)
			return
	for fighter: Dictionary in _figures:
		if not fighter.has("cell"):
			continue
		var center := field.position + (fighter.at as Vector2) * field.size
		if at.distance_to(center) < field.size.x * 0.038:
			target_pressed.emit(fighter.cell)
			return
