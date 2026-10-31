class_name TurnEdgeGlow
extends ColorRect
## Общая подсветка «твой ход»: края экрана мерцают неоново-синим, пока ход за мной.
## Цикл: 0.7 с яркость растёт до пика → 0.7 с спадает до базы → 1 с держит базу → повтор.
## Ставит TopBar на каждый стол; кто ходит — TurnSeats.is_mine(Net.view).

const COLOR := Color("2fa8ff")
const RADIUS := 56.0  # шире, чем вспышка ответа Things in Rings
const BASE := 0.32
const PEAK := 0.85
const RISE := 0.7
const FALL := 0.7
const HOLD := 1.0
const SHADER := preload("res://hub/turn_edge_glow.gdshader")

var _t := 0.0
var _on := 0.0  # плавное появление/исчезание всей рамки
var _mat: ShaderMaterial


func _init() -> void:
	name = "TurnEdgeGlow"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color.WHITE
	z_as_relative = false
	z_index = 97  # над столом и полосой, под модальными окнами
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("glow_color", COLOR)
	_mat.set_shader_parameter("radius", RADIUS)
	material = _mat
	modulate.a = 0.0


## Яркость цикла в момент t (0…PEAK), без плавного включения.
static func pulse(t: float) -> float:
	var p := fmod(t, RISE + FALL + HOLD)
	if p < RISE:
		return lerpf(BASE, PEAK, smoothstep(0.0, 1.0, p / RISE))
	if p < RISE + FALL:
		return lerpf(PEAK, BASE, smoothstep(0.0, 1.0, (p - RISE) / FALL))
	return BASE


var _was_mine := false


func _process(delta: float) -> void:
	var mine := _active()
	if mine and not _was_mine:
		Sfx.play("your_turn", -6.0, 0.0)  # кроме рамки — короткий сигнал: мой ход начался
	_was_mine = mine
	var want := 1.0 if mine else 0.0
	_on = move_toward(_on, want, delta / 0.35)
	visible = _on > 0.0
	if not visible:
		_t = 0.0
		return
	_t += delta
	modulate.a = _on
	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("strength", pulse(_t))


func _active() -> bool:
	if Net.view.is_empty() or bool(Net.view.get("game_paused", false)):
		return false
	return TurnSeats.is_mine(Net.view)
