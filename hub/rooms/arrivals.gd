extends Node
## Новые настолки в шкафу игрока (из обновления, свои, позже — из мастерской): каждая не встаёт в шкаф
## сама, а прилетает к игроку. Обычные комнаты — вылетает с левой стены (с полок), как выбранная игра,
## но вместо «Играть» над коробкой две кнопки: «Поставить на полку» и «Поставить в шкаф» (те же значки,
## что у переноса). Нет места в шкафу — говорим об этом, коробка остаётся в руках.
## Зимняя комната (тема с методом gift_pose) — коробка появляется под ёлкой в подарочной обёртке и так
## же летит к игроку; название и описание скрыты, пока не развернёт: 5 нажатий по коробке — слетает бант,
## затем по одному откидываются четыре клапана бумаги на обложке (остаются висеть), коробка вздрагивает.
## Какие игры уже «получены» — user://room_props.cfg [arrivals] seen. Первый запуск: всё, что есть, — получено.
## Узел — потомок NeonRoom (room); комната сама паркует новые коробки на нижней полке левой стены.

signal changed  # состояние прилёта (обёртка, кнопки) — хаб перерисовывает карточку

const SAVE_PATH := "user://room_props.cfg"
const CLICKS := 5  # нажатий: бант и четыре клапана

var room: Node3D
var box: GameBox  # прилетевшая сейчас
var wrapped := false
var clicks := 0
var _queue: Array = []
var _wrap: Node3D
var _parts: Array = []  # куски обёртки по шагам раскрытия
var _buttons: HBoxContainer
var _wait := 0.0
var _restore_home: Variant = null  # место на полке, пока подарок лежит под ёлкой


## Игры, которые игрок уже получил; null — список ещё не заводили.
static func seen_ids() -> Variant:
	var prefs := ConfigFile.new()
	if prefs.load(SAVE_PATH) != OK or not prefs.has_section_key("arrivals", "seen"):
		return null
	var list: Variant = prefs.get_value("arrivals", "seen", [])
	return list if list is Array else []


static func mark_seen(ids: Array) -> void:
	var prefs := ConfigFile.new()
	prefs.load(SAVE_PATH)
	var list: Array = prefs.get_value("arrivals", "seen", []) if prefs.has_section_key("arrivals", "seen") else []
	for id: String in ids:
		if not list.has(id):
			list.append(id)
	prefs.set_value("arrivals", "seen", list)
	prefs.save(SAVE_PATH)


func enqueue(list: Array) -> void:
	for b: GameBox in list:
		if not _queue.has(b) and b != box:
			_queue.append(b)
	_wait = 0.0


func busy() -> bool:
	return box != null


func _process(delta: float) -> void:
	if box != null:
		_place_buttons()
		return
	if _queue.is_empty():
		return
	_wait -= delta
	if _wait > 0.0:
		return
	if not _room_idle():
		_wait = 0.5
		return
	_start(_queue.pop_front())


func _room_idle() -> bool:
	return (
		not bool(room.get("remote_view")) and not bool(room.get("_editor_on")) and room.get("focused") == null
		and room.get("_drag_box") == null and not bool(room.call("board_focused")) and not bool(room.call("left_wall_view"))
		and not bool(room.get("_ball_held"))
	)


func _start(next: GameBox) -> void:
	if not is_instance_valid(next):
		return
	box = next
	clicks = 0
	var theme: Variant = room.get("_room_theme")
	wrapped = is_instance_valid(theme) and (theme as Node).has_method("gift_pose")
	room.set("arrival_box", box)
	if wrapped:
		# под ёлкой: коробка лежит, на ней обёртка; оттуда и вылетает
		var gift: Transform3D = (theme as Node).call("gift_pose", box.size)
		var local: Transform3D = (box.get_parent() as Node3D).global_transform.affine_inverse() * gift
		var real_home := box.home
		_restore_home = real_home
		box.transform = local
		box.home = local
		_make_wrap()
		Sfx.play("card_slide", -10)
		await get_tree().create_timer(0.29).timeout
		if box == null:
			return
		room.call("focus", box)
		box.home = real_home
		_restore_home = null
	else:
		room.call("focus", box, 1.0)  # с нижней полки левой стены, как обычная коробка
		Sfx.play("card_shove", -8)
	_make_buttons()
	changed.emit()


## Прерывание (редактор шкафа, комната друга): коробка возвращается на полку и прилетит позже.
func abort() -> void:
	if box == null:
		return
	_queue.push_front(box)
	_clear_wrap()
	_free_buttons()
	var was := box
	if _restore_home is Transform3D:
		was.home = _restore_home
		was.transform = _restore_home
	_restore_home = null
	box = null
	wrapped = false
	room.set("arrival_box", null)
	if room.get("focused") == was:
		room.call("release")
	_wait = 1.5


