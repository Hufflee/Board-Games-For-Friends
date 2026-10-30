class_name TopBar
extends PanelContainer
## Общая верхняя полоса стола: слева мелкое название игры и часы, под ними ход/раунд, по центру гнездо монетки, справа — общие кнопки
## Клавиша Esc выдвигает прежний ряд действий из-за верхнего края; слева всё видно постоянно.
## Всё общее живёт здесь, а стол игры начинается ниже (HEIGHT) — ничего не залезает на поле.
## Чат раскрывается выпадающей панелью справа под полосой. Пока полоса на экране, PauseLayer
## свои кнопки не показывает (группа "top_bar").
## Оформление — от игры: make_button(text, size) -> Button, фон полосы (StyleBox), цвета текста.

const HEIGHT := 48.0
static var _saved_match := ""
static var _saved_menu_open := false
var _match_key := ""
const MAX_INFO_W := 340.0  # строка хода/раунда длиннее — обрезается многоточием перед монеткой

var title: Label
var info: Label  # фаза / раунд — игра пишет сюда сама
var actions: HBoxContainer  # прежний однорядный набор кнопок игры
var chat: K12ChatPanel
var coin_dock: Control  # место для монетки-антистресса (Fidget встаёт сюда по умолчанию)
var coin_center := false  # гнездо монетки — по центру полосы (в некоторых играх), а не за часами
var coin_at := Callable()  # своё место гнезда: -> Vector2 (центр в экранных координатах), напр. под панелью игры
var _victory_screen: Control
var _table_panel: StyleBox
var _victory_panel: StyleBoxFlat
var _victory_backdrop := false
var _table_text := Color.WHITE
var _clock: TurnClock
var _left: VBoxContainer

var _make_button: Callable
var _chat_btn: Button
var _pause_btn: Button
var _pause_icon: PlayPauseIcon
var _spec_btn: Button
var _invite_btn: Button
var _esc_btn: Button
var _drawer: HBoxContainer
var _menu_open := false
var _menu_tween: Tween
var _menu_amount := 0.0:
	set(value):
		_menu_amount = value
		_place_actions()



