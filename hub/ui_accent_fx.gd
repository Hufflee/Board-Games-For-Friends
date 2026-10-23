class_name UIAccentFX
extends Node2D
## Ненавязчивые акценты: периодический диагональный блик главных кнопок и свечение рамки у курсора.
## Node2D не участвует в раскладке Container. Декоративный ColorRect пропускает мышь и фокус.

const FX_SHADER := preload("res://hub/ui_accent_fx.gdshader")
enum Mode { SHEEN, BORDER }
var _mode := Mode.SHEEN
var _host: Control
var _surface: ColorRect
var _material: ShaderMaterial
var _glow_color := Color("93a8d8")
var _opacity := 0.0


static func sheen(button: Button) -> void:
	if button.has_node("PrimarySheen"):
		return
	var fx: Node2D = load("res://hub/ui_accent_fx.gd").new()
	fx.name = "PrimarySheen"
	button.add_child(fx)


static func border(panel: Control, color: Color) -> void:
	if panel.has_node("BorderGlow"):
		return
	var fx: Node2D = load("res://hub/ui_accent_fx.gd").new()
	fx.name = "BorderGlow"
	fx._mode = Mode.BORDER
	fx._glow_color = color
	panel.add_child(fx)


func _ready() -> void:
	_host = get_parent() as Control
	if _host == null:
		queue_free()
		return
	_surface = ColorRect.new()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.focus_mode = Control.FOCUS_NONE
	_material = ShaderMaterial.new()
	_material.shader = FX_SHADER
	_material.set_shader_parameter("mode", _mode)
	# Разные фазы без расходования генератора случайных чисел игровой логики.
	_material.set_shader_parameter("phase_offset", fposmod(float(hash(get_instance_id())) * 0.001, 5.2))
	_material.set_shader_parameter("glow_color", _glow_color)
	_material.set_shader_parameter("opacity", 0.0)
	_surface.material = _material
	add_child(_surface)
	_host.resized.connect(_sync)
	_host.theme_changed.connect(_sync)
	_host.visibility_changed.connect(_sync)
	_host.draw.connect(_sync)
	if _host is Button:
		(_host as Button).button_down.connect(_sync)
		(_host as Button).button_up.connect(_sync)
	_sync.call_deferred()


## HCStyle используется также «Длиной волны»: свечение рамок нужно только этим двум играм.
func _modern_game() -> bool:
	if not is_inside_tree():
		return false
	var scene := get_tree().current_scene
	if scene:
		var path := scene.scene_file_path
		return "/hues_and_cues/" in path or "/word_slam/" in path
	return false


func _sync() -> void:
	if not is_inside_tree() or not is_instance_valid(_host) or not _host.is_inside_tree() or not is_instance_valid(_surface):
		return
	var allowed := _host.is_visible_in_tree() and _host.size.x > 1.0 and _host.size.y > 1.0
	var box: StyleBox
	if _host is Button:
		var button := _host as Button
		allowed = allowed and not button.disabled and not button.is_pressed()
		box = button.get_theme_stylebox("normal")
	else:
		allowed = allowed and _modern_game()
		box = _host.get_theme_stylebox("panel")
	var corners := Vector4.ZERO
	if box is StyleBoxFlat:
		var flat := box as StyleBoxFlat
		corners = Vector4(flat.corner_radius_top_left, flat.corner_radius_top_right, flat.corner_radius_bottom_right, flat.corner_radius_bottom_left)
	var padding := 5.0 if _mode == Mode.BORDER else 0.0
	_surface.position = Vector2.ONE * -padding
	_surface.size = _host.size + Vector2.ONE * padding * 2.0
	_material.set_shader_parameter("rect_size", _host.size)
	_material.set_shader_parameter("corners", corners)
	_material.set_shader_parameter("padding", padding)
	if _mode == Mode.SHEEN:
		_surface.visible = allowed
		_material.set_shader_parameter("opacity", 1.0 if allowed else 0.0)
		set_process(false)
	else:
		set_process(allowed)
		if not allowed:
			_opacity = 0.0
			_surface.hide()
			_material.set_shader_parameter("opacity", 0.0)


func _process(delta: float) -> void:
	var cursor := _host.get_local_mouse_position()
	var half := _host.size * 0.5
	var radius := minf(20.0, minf(half.x, half.y))
	var q := (cursor - half).abs() - half + Vector2.ONE * radius
	var edge_distance := q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0) - radius
	var target := 0.82 if absf(edge_distance) < 30.0 and _pointer_in_clip() else 0.0
	_opacity = lerpf(_opacity, target, minf(1.0, delta * 14.0))
	_surface.visible = _opacity > 0.005
	_material.set_shader_parameter("cursor", cursor)
	_material.set_shader_parameter("opacity", _opacity)


## Скрытые части прокручиваемой панели не должны подсвечиваться.
func _pointer_in_clip() -> bool:
	if not get_window().has_focus():
		return false
	var node: Node = _host
	while node:
		if node is Control:
			var control := node as Control
			if control.clip_contents and not Rect2(Vector2.ZERO, control.size).has_point(control.get_local_mouse_position()):
				return false
		node = node.get_parent()
	return Rect2(Vector2.ZERO, get_viewport_rect().size).has_point(get_viewport().get_mouse_position())
