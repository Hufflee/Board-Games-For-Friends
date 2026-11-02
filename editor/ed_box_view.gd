extends Control
## 3D-предпросмотр коробки и четыре 2D-грани для запекания. Только внутри редактора, игровой стол остаётся 2D.

const Library := preload("res://games/custom/logic/cg_library.gd")
const Style := preload("res://games/custom/ui/cg_style.gd")
const AssetReader := preload("res://games/custom/ui/cg_assets.gd")
const PARTS := ["front", "back", "spine", "top"]
const CORRECTION := preload("res://editor/ed_layer.gdshader")
const Fonts := preload("res://editor/ed_fonts.gd")
signal layer_moved(index: int, rect: Array)
signal layer_rotated(index: int, degrees: float)
var document: RefCounted
var surfaces: Dictionary = {}
var assets := AssetReader.new()
var _box: Node3D
var _camera: Camera3D
var _face_image: TextureRect
var _selection: Control
var _three: SubViewportContainer
var selected_face := "front"
var layer_index := -1
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_rect := Rect2()
var _drag_delta := Vector2.ZERO
var _drag_mode := "move"
var _drag_corner := Vector2.ONE
var _drag_rotation := 0.0
var _rotation_value := 0.0
var _start_angle := 0.0

func _layer_rotation() -> float:
	var layers: Array = document.data.box.get("faces", {}).get(selected_face, [])
	return deg_to_rad(float(layers[layer_index].get("rotation", 0))) if layer_index >= 0 and layer_index < layers.size() else 0.0

func _handle_point(rect: Rect2, corner: Vector2, angle: float) -> Vector2:
	return _face_origin() + (rect.get_center() + (rect.size * corner * 0.5).rotated(angle)) * _face_scale()

func _transformed_rect() -> Rect2:
	if not _dragging:
		return _selected_rect()
	if _drag_mode == "move":
		return Rect2(_drag_rect.position + _drag_delta, _drag_rect.size)
	if _drag_mode == "resize":
		var dimensions := _drag_rect.size + _drag_delta * _drag_corner
		var center := _drag_rect.get_center() + (_drag_delta * 0.5).rotated(_drag_rotation)
		return Rect2(center - dimensions * 0.5, dimensions)
	return _drag_rect

class Layer extends Control:
	var data: Dictionary
	var reader: RefCounted
	var gradient_texture: Texture2D
	func _draw() -> void:
		var color := Color.from_string(str(data.get("color", "#efdfb9")), Color("efdfb9"))
		var rect := Rect2(Vector2.ZERO, size)
		match str(data.get("kind", "fill")):
			"fill":
				if gradient_texture != null:
					draw_texture_rect(gradient_texture, rect, false)
				else:
					draw_rect(rect, color)
			"image":
				var texture: Texture2D = reader.image(str(data.get("asset", "")))
				if texture != null:
					draw_texture_rect(texture, rect, false)
			"text":
				var font: Font = Fonts.font(str(data.get("font", "")))
				if font == null:
					font = reader.font(str(data.get("font", "")))
				if font == null:
					font = Style.HEAD
				var font_size := clampi(int(data.get("font_size", 96)), 8, 512)
				var y := float(font_size)
				for line: String in str(data.get("text", "Текст")).split("\n"):
					var measured := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
					var x := (size.x - measured.x) / 2.0 if data.get("align", "center") == "center" else 0.0
					if data.get("shadow", false):
						draw_string(font, Vector2(x + 4, y + 5), line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.10, 0.08, 0.14, 0.4))
					var outline := clampi(int(data.get("outline", 0)), 0, 16)
					if outline > 0:
						draw_string_outline(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color.from_string(str(data.get("outline_color", "#ebe4d4")), Color("ebe4d4")))
					draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
					y += font_size * 1.16

