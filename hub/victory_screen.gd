extends Control
## Общий 2D-финал: одна звезда для победителей, короны, аватарки и доступ к исходному столу.
## Подключается TopBar автоматически; не меняет состояние партии и маршруты приложений.

const Result := preload("res://hub/victory_result.gd")
const AvatarMask := preload("res://hub/victory_avatar.gdshader")
var table: Control
var top_bar: TopBar
var make_button: Callable
var game := ""
var outcome: Dictionary = {}
var players: Array = []
var accent := Color("d3a44a")
var _surface: Control
var _backdrop: Control
var _return: Button
var _buttons: HBoxContainer
var _cards: Array[Control] = []
var _hidden_layers: Array[WeakRef] = []
var _showing := true
var _key := ""
var _avatar_check_ms := 0
var _leader_card: Control
var _like_button: Button
var _my_seat := -1
var _likes_heard := 0

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
	_backdrop = Control.new()
	_backdrop.name = "VictoryBackdrop"
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.offset_top = -TopBar.HEIGHT
	add_child(_backdrop)
	_backdrop.draw.connect(_draw_backdrop)
	var art := _game_backdrop()
	if art != null:
		art.name = "GameBackdrop"
		_backdrop.add_child(art)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	Net.victory_likes_changed.connect(_on_likes)

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
	top_bar.set_victory_backdrop(visible and _showing, _top_ink())
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
		if is_instance_valid(_like_button):
			_like_button.queue_free()
		_leader_card = null
		_like_button = null
		_likes_heard = 0
		_my_seat = int(view.get("seat", view.get("you", -1)))
		for seat: int in outcome.winners:
			_add_person(seat, true)
		for seat: int in outcome.others:
			_add_person(seat, false)
		if int(outcome.leader) >= 0:
			_add_leader(int(outcome.leader))
		if not outcome.winners.is_empty():
			_confetti.call_deferred()
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
		avatar.texture = _avatar_texture(Net.avatar(steam_id))
		if avatar.texture != null:
			var initials := card.get_node_or_null("Initials") as Label
			if initials:
				initials.hide()

