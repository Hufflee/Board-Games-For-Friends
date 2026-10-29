extends Control
## Общий 2D-финал: одна звезда для победителей, короны, аватарки и доступ к исходному столу.
## Подключается TopBar автоматически; не меняет состояние партии и маршруты приложений.

const Result := preload("res://hub/victory_result.gd")
var table: Control
var make_button: Callable
var game := ""
var outcome: Dictionary = {}
var players: Array = []
var accent := Color("d3a44a")
var _surface: Control
var _return: Button
var _buttons: HBoxContainer
var _cards: Array[Control] = []
var _hidden_layers: Array[WeakRef] = []
var _showing := true
var _key := ""
var _avatar_check_ms := 0

func _ready() -> void:
	accent = {
		"the_gang": Color("d9bd65"), "king_of_12": Color("c7a951"), "perudo": Color("c7a460"),
		"wavelength": Color("6b82b3"), "dangerous_words": Color("b07cff"),
		"hues_and_cues": Color("5e8d7d"), "word_slam": Color("5e8d7d"),
		"ready_set_bet": Color("e9c45a"), "tip_top": Color("2f7f86"), "tip_top_18": Color("cf4d90"),
		"not_a_hat": Color("e5007e"), "gloom": Color("a3202a"), "gloomier": Color("704c88"),
		"brodilka": Color("327eb8"), "phantom_ink": Color("4e9685"),
		"four_souls": Color("9d794c"), "stillion": Color("e8b33a"),
	}.get(game, accent)
	name = "VictoryScreen"
	z_as_relative = false
	z_index = 80
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_top = TopBar.HEIGHT
	_surface = Control.new()
	_surface.name = "VictorySurface"
	_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_surface)
	_surface.draw.connect(_draw_surface)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 16)
	_surface.add_child(_buttons)
	var inspect := _button("Показать стол", "ShowTable")
	inspect.pressed.connect(func(): show_results(false))
	_buttons.add_child(inspect)
	if Net.is_host():
		var lobby := _button("В лобби", "VictoryLobby")
		lobby.pressed.connect(Net.end_game)
		_buttons.add_child(lobby)
	var app: Node = table.get("app")
	if is_instance_valid(app):
		var route := "back_to_menu" if app.has_method("back_to_menu") else "back_to_hub"
		if app.has_method(route):
			var menu := _button("К выбору игры" if Net.is_party() else "В меню", "VictoryMenu")
			LeaveGuard.wire(menu, "Выйти?", "Вернуться к выбору игры.", func():
				Sfx.stop_victory()
				app.call(route))
			_buttons.add_child(menu)
	_return = _button("Вернуться к результатам", "ReturnResults")
	_return.position = Vector2(16, 12)
	_return.visible = false
	_return.pressed.connect(func(): show_results(true))
	add_child(_return)
	resized.connect(_layout)

func _button(text: String, id: String) -> Button:
	var button: Button = make_button.call(text, 16)
	button.name = id
	button.custom_minimum_size.y = 44
	button.focus_mode = Control.FOCUS_NONE
	var dark := Prefs.dark_theme() or game == "the_gang"
	var primary := id == "VictoryLobby"
	var fill := accent.lightened(0.25) if primary else accent.darkened(0.76) if dark else accent.lightened(0.82)
	var ink := Color("211d18") if primary or not dark else Color("f5eddc")
	for state: String in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = fill.lightened(0.1) if state == "hover" else fill.darkened(0.1) if state == "pressed" else fill
		box.set_corner_radius_all(10)
		box.set_content_margin_all(14)
		box.set_border_width_all(1)
		box.border_color = Color(accent.lightened(0.3), 0.5)
		button.add_theme_stylebox_override(state, box)
		button.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), ink)
	return button

func sync(view: Dictionary) -> void:
	var next: Dictionary = Result.resolve(game, view)
	visible = bool(next.finished)
	if not visible:
		_restore_layers()
		return
	var signature := str([game, view.get("game_id", ""), next.winners, view.get("players", [])])
	if _key != signature:
		_key = signature
		outcome = next
		players = view.get("players", [])
		for card: Control in _cards:
			card.queue_free()
		_cards.clear()
		for seat: int in outcome.winners:
			_add_person(seat, true)
		for seat: int in outcome.others:
			_add_person(seat, false)
		_layout()
		_layout.call_deferred()
	_refresh_avatars()
	if not outcome.winners.is_empty():
		Sfx.victory()

	if not _showing:
		_hide_final_layers()
	_surface.queue_redraw()