func setup(doc: RefCounted, with_3d: bool = true) -> void:
	document = doc
	custom_minimum_size = Vector2(400, 320)
	size_flags_vertical = SIZE_EXPAND_FILL
	clip_contents = true
	assets.configure(str(document.data.id), "", true)
	_load_current_assets()
	for part: String in PARTS:
		var viewport := SubViewport.new()
		viewport.disable_3d = true
		viewport.transparent_bg = false
		viewport.size = face_size(document.data, part)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		surfaces[part] = viewport
		_build_face(part)
	if not with_3d:
		return
	_three = SubViewportContainer.new()
	_three.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_three.stretch = true
	_three.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_three)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_three.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Style.panel()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("ddd7e4")
	environment.environment.ambient_light_energy = 0.8
	world.add_child(environment)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 0.52
	_camera.near = 0.01
	_camera.far = 10.0
	_camera.position = Vector3(0, 0, 1.5)
	world.add_child(_camera)
	_camera.current = true
	_box = Node3D.new()
	_box.rotation_degrees = Vector3(-15, -24, 0)
	world.add_child(_box)
	var dimensions: Vector2 = Library.SHAPES.get(str(document.data.box.get("template", "square")), Library.SHAPES.square)
	var thickness := clampf(float(document.data.box.get("thickness", 0.06)), 0.04, 0.12)
	var core := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(dimensions.x, dimensions.y, thickness)
	core.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b9ae9d")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = material
	_box.add_child(core)
	_face("front", Vector2(dimensions.x, dimensions.y), Vector3(0, 0, thickness / 2 + 0.002), Vector3.ZERO)
	_face("back", Vector2(dimensions.x, dimensions.y), Vector3(0, 0, -thickness / 2 - 0.002), Vector3(0, PI, 0))
	_face("spine", Vector2(thickness, dimensions.y), Vector3(-dimensions.x / 2 - 0.002, 0, 0), Vector3(0, -PI / 2, 0))
	_face("top", Vector2(dimensions.x, thickness), Vector3(0, dimensions.y / 2 + 0.002, 0), Vector3(-PI / 2, 0, 0))
	# Противоположные торцы используют тот же рисунок: картонная основа не светит белым.
	_face("spine", Vector2(thickness, dimensions.y), Vector3(dimensions.x / 2 + 0.002, 0, 0), Vector3(0, PI / 2, 0))
	_box.get_child(_box.get_child_count() - 1).set_meta("opposite", true)
	_face("top", Vector2(dimensions.x, thickness), Vector3(0, -dimensions.y / 2 - 0.002, 0), Vector3(PI / 2, 0, 0))
	_box.get_child(_box.get_child_count() - 1).set_meta("opposite", true)
	_face_image = TextureRect.new()
	_face_image.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_face_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_face_image.mouse_filter = MOUSE_FILTER_IGNORE
	_face_image.hide()
	add_child(_face_image)
	_selection = Control.new()
	_selection.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_selection.mouse_filter = MOUSE_FILTER_IGNORE
	_selection.draw.connect(_draw_selection)
	add_child(_selection)
	gui_input.connect(_input_view)

func _load_current_assets() -> void:
	# Несохранённый импорт тоже виден автору; пути берутся только из whitelist пакета.
	for hash_value: String in document.data.get("assets", {}):
		var entry: Variant = document.data.assets[hash_value]
		if not entry is Dictionary:
			continue
		var path := str(entry.get("path", ""))
		if not AssetReader.Package.path_valid(path) or not path.begins_with("assets/") or path.get_file().get_basename() != hash_value:
			continue
		if assets.files.has(path):
			continue
		var file := FileAccess.open(Library.folder(str(document.data.id)) + "/" + path, FileAccess.READ)
		if file != null and file.get_length() <= AssetReader.Package.FONT_LIMIT:
			assets.files[path] = file.get_buffer(file.get_length())

func refresh() -> void:
	_load_current_assets()
	for part: String in PARTS:
		surfaces[part].size = face_size(document.data, part)
		for child: Node in surfaces[part].get_children():
			child.queue_free()
		_build_face(part)
	var shape: Vector2 = Library.SHAPES.get(str(document.data.box.get("template", "square")), Library.SHAPES.square)
	var thick := clampf(float(document.data.box.get("thickness", 0.06)), 0.04, 0.12)
	if is_instance_valid(_box):
		_box.get_child(0).mesh.size = Vector3(shape.x, shape.y, thick)
		for child: Node3D in _box.get_children():
			match str(child.get_meta("part", "")):
				"front", "back":
					child.mesh.size = shape
					child.position.z = (thick / 2 + 0.002) * (1 if child.get_meta("part") == "front" else -1)
				"spine":
					child.mesh.size = Vector2(thick, shape.y)
					child.position.x = (shape.x / 2 + 0.002) * (1 if child.get_meta("opposite", false) else -1)
				"top":
					child.mesh.size = Vector2(shape.x, thick)
					child.position.y = (shape.y / 2 + 0.002) * (-1 if child.get_meta("opposite", false) else 1)

static func face_size(data: Dictionary, part: String) -> Vector2i:
	var shape: Vector2 = Library.SHAPES.get(str(data.get("box", {}).get("template", "square")), Library.SHAPES.square)
	var thick := clampf(float(data.get("box", {}).get("thickness", 0.06)), 0.04, 0.12)
	var face := Vector2(thick, shape.y) if part == "spine" else (Vector2(shape.x, thick) if part == "top" else shape)
	var factor := 1024.0 / maxf(face.x, face.y)
	return Vector2i(maxi(1, roundi(face.x * factor)), maxi(1, roundi(face.y * factor)))