## Уже скруглённый квадрат обрезаем до непрозрачных углов, затем накладываем маску слота.
## Проверка середин сторон отличает обычный портрет от силуэта с прозрачным окружением.
func _avatar_texture(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null:
		return texture
	if image.is_compressed() and image.decompress() != OK:
		return texture
	var side := mini(image.get_width(), image.get_height())
	var origin := Vector2i((image.get_width() - side) / 2, (image.get_height() - side) / 2)
	for point: Vector2i in [Vector2i(0, side / 2), Vector2i(side - 1, side / 2), Vector2i(side / 2, 0), Vector2i(side / 2, side - 1)]:
		if image.get_pixelv(origin + point).a < 0.95:
			return texture
	for inset: int in range(ceili(side * 0.15)):
		var opaque := true
		for point: Vector2i in [Vector2i(inset, inset), Vector2i(side - inset - 1, inset), Vector2i(inset, side - inset - 1), Vector2i(side - inset - 1, side - inset - 1)]:
			opaque = opaque and image.get_pixelv(origin + point).a >= 0.95
		if opaque:
			if inset == 0:
				return texture
			var cropped := AtlasTexture.new()
			cropped.atlas = texture
			cropped.region = Rect2(origin + Vector2i.ONE * inset, Vector2i.ONE * (side - inset * 2))
			return cropped
	return texture

func _top_ink() -> Color:
	return Color("f9edd8") if Prefs.dark_theme() or game == "the_gang" else Color("312d29")

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
	avatar.texture = _avatar_texture(Net.avatar(int(players[seat].get("steam_id", 0))))
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var mask := ShaderMaterial.new()
	mask.shader = AvatarMask
	avatar.material = mask
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

## Конфетти сыплются сверху вниз по всей ширине, между фоном и карточками.
func _confetti() -> void:
	var old := get_node_or_null("Confetti")
	if old:
		old.free()
	var conf := CPUParticles2D.new()
	conf.name = "Confetti"
	conf.position = Vector2(size.x * 0.5, -TopBar.HEIGHT - 16)
	conf.amount = 180
	conf.lifetime = 4.5
	conf.one_shot = true
	conf.explosiveness = 0.55
	conf.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	conf.emission_rect_extents = Vector2(size.x * 0.5, 8)
	conf.direction = Vector2(0, 1)
	conf.spread = 25.0
	conf.gravity = Vector2(0, 240)
	conf.initial_velocity_min = 60.0
	conf.initial_velocity_max = 200.0
	conf.angular_velocity_min = -360.0
	conf.angular_velocity_max = 360.0
	conf.scale_amount_min = 4.0
	conf.scale_amount_max = 8.0
	var hues := Gradient.new()
	hues.set_color(0, accent.lightened(0.3))
	hues.set_color(1, Color("5fb4ef"))
	hues.add_point(0.33, Color("e2645c"))
	hues.add_point(0.66, Color("6fcf6f"))
	conf.color_initial_ramp = hues
	add_child(conf)
	move_child(conf, _backdrop.get_index() + 1)
	conf.emitting = true
	get_tree().create_timer(6.0).timeout.connect(func():
		if is_instance_valid(conf):
			conf.queue_free())

## Ведущий без собственного условия победы: отдельно, справа ниже звезды, с лайками игроков.
func _add_leader(seat: int) -> void:
	_add_person(seat, false)
	_leader_card = _cards.back()
	_leader_card.name = "Leader" + str(seat)
	_leader_card.set_meta("leader", true)
	_leader_card.modulate = Color.WHITE
	_like_button = _button("", "LeaderLike")
	_like_button.custom_minimum_size = Vector2(52, 44)
	_like_button.tooltip_text = "Понравилось, как вёл ведущий"
	_like_button.draw.connect(_draw_thumb)
	_like_button.pressed.connect(func():
		Sfx.play("click", -8)
		Net.send_victory_like(_my_seat))
	_like_button.visible = _my_seat >= 0 and _my_seat != seat
	_surface.add_child(_like_button)
	_on_likes()

func _liked_seats() -> Array:
	if str(Net.victory_likes.get("game_id", "")) != str(Net.view.get("game_id", "")):
		return []
	return Net.victory_likes.get("seats", [])

func _on_likes() -> void:
	if not is_instance_valid(_leader_card):
		return
	var seats := _liked_seats()
	if is_instance_valid(_like_button):
		_like_button.disabled = seats.has(_my_seat)
	# Ведущему — мягкая зелёная рамка и звук правильного ответа на каждый новый лайк.
	if seats.size() > _likes_heard and _my_seat == int(outcome.leader):
		_flash_like()
	_likes_heard = seats.size()
	_leader_card.queue_redraw()

func _flash_like() -> void:
	var layer := Control.new()
	layer.name = "LikeFlash"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.offset_top = -TopBar.HEIGHT
	add_child(layer)
	layer.draw.connect(func():
		for i: int in 12:
			var inset := float(i) * 2.0 + 1.0
			layer.draw_rect(Rect2(Vector2(inset, inset), layer.size - Vector2.ONE * inset * 2), Color(Color("62e6a5"), 0.18 * (1.0 - float(i) / 12.0)), false, 3.0))
	var sound := AudioStreamPlayer.new()
	sound.bus = "SFX"
	sound.volume_db = -6
	sound.stream = load("res://games/things_in_rings/audio/correct.ogg")
	layer.add_child(sound)
	sound.play()
	var fade := layer.create_tween()
	fade.tween_interval(0.65)
	fade.tween_property(layer, "modulate:a", 0.0, 0.35)
	fade.tween_callback(layer.queue_free)

## Плоский одноцветный большой палец вверх.
func _draw_thumb() -> void:
	var c := _like_button.size * 0.5 + Vector2(1, 1)
	var ink: Color = _like_button.get_theme_color("font_color")
	if _like_button.disabled:
		ink = Color(ink, 0.45)
	_like_button.draw_rect(Rect2(c + Vector2(-11, -2), Vector2(5, 12)), ink)
	_like_button.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-5, -2), c + Vector2(-1, -12), c + Vector2(2, -12), c + Vector2(2, -4),
		c + Vector2(9, -4), c + Vector2(10, -2), c + Vector2(8, 10), c + Vector2(-5, 10)]), ink)

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
		if card.has_meta("leader"):
			_layout_leader(card)
			continue
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
		(avatar.material as ShaderMaterial).set_shader_parameter("slot_size", avatar.size)
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
	if is_instance_valid(_leader_card) and is_instance_valid(_like_button):
		var leader_avatar := _leader_card.get_node("Avatar") as Control
		_like_button.reset_size()
		_like_button.position = _leader_card.position + leader_avatar.position + Vector2(leader_avatar.size.x + 12, leader_avatar.size.y - _like_button.size.y)
	_surface.queue_redraw()
	_backdrop.queue_redraw()

