extends Control
## Общий 2D-стол JSON-игры: раскладка, адресные действия, карты и d6 из общих компонентов.

const Style := preload("res://games/custom/ui/cg_style.gd")
const Assets := preload("res://games/custom/ui/cg_assets.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
const Session := preload("res://games/custom/logic/cg_session.gd")
const Layout := preload("res://games/custom/logic/cg_layout.gd")
var _assets := Assets.new()
var app: Node
var _top: TopBar
var _field: Control
var _view: Dictionary = {}
var _seat := -2
var _shown := false
var _preview: Control
var _zones: Dictionary = {}
var _cards: Dictionary = {}
var _die_key := ""
var _rebuild_queued := false
var _pages: Dictionary = {}
var _debug: RefCounted
var _debug_window: Window
var _debug_text: TextEdit
var _debug_back: Button
var _sound_id := -1

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Style.bg()
	background.mouse_filter = MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)
	_top = TopBar.make(self, "Пользовательская игра", Style.button, null, Style.ink(), Style.HEAD)
	var theme_button := Style.button("Тема", 16)
	theme_button.pressed.connect(func(): Prefs.set_value("theme_mode", "light" if Style.dark() else "dark"))
	_top.actions.add_child(theme_button)
	if _author_test():
		_debug = load("res://editor/ed_debug.gd").new()
		var debug_button := Style.button("Отладка", 16)
		debug_button.pressed.connect(_show_debug)
		_top.actions.add_child(debug_button)
	var leave := Style.button("Выйти", 16)
	LeaveGuard.wire(leave, "Выйти?", "Вернуться к выбору игры.", app.back_to_hub)
	_top.actions.add_child(leave)
	_field = Control.new()
	_field.size = Vector2(1280, 672)
	_field.clip_contents = true
	add_child(_field)
	resized.connect(_fit)
	Net.state_changed.connect(_state)
	_fit()
	if not Net.view.is_empty():
		_state(Net.view)

func _fit() -> void:
	if not is_instance_valid(_field):
		return
	var zoom := minf(size.x / 1280.0, (size.y - TopBar.HEIGHT) / 672.0)
	zoom = maxf(0.1, zoom)
	var area := Layout.BASE
	if Layout.adaptive(_view.get("cg_layout", {})):
		area = Vector2(size.x, maxf(0, size.y - TopBar.HEIGHT)) / zoom
	var changed := not _field.size.is_equal_approx(area)
	_field.size = area
	_field.scale = Vector2.ONE * zoom
	_field.position = Vector2((size.x - area.x * zoom) / 2.0, TopBar.HEIGHT)
	if changed and not _view.is_empty() and not _rebuild_queued:
		_rebuild_queued = true
		_render_pending.call_deferred()

func _state(view: Dictionary) -> void:
	if not Net.is_custom_game(str(view.get("game", ""))):
		return
	var previous := _view.duplicate()
	var incoming := view.duplicate()
	# Часы TopBar обновляются отдельно; служебные метрики не меняют содержимое стола.
	for key: String in ["turn_left", "personal_stats", "auto_in"]:
		previous.erase(key)
		incoming.erase(key)
	var same_contents := previous == incoming
	if _seat != int(view.get("seat", -1)) or _view.get("game_id") != view.get("game_id"):
		_shown = _author_test() or not bool(view.get("hotseat", false))
		if _view.get("game_id") != view.get("game_id"):
			_pages.clear()
			_sound_id = -1
	_seat = int(view.get("seat", -1))
	_view = view
	_fit()
	var sound_event: Dictionary = view.get("sound_event", {})
	if int(sound_event.get("id", -1)) != _sound_id:
		_sound_id = int(sound_event.get("id", -1))
		if str(sound_event.get("name", "")) in preload("res://games/custom/logic/cg_blocks.gd").SOUNDS:
			Sfx.play(str(sound_event.name))
	if _author_test() and _debug != null and Net.cg != null:
		_debug.capture(Net.cg)
		_update_debug()
	if str(view.get("game", "")).begins_with("custom:"):
		_assets.configure(str(view.game).trim_prefix("custom:"), str(Net.cg_transfer.manifest.get("hash", "")), Net.is_host())
	if same_contents:
		return
	# Хост может ответить синхронно из сигнала TossDie.thrown. Сначала завершаем input кубика.
	if not _rebuild_queued:
		_rebuild_queued = true
		_render_pending.call_deferred()

