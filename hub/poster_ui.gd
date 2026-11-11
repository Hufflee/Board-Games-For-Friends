extends Control
## Плакаты в хабе (поверх 3D-комнаты): после удержания плаката над ним появляется значок галереи; нажатие —
## проводник Windows, выбранная фотография становится плакатом (рамка — по пропорциям фото, размер плаката
## постоянный, большое фото — только чётче). Места и картинки плакатов своей комнаты сохраняются и через хоста
## видны друзьям в режиме наблюдения (Net.stickers, hub/sticker_net.gd). Создаёт hub.gd.
## Крестик рядом со значками (удержать) снимает плакат совсем; новый плакат — add_poster() (кнопка редактора шкафа).

const Stickers := preload("res://hub/stickers.gd")
const RoomIcons := preload("res://hub/room_icons.gd")
const ICON := Vector2(48, 40)
const SHOW_TIME := 6.0  # сколько висит значок после удержания

var _room: NeonRoom
var _watch_peer: Callable
var _icon: Button
var _size_button: Button  # ⤢ рядом со значком галереи: размер плаката ×1 / ×1,5 / ×2
var _remove: Button  # крестик: удержать — снять плакат
var _slot := -1  # плакат, над которым значок
var _icon_left := 0.0
var _clock := 0.0


func _init(room: NeonRoom, watch_peer: Callable) -> void:
	_room = room
	_watch_peer = watch_peer


func _ready() -> void:
	name = "PosterUI"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon = HubStyle.button("", 14)
	_icon.name = "PosterGallery"
	_icon.custom_minimum_size = ICON
	_icon.tooltip_text = "Заменить картинку плаката — выбрать фото или GIF"
	_icon.draw.connect(_draw_gallery)
	_icon.pressed.connect(_choose_picture)
	_icon.visible = false
	add_child(_icon)
	_size_button = HubStyle.button("×1", 13)
	_size_button.name = "PosterSize"
	_size_button.custom_minimum_size = Vector2(52, ICON.y)
	_size_button.tooltip_text = "Размер плаката: обычный, ×1,5 или ×2"
	_size_button.pressed.connect(_cycle_size)
	_size_button.visible = false
	add_child(_size_button)
	_remove = HubStyle.button("", 14)
	_remove.name = "PosterRemove"
	_remove.custom_minimum_size = Vector2(ICON.y, ICON.y)
	_remove.draw.connect(func(): RoomIcons.cross(_remove, HubStyle.PINK))
	LeaveGuard.hold(_remove, _remove_poster, "Снять плакат со стены")
	_remove.visible = false
	add_child(_remove)
	_room.poster_held.connect(_on_held)
	_room.poster_add_requested.connect(add_poster)
	_room.poster_moved.connect(func(slot: int, center: Vector2):
		if _own_room():
			Net.stickers.set_poster_pos(slot, center))
	Net.stickers.poster_ready.connect(func(_hash): _apply())
	Net.stickers.changed.connect(func(_peer): _apply())
	_apply()


func _peer() -> int:
	return int(_watch_peer.call())


func _own_room() -> bool:
	return _peer() == 0 and not _room.remote_view


## Плакаты той комнаты, что на экране: места и картинки (пока картинка друга качается — стандартная).
func _apply() -> void:
	if not is_instance_valid(_room):
		return
	var data: Dictionary = Net.stickers.room_of(_peer())
	var list: Array = data.get("posters", [])
	var shown: Array = Stickers.poster_slots(data)
	_room.show_posters(shown)
	for slot: int in shown:
		var poster: Node3D = _room.posters[slot]
		var entry: Array = list[slot] if slot < list.size() and list[slot] is Array else []
		var center: Vector2 = Vector2(float(entry[0]), float(entry[1])) if entry.size() >= 3 else _room.poster_default_position(slot)
		var hash: String = str(entry[2]) if entry.size() >= 3 else ""
		poster.set_size_scale(float(entry[3]) if entry.size() >= 4 else 1.0)
		if hash.is_empty():
			poster.show_default()
		elif poster.picture_key != hash:
			var texture: Resource = Net.stickers.poster_texture(hash)
			if texture != null:
				poster.set_picture(texture, hash)
		_room.set_poster_position(slot, center, Net.stickers.poster_layer(_peer(), slot))


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= 0.3:
		_clock = 0.0
		_apply()
	if _slot < 0:
		return
	_icon_left -= delta
	var dragging: bool = _room.poster_dragging != null
	if (_icon_left <= 0.0 and not dragging) or not _own_room() or _slot >= _room.posters.size() or not _room.posters[_slot].visible:
		_hide_icon()
		return
	# Над верхним краем плаката, по центру.
	var poster: Node3D = _room.posters[_slot]
	var top: Vector3 = poster.global_position + Vector3(0, poster.wall_size().y / 2.0 + 0.03, 0.02)
	if _room.camera.is_position_behind(top):
		_icon.visible = false
		return
	_icon.visible = true
	var at := _room.camera.unproject_position(top) - Vector2(ICON.x / 2.0, ICON.y + 4)
	_icon.position = at - Vector2(30, 0)
	_size_button.visible = true
	_size_button.position = at + Vector2(ICON.x - 22, 0)
	_size_button.text = "×%s" % _scale_text(poster.size_scale)
	_remove.visible = true
	_remove.position = at + Vector2(ICON.x + 36, 0)


