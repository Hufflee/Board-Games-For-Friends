extends Control
## BGSocial — отдельное окно «Общение» с той же сетью, чатом и мини-играми, что у основного приложения.
## Окно прозрачное, без рамки, поверх всех окон и размером с рабочую область экрана: видна только панель
## (или кнопка «Общение»), её можно таскать по всему экрану. Клики мимо панели проходят в окна под ней —
## область приёма мыши каждые 0,1 с пересобирается из прямоугольников панели, её меню и всплывашек.
## Иконка в трее: клик — открыть/свернуть панель, меню — показать, спрятать, выйти.
## Прозрачность включается настройками проекта с feature `bgs_social` (project.godot), поэтому
## работает только в экспортированном BGSocial.exe; запуск из проекта `-- --social` — обычное окно.

const ICON_PATH := "res://hub/art/brand/social.png"
const REGION_EVERY := 0.1
const MARGIN := 6.0  # запас вокруг панели — тень и уголок изменения размера

var _panel: Control
var _attempted := false
var _friends: PopupMenu
var _lobbies: Array = []
var _tray: StatusIndicator
var _region_wait := 0.0
var _region: PackedVector2Array = []
var _overlay := false  # открыт оверлей Steam — он рисуется на всё окно
var _overlay_wait := 0.0  # ждём, что оверлей правда открылся (иначе — своё окно приглашений)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var window := get_window()
	window.title = "BGSocial"
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.min_size = Vector2i(1, 1)
	window.mode = Window.MODE_WINDOWED
	window.borderless = true
	window.always_on_top = true
	window.transparent = true
	get_viewport().transparent_bg = true
	window.close_requested.connect(get_tree().quit)
	var desktop := DisplayServer.screen_get_usable_rect(window.current_screen)
	window.position = desktop.position
	window.size = desktop.size
	var icon := _icon()
	if icon != null:
		DisplayServer.set_icon(icon.get_image())
	_panel = Net.chat.panel()
	await get_tree().process_frame
	_panel.set_mode(1)
	if Net.steam_ok and Net.steam.has_signal("overlay_toggled"):
		Net.steam.overlay_toggled.connect(func(active: bool, _user: bool = false, _app: int = 0):
			_overlay = active
			_overlay_wait = 0.0)
	_friends = PopupMenu.new()
	add_child(_friends)
	_friends.index_pressed.connect(_join_friend)
	_make_tray(icon)
	var shot := OS.get_environment("BGS_SHOT")  # проверка: снимок своего кадра (с прозрачностью) и выход
	if shot != "":
		if OS.get_environment("BGS_SHOT_OPEN") == "1":
			_panel.set_mode(0)
		await get_tree().create_timer(4.0).timeout
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()


func _icon() -> Texture2D:
	if ResourceLoader.exists(ICON_PATH):
		return load(ICON_PATH) as Texture2D
	var img := Image.load_from_file(ProjectSettings.globalize_path(ICON_PATH))
	return ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null


func _process(delta: float) -> void:
	if Net.steam_ok and not _attempted and not Net._joining and not Net._hosting_steam:
		_attempted = true
		if not Net.is_party():
			Net.host_steam()
	if not is_instance_valid(_panel):
		return
	if _overlay_wait > 0.0:
		_overlay_wait -= delta
		if _overlay_wait <= 0.0 and _overlay:
			# Оверлей Steam не открылся (выключен или не встроился) — своё окно приглашений.
			_overlay = false
			SteamInvite.open_panel(100)
	_region_wait -= delta
	if _region_wait <= 0.0:
		_region_wait = REGION_EVERY
		_collect_extras()
	_update_region()


## Меню и подсказки, вылезающие за панель (кнопки «+», «друзья», «Фразы»…) и всплывающие окна.
var _extras: Array[Rect2] = []

func _collect_extras() -> void:
	_extras.clear()
	var own := _panel.get_global_rect()
	var found: Array[Node] = _panel.get_parent().find_children("*", "Control", true, false)
	for n: Node in get_tree().root.get_children():
		if n is SteamInvite:  # всплывающее «вас пригласили» — его кнопки тоже нажимаются
			found.append_array(n.find_children("*", "Control", true, false))
	for c: Node in found:
		var ctrl := c as Control
		if ctrl == _panel or not ctrl.is_visible_in_tree() or ctrl.mouse_filter != Control.MOUSE_FILTER_STOP:
			continue
		var r := ctrl.get_global_rect()
		if r.has_area() and not own.encloses(r):
			_extras.append(r)
	for w: Window in get_viewport().get_embedded_subwindows():
		if w.visible:
			_extras.append(Rect2(Vector2(w.position), Vector2(w.size)).grow(MARGIN))