## Steam может доставить изображение уже после создания экрана. Инициалы остаются до готовности.
func _refresh_avatars() -> void:
	var now := Time.get_ticks_msec()
	if not Net.steam_ok or now < _avatar_check_ms:
		return
	_avatar_check_ms = now + 500
	for card: Control in _cards:
		var avatar := card.get_node("Avatar") as TextureRect
		if avatar.texture != null:
			continue
		var seat: int = card.get_meta("seat")
		var steam_id := int(players[seat].get("steam_id", 0))
		if steam_id == 0:
			continue
		avatar.texture = Net.avatar(steam_id)
		if avatar.texture != null:
			var initials := card.get_node_or_null("Initials") as Label
			if initials:
				initials.hide()

func _add_person(seat: int, winner: bool) -> void:
	var card := Control.new()
	card.name = ("Winner" if winner else "Participant") + str(seat)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_meta("seat", seat)
	card.set_meta("winner", winner)
	_surface.add_child(card)
	_cards.append(card)
	var avatar := TextureRect.new()
	avatar.name = "Avatar"
	avatar.texture = Net.avatar(int(players[seat].get("steam_id", 0)))
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(avatar)
	if avatar.texture == null:
		var initials := Label.new()
		initials.name = "Initials"
		var words: PackedStringArray = str(players[seat].get("name", "?")).strip_edges().split(" ", false)
		initials.text = words[0].left(1).to_upper() if not words.is_empty() else "?"
		if words.size() > 1:
			initials.text += words[1].left(1).to_upper()
		initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initials.add_theme_font_size_override("font_size", 28 if winner else 20)
		initials.add_theme_color_override("font_color", Color("fff2cd"))
		card.add_child(initials)
	var nick := Label.new()
	nick.name = "Nickname"
	nick.text = str(players[seat].get("name", "Игрок"))
	nick.tooltip_text = nick.text
	nick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nick.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nick.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nick.max_lines_visible = 2
	nick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nick.add_theme_font_size_override("font_size", 18 if winner else 14)
	nick.add_theme_color_override("font_color", Color("fff5da") if winner else Color("b4b2ad"))
	if winner:
		nick.add_theme_color_override("font_outline_color", accent.darkened(0.65))
		nick.add_theme_constant_override("outline_size", 5)
		nick.add_theme_color_override("font_shadow_color", Color(accent.lightened(0.2), 0.65))
		nick.add_theme_constant_override("shadow_outline_size", 7)
	card.add_child(nick)
	if not winner:
		card.modulate = Color(0.8, 0.8, 0.8, 0.78)
	card.draw.connect(func(): _draw_person(card))

func _layout() -> void:
	if not is_instance_valid(_surface):
		return
	var winners: Array = outcome.get("winners", [])
	var others: Array = outcome.get("others", [])
	var win_count := winners.size()
	var team_win := bool(outcome.get("team", false))
	var cols := maxi(1, win_count) if team_win else mini(5, maxi(1, win_count))
	var rows := ceili(float(win_count) / cols)
	var cell_w := minf(190.0, (size.x - 128.0) / cols)
	if team_win and win_count > 5:
		cell_w = minf(156.0, (size.x - 320.0) / cols)
	var center_y := size.y * 0.40
	var wi := 0
	var oi := 0
	for card: Control in _cards:
		var winner: bool = card.get_meta("winner")
		var side := 104.0 if winner and win_count == 1 else 64.0 if winner else 48.0
		if winner and team_win and win_count > 5:
			side = clampf(cell_w - 40.0, 48.0, 64.0)
		if winner:
			var row := int(wi / cols)
			var row_count := mini(cols, win_count - row * cols)
			card.size = Vector2(cell_w - 12, 142)
			card.position = Vector2(size.x * 0.5 - row_count * cell_w * 0.5 + (wi % cols) * cell_w + 6,
				center_y - rows * 75.0 + row * 150.0)
			wi += 1
		else:
			var width := minf(160.0, (size.x - 64.0) / maxi(1, others.size()))
			card.size = Vector2(width - 8, 98)
			card.position = Vector2(size.x * 0.5 - others.size() * width * 0.5 + oi * width + 4, size.y - 198)
			oi += 1
		var avatar := card.get_node("Avatar") as TextureRect
		avatar.position = Vector2((card.size.x - side) * 0.5, 24 if winner else 0)
		avatar.size = Vector2.ONE * side
		var initials := card.get_node_or_null("Initials") as Label
		if initials:
			initials.position = avatar.position
			initials.size = avatar.size
		var nick := card.get_node("Nickname") as Label
		if winner:
			nick.add_theme_font_size_override("font_size", 14 if team_win and win_count >= 8 else 18)
		nick.position = Vector2(0, avatar.position.y + side + 6)
		nick.size = Vector2(card.size.x, 46 if winner else 38)
		if not winner:
			nick.add_theme_color_override("font_color", Color("b4b2ad") if Prefs.dark_theme() or game == "the_gang" else Color("3c3831"))
		card.queue_redraw()
	_buttons.reset_size()
	_buttons.position = Vector2((size.x - _buttons.size.x) * 0.5, size.y - 64)
	_surface.queue_redraw()