func _on_held(slot: int) -> void:
	if not _own_room():
		return
	_slot = slot
	_icon_left = SHOW_TIME
	_icon.visible = true


func _hide_icon() -> void:
	_slot = -1
	_icon.visible = false
	_size_button.visible = false
	_remove.visible = false


## Крестик удержан: плакат снимается совсем (повесить снова — кнопкой плаката в редакторе шкафа).
func _remove_poster() -> void:
	var slot := _slot
	_hide_icon()
	if slot < 0 or not _own_room():
		return
	Net.stickers.remove_poster(slot)
	Sfx.play("card_shove", -6, 0.08)
	_apply()
	_toast("Плакат снят · новый можно повесить в редакторе шкафа")


## Новый плакат появляется сразу. Картинку можно сменить через его меню.
func add_poster() -> void:
	if not _own_room():
		return
	var slot: int = Net.stickers.free_poster_slot()
	if slot < 0:
		_toast("Плакатов уже %d — снимите какой-нибудь, чтобы повесить новый" % Stickers.POSTERS_MAX)
		return
	var center: Vector2 = _room.free_wall_spot(Vector2(0.5, 0.4))
	Net.stickers.set_default_poster(slot, center)
	Sfx.play("card_place", -6, 0.08)
	_apply()
	_toast("Плакат повешен · удерживайте его, чтобы сменить картинку")


func _scale_text(scale: float) -> String:
	return "2" if scale >= 1.99 else ("1,5" if scale >= 1.49 else "1")


## Размер по кругу: обычный → ×1,5 → ×2 → обычный.
func _cycle_size() -> void:
	if _slot < 0 or _slot >= _room.posters.size():
		return
	_icon_left = SHOW_TIME
	var poster: Node3D = _room.posters[_slot]
	var next := 1.5 if poster.size_scale < 1.49 else (2.0 if poster.size_scale < 1.99 else 1.0)
	poster.set_size_scale(next)
	var center := _room.clamp_poster(poster, Vector2(poster.position.x, poster.position.y))
	Net.stickers.set_poster_scale(_slot, center, next)
	Sfx.play("card_place", -8, 0.08)
	_apply()


## Минималистичный значок галереи: рамка со скруглёнными углами, две горы и солнце — линиями.
func _draw_gallery() -> void:
	var color := HubStyle.TEXT
	var box := Rect2(Vector2(9, 8), _icon.size - Vector2(18, 16))
	var r := 4.0
	var points := PackedVector2Array()
	for corner in 4:
		var center := [box.position + Vector2(r, r), Vector2(box.end.x - r, box.position.y + r), box.end - Vector2(r, r), Vector2(box.position.x + r, box.end.y - r)][corner] as Vector2
		for step in 5:
			var angle := PI + corner * PI / 2.0 + step * PI / 8.0
			points.append(center + Vector2(cos(angle), sin(angle)) * r)
	points.append(points[0])
	_icon.draw_polyline(points, color, 2.0, true)
	var base := box.end.y - 1.0
	_icon.draw_polyline(PackedVector2Array([Vector2(box.position.x + 3, base), Vector2(box.position.x + box.size.x * 0.38, box.position.y + box.size.y * 0.32), Vector2(box.position.x + box.size.x * 0.66, base)]), color, 2.0, true)
	_icon.draw_polyline(PackedVector2Array([Vector2(box.position.x + box.size.x * 0.52, box.position.y + box.size.y * 0.66), Vector2(box.position.x + box.size.x * 0.7, box.position.y + box.size.y * 0.48), Vector2(box.end.x - 3, base)]), color, 2.0, true)
	_icon.draw_arc(Vector2(box.end.x - box.size.x * 0.22, box.position.y + box.size.y * 0.3), 3.2, 0, TAU, 16, color, 2.0, true)


## Проводник Windows (системное окно): выбрать любую фотографию.
func _choose_picture() -> void:
	var slot := _slot
	if slot < 0:
		return
	_icon_left = SHOW_TIME
	var filters := PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.gif ; Картинки и GIF"])
	var start := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	var err := DisplayServer.file_dialog_show("Картинка для плаката", start, "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters,
		func(status: bool, paths: PackedStringArray, _filter: int): _picked(slot, status, paths))
	if err != OK:
		_toast("Не удалось открыть проводник")


func _picked(slot: int, status: bool, paths: PackedStringArray, at: Variant = null) -> void:
	if not status or paths.is_empty() or slot < 0 or slot >= _room.posters.size():
		return
	var poster: Node3D = _room.posters[slot]
	var center: Vector2 = at if at is Vector2 else Vector2(poster.position.x, poster.position.y)
	var hash: String
	if paths[0].get_extension().to_lower() == "gif":
		var file := FileAccess.open(paths[0], FileAccess.READ)
		if file == null or file.get_length() > Stickers.POSTER_MAX_BYTES:
			_toast("Не удалось открыть GIF. Максимальный размер — 900 КБ.")
			return
		hash = Net.stickers.set_poster_gif(slot, file.get_buffer(file.get_length()), center)
	else:
		var image := Image.load_from_file(paths[0])
		if image == null or image.is_empty():
			_toast("Эту картинку не получилось открыть — подойдут PNG, JPG, WEBP, BMP и GIF")
			return
		hash = Net.stickers.set_poster_picture(slot, image, center)
	if hash != "":
		Sfx.play("card_place", -6, 0.08)
		_apply()
		_hide_icon()


func _toast(text: String) -> void:
	_room.shelf_hint.emit(text)