## Мышь принимают только панель и её всплывашки — остальное окно «дырявое». В Windows эта же область
## обрезает и отрисовку, поэтому пока панель тащат или тянут за уголок, окно целиком — иначе она мелькает.
func _update_region() -> void:
	var rects: Array[Rect2] = []
	if _panel.get("_dragging") or _panel.get("_resizing") or _overlay or _invite_open():
		rects.append(Rect2(Vector2.ZERO, Vector2(get_window().size)))
	else:
		if _panel.visible:
			rects.append(_panel.get_global_rect().grow(MARGIN))
		rects.append_array(_extras)
	var poly := _region_polygon(rects)
	if poly == _region:
		return
	_region = poly
	var window := get_window()
	if poly.is_empty():
		# Пустой список отключил бы «дырявость» целиком — вместо этого прячем окно (остаётся трей).
		window.visible = false
		return
	if not window.visible:
		window.visible = true
	DisplayServer.window_set_mouse_passthrough(poly, window.get_window_id())


## Своё окно приглашений Steam (SteamInvite) открыто — оно по центру экрана с затемнением.
func _invite_open() -> bool:
	for n: Node in get_tree().root.get_children():
		if n is SteamInvite and (n.has_meta("panel") or bool(n.get("_browse"))):
			return true
	return false


## «Пригласить»: оверлей Steam на весь экран; без Steam/оверлея — своё окно приглашений.
func invite_friends() -> void:
	if Net.steam_ok and Net.lobby_id != 0 and Net.steam.isOverlayEnabled():
		_overlay = true  # окно целиком ещё до первого кадра оверлея, иначе он обрежется по панели
		_overlay_wait = 2.0
		Net.steam.activateGameOverlayInviteDialog(Net.lobby_id)
	else:
		SteamInvite.open_panel(100)


## Один многоугольник из нескольких прямоугольников: пересекающиеся сливаем, отдельные соединяем
## нулевыми «перемычками» через первую вершину (Windows заполняет по правилу чередования).
static func _region_polygon(rects: Array[Rect2]) -> PackedVector2Array:
	var shapes: Array[PackedVector2Array] = []
	for r: Rect2 in rects:
		var p := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		var merged := true
		while merged:
			merged = false
			for i in shapes.size():
				var m := Geometry2D.merge_polygons(shapes[i], p)
				if m.size() == 1:
					p = m[0]
					shapes.remove_at(i)
					merged = true
					break
		shapes.append(p)
	var out := PackedVector2Array()
	for s: PackedVector2Array in shapes:
		out.append_array(s)
		out.append(s[0])
		out.append(shapes[0][0])
	for i in out.size():
		out[i] = out[i].round()
	return out


func _make_tray(icon: Texture2D) -> void:
	var menu := PopupMenu.new()
	menu.prefer_native_menu = true
	menu.add_item("Показать «Общение»", 0)
	menu.add_item("Спрятать в трей", 1)
	menu.add_separator()
	menu.add_item("Выйти", 2)
	menu.id_pressed.connect(_tray_menu)
	add_child(menu)
	_tray = StatusIndicator.new()
	_tray.tooltip = "BGSocial — общение"
	if icon != null:
		_tray.icon = icon
	add_child(_tray)
	_tray.menu = _tray.get_path_to(menu)
	_tray.pressed.connect(_tray_pressed)


func _tray_pressed(button: int, _at: Vector2i) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	# Открыта — в кнопку, иначе — открыть (в том числе из трея).
	_show(1 if _panel.mode == 0 else 0)


func _tray_menu(id: int) -> void:
	match id:
		0: _show(0)
		1: _panel.set_mode(2)
		2: get_tree().quit()


func _show(mode: int) -> void:
	var window := get_window()
	window.visible = true
	if window.mode == Window.MODE_MINIMIZED:
		window.mode = Window.MODE_WINDOWED
	_panel.set_mode(mode)
	_region_wait = 0.0


func show_friends(anchor: Button) -> void:
	_lobbies = Net.steam_friend_parties()
	_friends.clear()
	for lobby: Dictionary in _lobbies:
		_friends.add_item(str(lobby.name))
	if _lobbies.is_empty():
		_friends.add_item("У друзей пока нет открытых лобби" if Net.steam_ok else "Войдите в Steam")
		_friends.set_item_disabled(0, true)
	var at := Vector2i(anchor.global_position + Vector2(0, anchor.size.y))
	if not get_window().gui_embed_subwindows:
		at += get_window().position
	_friends.popup(Rect2i(at, Vector2i(250, 0)))


func _join_friend(index: int) -> void:
	if index < _lobbies.size():
		Net.join_steam(int(_lobbies[index].lobby))