func _draw_surface() -> void:
	var dark := Prefs.dark_theme() or game == "the_gang"
	var bg := Color("141a22") if dark else Color("e8e3da")
	bg = bg.lerp(accent, 0.08)
	if game == "things_in_rings":
		preload("res://games/things_in_rings/ui/tr_backdrop.gd").paint(_surface, size)
	else:
		_surface.draw_rect(Rect2(Vector2.ZERO, size), bg)
	if not outcome.get("winners", []).is_empty():
		var points := star_polygon()
		_surface.draw_colored_polygon(points, accent.darkened(0.28))
		points.append(points[0])
		_surface.draw_polyline(points, accent.lightened(0.25), 3.0, true)
	var font := ThemeDB.fallback_font
	var heading: String = outcome.get("title", "")
	var ink := Color("f9edd8") if dark else Color("312d29")
	var heading_w := font.get_string_size(heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	_surface.draw_string(font, Vector2((size.x - heading_w) * 0.5, 34), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	if not outcome.get("others", []).is_empty():
		var caption := "Участники" if outcome.get("winners", []).is_empty() else "Спасибо за игру!"
		var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_surface.draw_string(font, Vector2((size.x - width) * 0.5, size.y - 214), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)

## Геометрия общей звезды также используется проверкой попадания карточек внутрь силуэта.
func star_polygon() -> PackedVector2Array:
	var count: int = outcome.get("winners", []).size()
	var team_win := bool(outcome.get("team", false))
	var center := Vector2(size.x * 0.5, size.y * 0.40)
	var wide := team_win and count > 5
	var radius := Vector2(
		minf(size.x * 0.48, count * 110.0) if wide else minf(size.x * 0.46, maxf(280, mini(count, 5) * 110)),
		218 if count > 5 and not team_win else 174)
	var points := PackedVector2Array()
	for index: int in 36:
		var angle := TAU * index / 36.0 - PI * 0.5
		var reach := 1.0 if index % 2 == 0 else 0.81
		var direction := Vector2(signf(cos(angle)) * sqrt(absf(cos(angle))), signf(sin(angle)) * sqrt(absf(sin(angle))))
		points.append(center + direction * radius * reach)
	return points

func _draw_person(card: Control) -> void:
	var avatar := card.get_node("Avatar") as TextureRect
	var rect := Rect2(avatar.position, avatar.size)
	card.draw_style_box(_avatar_box(), rect.grow(3))
	if bool(card.get_meta("winner")):
		var center := Vector2(card.size.x * 0.5, 16)
		var points := PackedVector2Array([
			center + Vector2(-20, -10), center + Vector2(-13, -4), center + Vector2(-9, -17),
			center + Vector2(0, -8), center + Vector2(9, -17), center + Vector2(13, -4),
			center + Vector2(20, -10), center + Vector2(16, 6), center + Vector2(-16, 6)])
		card.draw_colored_polygon(points, Color("ffe6a0"))

func _avatar_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = accent.darkened(0.7)
	box.set_corner_radius_all(12)
	box.set_border_width_all(2)
	box.border_color = accent.lightened(0.5)
	return box

func show_results(show: bool) -> void:
	_showing = show
	_surface.visible = show
	_return.visible = not show
	if show:
		_restore_layers()
	else:
		_hide_final_layers()

func _hide_final_layers() -> void:
	# Только известные финальные слои. Правила, настройки и LeaveGuard здесь не затрагиваются.
	var layer: Control
	if game == "perudo":
		layer = table.get("_overlay")
	elif game == "stillion":
		layer = table.get("_over")
	elif game == "brodilka":
		layer = table.get_node_or_null("FinalResults")
	if is_instance_valid(layer) and layer.visible:
		_hidden_layers.append(weakref(layer))
		layer.hide()

func _restore_layers() -> void:
	for ref: WeakRef in _hidden_layers:
		var layer: Control = ref.get_ref()
		if is_instance_valid(layer):
			layer.show()
	_hidden_layers.clear()
