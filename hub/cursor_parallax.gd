extends RefCounted
## Плавное смещение декоративного фона за курсором; интерфейс и поле остаются неподвижны.

static func step(control: Control, current: Vector2, delta: float, amplitude: float = 10.0) -> Vector2:
	var viewport_size := control.get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return current
	var viewport := control.get_viewport()
	var pointer := Prefs.pointer_position if viewport == control.get_tree().root else viewport.get_mouse_position()
	var normalized := pointer / viewport_size * 2.0 - Vector2.ONE
	var target := -normalized.clamp(-Vector2.ONE, Vector2.ONE) * amplitude
	if not Prefs.parallax:
		target = Vector2.ZERO  # параллакс выключен в настройках: фон плавно возвращается на место
	return current.lerp(target, 1.0 - exp(-maxf(delta, 0.0) * 4.0))


static func watch(control: Control, update: Callable, amplitude: float = 12.0) -> void:
	var driver := Driver.new()
	driver.sample = func(current: Vector2, delta: float) -> Vector2: return step(control, current, delta, amplitude)
	driver.update = update
	control.add_child(driver)


## У текстуры есть запас по краям, поэтому курсор не открывает пустые полосы.
static func follow_texture(texture: TextureRect, amplitude: float = 12.0) -> void:
	watch(texture, func(shift: Vector2):
		texture.offset_left = -amplitude + shift.x
		texture.offset_right = amplitude + shift.x
		texture.offset_top = -amplitude + shift.y
		texture.offset_bottom = amplitude + shift.y, amplitude)
	texture.offset_left = -amplitude
	texture.offset_right = amplitude
	texture.offset_top = -amplitude
	texture.offset_bottom = amplitude


## Для однотонного фона или фона с рамкой, которую нельзя сдвигать, движется мягкий свет.
static func add_light(parent: Control, tint: Color) -> void:
	var layer := ColorRect.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = preload("res://hub/parallax_light.gdshader")
	material.set_shader_parameter("tint", tint)
	layer.material = material
	parent.add_child(layer)
	watch(layer, func(shift: Vector2): material.set_shader_parameter("drift", shift / layer.size.max(Vector2.ONE)), 24.0)


class Driver extends Node:
	var sample: Callable
	var update: Callable
	var motion := Vector2.ZERO

	func _process(delta: float) -> void:
		var next: Vector2 = sample.call(motion, delta)
		if next.distance_to(motion) > 0.001:
			motion = next
			update.call(motion)