func _face(part: String, dimensions: Vector2, position_value: Vector3, rotation_value: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.set_meta("part", part)
	var mesh := QuadMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.position = position_value
	instance.rotation = rotation_value
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = surfaces[part].get_texture()
	instance.material_override = material
	_box.add_child(instance)

func _build_face(part: String) -> void:
	var viewport: SubViewport = surfaces[part]
	var background := ColorRect.new()
	background.color = Color("ddd4c4")
	background.size = viewport.size
	viewport.add_child(background)
	var layers: Array = document.data.box.get("faces", {}).get(part, [])
	if part == "back" and layers.is_empty():
		layers = document.data.box.get("faces", {}).get("front", [])
	if layers.is_empty():
		layers = [{"kind": "text", "text": document.data.meta.title, "color": "#30263f", "rect": [32, viewport.size.y * 0.28, viewport.size.x - 64, viewport.size.y * 0.65], "font_size": 80 if part not in ["spine", "top"] else 40}]
	for index in layers.size():
		var entry: Dictionary = layers[index]
		if not entry.get("visible", true):
			continue
		var layer := Layer.new()
		layer.set_meta("layer_index", index)
		layer.data = entry
		layer.reader = assets
		if entry.get("kind") == "fill" and entry.get("gradient", false):
			var gradient := GradientTexture2D.new()
			gradient.gradient = Gradient.new()
			gradient.gradient.colors = PackedColorArray([Color.from_string(str(entry.get("color", "#b7c9bd")), Color("b7c9bd")), Color.from_string(str(entry.get("color2", "#30263f")), Color("30263f"))])
			gradient.fill_from = Vector2.ZERO
			gradient.fill_to = Vector2.ONE
			layer.gradient_texture = gradient
		var rect: Array = entry.get("rect", [0, 0, viewport.size.x, viewport.size.y])
		layer.position = Vector2(float(rect[0]), float(rect[1]))
		layer.size = Vector2(float(rect[2]), float(rect[3]))
		layer.pivot_offset = layer.size / 2
		layer.rotation_degrees = float(entry.get("rotation", 0))
		layer.scale = Vector2(-1 if entry.get("flip_x", false) else 1, -1 if entry.get("flip_y", false) else 1)
		layer.modulate.a = clampf(float(entry.get("opacity", 1)), 0, 1)
		var correction := ShaderMaterial.new()
		correction.shader = CORRECTION
		correction.set_shader_parameter("tint", Color.from_string(str(entry.get("tint", "#ffffff")), Color.WHITE))
		for key: String in ["brightness", "contrast", "saturation", "exposure", "hue"]:
			var value := float(entry.get(key, 1.0 if key in ["contrast", "saturation"] else 0.0))
			correction.set_shader_parameter(key, deg_to_rad(value) if key == "hue" else value)
		layer.material = correction
		viewport.add_child(layer)

func show_face(part: String) -> void:
	selected_face = part
	_three.visible = part.is_empty()
	_face_image.visible = not part.is_empty()
	if not part.is_empty():
		_face_image.texture = surfaces[part].get_texture()
	queue_redraw()

func _face_scale() -> float:
	var pixels: Vector2 = surfaces[selected_face].size
	return minf(size.x / pixels.x, size.y / pixels.y)

func _face_origin() -> Vector2:
	return (size - Vector2(surfaces[selected_face].size) * _face_scale()) / 2.0

func _selected_rect() -> Rect2:
	var layers: Array = document.data.box.get("faces", {}).get(selected_face, [])
	if layer_index < 0 or layer_index >= layers.size():
		return Rect2()
	var rect: Array = layers[layer_index].rect
	return Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))

func _draw() -> void:
	if is_instance_valid(_selection):
		_selection.queue_redraw()

func _draw_selection() -> void:
	if selected_face.is_empty() or not is_instance_valid(_face_image) or not _face_image.visible:
		return
	var rect := _transformed_rect()
	if rect.has_area():
		var angle := _rotation_value if _dragging else _layer_rotation()
		var points := PackedVector2Array()
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var point := _handle_point(rect, corner, angle)
			points.append(point)
			_selection.draw_rect(Rect2(point - Vector2(5, 5), Vector2(10, 10)), Style.accent())
		points.append(points[0])
		_selection.draw_polyline(points, Style.accent(), 2, true)
		var top := _handle_point(rect, Vector2(0, -1), angle)
		var rotate_handle := top + Vector2(0, -28).rotated(angle)
		_selection.draw_line(top, rotate_handle, Style.accent(), 2, true)
		_selection.draw_circle(rotate_handle, 6, Style.accent())