# --- Обёртка ------------------------------------------------------------------------------

## Обёртка: бумага на всех сторонах, а обложку (+X) закрывают четыре треугольных клапана от краёв к центру
## (как конверт); в центре — лоу-поли бант зимней комнаты, параллельно обложке.
## Шаги: 1 — бант слетает, 2–5 — клапаны по одному откидываются наружу и остаются висеть за краем коробки.
func _make_wrap() -> void:
	_clear_wrap()
	_wrap = Node3D.new()
	_wrap.name = "GiftWrap"
	box.add_child(_wrap)
	var size := box.size + Vector3.ONE * 0.006
	var paper := StandardMaterial3D.new()
	paper.albedo_texture = load("res://hub/art/winter/wrap.png")
	paper.uv1_triplanar = true
	paper.uv1_scale = Vector3.ONE * 3.2
	paper.roughness = 0.55
	paper.cull_mode = BaseMaterial3D.CULL_DISABLED
	var faces := {
		"top": [Vector3(size.x, 0.002, size.z), Vector3(0, size.y * 0.5, 0)],
		"back": [Vector3(0.002, size.y, size.z), Vector3(-size.x * 0.5, 0, 0)],
		"bottom": [Vector3(size.x, 0.002, size.z), Vector3(0, -size.y * 0.5, 0)],
		"left": [Vector3(size.x, size.y, 0.002), Vector3(0, 0, -size.z * 0.5)],
		"right": [Vector3(size.x, size.y, 0.002), Vector3(0, 0, size.z * 0.5)],
	}
	for key: String in faces:
		_part(faces[key][0], faces[key][1], paper, _wrap)
	# клапаны: [середина петли-кромки, направление к центру обложки, полуширина кромки, ось кромки]
	var fx := size.x * 0.5 + 0.002
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var flaps: Array = []
	for spec: Array in [[Vector3(fx, hy, 0), Vector3.DOWN, hz, Vector3.BACK], [Vector3(fx, 0, hz), Vector3.FORWARD, hy, Vector3.UP],
			[Vector3(fx, -hy, 0), Vector3.UP, hz, Vector3.BACK], [Vector3(fx, 0, -hz), Vector3.BACK, hy, Vector3.UP]]:
		var pivot := Node3D.new()
		pivot.position = spec[0]
		_wrap.add_child(pivot)
		var inward: Vector3 = spec[1]
		var edge: Vector3 = spec[3]
		var reach := hy if absf(inward.y) > 0.5 else hz
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v: Vector3 in [edge * float(spec[2]), -edge * float(spec[2]), inward * reach]:
			st.set_normal(Vector3.RIGHT)
			st.set_uv(Vector2(v.z, v.y) * 3.0)
			st.add_vertex(v)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = paper
		pivot.add_child(mi)
		# ось поворота: при открытии клапан сначала выходит наружу (+X), потом за край коробки
		pivot.set_meta("flap_axis", inward.cross(Vector3.RIGHT).normalized())
		flaps.append(pivot)
	# бант — лоу-поли из зимней темы, лежит на обложке поверх клапанов
	var bow: Node3D = null
	var theme: Variant = room.get("_room_theme")
	if theme is Node and (theme as Node).has_method("_bow"):
		var scale := clampf(minf(size.y, size.z) * 0.5 / 0.15, 0.5, 1.4)
		bow = (theme as Node).call("_bow", Vector3(fx + 0.004, 0.0, 0.0), PI * 0.5, _wrap, scale)
	_parts = [[bow] if bow != null else [], [flaps[0]], [flaps[1]], [flaps[2]], [flaps[3]]]