## bar — фон полосы (null — прозрачная: сквозь неё виден фон игры);
## text — цвет надписей; parent — экран стола (чат вешается на него).
static func make(parent: Control, game_title: String, make_button: Callable, bar: StyleBox, text: Color, title_font: Font = null) -> TopBar:
	var t := TopBar.new()
	t._match_key = Net.game_id
	if _saved_match != t._match_key or t._match_key.is_empty():
		_saved_match = t._match_key
		_saved_menu_open = false
	t._menu_open = _saved_menu_open
	t._menu_amount = 1.0 if t._menu_open else 0.0
	t._make_button = make_button
	t._table_text = text
	if bar == null:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.0)
		sb.content_margin_left = 16
		sb.content_margin_right = 12
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		bar = sb
	t.add_theme_stylebox_override("panel", bar)
	t._table_panel = bar
	t._victory_panel = StyleBoxFlat.new()
	t._victory_panel.bg_color = Color.TRANSPARENT
	for edge: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		t._victory_panel.set_content_margin(edge, bar.get_content_margin(edge))
	t.place()
	t.mouse_filter = Control.MOUSE_FILTER_STOP
	t.z_as_relative = false
	t.z_index = 90
	t.add_to_group("top_bar")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	t.add_child(row)
	# слева, как в Hues and Cues: сверху мелкое название игры прописными в разрядку и часы,
	# под ними крупно ход/раунд
	var left := VBoxContainer.new()
	t._left = left
	left.add_theme_constant_override("separation", -3)
	left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN  # ширину задаём сами: до гнезда монетки
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(left)
	t.title = Label.new()
	t.title.text = game_title.to_upper()
	t.title.add_theme_font_size_override("font_size", 11)
	t.title.add_theme_color_override("font_color", Color(text, 0.8))
	var tf := FontVariation.new()  # разрядка букв
	tf.base_font = title_font if title_font else ThemeDB.fallback_font
	tf.spacing_glyph = 2
	t.title.add_theme_font_override("font", tf)
	t.title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# часы — справа от названия: название не меняется, часы не прыгают
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(t.title)
	left.add_child(head)
	t.info = Label.new()
	t.info.add_theme_font_size_override("font_size", 19)
	t.info.add_theme_color_override("font_color", text)
	t.info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.info.clip_text = true  # длинный ник — многоточием
	t.info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	left.add_child(t.info)
	t._clock = TurnClock.new()
	t._clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t._clock.scale = Vector2(0.8, 0.8)  # в строке мелкого названия — чуть меньше
	head.add_child(t._clock)
	row.add_child(spacer)
	t._esc_btn = load("res://hub/escape_key.gd").new()
	t._esc_btn.set_ink(text)
	t._esc_btn.name = "EscapeMenu"
	t._esc_btn.tooltip_text = "Показать или скрыть меню (Escape)"
	t._esc_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t._esc_btn.set_meta("top_bar_escape", true)
	t._esc_btn.pressed.connect(t.toggle_menu)
	row.add_child(t._esc_btn)
	# Ряд движется целиком в прежней верхней полосе; плашки под ним нет.
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(overlay)
	t._drawer = HBoxContainer.new()
	t._drawer.name = "ActionDrawer"
	t._drawer.visible = t._menu_open
	t._drawer.add_theme_constant_override("separation", 6)
	overlay.add_child(t._drawer)
	var right := t._drawer
	t._chat_btn = t._btn("Чат", "Чат и быстрые фразы (Enter)")
	t._chat_btn.pressed.connect(func(): t.chat.expanded = not t.chat.expanded)
	right.add_child(t._chat_btn)
	t._invite_btn = t._btn("Пригласить", "Позвать друзей в пати")
	t._invite_btn.pressed.connect(t._invite)
	right.add_child(t._invite_btn)
	t._spec_btn = t._btn("Зритель", "Выйти из-за стола и смотреть: за ваше место будет играть бот. Вернуть может хост через «Паузу».")
	t._spec_btn.pressed.connect(func():
		LeaveGuard.ask(t._spec_btn, "Стать зрителем?", "За ваше место будет играть бот. Вы увидите стол как обычный игрок; вернуть за стол может хост через «Паузу».", "Смотреть", Net.become_spectator, "Остаться в игре"))
	right.add_child(t._spec_btn)
	t._pause_btn = t._btn("Пауза", "Поставить игру на паузу (только хост). Здесь же — посадить друзей за стол и пригласить новых.")
	var pic := PlayPauseIcon.attach(t._pause_btn, Net.paused)
	t._pause_icon = pic
	t._pause_btn.pressed.connect(func():
		# «‖» перетекает в «▶» — и только потом пауза (иначе окно паузы закроет анимацию)
		var to_play := not Net.paused
		pic.morph(to_play, func(): Net.set_paused(to_play)))
	right.add_child(t._pause_btn)
	var sep := VSeparator.new()
	sep.modulate = Color(text, 0.3)
	right.add_child(sep)
	t.actions = HBoxContainer.new()
	t.actions.add_theme_constant_override("separation", 6)
	right.add_child(t.actions)
	# гнездо для монетки — справа от часов (без часов — на их месте), поверх строки
	var mid := Control.new()
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(mid)
	t.coin_dock = Control.new()
	t.coin_dock.size = Vector2(56, 36)
	t.coin_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.coin_dock.tooltip_text = "Слот под монетку"
	# лунка всегда под монеткой: даже если игра подняла полосу по z_index, гнездо остаётся на нижнем слое
	t.coin_dock.z_as_relative = false
	t.coin_dock.z_index = 0
	t.coin_dock.draw.connect(func():
		var c := t.coin_dock.size * 0.5
		t.coin_dock.draw_circle(c, 23.0, Color(0, 0, 0, 0.32))  # лунка
		t.coin_dock.draw_arc(c + Vector2(0, 1), 23.0, PI * 0.15, PI * 0.85, 16, Color(1, 1, 1, 0.12), 2.0, true)  # блик снизу
		t.coin_dock.draw_arc(c, 23.0, PI * 1.15, PI * 1.85, 16, Color(0, 0, 0, 0.35), 2.0, true))  # тень сверху
	mid.add_child(t.coin_dock)
	# чат — выпадает справа под полосой, в свёрнутом виде его не видно
	t.chat = K12ChatPanel.new()
	t.chat.docked_top = true
	t.chat.z_as_relative = false
	t.chat.z_index = 95
	t.chat.corner_margin = Vector2(12, HEIGHT + 8)
	parent.add_child(t.chat)
	parent.add_child(t)
	var victory := load("res://hub/victory_screen.gd").new() as Control
	victory.table = parent
	victory.top_bar = t
	victory.make_button = make_button
	victory.game = "gloomier" if Net.party_game == "gloom" and str(Net.settings.get("gl_sets", "base")) == "gm" else Net.party_game
	var entry := HubGames.by_id(Net.party_game)
	victory.accent = entry.get("color", Color("b99346"))
	parent.add_child(victory)
	t._victory_screen = victory
	return t