func _render_pending() -> void:
	_rebuild_queued = false
	_rebuild()

func _author_test() -> bool:
	return Net.mode == "offline" and Net.is_host() and Net.settings.get("cg_editor_return", false)

func presentation_view() -> Dictionary:
	if _author_test() and _view.get("phase") == "game_over":
		var result := _view.duplicate()
		result.phase = "editor_result"
		return result
	return _view

func _show_debug() -> void:
	if not _author_test() or Net.cg == null:
		return
	if is_instance_valid(_debug_window):
		_debug_window.popup_centered()
		_update_debug()
		return
	_debug_window = Window.new()
	_debug_window.title = "Проверка · играть за всех"
	_debug_window.size = Vector2i(800, 560)
	_debug_window.theme = Style.theme()
	Style.window_surface(_debug_window)
	add_child(_debug_window)
	var col := Style.column(8)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_debug_window.add_child(col)
	col.offset_left = 16
	col.offset_top = 16
	col.offset_right = -16
	col.offset_bottom = -16
	col.add_child(Style.label("Полное состояние доступно автору только в локальной проверке."))
	var row := Style.row(8)
	col.add_child(row)
	_debug_back = Style.button("← Назад на действие")
	_debug_back.pressed.connect(_debug_step_back)
	row.add_child(_debug_back)
	var pause := Style.button("Пауза / продолжить")
	pause.pressed.connect(func(): Net.set_paused(not Net.paused))
	row.add_child(pause)
	for same_seed: bool in [false, true]:
		var again := Style.button("Тот же расклад" if same_seed else "Заново")
		again.pressed.connect(func(): _debug_restart(same_seed))
		row.add_child(again)
	_debug_text = TextEdit.new()
	_debug_text.editable = false
	_debug_text.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(_debug_text)
	_debug_window.close_requested.connect(_debug_window.hide)
	_update_debug()
	_debug_window.popup_centered()

func _update_debug() -> void:
	if not _author_test() or not is_instance_valid(_debug_text) or Net.cg == null:
		return
	_debug_text.text = _debug.describe(Net.cg)
	_debug_back.disabled = _debug.history.size() < 2

func _debug_step_back() -> void:
	if _author_test() and _debug != null and _debug.back(Net.cg):
		_shown = true
		Net._push_state()

func _debug_restart(same_seed: bool) -> void:
	if not _author_test() or _debug == null or Net.cg == null:
		return
	if _debug.restart(Net.cg, same_seed):
		Net.cg_view_seat = 0
		_shown = true
		_die_key = ""
		_sound_id = -1
		Net.set_paused(false)
		Net._push_state()
	else:
		_update_debug()

func _send(action: Dictionary, value: Variant = null) -> void:
	var data := action.duplicate(true)
	data["revision"] = _view.get("revision", -1)
	if action.get("kind") == "answer":
		data["value"] = value
	Net.send_action(str(action.kind), data)

