class_name UIAccentFX
extends Node2D
## Ненавязчивые акценты: периодический диагональный блик главных кнопок и свечение рамки у курсора.
## Node2D не участвует в раскладке Container. Декоративный ColorRect пропускает мышь и фокус.
## Свечение рамки — у всех панелей во всех играх: watch_panels() (зовёт автозагрузка Prefs) вешает его
## на каждую PanelContainer/Panel. Не светятся кнопки, карты, верхняя полоса, мелкие плашки и
## полноэкранные подложки; отключить у панели — set_meta("no_border_glow", true).

const FX_SHADER := preload("res://hub/ui_accent_fx.gdshader")
enum Mode { SHEEN, BORDER }
var _mode := Mode.SHEEN
var _host: Control
var _surface: ColorRect
var _material: ShaderMaterial
var _glow_color := Color("93a8d8")
var _auto_color := false  # цвет свечения — от рамки/фона самой панели
var _opacity := 0.0

const MIN_SIZE := Vector2(120, 60)  # меньше — плашка/бейдж, не панель
## Внутри них панели не светятся: карты, верхняя полоса, часы хода.
const SKIP_SCRIPTS := ["res://games/king_of_12/ui/card_view.gd", "res://hub/top_bar.gd", "res://hub/turn_clock.gd"]


static func sheen(button: Button) -> void:
	if button.has_node("PrimarySheen"):
		return
	var fx: Node2D = load("res://hub/ui_accent_fx.gd").new()
	fx.name = "PrimarySheen"
	button.add_child(fx, false, Node.INTERNAL_MODE_FRONT)


static func border(panel: Control, color: Color) -> void:
	if panel.has_node("BorderGlow"):
		return
	var fx: Node2D = load("res://hub/ui_accent_fx.gd").new()
	fx.name = "BorderGlow"
	fx._mode = Mode.BORDER
	fx._glow_color = color
	panel.add_child(fx, false, Node.INTERNAL_MODE_FRONT)  # внутренний: его не снимут очистки детей панели


## Один раз при запуске: свечение края у каждой новой панели.
static func watch_panels(tree: SceneTree) -> void:
	tree.node_added.connect(func(n: Node) -> void:
		if n is PanelContainer or n.get_class() == "Panel":
			_auto_border.call_deferred(n))


static func _auto_border(n: Variant) -> void:  # без типа: узел мог быть удалён до вызова
	if not is_instance_valid(n) or not (n as Node).is_inside_tree() or (n as Node).has_node("BorderGlow"):
		return
	var a: Node = n
	while a != null:
		if a is BaseButton or a.has_meta("no_border_glow"):
			return
		var sc: Script = a.get_script()
		if sc != null and sc.resource_path in SKIP_SCRIPTS:
			return
		a = a.get_parent()
	var fx: Node2D = load("res://hub/ui_accent_fx.gd").new()
	fx.name = "BorderGlow"
	fx._mode = Mode.BORDER
	fx._auto_color = true
	n.add_child(fx, false, Node.INTERNAL_MODE_FRONT)


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


## Светится только заметная панель: не мелкая, не во весь экран и с видимым фоном или рамкой.
## Стиль проверяется по свойствам (bg_color, border_color): так подходят и свои StyleBox игр (STInkBox).
func _panel_ok(box: StyleBox) -> bool:
	var sz := _host.size
	if sz.x < MIN_SIZE.x or sz.y < MIN_SIZE.y:
		return false
	var vs := get_viewport_rect().size
	if sz.x >= vs.x * 0.9 and sz.y >= vs.y * 0.8:
		return false
	if box is StyleBoxTexture:
		return true
	if box == null or box is StyleBoxEmpty or not ("bg_color" in box):
		return false
	var bg: Color = box.get("bg_color")
	var line: Color = box.get("border_color") if "border_color" in box else Color.TRANSPARENT
	return bg.a >= 0.3 or (line.a >= 0.3 and _border_w(box) > 0)


static func _border_w(box: StyleBox) -> int:
	return int(box.get("border_width_top")) if "border_width_top" in box else 0


## Цвет свечения по самой панели: заметная светлая рамка — её цвет, иначе от фона
## (на светлом фоне — сумеречно-синий, на тёмном — светло-голубой).
static func _color_for(box: StyleBox) -> Color:
	if box != null and "bg_color" in box:
		var line: Color = box.get("border_color") if "border_color" in box else Color.TRANSPARENT
		if line.a >= 0.45 and _border_w(box) > 0 and line.get_luminance() > 0.12:
			line.a = 1.0
			return line.lightened(0.2)
		if (box.get("bg_color") as Color).get_luminance() > 0.55:
			return Color("6f86c4")
	return Color("93a8d8")


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
		box = _host.get_theme_stylebox("panel")
		allowed = allowed and _panel_ok(box)
		if _auto_color:
			_material.set_shader_parameter("glow_color", _color_for(box))
	var corners := Vector4.ONE * 6.0 if box is StyleBoxTexture else Vector4.ZERO
	if box != null and "corner_radius_top_left" in box:
		corners = Vector4(box.get("corner_radius_top_left"), box.get("corner_radius_top_right"), box.get("corner_radius_bottom_right"), box.get("corner_radius_bottom_left"))
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