## Во время финала фон общий на весь экран; настоящие часы, кнопки и гнездо остаются сверху.
func set_victory_backdrop(active: bool, ink := Color("f9edd8")) -> void:
	if _victory_backdrop == active:
		return
	_victory_backdrop = active
	add_theme_stylebox_override("panel", _victory_panel if active else _table_panel)
	coin_dock.z_index = z_index if active else 0
	var text := ink if active else _table_text
	title.add_theme_color_override("font_color", Color(text, 0.8))
	info.add_theme_color_override("font_color", text)
	_esc_btn.set_ink(text)


## Прижать полосу к верху экрана.
func place() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_top = 0
	offset_bottom = HEIGHT


func _btn(text: String, tip: String) -> Button:
	var b: Button = _make_button.call(text, 14)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	return b


func _invite() -> void:
	if Net.mode == "steam" and Net.steam_ok:
		SteamInvite.open_panel()
	else:
		DisplayServer.clipboard_set(Net.lobby_code())
		_invite_btn.text = "Код скопирован ✓"
		get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(_invite_btn):
				_invite_btn.text = "Пригласить")


func _process(_d: float) -> void:
	if is_instance_valid(_victory_screen):
		_victory_screen.sync(Net.view)
	# z_index влияет на рисунок, но поздние контейнеры стола перехватывают GUI.
	# Поднимаем полосу только под немодальными соседями; окна остаются последними.
	var parent := get_parent()
	if parent != null:
		var target := parent.get_child_count() - 1
		for sibling: Node in parent.get_children():
			if sibling != self and sibling is Control and sibling.is_visible_in_tree() and sibling.z_index >= 100:
				target = mini(target, sibling.get_index() - 1)
		# GUI выбирает узлы по дереву, независимо от z_index. Общий финал и чат
		# должны идти после поздно созданных игровых панелей, но перед модальными окнами.
		var ordered: Array[Control] = []
		if is_instance_valid(_victory_screen):
			ordered.append(_victory_screen)
		if is_instance_valid(chat):
			ordered.append(chat)
		ordered.append(self)
		for index: int in ordered.size():
			var wanted := maxi(0, target - ordered.size() + 1 + index)
			if ordered[index].get_index() != wanted:
				parent.move_child(ordered[index], wanted)
		z_index = maxi(z_index, 90)
	if coin_dock and _left:
		# гнездо — вплотную за часами (или за названием, если часов нет) либо за строкой хода — что длиннее;
		# слишком длинная строка обрезается многоточием перед монеткой (не дальше MAX_INFO_W)
		var mid := coin_dock.get_parent() as Control
		var head_end := _clock.get_global_rect().end.x if _clock.visible else title.get_global_rect().end.x
		var f := info.get_theme_font("font")
		var fs := info.get_theme_font_size("font_size")
		var text_end := info.global_position.x + (f.get_string_size(info.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if f else 0.0)
		var anchor_x := minf(maxf(head_end, text_end) + 8.0, _left.global_position.x + MAX_INFO_W)
		if coin_center:
			anchor_x = mid.global_position.x + (mid.size.x - coin_dock.size.x) * 0.5
		var w := MAX_INFO_W
		if coin_at.is_valid():
			# гнездо вне полосы — там, где скажет игра; строке хода — вся ширина
			coin_dock.global_position = (coin_at.call() as Vector2) - coin_dock.size * 0.5
		else:
			coin_dock.position = Vector2(anchor_x - mid.global_position.x, (mid.size.y - coin_dock.size.y) * 0.5)
			if not coin_center:
				w = maxf(anchor_x - 6.0 - _left.global_position.x, 60.0)
		if absf(_left.custom_minimum_size.x - w) > 0.5:
			_left.custom_minimum_size.x = w
	var playing := Net.in_session() and not Net.view.is_empty()
	var spectator := bool(Net.view.get("spectator", false))
	_pause_btn.visible = playing and Net.is_host()
	_pause_icon.sync_state(Net.paused)
	_pause_btn.text = "Продолжить" if Net.paused else "Пауза"
	_invite_btn.visible = Net.is_party()
	_spec_btn.visible = playing and not spectator and Net.can_spectate()
	var unread := chat.unread() if chat else 0
	var t := "Чат" + (" (%d)" % unread if unread > 0 else "")
	if _chat_btn.text != t:
		_chat_btn.text = t
	_place_actions()


## Тот же однорядный набор и размеры; лишь очень длинный ряд уменьшаем до свободной ширины.
func _place_actions() -> void:
	if not is_instance_valid(_drawer) or not is_instance_valid(_esc_btn):
		return
	var natural := _drawer.get_combined_minimum_size()
	var right := _esc_btn.global_position.x - 6.0
	var left := _left.get_global_rect().end.x + 12.0
	if not coin_center and not coin_at.is_valid():
		left = maxf(left, coin_dock.get_global_rect().end.x + 12.0)
	var fit := minf(1.0, maxf(1.0, right - left) / maxf(1.0, natural.x))
	# Раньше правый HBox растягивался по высоте общей строки вместе с левым блоком.
	_drawer.size = Vector2(natural.x, maxf(natural.y, _left.size.y))
	_drawer.scale = Vector2(fit, fit)
	var height := _drawer.size.y * fit
	var shown_y := global_position.y + (size.y - height) * 0.5
	var hidden_y := -height - 2.0
	_drawer.global_position = Vector2(right - natural.x * fit, lerpf(hidden_y, shown_y, _menu_amount))


## Повторное нажатие разворачивает текущую анимацию без второго обработчика.
func toggle_menu() -> void:
	set_menu_open(not _menu_open)


func set_menu_open(open: bool) -> void:
	_menu_open = open
	if not _match_key.is_empty() and Net.game_id == _match_key:
		_saved_match = _match_key
		_saved_menu_open = open
	if _menu_tween != null and _menu_tween.is_valid():
		_menu_tween.kill()
	if open:
		_drawer.show()
	# Во время закрытия панель уже не принимает клики по старой позиции.
	_drawer.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	_set_drawer_input(_drawer, open)
	_menu_tween = create_tween()
	_menu_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_menu_tween.tween_property(self, "_menu_amount", 1.0 if open else 0.0, 0.22)
	if not open:
		_menu_tween.tween_callback(_drawer.hide)


func _set_drawer_input(node: Node, on: bool) -> void:
	for child: Node in node.get_children():
		if child is Control:
			# При закрытии не меняем disabled: права и состояние задаёт игра.
			if not on and child.has_focus():
				child.release_focus()
			if not on and not child.has_meta("drawer_mouse_filter"):
				child.set_meta("drawer_mouse_filter", child.mouse_filter)
			if on and child.has_meta("drawer_mouse_filter"):
				child.mouse_filter = int(child.get_meta("drawer_mouse_filter"))
				child.remove_meta("drawer_mouse_filter")
			elif not on:
				child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_drawer_input(child, on)


## Окна правил/настроек могут закрываться без set_input_as_handled().
## Поэтому наличие видимого модального слоя проверяем до переключения меню.
func _has_modal(node: Node) -> bool:
	if node == null or node == self or node == chat:
		return false
	if node is Window and node != get_tree().root and node.visible:
		return true
	if node is Control and node.is_visible_in_tree() and node.z_index >= 100:
		return true
	for child: Node in node.get_children():
		if _has_modal(child):
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _has_modal(get_tree().current_scene):
			return
		toggle_menu()
		get_viewport().set_input_as_handled()