func _part(extent: Vector3, at: Vector3, material: Material, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = extent
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = at
	parent.add_child(mi)
	return mi


func _clear_wrap() -> void:
	if is_instance_valid(_wrap):
		_wrap.queue_free()
	_wrap = null
	_parts.clear()


## Нажатие по коробке в обёртке: кусок обёртки отлетает, коробка вздрагивает.
func _unwrap_step() -> void:
	clicks += 1
	_shake()
	var step: Array = _parts[clicks - 1] if clicks - 1 < _parts.size() else []
	var away := Vector3(1.0, 0.6, 0.0)
	for node: Node3D in step:
		if not is_instance_valid(node):
			continue
		if node.has_meta("flap_axis"):
			# клапан откидывается на петле и остаётся держаться за краем (бумага единая)
			var axis: Vector3 = node.get_meta("flap_axis")
			var turn := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			turn.tween_method(func(a: float): node.basis = Basis(axis, a), 0.0, deg_to_rad(200.0), 0.45)
			continue
		var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var dir := (node.position.normalized() if node.position.length() > 0.001 else away) * 0.18 + Vector3(0, 0.08, 0)
		t.tween_property(node, "position", node.position + dir, 0.35)
		t.tween_property(node, "rotation", node.rotation + Vector3(randf_range(-1.2, 1.2), randf_range(-1.2, 1.2), randf_range(-1.2, 1.2)), 0.35)
		t.tween_property(node, "scale", Vector3.ONE * 0.05, 0.35).set_delay(0.12)
		t.chain().tween_callback(node.queue_free)
	Sfx.play("card_slide" if clicks < CLICKS else "card_place", -6, 0.1)
	if clicks >= CLICKS:
		wrapped = false  # раскрытая бумага остаётся на коробке, пока её не поставят на место
		_make_buttons()
	changed.emit()


func _shake() -> void:
	var base: Transform3D = box.get("_focus_target")
	var t := create_tween().set_trans(Tween.TRANS_SINE)
	for a: float in [0.07, -0.06, 0.04, -0.02, 0.0]:
		t.tween_property(box, "transform", Transform3D(base.basis * Basis(Vector3.UP, a), base.origin), 0.05)


func _input(event: InputEvent) -> void:
	if box == null or not wrapped or bool(room.get("remote_view")):
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var camera: Camera3D = room.get("camera")
	var origin := camera.project_ray_origin(event.position)
	var dir := camera.project_ray_normal(event.position)
	var inv := box.global_transform.affine_inverse()
	var half := box.size * 0.5 + Vector3.ONE * 0.03
	if AABB(-half, half * 2.0).intersects_ray(inv * origin, inv.basis * dir) != null:
		get_viewport().set_input_as_handled()
		_unwrap_step()


# --- Кнопки «на полку» / «в шкаф» -------------------------------------------------------------

func _make_buttons() -> void:
	_free_buttons()
	if wrapped:
		return
	_buttons = HBoxContainer.new()
	_buttons.name = "ArrivalButtons"
	_buttons.add_theme_constant_override("separation", 6)
	(room as Node).add_child(_buttons)
	var shelf := HubStyle.button("", 14)
	shelf.name = "ArrivalToShelf"
	shelf.custom_minimum_size = Vector2(46, 44)
	shelf.icon = ShelfIcons.icon(-2)
	shelf.tooltip_text = "Поставить на полку у левой стены"
	shelf.pressed.connect(_to_shelf)
	_buttons.add_child(shelf)
	var cabinet := HubStyle.button("", 14)
	cabinet.name = "ArrivalToCabinet"
	cabinet.custom_minimum_size = Vector2(46, 44)
	cabinet.icon = ShelfIcons.icon(-3)
	cabinet.tooltip_text = "Поставить в шкаф"
	cabinet.pressed.connect(_to_cabinet)
	_buttons.add_child(cabinet)
	_place_buttons()


func _free_buttons() -> void:
	if is_instance_valid(_buttons):
		_buttons.queue_free()
	_buttons = null


func _place_buttons() -> void:
	if not is_instance_valid(_buttons) or box == null:
		return
	var camera: Camera3D = room.get("camera")
	var top := box.global_transform * Vector3(0, box.size.y * 0.5 + 0.03, 0)
	var at := camera.unproject_position(top) - Vector2(49, 56)
	_buttons.position = at.clamp(Vector2(8, 70), (room as Node).get_viewport().get_visible_rect().size - Vector2(110, 52))


func _to_shelf() -> void:
	if not bool(room.call("park_on_wall", box)):
		room.emit_signal("shelf_hint", "На полке у левой стены нет места")
		return
	_finish("Игра на полке у левой стены")


func _to_cabinet() -> void:
	if not bool(room.call("arrival_to_cabinet", box)):
		room.emit_signal("shelf_hint", "В шкафу не хватает места — освободите место или поставьте игру на полку")
		_flash_no_room()
		return
	_finish("Игра в шкафу")


func _flash_no_room() -> void:
	if not is_instance_valid(_buttons):
		return
	var note := HubStyle.label("В шкафу не хватает места", 14, HubStyle.YELLOW)
	note.name = "ArrivalNoRoom"
	note.position = _buttons.position + Vector2(-60, -30)
	(room as Node).add_child(note)
	var t := note.create_tween()
	t.tween_interval(1.8)
	t.tween_property(note, "modulate:a", 0.0, 0.4)
	t.tween_callback(note.queue_free)


func _finish(message: String) -> void:
	var done := box
	mark_seen([str(done.get_meta("shelf_id", done.game.get("id", "")))])
	_free_buttons()
	_clear_wrap()
	box = null
	wrapped = false
	room.set("arrival_box", null)
	room.call("release")
	room.call("_save_shelf")
	room.emit_signal("shelf_hint", message)
	changed.emit()
	_wait = 0.0
