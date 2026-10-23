class_name TopBar
extends PanelContainer
## Общая верхняя полоса стола: слева мелкое название игры и часы, под ними ход/раунд, по центру гнездо монетки, справа — общие кнопки
## (чат, пауза у хоста, «стать зрителем», пригласить) и кнопки игры (правила, настройки, тема, выход).
## Всё общее живёт здесь, а стол игры начинается ниже (HEIGHT) — ничего не залезает на поле.
## Чат раскрывается выпадающей панелью справа под полосой. Пока полоса на экране, PauseLayer
## свои кнопки не показывает (группа "top_bar").
## Оформление — от игры: make_button(text, size) -> Button, фон полосы (StyleBox), цвета текста.

const HEIGHT := 48.0
const MAX_INFO_W := 340.0  # строка хода/раунда длиннее — обрезается многоточием перед монеткой

var title: Label
var info: Label  # фаза / раунд — игра пишет сюда сама
var actions: HBoxContainer  # сюда игра кладёт свои кнопки (правила, настройки, тема, выход)
var chat: K12ChatPanel
var coin_dock: Control  # место для монетки-антистресса (Fidget встаёт сюда по умолчанию)
var coin_center := false  # гнездо монетки — по центру полосы (в некоторых играх), а не за часами
var coin_at := Callable()  # своё место гнезда: -> Vector2 (центр в экранных координатах), напр. под панелью игры
var _clock: TurnClock
var _left: VBoxContainer

var _make_button: Callable
var _chat_btn: Button
var _pause_btn: Button
var _spec_btn: Button
var _invite_btn: Button


## bar — фон полосы (null — прозрачная: сквозь неё виден фон игры);
## text — цвет надписей; parent — экран стола (чат вешается на него).
static func make(parent: Control, game_title: String, make_button: Callable, bar: StyleBox, text: Color, title_font: Font = null) -> TopBar:
	var t := TopBar.new()
	t._make_button = make_button
	if bar == null:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.0)
		sb.content_margin_left = 16
		sb.content_margin_right = 12
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		bar = sb
	t.add_theme_stylebox_override("panel", bar)
	t.place()
	t.mouse_filter = Control.MOUSE_FILTER_STOP
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
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(right)
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
	t._pause_btn.pressed.connect(func(): Net.set_paused(true))
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
	t.chat.corner_margin = Vector2(12, HEIGHT + 8)
	parent.add_child(t.chat)
	parent.add_child(t)
	return t


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
	_invite_btn.visible = Net.is_party()
	_spec_btn.visible = playing and not spectator and Net.can_spectate()
	var unread := chat.unread() if chat else 0
	var t := ("Скрыть чат" if chat and chat.expanded else "Чат") + (" (%d)" % unread if unread > 0 else "")
	if _chat_btn.text != t:
		_chat_btn.text = t
