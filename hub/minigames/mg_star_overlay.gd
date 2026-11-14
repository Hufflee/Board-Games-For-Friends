extends CanvasLayer
## «Лови звёздочку»: звезда поверх всего интерфейса (создаёт hub/minigames/mg_net.gd у участников комнаты).
## Место — доли экрана от хоста. Нажатие по звезде съедается: не доходит ни до _input сцены, ни до кнопок под ней.
## Для этого слой — последний ребёнок корня (его _input вызывается первым) и сам гасит событие.
## Хитбокс чуть больше рисунка (HIT_SCALE).

signal caught(id: int)

const LAYER := 118  # выше окна «Общение» (45) и игровых окон, ниже шторки смены сцены (120)
const RADIUS := 22.0  # радиус лучей звезды, px при высоте экрана 720
const HIT_SCALE := 1.35
const FACE_LIGHT := Color("fff1b0")  # грань к свету
const FACE_DARK := Color("e08a1e")  # грань в тени
const EDGE := Color("8a4a08")
const GLOW := Color("ffcf5a")

var _star: Dictionary = {}
var _clock := 0.0
var _swallow_release := false
var _sprite: Control
var blocked: Callable  # -> bool: мини-игры заблокированы (мой ход) — звезду не показываем и не ловим


func _init() -> void:
	layer = LAYER
	name = "StarOverlay"
	add_to_group("pause_allowed")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sprite = Control.new()
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE  # ввод ловит _input слоя
	_sprite.draw.connect(_draw_star)
	add_child(_sprite)


func show_star(star: Dictionary) -> void:
	if star.is_empty() or int(star.get("id", -1)) != int(_star.get("id", -2)):
		_clock = 0.0
	_star = star
	_sprite.visible = not star.is_empty()
	_sprite.queue_redraw()


func _scale() -> float:
	return maxf(0.6, get_viewport().get_visible_rect().size.y / 720.0)


func center() -> Vector2:
	var view := get_viewport().get_visible_rect().size
	return Vector2(float(_star.get("x", 0.5)) * view.x, float(_star.get("y", 0.5)) * view.y)


## Попадает ли точка экрана в звезду (с запасом).
func hit(point: Vector2) -> bool:
	return not _star.is_empty() and point.distance_to(center()) <= RADIUS * _scale() * HIT_SCALE


func _process(delta: float) -> void:
	var parent := get_parent()
	if parent != null and get_index() != parent.get_child_count() - 1:
		parent.move_child(self, -1)  # новая сцена встаёт в конец корня — возвращаемся за неё
	var hidden := blocked.is_valid() and bool(blocked.call())
	_sprite.visible = not _star.is_empty() and not hidden
	if not _sprite.visible:
		return
	_clock += delta
	var side := RADIUS * _scale() * 4.6  # с запасом под лучи-блики и искорки
	_sprite.size = Vector2(side, side)
	_sprite.position = center() - _sprite.size * 0.5
	_sprite.queue_redraw()


func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null:
		return
	if not button.pressed:
		if _swallow_release and button.button_index == MOUSE_BUTTON_LEFT:
			_swallow_release = false
			get_viewport().set_input_as_handled()
		return
	if button.button_index != MOUSE_BUTTON_LEFT or not _sprite.visible or not hit(button.position):
		return
	get_viewport().set_input_as_handled()
	_swallow_release = true
	var id := int(_star.id)
	show_star({})  # исчезает сразу; очко подтвердит хост
	caught.emit(id)


## Звезда-самоцвет: мягкое сияние, длинные мерцающие лучи-блики, пять огранённых лучей (каждый — светлая
## и тёмная грань, как у кристалла под светом сверху-слева), белая искра в сердцевине и кружащие искорки.
func _draw_star() -> void:
	if _star.is_empty():
		return
	var s := _scale()
	var c := _sprite.size * 0.5
	var t := _clock
	var pulse := 1.0 + 0.06 * sin(t * 5.0)
	var outer := RADIUS * s * pulse
	var spin := sin(t * 1.3) * 0.18  # покачивается, а не крутится волчком
	# сияние: несколько прозрачных кругов — мягкий ореол
	for k in 14:
		var f := 2.3 - k * 0.1  # от широкого к узкому: прозрачные слои складываются в плавный ореол
		_sprite.draw_circle(c, outer * f, Color(GLOW, 0.022))
	# длинные лучи-блики (четыре, по диагонали к звезде), мерцают по очереди
	for k in 4:
		var angle := PI / 4.0 + k * PI / 2.0 - spin * 0.5
		var twinkle := 0.55 + 0.45 * sin(t * 4.0 + k * 1.7)
		var length := outer * (1.55 + 0.35 * twinkle)
		var dir := Vector2.from_angle(angle)
		var side := dir.orthogonal() * outer * 0.09
		_sprite.draw_colored_polygon(PackedVector2Array([c + side, c + dir * length, c - side]), Color(1, 0.97, 0.85, 0.75 * twinkle))
	# Варианты из референса: ромб с вогнутыми краями, пяти- и восьмилучевая звезда.
	var variant := posmod(int(_star.id), 3)
	var rays: int = [4, 5, 8][variant]
	var inset: float = [0.25, 0.46, 0.36][variant]
	var outline := PackedVector2Array()
	for k in rays * 2:
		var angle := -PI / 2.0 + k * PI / rays + spin
		var radius := outer if k % 2 == 0 else outer * inset
		if variant == 2 and k % 4 == 2:
			radius *= 0.68
		outline.append(c + Vector2.from_angle(angle) * radius)
	_sprite.draw_colored_polygon(outline, FACE_LIGHT)
	outline.append(outline[0])
	_sprite.draw_polyline(outline, EDGE, maxf(2.0, 2.0 * s), true)
	# искра в сердцевине
	_sprite.draw_circle(c + Vector2(-0.12, -0.15) * outer, outer * 0.16, Color(1, 1, 1, 0.9))
	_sprite.draw_circle(c + Vector2(-0.12, -0.15) * outer, outer * 0.28, Color(1, 1, 1, 0.25))
	# три искорки на орбите — маленькие четырёхлучевые блики
	for k in 3:
		var orbit := t * 1.6 + k * TAU / 3.0
		var at := c + Vector2.from_angle(orbit) * outer * (1.45 + 0.1 * sin(t * 3.0 + k))
		var size := outer * (0.12 + 0.08 * (0.5 + 0.5 * sin(t * 6.0 + k * 2.0)))
		_sparkle(at, size, Color(1, 0.95, 0.75, 0.9))


func _sparkle(at: Vector2, size: float, color: Color) -> void:
	var thin := size * 0.22
	_sprite.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -size), at + Vector2(thin, 0), at + Vector2(0, size), at + Vector2(-thin, 0)]), color)
	_sprite.draw_colored_polygon(PackedVector2Array([at + Vector2(-size, 0), at + Vector2(0, -thin), at + Vector2(size, 0), at + Vector2(0, thin)]), color)
