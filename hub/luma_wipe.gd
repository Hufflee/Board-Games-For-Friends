class_name LumaWipe
extends CanvasLayer
## Случайный переход из хаба: шесть эффектов, фоновая загрузка и защита от повторного запуска.
## Запуск: change_scene(path, {"box": коробка, "camera": камера, "game": описание игры}).

const TRANSITION_SHADER := preload("res://hub/scene_transition.gdshader")
const EFFECTS := ["luma_wipe", "gradient_wipe", "blur_dissolve", "cross_zoom", "smoke_dissolve", "ink_bleed"]
# Номера веток шейдера сохраняются независимо от списка доступных переходов.
const SHADER_EFFECTS := [0, 1, 3, 5, 6, 8]
const DURATIONS := [1.9, 1.35, 1.5, 1.35, 1.9, 1.7]
const PREP := 0.16
static var _bag: Array[int] = []
static var _last_effect := -1
static var _active: LumaWipe

var _rect: TextureRect
var _path := ""
var _effect := 0
var _elapsed := 0.0
var _t := 0.0
var _switching := false
var _scene_ready := false
var _capture_ready := true
var _origin: WeakRef
var _box_viewport: SubViewport


## Перемешанная колода: каждый эффект встречается за цикл, на стыке циклов нет повтора.
static func next_effect() -> int:
	if _bag.is_empty():
		for i in EFFECTS.size():
			_bag.append(i)
		_bag.shuffle()
		if _bag[-1] == _last_effect:
			var swap := _bag[0]
			_bag[0] = _bag[-1]
			_bag[-1] = swap
	_last_effect = _bag.pop_back()
	return _last_effect


## Возвращает false, если переход не запущен. Повторный вызов не создаёт второй слой.
static func change_scene(path: String, context: Dictionary = {}) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or is_instance_valid(_active):
		return false
	if not ResourceLoader.exists(path, "PackedScene"):
		push_error("Переход: сцена не найдена — " + path)
		return false
	# В headless нет кадра для эффекта; сохраняем возможность служебного запуска.
	if DisplayServer.get_name() == "headless":
		return tree.change_scene_to_file(path) == OK
	var image := tree.root.get_texture().get_image()
	if image == null or image.is_empty():
		return tree.change_scene_to_file(path) == OK
	var error := ResourceLoader.load_threaded_request(path, "PackedScene")
	if error != OK:
		push_error("Переход: не удалось начать загрузку — " + path)
		return false
	image.generate_mipmaps()
	var transition := LumaWipe.new()
	transition.layer = 120
	transition.process_mode = Node.PROCESS_MODE_ALWAYS
	transition._path = path
	transition._effect = next_effect()
	if tree.current_scene:
		transition._origin = weakref(tree.current_scene)
	_active = transition
	tree.root.add_child(transition)
	transition.add_to_group("scene_transition")
	transition._setup(ImageTexture.create_from_image(image), tree.root.get_visible_rect().size, context)
	return true


func _setup(texture: Texture2D, viewport_size: Vector2, context: Dictionary = {}) -> void:
	_rect = TextureRect.new()
	_rect.texture = texture
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var material := ShaderMaterial.new()
	material.shader = TRANSITION_SHADER
	material.set_shader_parameter("old_screen", texture)
	material.set_shader_parameter("effect", SHADER_EFFECTS[_effect])
	material.set_shader_parameter("aspect", viewport_size.x / maxf(viewport_size.y, 1.0))
	material.set_shader_parameter("seed", randf())
	var box := context.get("box") as Node3D
	var camera := context.get("camera") as Camera3D
	if is_instance_valid(box) and is_instance_valid(camera):
		var center := camera.unproject_position(box.global_position) / viewport_size
		material.set_shader_parameter("focus", center.clamp(Vector2(0.2, 0.2), Vector2(0.8, 0.8)))
	_rect.material = material
	add_child(_rect)
	if _effect == EFFECTS.find("morph_cut"):
		_capture_ready = false
		_capture_box.call_deferred(context, Vector2i(viewport_size))


## Изолированный прозрачный кадр настоящей коробки: без комнаты и без панелей хаба.
func _capture_box(context: Dictionary, viewport_size: Vector2i) -> void:
	_box_viewport = SubViewport.new()
	_box_viewport.size = viewport_size
	_box_viewport.transparent_bg = true
	_box_viewport.own_world_3d = true
	_box_viewport.msaa_3d = Viewport.MSAA_4X
	_box_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_box_viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	_box_viewport.add_child(environment)
	var source := context.get("box") as Node3D
	var source_camera := context.get("camera") as Camera3D
	var camera: Camera3D
	if is_instance_valid(source) and is_instance_valid(source_camera):
		var original_environment := source.get_world_3d().environment
		if original_environment:
			environment.environment = original_environment.duplicate() as Environment
			environment.environment.background_mode = Environment.BG_CLEAR_COLOR
		var copy := source.duplicate(0) as Node3D
		# Геометрия уже построена. Повторный _ready GameBox создал бы её второй раз.
		copy.set_script(null)
		copy.transform = source.global_transform
		_box_viewport.add_child(copy)
		camera = source_camera.duplicate(0) as Camera3D
		camera.transform = source_camera.global_transform
	else:
		# У участника пати коробка может ещё стоять в шкафу: показываем выбранную игру.
		var box := GameBox.new()
		box.setup(context.get("game", {}), Vector3(0.075, 0.30, 0.30), Color("6b3fa0"))
		box.rotation.y = -PI / 2.0
		_box_viewport.add_child(box)
		camera = Camera3D.new()
		camera.position = Vector3(0, 0, 0.7)
		camera.fov = 52.0
	_box_viewport.add_child(camera)
	camera.current = true
	if not is_instance_valid(source):
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-25, -30, 0)
		light.light_energy = 0.8
		_box_viewport.add_child(light)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not is_instance_valid(_box_viewport):
		return
	var image := _box_viewport.get_texture().get_image()
	if image != null and not image.is_empty():
		image.generate_mipmaps()
		var material := _rect.material as ShaderMaterial
		material.set_shader_parameter("box_screen", ImageTexture.create_from_image(image))
		material.set_shader_parameter("has_box", true)
	_box_viewport.queue_free()
	_box_viewport = null
	_capture_ready = true


func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_elapsed += delta
	if not _scene_ready:
		if _switching or _elapsed < PREP or not _capture_ready:
			return
		var status := ResourceLoader.load_threaded_get_status(_path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			_abort("Не удалось загрузить игру. Попробуйте ещё раз.")
			return
		_switching = true
		_switch_scene.call_deferred()
		return
	_t += delta
	var progress := clampf(_t / float(DURATIONS[_effect]), 0.0, 1.0)
	(_rect.material as ShaderMaterial).set_shader_parameter("progress", 0.5 - 0.5 * cos(progress * PI))
	if progress >= 1.0:
		queue_free()


func _switch_scene() -> void:
	var scene := ResourceLoader.load_threaded_get(_path) as PackedScene
	if scene == null or get_tree().change_scene_to_packed(scene) != OK:
		_abort("Не удалось открыть игру. Попробуйте ещё раз.")
		return
	# Старый кадр непрозрачен, пока новая сцена строится и рисует первые кадры.
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_scene_ready = true
	_t = 0.0


func _abort(message: String) -> void:
	push_error("Переход: " + message)
	if _origin:
		var origin: Object = _origin.get_ref()
		if is_instance_valid(origin) and origin.has_method("_on_transition_failed"):
			origin._on_transition_failed(message)
	queue_free()


func _exit_tree() -> void:
	if _active == self:
		_active = null