func _drag_face(event: InputEvent) -> bool:
	if selected_face.is_empty() or not _face_image.visible:
		return false
	var layers: Array = document.data.box.get("faces", {}).get(selected_face, [])
	if layer_index < 0 or layer_index >= layers.size() or layers[layer_index].get("locked", false):
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var point: Vector2 = (event.position - _face_origin()) / _face_scale()
			_drag_rotation = _layer_rotation()
			_rotation_value = _drag_rotation
			_drag_rect = _selected_rect()
			_drag_mode = "move"
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				if event.position.distance_to(_handle_point(_drag_rect, corner, _drag_rotation)) < 12:
					_drag_corner = corner
					_drag_mode = "resize"
			var rotate_handle := _handle_point(_drag_rect, Vector2(0, -1), _drag_rotation) + Vector2(0, -28).rotated(_drag_rotation)
			if event.position.distance_to(rotate_handle) < 12:
				_drag_mode = "rotate"
			var local_point := (point - _drag_rect.get_center()).rotated(-_drag_rotation) + _drag_rect.get_center()
			if _drag_mode == "move" and not _drag_rect.has_point(local_point):
				return false
			_dragging = true
			_drag_start = point
			_start_angle = (point - _drag_rect.get_center()).angle()
			_drag_delta = Vector2.ZERO
		elif _dragging:
			var result := _transformed_rect()
			_dragging = false
			if _drag_mode == "rotate":
				layer_rotated.emit(layer_index, rad_to_deg(_rotation_value))
			else:
				layer_moved.emit(layer_index, [result.position.x, result.position.y, result.size.x, result.size.y])
			_drag_delta = Vector2.ZERO
		queue_redraw()
		return true
	if event is InputEventMouseMotion and _dragging:
		var point: Vector2 = (event.position - _face_origin()) / _face_scale()
		_drag_delta = point - _drag_start
		if _drag_mode == "resize":
			_drag_delta = (_drag_delta.rotated(-_drag_rotation) / 8.0).round() * 8
			var dimensions := _drag_rect.size + _drag_delta * _drag_corner
			if event.shift_pressed:
				dimensions = _drag_rect.size * maxf(dimensions.x / _drag_rect.size.x, dimensions.y / _drag_rect.size.y)
			dimensions = dimensions.clamp(Vector2(8, 8), Vector2(4096, 4096))
			_drag_delta = (dimensions - _drag_rect.size) * _drag_corner
		elif _drag_mode == "rotate":
			_rotation_value = _drag_rotation + angle_difference(_start_angle, (point - _drag_rect.get_center()).angle())
			if event.shift_pressed:
				_rotation_value = snappedf(_rotation_value, PI / 12.0)
		else:
			_drag_delta = (_drag_delta / 8.0).round() * 8
			_drag_delta.x = clampf(_drag_rect.position.x + _drag_delta.x, -2048, 4096) - _drag_rect.position.x
			_drag_delta.y = clampf(_drag_rect.position.y + _drag_delta.y, -2048, 4096) - _drag_rect.position.y
		for layer: Control in surfaces[selected_face].get_children():
			if layer.get_meta("layer_index", -1) == layer_index:
				var rect := _transformed_rect()
				layer.position = rect.position
				layer.size = rect.size
				layer.pivot_offset = rect.size / 2
				layer.rotation = _rotation_value
				layer.queue_redraw()
		queue_redraw()
		return true
	return false

func _input_view(event: InputEvent) -> void:
	if _drag_face(event):
		accept_event()
		return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_box.rotation.y += event.relative.x * 0.01
		_box.rotation.x = clampf(_box.rotation.x + event.relative.y * 0.01, -1.4, 1.4)
		accept_event()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_camera.size = clampf(_camera.size * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.2, 1.2)
			accept_event()

func bake() -> String:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return bake_now()

func bake_now() -> String:
	var folder := Library.folder(str(document.data.id)) + "/covers"
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return "Не удалось создать папку обложек."
	for part: String in PARTS:
		var image: Image = surfaces[part].get_texture().get_image()
		if image == null or image.is_empty() or image.save_png(folder + "/" + part + ".png") != OK:
			return "Не удалось запечь грань «%s»." % part
	var thumb: Image = surfaces.front.get_texture().get_image()
	thumb.resize(256, maxi(1, roundi(256.0 * thumb.get_height() / thumb.get_width())), Image.INTERPOLATE_LANCZOS)
	if thumb.save_png(Library.folder(str(document.data.id)) + "/thumb.png") != OK:
		return "Не удалось сохранить миниатюру."
	Library.invalidate()
	return ""