## Справа от звезды; если звезда широкая — под её правым краем.
func _layout_leader(card: Control) -> void:
	var side := 64.0
	card.size = Vector2(150, 150)
	var right := 0.0
	var bottom := 0.0
	for point: Vector2 in star_polygon():
		right = maxf(right, point.x)
		bottom = maxf(bottom, point.y)
	var x := right + 24.0
	var y := size.y * 0.40 - 20.0
	if x + card.size.x + 72.0 > size.x - 16.0:
		x = size.x - card.size.x - 88.0
		y = bottom - 40.0
	card.position = Vector2(x, y)
	var avatar := card.get_node("Avatar") as TextureRect
	avatar.position = Vector2((card.size.x - side) * 0.5, 28)
	avatar.size = Vector2.ONE * side
	(avatar.material as ShaderMaterial).set_shader_parameter("slot_size", avatar.size)
	var initials := card.get_node_or_null("Initials") as Label
	if initials:
		initials.position = avatar.position
		initials.size = avatar.size
	var nick := card.get_node("Nickname") as Label
	nick.position = Vector2(0, avatar.position.y + side + 6)
	nick.size = Vector2(card.size.x, 38)
	nick.add_theme_color_override("font_color", _top_ink())
	card.queue_redraw()

## Фон самой игры, без поля и карт: отдельный экземпляр того же задника, что под столом.
func _game_backdrop() -> Control:
	match game:
		"brodilka":
			return preload("res://games/brodilka/ui/br_style.gd").Backdrop.new()
		"four_souls":
			return preload("res://games/four_souls/ui/fs_style.gd").Backdrop.new()
		"gloom", "gloomier":
			return preload("res://games/gloom/ui/gl_style.gd").Backdrop.new()
		"not_a_hat":
			return preload("res://games/not_a_hat/ui/nh_style.gd").Backdrop.new()
		"phantom_ink":
			return preload("res://games/phantom_ink/ui/pi_style.gd").Backdrop.new()
		"ready_set_bet":
			return preload("res://games/ready_set_bet/ui/rsb_style.gd").Backdrop.new()
		"stillion":
			return preload("res://games/stillion/ui/st_style.gd").Backdrop.new()
		"the_gang":
			return preload("res://games/the_gang/ui/tg_style.gd").Background.new()
		"tip_top", "tip_top_18":
			return preload("res://games/tip_top/ui/tt_style.gd").Rays.new()
		"dangerous_words":
			return DWNight.new()
		"hues_and_cues", "word_slam":
			return HCBackdrop.new()
		"wavelength":
			return preload("res://games/wavelength/ui/wl_backdrop.gd").new()
		"king_of_12", "perudo":
			# Только комната таверны: стол с сукном — это игровое поле.
			return K12Tavern.new(false)
	return null

func _draw_backdrop() -> void:
	var dark := Prefs.dark_theme() or game == "the_gang"
	var bg := Color("141a22") if dark else Color("e8e3da")
	bg = bg.lerp(accent, 0.08)
	if game == "things_in_rings":
		preload("res://games/things_in_rings/ui/tr_backdrop.gd").paint(_backdrop, _backdrop.size)
	elif game == "khorom":
		preload("res://games/khorom/ui/kh_style.gd").paint_backdrop(_backdrop, _backdrop.size)
	elif game == "poker":
		preload("res://games/poker/ui/pk_style.gd").paint_backdrop(_backdrop, _backdrop.size)
	else:
		_backdrop.draw_rect(Rect2(Vector2.ZERO, _backdrop.size), bg)

func _draw_surface() -> void:
	var dark := Prefs.dark_theme() or game == "the_gang"
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
	var summary: String = outcome.get("summary", "")
	if not summary.is_empty():
		var summary_w := font.get_string_size(summary, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var summary_y := size.y - 92 if outcome.get("others", []).is_empty() else size.y - 240
		_surface.draw_string(font, Vector2((size.x - summary_w) * 0.5, summary_y), summary, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)
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
	# рамка вплотную к аватарке и на 1 px заходит под неё: сглаженный край маски ложится на обводку, а не на тёмный фон
	card.draw_style_box(_avatar_box(), rect.grow(2))
	if card.has_meta("leader"):
		var font := ThemeDB.fallback_font
		var caption := "Ведущий"
		var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		card.draw_string(font, Vector2((card.size.x - width) * 0.5, 16), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, _top_ink())
		# Цветные точки игроков, поставивших лайк, — столбиком слева от аватарки.
		var index := 0
		for seat: int in _liked_seats():
			if seat < 0 or seat >= players.size():
				continue
			var tint := Color(Net.PLAYER_COLORS[int(players[seat].get("color", seat)) % Net.PLAYER_COLORS.size()])
			var at := rect.position + Vector2(-14 - int(index / 4) * 14, 8 + (index % 4) * 14)
			card.draw_circle(at, 5.0, tint)
			card.draw_arc(at, 5.5, 0, TAU, 16, Color(0, 0, 0, 0.35), 1.0, true)
			index += 1
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
	box.set_corner_radius_all(12)  # внутренний радиус 12 - 2 = 10 — как у маски аватарки
	box.set_border_width_all(3)
	box.border_color = accent.lightened(0.5)
	return box

func show_results(show: bool) -> void:
	_showing = show
	_backdrop.visible = show
	_surface.visible = show
	top_bar.set_victory_backdrop(visible and show, _top_ink())
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
