class_name SteamInvite
extends CanvasLayer
## Приглашения Steam внутри игры — без оверлея Steam (он не появляется, если игру запустили
## не из библиотеки Steam). Окно со списком друзей и кнопкой «Пригласить», а входящее приглашение —
## всплывающая плашка «Принять / Отклонить». Оформление нейтральное, кнопки берут тему текущей игры.

const STATES := {0: "не в сети", 1: "в сети", 2: "занят", 3: "отошёл", 4: "спит", 5: "хочет обменяться", 6: "хочет поиграть"}

var _list: VBoxContainer
var _status: Label
var _invited := {}
var _browse := false  # окно «Пати друзей»: не приглашать, а войти к другу


## Окно «Пригласить друзей». Открывается поверх любого экрана.
## on_layer — слой окна (из меню паузы — выше её затемнения).
static func open_panel(on_layer: int = 50) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for n in tree.root.get_children():
		if n is SteamInvite and n.has_meta("panel"):
			return
	var layer := SteamInvite.new()
	layer.set_meta("panel", true)
	layer.layer = on_layer
	tree.root.add_child(layer)
	layer._build_panel()


## Окно «Пати друзей»: друзья, которые сейчас в пати этой игры, — кнопка «Войти».
static func open_browser(on_layer: int = 50) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var layer := SteamInvite.new()
	layer.set_meta("panel", true)
	layer._browse = true
	layer.layer = on_layer
	tree.root.add_child(layer)
	layer._build_panel()


## Входящее приглашение: «Имя приглашает вас» — Принять / Отклонить.
static func show_incoming(from_name: String, lobby: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var layer := SteamInvite.new()
	layer.layer = 60
	tree.root.add_child(layer)
	layer._build_toast(from_name, lobby)


static func _box(color: Color, radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(16)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 12
	return sb


static func _label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _build_panel() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			queue_free())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(0.1, 0.11, 0.14, 0.97)))
	p.custom_minimum_size = Vector2(460, 0)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	p.add_child(col)
	col.add_child(_label("Browse lobbies" if _browse else "Пригласить друзей из Steam", 22))
	col.add_child(_label("Друзья из Steam, которые сейчас собрались в этой игре." if _browse else "Друг получит приглашение в Steam и прямо в игре, если она запущена.", 13, Color(1, 1, 1, 0.6)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	col.add_child(scroll)
	_status = _label("", 13, Color("9fe0a0"))
	col.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if not _browse and Net.steam_ok and Net.steam.isOverlayEnabled():
		var ov := Button.new()
		ov.text = "Оверлей Steam"
		ov.pressed.connect(func(): Net.steam.activateGameOverlayInviteDialog(Net.lobby_id))
		row.add_child(ov)
	var refresh := Button.new()
	refresh.text = "Обновить"
	refresh.pressed.connect(_fill)
	row.add_child(refresh)
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(queue_free)
	row.add_child(close)
	col.add_child(row)
	_fill()


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	if _browse:
		_fill_parties()
		return
	if not Net.steam_ok or Net.lobby_id == 0:
		_list.add_child(_label("Приглашать через Steam можно из пати, созданной через Steam.", 15, Color(1, 1, 1, 0.8)))
		return
	var friends := Net.steam_friends()
	if friends.is_empty():
		_list.add_child(_label("Список друзей пуст или Steam ещё не загрузил его.", 15, Color(1, 1, 1, 0.8)))
		return
	for f in friends:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var av := TextureRect.new()
		av.custom_minimum_size = Vector2(32, 32)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av.texture = Net.avatar(int(f["id"]))
		row.add_child(av)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", -2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_label(str(f["name"]), 16))
		var st: String = STATES.get(int(f["state"]), "")
		if f.get("in_party", false):
			st = "уже в пати"
		info.add_child(_label(st, 12, Color(1, 1, 1, 0.5) if int(f["state"]) == 0 else Color("9fe0a0")))
		row.add_child(info)
		var b := Button.new()
		var id: int = f["id"]
		b.text = "Приглашён ✓" if _invited.has(id) else "Пригласить"
		b.disabled = _invited.has(id) or f.get("in_party", false)
		b.pressed.connect(func():
			if Net.invite_friend(id):
				_invited[id] = true
				b.text = "Приглашён ✓"
				b.disabled = true
				_status.text = "Приглашение отправлено: %s" % f["name"]
			else:
				_status.text = "Steam не принял приглашение — попробуйте ещё раз.")
		row.add_child(b)
		_list.add_child(row)


func _fill_parties() -> void:
	if not Net.steam_ok:
		_list.add_child(_label("Steam недоступен — запустите Steam и перезапустите игру.", 15, Color(1, 1, 1, 0.8)))
		return
	var parties := Net.steam_friend_parties()
	if parties.is_empty():
		var l := _label("Сейчас никто из друзей не собрал пати. Создайте свою и пригласите их — или нажмите «Обновить» чуть позже.", 15, Color(1, 1, 1, 0.8))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(l)
		return
	for f in parties:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var av := TextureRect.new()
		av.custom_minimum_size = Vector2(32, 32)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av.texture = Net.avatar(int(f["id"]))
		row.add_child(av)
		var nm := _label("Пати: %s" % f["name"], 16)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var b := Button.new()
		b.text = "Войти"
		var lobby: int = f["lobby"]
		b.pressed.connect(func():
			_status.text = "Входим в пати %s…" % f["name"]
			Net.join_steam(lobby)
			queue_free())
		row.add_child(b)
		_list.add_child(row)


func _build_toast(from_name: String, lobby: int) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(0.1, 0.11, 0.14, 0.96)))
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.offset_top = 16
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	p.add_child(col)
	col.add_child(_label("%s приглашает вас в игру" % from_name, 18))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var ok := Button.new()
	ok.text = "Принять"
	ok.pressed.connect(func():
		queue_free()
		Net.join_steam(lobby))
	row.add_child(ok)
	var no := Button.new()
	no.text = "Отклонить"
	no.pressed.connect(queue_free)
	row.add_child(no)
	col.add_child(row)
	Sfx.play("chips_win", -4)
	get_tree().create_timer(45.0).timeout.connect(func():
		if is_instance_valid(self):
			queue_free())
