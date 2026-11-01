extends Control
## 3D-предпросмотр коробки и четыре 2D-грани для запекания. Только внутри редактора, игровой стол остаётся 2D.

const Library := preload("res://games/custom/logic/cg_library.gd")
const Style := preload("res://games/custom/ui/cg_style.gd")
const AssetReader := preload("res://games/custom/ui/cg_assets.gd")
const PARTS := ["front", "back", "spine", "top"]
const CORRECTION := preload("res://editor/ed_layer.gdshader")
const Fonts := preload("res://editor/ed_fonts.gd")
signal layer_moved(index: int, rect: Array)
var document: RefCounted
var surfaces: Dictionary = {}
var assets := AssetReader.new()
var _box: Node3D
var _camera: Camera3D
var _face_image: TextureRect
var _three: SubViewportContainer
var selected_face := "front"
var layer_index := -1
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_rect := Rect2()
var _drag_delta := Vector2.ZERO
var _drag_mode := "move"

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
	_face_image = TextureRect.new()
	_face_image.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_face_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_face_image.mouse_filter = MOUSE_FILTER_IGNORE
	_face_image.hide()
	add_child(_face_image)
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
					child.position.x = -shape.x / 2 - 0.002
				"top":
					child.mesh.size = Vector2(shape.x, thick)
					child.position.y = shape.y / 2 + 0.002

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
	if selected_face.is_empty() or not is_instance_valid(_face_image) or not _face_image.visible:
		return
	var rect := _selected_rect()
	if rect.has_area():
		if _drag_mode == "resize":
			rect.size += _drag_delta
		else:
			rect.position += _drag_delta
		draw_rect(Rect2(_face_origin() + rect.position * _face_scale(), rect.size * _face_scale()), Style.accent(), false, 2.0)
		draw_rect(Rect2(_face_origin() + rect.end * _face_scale() - Vector2(5, 5), Vector2(10, 10)), Style.accent())

func _drag_face(event: InputEvent) -> bool:
	if selected_face.is_empty() or not _face_image.visible:
		return false
	var layers: Array = document.data.box.get("faces", {}).get(selected_face, [])
	if layer_index < 0 or layer_index >= layers.size() or layers[layer_index].get("locked", false):
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var point: Vector2 = (event.position - _face_origin()) / _face_scale()
			_drag_mode = "resize" if event.position.distance_to(_face_origin() + _selected_rect().end * _face_scale()) < 12 else "move"
			if _drag_mode != "resize" and not _selected_rect().has_point(point):
				return false
			_dragging = true
			_drag_start = point
			_drag_rect = _selected_rect()
			_drag_delta = Vector2.ZERO
		elif _dragging:
			_dragging = false
			var position_value := _drag_rect.position + (_drag_delta if _drag_mode == "move" else Vector2.ZERO)
			var size_value := _drag_rect.size + (_drag_delta if _drag_mode == "resize" else Vector2.ZERO)
			layer_moved.emit(layer_index, [position_value.x, position_value.y, size_value.x, size_value.y])
			_drag_delta = Vector2.ZERO
		queue_redraw()
		return true
	if event is InputEventMouseMotion and _dragging:
		_drag_delta = (((event.position - _face_origin()) / _face_scale() - _drag_start) / 8.0).round() * 8
		if _drag_mode == "resize":
			_drag_delta.x = clampf(_drag_rect.size.x + _drag_delta.x, 8, 4096) - _drag_rect.size.x
			_drag_delta.y = clampf(_drag_rect.size.y + _drag_delta.y, 8, 4096) - _drag_rect.size.y
		else:
			_drag_delta.x = clampf(_drag_rect.position.x + _drag_delta.x, -2048, 4096) - _drag_rect.position.x
			_drag_delta.y = clampf(_drag_rect.position.y + _drag_delta.y, -2048, 4096) - _drag_rect.position.y
		for layer: Control in surfaces[selected_face].get_children():
			if layer.get_meta("layer_index", -1) == layer_index:
				if _drag_mode == "resize":
					layer.size = _drag_rect.size + _drag_delta
					layer.queue_redraw()
				else:
					layer.position = _drag_rect.position + _drag_delta
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