func _at(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size
	_field.add_child(control)

func _rebuild() -> void:
	Style.clear(_field)
	_zones.clear()
	_cards.clear()
	_preview = null
	_top.title.text = str(_view.get("cg_meta", {}).get("title", "Пользовательская игра")).to_upper()
	_top.info.text = "Раунд %d · ход %d" % [int(_view.get("round", 1)), int(_view.get("turn_no", 1))]
	var custom: bool = _view.get("cg_layout", {}).get("custom", false)
	var roster := HBoxContainer.new()
	roster.add_theme_constant_override("separation", 8)
	_at(roster, Rect2(24, 8, 1232, 48))
	roster.visible = not custom
	for i in _view.players.size():
		var p: Dictionary = _view.players[i]
		var caption := ("● " if _active_seat(i) else "") + str(p.get("name", "Игрок"))
		var hand_count := 0
		for key: String in _view.zones:
			if key.ends_with("@%d" % i):
				hand_count += _view.zones[key].size()
		caption += " · %d карт" % hand_count
		if _view.get("ready_seats", []).has(i):
			caption += " · готов"
		var seat_button := Style.button(caption)
		seat_button.size_flags_horizontal = SIZE_EXPAND_FILL
		seat_button.clip_text = true
		seat_button.disabled = not bool(_view.get("hotseat", false))
		seat_button.pressed.connect(func(): Net.send_action("view_seat", {"seat": i}))
		roster.add_child(seat_button)
		TurnNameGlow.apply(seat_button, _active_seat(i))
	var phases: Dictionary = _view.get("cg_meta", {}).get("phase_titles", {})
	var status := Style.label(_phase_caption())
	_at(status, Rect2(32, 72, 600, 32))
	status.visible = not custom
	var scoreboard := Style.label(_scores())
	scoreboard.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_at(scoreboard, Rect2(656, 72, 592, 32))
	scoreboard.visible = not custom
	if custom:
		_top.info.text = _phase_caption()
	var shared := 0
	for screen: Dictionary in _view.get("cg_layout", {}).get("screens", []):
		for item: Dictionary in screen.get("items", []):
			if not _item_visible(item):
				continue
			if item.get("kind") == "zone":
				var key := str(item.id)
				if item.get("owner", "shared") == "player":
					if _seat < 0:
						continue
					key += "@%d" % _seat
				elif item.get("owner", "shared") == "team":
					if _seat < 0:
						continue
					key += "#%s" % str(_view.players[_seat].get("team", 0))
				var own: bool = item.get("owner", "shared") != "shared"
				var fallback := Rect2(288, 352, 704, 192) if own else Rect2(176 + shared * 544, 128, 368, 200)
				_zone(key, item, _rect(item, fallback), own)
				if not own:
					shared += 1
			elif item.get("kind") == "text":
				_at(Style.label(str(item.get("text", ""))), _rect(item, Rect2(32, 112, 360, 32)))
			elif item.get("kind") == "counter":
				var variable := str(item.get("var", ""))
				_at(Style.heading("%s: %s" % [item.get("title", item.get("text", variable)), _variable(variable)]), _rect(item, Rect2(32, 112, 360, 40)))
			elif item.get("kind") == "button":
				_layout_button(item)
			elif item.get("kind") == "image":
				var image := TextureRect.new()
				image.texture = _assets.image(str(item.get("asset", "")))
				image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				image.mouse_filter = MOUSE_FILTER_IGNORE
				_at(image, _rect(item, Rect2(32, 112, 160, 160)))
			elif item.get("kind") == "phase":
				_at(Style.heading(str(phases.get(str(_view.phase), str(_view.phase)))), _rect(item, Rect2(32, 72, 320, 40)))
			elif item.get("kind") == "journal":
				var label := Style.label("\n".join((_view.get("log", []) as Array).slice(-6)))
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_at(label, _rect(item, Rect2(32, 440, 320, 160)))
			elif item.get("kind") == "players":
				_layout_players(_rect(item, Rect2(24, 8, 1232, 96)))
			elif item.get("kind") == "self_panel":
				if _seat >= 0:
					_player_panel(_seat, _rect(item, Rect2(32, 376, 240, 160)))
			elif item.get("kind") == "opponents":
				_opponents(_rect(item, Rect2(24, 8, 1232, 112)))
			elif item.get("kind") == "teams":
				_teams(_rect(item, Rect2(32, 128, 256, 192)))
	_actions()
	_dice()
	var log_text := "\n".join((_view.get("log", []) as Array).slice(-3))
	if not _view.get("hints", []).is_empty():
		log_text += "\n" + " · ".join(_view.hints)
	var journal := Style.label(log_text)
	journal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_at(journal, Rect2(32, _field.size.y - 64, _field.size.x - 64, 56))
	journal.visible = not custom or not _view.get("hints", []).is_empty()
	_present_cards()

func _present_cards() -> void:
	var ids: Array = _view.get("show_cards", [])
	if ids.is_empty():
		return
	var found: Dictionary = {}
	for cards: Array in _view.get("zones", {}).values():
		for card: Dictionary in cards:
			if not card.get("hidden", false) and str(card.get("id", "")) == str(ids.back()):
				found = card
	if found.is_empty():
		return
	var fields: Dictionary = Session.face_fields(_view, found)
	var preview: Control = Style.TokenFace.new(fields) if fields.get("kind") == "token" else Style.CardFace.new(fields)
	if preview is Style.CardFace:
		preview.layer_reader = _assets
		preview.art_texture = _assets.image(str(fields.get("art", "")))
		preview.custom_font = _assets.font(str(fields.get("font", "")))
	preview.mouse_filter = MOUSE_FILTER_IGNORE
	preview.z_index = 125
	preview.name = "ShownByRules"
	var dimensions := Vector2(192, 192) if fields.get("kind") == "token" else _preview_size(found)
	_at(preview, Rect2(Vector2((_field.size.x - dimensions.x) * 0.5, 128), dimensions))

func _preview_size(data: Dictionary) -> Vector2:
	var dimensions := Vector2(Definition.CARD_SIZES[clampi(int(data.get("size", 3)) - 1, 0, 8)])
	return dimensions * minf(252.0 / dimensions.x, 352.0 / dimensions.y)

func _item_visible(item: Dictionary) -> bool:
	var visible: Variant = item.get("visible", ["all"])
	if not visible is Array or visible.has("all"):
		return true
	if _seat < 0:
		return visible.has("spectator")
	var role := str(_view.players[_seat].get("role", "player"))
	return role != "leader" and visible.has("role:" + role) or visible.has("role:leader") and _seat == int(_view.leader)

func _layout_button(item: Dictionary) -> void:
	var button := Style.button(str(item.get("title", "Действие")))
	button.disabled = true
	for action: Dictionary in _view.get("legal", []):
		if action.kind == "button" and str(action.id) == str(item.get("action", item.get("id", ""))):
			button.disabled = false
			button.pressed.connect(func(): _send(action))
			break
	_at(button, _rect(item, Rect2(416, 504, 320, 48)))

func _layout_players(rect: Rect2) -> void:
	var grid := GridContainer.new()
	grid.columns = mini(4, _view.players.size())
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_at(grid, rect)
	for index in _view.players.size():
		var button := Style.button(("● " if _active_seat(index) else "") + str(_view.players[index].name) + (" · готов" if _view.get("ready_seats", []).has(index) else ""))
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.clip_text = true
		button.disabled = not _view.get("hotseat", false)
		button.pressed.connect(func(): Net.send_action("view_seat", {"seat": index}))
		grid.add_child(button)

func _player_text(seat: int) -> String:
	var lines: Array[String] = [str(_view.players[seat].name)]
	if _view.get("ready_seats", []).has(seat):
		lines[0] += " · готов"
	for entry: Dictionary in _view.get("cg_vars", []):
		if entry.get("scope") == "player" and _view.vars.player[seat].has(str(entry.id)):
			lines.append("%s: %s" % [entry.get("title", entry.id), Style.value_text(_view.vars.player[seat][entry.id])])
	return "\n".join(lines)

func _phase_caption() -> String:
	var phases: Dictionary = _view.get("cg_meta", {}).get("phase_titles", {})
	var caption: String = str(phases.get(str(_view.phase), str(_view.phase)))
	if _view.get("turn_mode", "circle") == "simultaneous":
		var alive := 0
		var ready := 0
		for seat in _view.players.size():
			if not _view.players[seat].get("eliminated", false):
				alive += 1
				ready += 1 if _view.get("ready_seats", []).has(seat) else 0
		return "%s · Готовы %d/%d" % [caption, ready, alive]
	return "%s · %s" % [caption, str(_view.players[int(_view.current)].name)]

func _active_seat(seat: int) -> bool:
	if _view.get("turn_mode", "circle") == "simultaneous":
		return not _view.players[seat].get("eliminated", false) and not _view.get("ready_seats", []).has(seat)
	return seat == int(_view.current)

func _player_panel(seat: int, rect: Rect2, compact: bool = false) -> void:
	var panel := Panel.new()
	panel.name = "PlayerPanel_%d" % seat
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", Style.box(Style.panel()))
	_at(panel, rect)
	var text := Style.label(_player_text(seat).replace("\n", " · ") if compact else _player_text(seat))
	text.position = Vector2(16, 8)
	text.size = Vector2(maxf(8, rect.size.x - 32), maxf(8, rect.size.y - 16))
	text.clip_text = true
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(text)

func _opponents(rect: Rect2) -> void:
	var seats: Array = []
	for seat in _view.players.size():
		if seat != _seat:
			seats.append(seat)
	if seats.is_empty():
		return
	var columns := mini(4, seats.size())
	var rows := ceili(seats.size() / float(columns))
	var width := (rect.size.x - (columns - 1) * 8) / columns
	var height := (rect.size.y - (rows - 1) * 8) / rows
	for index in seats.size():
		_player_panel(int(seats[index]), Rect2(rect.position + Vector2((index % columns) * (width + 8), (index / columns) * (height + 8)), Vector2(width, height)), true)

func _teams(rect: Rect2) -> void:
	var members: Dictionary = {}
	for player: Dictionary in _view.players:
		var key := str(player.get("team", 0))
		if not members.has(key):
			members[key] = []
		members[key].append(str(player.name))
	var lines: Array[String] = []
	for key: String in members:
		lines.append("Команда %d: %s" % [int(key) + 1, ", ".join(members[key])])
		for entry: Dictionary in _view.get("cg_vars", []):
			if entry.get("scope") == "team" and _view.vars.team.get(key, {}).has(str(entry.id)):
				lines.append("%s: %s" % [entry.get("title", entry.id), Style.value_text(_view.vars.team[key][entry.id])])
	var panel := Panel.new()
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", Style.box(Style.panel()))
	_at(panel, rect)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(12, 12)
	scroll.size = Vector2(maxf(8, rect.size.x - 24), maxf(8, rect.size.y - 24))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var text := Style.label("\n".join(lines))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	text.custom_minimum_size.x = maxf(8, scroll.size.x - 16)
	scroll.add_child(text)

func _has_layout_action(id: String) -> bool:
	for screen: Dictionary in _view.get("cg_layout", {}).get("screens", []):
		for item: Dictionary in screen.get("items", []):
			if item.get("kind") == "button" and str(item.get("action", item.get("id", ""))) == id:
				return true
	return false

func _rect(item: Dictionary, fallback: Rect2) -> Rect2:
	var rect: Variant = item.get("rect", [])
	if rect is Array and rect.size() == 4:
		fallback = Rect2(float(rect[0]), maxf(0, float(rect[1]) - TopBar.HEIGHT), maxf(32, float(rect[2])), maxf(32, float(rect[3])))
	return Layout.rect(fallback, item, _field.size)

func _variable(id: String) -> String:
	if _view.vars.shared.has(id):
		return Style.value_text(_view.vars.shared[id])
	if _seat >= 0 and _view.vars.player[_seat].has(id):
		return Style.value_text(_view.vars.player[_seat][id])
	return "—"

func _scores() -> String:
	var text: Array[String] = []
	for v: Dictionary in _view.get("cg_vars", []):
		if v.get("scope", "shared") == "shared" and _view.vars.shared.has(v.id):
			text.append("%s: %s" % [v.get("title", v.id), Style.value_text(_view.vars.shared[v.id])])
		elif v.get("scope") == "player" and _seat >= 0:
			text.append("%s: %s" % [v.get("title", v.id), _variable(v.id)])
	return " · ".join(text)

func _zone(key: String, spec: Dictionary, rect: Rect2, own: bool) -> void:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", Style.box(Style.panel()))
	_at(panel, rect)
	_zones[key] = panel
	var cards: Array = _view.zones.get(key, [])
	var title := Style.label("%s · %d" % [spec.get("title", "Ваша рука" if own else str(spec.id)), cards.size()])
	title.position = Vector2(16, 8)
	panel.add_child(title)
	if own and not _shown:
		var show_button := Style.primary("Показать мою руку")
		show_button.position = rect.position + Vector2(24, 80)
		show_button.pressed.connect(func():
			_shown = true
			_rebuild())
		_field.add_child(show_button)
		return
	var pile: bool = spec.get("view", "row") in ["pile", "discard"]
	var count := mini(cards.size(), 30)
	var page := clampi(int(_pages.get(key, 0)), 0, maxi(0, ceili(cards.size() / 30.0) - 1))
	if pile:
		count = mini(cards.size(), 3)
	else:
		count = mini(30, cards.size() - page * 30)
		if cards.size() > 30:
			for direction: int in [-1, 1]:
				var step := LinkButton.new()
				step.text = "←" if direction < 0 else "→"
				step.position = Vector2(rect.size.x - 80 + (40 if direction > 0 else 0), 8)
				step.custom_minimum_size = Vector2(32, 24)
				step.disabled = page == 0 if direction < 0 else (page + 1) * 30 >= cards.size()
				step.pressed.connect(func():
					_pages[key] = page + direction
					_rebuild.call_deferred())
				panel.add_child(step)
	for k in count:
		var index: int = cards.size() - count + k if pile else page * 30 + k
		var data: Dictionary = cards[index]
		var fields: Dictionary = Session.face_fields(_view, data)
		var token: bool = fields.get("kind") == "token"
		var face: Control = Style.TokenFace.new(fields) if token else Style.CardFace.new(fields)
		if not token:
			face.layer_reader = _assets
			face.art_texture = _assets.image(str(fields.get("art", "")))
			face.custom_font = _assets.font(str(fields.get("font", "")))
		var card_size := Vector2(Definition.CARD_SIZES[clampi(int(data.get("size", 3)) - 1, 0, 8)])
		if token:
			card_size = Vector2(72, 72)
		var card := K12TableCard.new(str(data.get("id", "")), not data.get("hidden", false), face, card_size)
		card.back_drawer = Style.card_back
		var back_texture := _assets.image(str(data.get("back", "")))
		if back_texture != null:
			card.back_drawer = func(canvas: CanvasItem, back_rect: Rect2): canvas.draw_texture_rect(back_texture, back_rect, false)
			card.set_meta("cg_back", str(data.back))
		card.base_scale = minf(0.8, (rect.size.y - 56) / card_size.y)
		card.scale = Vector2.ONE * card.base_scale
		var x: float = rect.position.x + (rect.size.x - card_size.x * card.base_scale) / 2.0 + k * 3.0 if pile else rect.position.x + 24 + k * minf(108.0, (rect.size.x - 144) / maxf(1, count - 1))
		card.position = Vector2(x, rect.position.y + 40 + (k * 2 if pile else 0))
		if spec.get("view") == "free":
			var point: Array = data.get("pos", [float(k % 5) / 4.0, minf(1.0, floorf(k / 5.0) / 5.0)])
			var available := (rect.size - Vector2(48, 56) - card_size * card.base_scale).max(Vector2.ZERO)
			card.position = rect.position + Vector2(24, 40) + Vector2(float(point[0]), float(point[1])) * available
		# Control масштабируется вокруг pivot: заданная точка — видимый левый верхний угол.
		card.position -= card.pivot_offset * (1.0 - card.base_scale)
		card.draggable = not data.get("hidden", false) and _has_card_action(str(data.get("id", "")))
		if data.get("hidden", false) and index == cards.size() - 1:
			card.draggable = _view.get("legal", []).any(func(action: Dictionary): return action.kind == "manual_place_top" and action.id == key)
		card.clicked.connect(func(_c: K12TableCard): _activate(str(data.get("id", ""))))
		card.dropped.connect(func(c: K12TableCard, at: Vector2): _drop(c, at, key))
		card.right_clicked.connect(func(_c: K12TableCard):
			if data.get("hidden", false):
				_flip_top(key)
			else:
				_flip(str(data.get("id", ""))))
		card.hovered.connect(func(_c: K12TableCard, on: bool): _hover(data, card, on))
		_field.add_child(card)
		if data.has("id"):
			_cards[str(data.id)] = card
	if pile:
		for action: Dictionary in _view.get("legal", []):
			if action.kind == "manual_shuffle" and action.id == key:
				var shuffle := LinkButton.new()
				shuffle.text = "Перемешать"
				shuffle.position = Vector2(maxf(16, rect.size.x - 128), 8)
				shuffle.pressed.connect(func(): _send(action))
				panel.add_child(shuffle)
				break
		for action: Dictionary in _view.get("legal", []):
			if action.kind == "manual_move" and action.id == key and action.get("card", "") == "":
				var draw_button := Style.button("Взять → " + str(action.to))
				draw_button.position = rect.position + Vector2(16, rect.size.y - 48)
				draw_button.pressed.connect(func(): _send(action))
				_field.add_child(draw_button)
				break

func _has_card_action(id: String) -> bool:
	for action: Dictionary in _view.get("legal", []):
		if action.get("card", "") == id and action.kind in ["card", "manual_move", "manual_flip", "manual_place"]:
			return true
	return false

func _activate(id: String) -> void:
	if id.is_empty():
		return
	for action: Dictionary in _view.get("legal", []):
		if action.kind == "card" and action.get("card") == id:
			_send(action)
			return

func _flip(id: String) -> void:
	for action: Dictionary in _view.get("legal", []):
		if action.kind == "manual_flip" and action.get("card") == id:
			_send(action)
			return

func _flip_top(zone: String) -> void:
	for action: Dictionary in _view.get("legal", []):
		if action.kind == "manual_flip_top" and action.id == zone:
			_send(action)
			return

func _drop_point(card: K12TableCard, target: Control) -> Array:
	var available := (target.size - Vector2(48, 56) - card.card_size * card.base_scale).max(Vector2.ONE)
	var visible_origin := card.position + card.pivot_offset * (1.0 - card.base_scale)
	var point := (visible_origin - target.position - Vector2(24, 40)) / available
	return [clampf(point.x, 0, 1), clampf(point.y, 0, 1)]

func _drop(card: K12TableCard, at: Vector2, source: String) -> void:
	for zone: String in _zones:
		var target: Control = _zones[zone]
		if not Rect2(target.position, target.size).has_point(at):
			continue
		for action: Dictionary in _view.get("legal", []):
			if zone == source and action.kind in ["manual_place", "manual_place_top"] and action.get("card", "") == card.card and action.id == zone:
				var placed := action.duplicate(true)
				placed["pos"] = _drop_point(card, target)
				_send(placed)
				return
			if action.kind == "manual_move" and action.get("card") == card.card and action.to == zone:
				var moved := action.duplicate(true)
				moved["pos"] = _drop_point(card, target)
				_send(moved)
				return
		if zone == source:
			continue
		_activate(card.card)
	_rebuild()

func _hover(data: Dictionary, card: Control, on: bool) -> void:
	if on and preload("res://hub/card_magnifier.gd").offer(card):
		return
	if is_instance_valid(_preview):
		_preview.queue_free()
		_preview = null
	if not on:
		return
	if data.get("hidden", false):
		var back_texture := _assets.image(str(data.get("back", "")))
		if back_texture == null:
			return
		var back := TextureRect.new()
		back.texture = back_texture
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		back.mouse_filter = MOUSE_FILTER_IGNORE
		back.size = Vector2(252, 352)
		back.position = Vector2(clampf(card.position.x + 112, 16, 1012), clampf(card.position.y - 160, 72, 280))
		back.z_index = 120
		_preview = back
		_field.add_child(back)
		return
	var fields: Dictionary = Session.face_fields(_view, data)
	if fields.get("kind") == "token":
		_preview = Style.TokenFace.new(fields)
		_preview.size = Vector2(192, 192)
	else:
		_preview = Style.CardFace.new(fields)
		_preview.layer_reader = _assets
		_preview.art_texture = _assets.image(str(fields.get("art", "")))
		_preview.custom_font = _assets.font(str(fields.get("font", "")))
		_preview.size = _preview_size(data)
	_preview.position = Vector2(clampf(card.position.x + 112, 16, _field.size.x - _preview.size.x - 16), clampf(card.position.y - 160, 72, _field.size.y - _preview.size.y - 40))
	_preview.z_index = 120
	_field.add_child(_preview)

func _actions() -> void:
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = MOUSE_FILTER_IGNORE
	var has_ready: bool = _view.get("legal", []).any(func(action): return action.kind in ["ready", "unready"])
	_at(scroll, Rect2(32, _field.size.y - 120, 448 if has_ready else _field.size.x - 64, 48))
	var actions := Style.row()
	scroll.add_child(actions)
	if _view.get("hotseat", false) and _view.get("cg_layout", {}).get("custom", false):
		var seat := OptionButton.new()
		for player: Dictionary in _view.players:
			seat.add_item(str(player.name))
		seat.select(maxi(0, _seat))
		seat.item_selected.connect(func(index: int): Net.send_action("view_seat", {"seat": index}))
		actions.add_child(seat)
	for action: Dictionary in _view.get("legal", []):
		if action.kind in ["ready", "unready"]:
			var button := Style.primary("Готов") if action.kind == "ready" else Style.button("Изменить решение")
			button.name = "CustomPhaseReady"
			button.pressed.connect(func(): _send(action))
			_at(button, Rect2((_field.size.x - 240) * 0.5, _field.size.y - 120, 240, 56))
		elif action.kind == "button" and not _has_layout_action(str(action.id)):
			var button := Style.primary(str(_view.get("cg_meta", {}).get("action_titles", {}).get(str(action.id), str(action.id))))
			button.pressed.connect(func(): _send(action))
			actions.add_child(button)
		elif action.kind == "manual_roll":
			var button := Style.button("Бросить · " + str(action.title))
			button.pressed.connect(func(): _send(action))
			actions.add_child(button)
		elif action.kind == "manual_resource":
			var button := Style.button(str(action.title) + (" +1" if int(action.delta) > 0 else " −1"))
			button.pressed.connect(func(): _send(action))
			actions.add_child(button)
	var pending: Dictionary = _view.get("pending", {})
	if pending.is_empty():
		return
	if pending.kind == "ask_number":
		var number := SpinBox.new()
		number.min_value = float(pending.min)
		number.max_value = float(pending.max)
		actions.add_child(number)
		var confirm := Style.primary("Выбрать")
		confirm.pressed.connect(func(): _send({"kind": "answer"}, number.value))
		actions.add_child(confirm)
	elif pending.kind in ["ask_option", "ask_player", "ask_card"]:
		var choice := OptionButton.new()
		for value: Variant in pending.options:
			choice.add_item(str(_view.players[int(value)].name) if pending.kind == "ask_player" else str(value))
		actions.add_child(choice)
		var confirm := Style.primary("Выбрать")
		confirm.pressed.connect(func():
			if choice.selected >= 0:
				_send({"kind": "answer"}, pending.options[choice.selected]))
		actions.add_child(confirm)

func _dice() -> void:
	var pending: Dictionary = _view.get("pending", {})
	var rolling: bool = pending.get("kind") == "roll"
	var tray := Rect2(24, 112, 1232, 432)
	var has_tray := false
	for screen: Dictionary in _view.get("cg_layout", {}).get("screens", []):
		for item: Dictionary in screen.get("items", []):
			if item.get("kind") == "dice_tray" and _item_visible(item):
				tray = _rect(item, tray)
				has_tray = true
	if _view.get("cg_layout", {}).get("custom", false) and not has_tray and not rolling:
		return
	var key := str([_view.get("game_id"), _view.get("dice", {}), rolling])
	var animate := key != _die_key
	_die_key = key
	var group := 0
	for seat: String in _view.get("dice", {}):
		var values: Variant = _view.dice[seat]
		var origin := Vector2(40 + (group % 4) * 304, 160 + (group / 4) * 200)
		if has_tray:
			origin = tray.position + Vector2(16 + (group % 4) * tray.size.x / 4.0, 16 + (group / 4) * tray.size.y / 2.0)
		group += 1
		_at(Style.label(str(_view.players[int(seat)].name)), Rect2(origin, Vector2(264, 32)))
		if values is Dictionary:
			_at(Style.label("%d закрытых d6" % int(values.count)), Rect2(origin + Vector2(0, 48), Vector2(264, 32)))
			continue
		var x := origin.x
		for index in values.size():
			var face: Variant = values[index]
			var die := TossDie.new()
			var compact: bool = values.size() > 3
			die.scale = Vector2.ONE * (0.5 if compact else 1.0)
			die.home = origin + Vector2(24 + (index % 6) * 40, 56 + (index / 6) * 32) if compact else Vector2(x + 32, origin.y + 80)
			die.area = tray
			_field.add_child(die)
			if animate:
				die.throw(Vector2(320, -160), int(face))
			else:
				die.position = die.home - Vector2(32, 32)
				die._die.value = int(face)
			x += 72
	if rolling:
		var die := TossDie.new()
		die.home = tray.get_center() if has_tray else Vector2(_field.size.x * 0.5, 320)
		die.area = tray
		die.draggable = true
		die.thrown.connect(func(_velocity: Vector2): _send({"kind": "answer"}))
		_field.add_child(die)
		die.wait_for_roll()
		_at(Style.label("Потяните и бросьте кубик"), Rect2(536, 392, 300, 32))
