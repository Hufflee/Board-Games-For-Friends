class_name K12ChatPanel
extends "res://hub/float_panel.gd"
## Чат пати: плавающее окно со вкладками («Всем», личные, «Команда»). Enter — открыть и писать.
## Окно двигают за полосу вкладок, меняют размер за уголок (текст растёт вместе с окном), сворачивают
## в кнопку «Чат» и закрывают; в играх с верхней полосой его открывает и кнопка «Чат» полосы.
## Наведение на сообщение — «ответить» и реакция; скрепка, Ctrl+V или перетаскивание файла — картинка/GIF.
## Сами разговоры хранит узел Net.chat (hub/chat_net.gd), поэтому вкладки переживают смену экрана.

const REACTIONS := ["Думаю...", "Блефую!", "Кидаю кость!", "Хитро!", "Ой…", "Мне повезёт!", "Удивительно!", "Эй, вы ещё здесь?"]
const EMOTE := Color("e8c26a")
const SYSTEM := Color("9fb6ab")

var expanded: bool:
	get:
		return mode == Mode.OPEN
	set(value):
		_expanded_set = true
		_expanded_want = value
		if _built:
			set_mode(Mode.OPEN if value else _rest_mode())

var corner_margin := Vector2(14, 14)  # отступ от правого нижнего угла родителя (docked_top — от правого верхнего)
## Чат в верхней полосе стола (TopBar): открывается и кнопкой полосы, по умолчанию закрыт.
var docked_top := false
## На экране есть своя кнопка «Чат» (хаб): крестик закрывает окно совсем.
var external_button := false
var quick_open := false

var _expanded_set := false
var _expanded_want := false
var _input: LineEdit
var _scroll: ScrollContainer
var _list: VBoxContainer
var _quick: HFlowContainer
var _quick_btn: Button
var _reply_bar: HBoxContainer
var _reply_label: Label
var _attach_bar: HBoxContainer
var _attach_label: Label
var _notice: Label
var _hover_bar: PanelContainer
var _hover_row: Control
var _emoji_open := false
var _menu: PanelContainer
var _viewer: Control
var _rows: Dictionary = {}  # id сообщения → строка
var _reply: Dictionary = {}
var _pending_image := PackedByteArray()
var _stick := 0  # сколько кадров ещё прижимать прокрутку к низу
var _shown := ""
var _colors_key := ""
var _draft := ""


func _ready() -> void:
	var parent := get_parent()
	for sibling: Node in parent.get_children():
		if sibling is K12ChatPanel and sibling != self and not sibling.is_queued_for_deletion():
			# второй чат на том же экране не нужен — раскрываем уже существующий
			(sibling as K12ChatPanel).expanded = true
			mode = Mode.CLOSED
			set_process(false)
			queue_free()
			return
	key = "chat"
	mode_key = "chat_top" if docked_top else "chat"
	title = "Чат"
	base_size = Vector2(340, 330)
	close_minimizes = not docked_top and not external_button
	mode = Mode.OPEN if _expanded_set and _expanded_want else _rest_mode()
	default_place = _default_place
	super._ready()
	tab_selected.connect(func(id: String): Net.chat.select(id))
	tab_closed.connect(func(id: String): Net.chat.close_conv(id))
	mode_changed.connect(_on_mode)
	Net.chat.changed.connect(_sync_tabs)
	Net.chat.entry_added.connect(_on_entry)
	Net.chat.reactions_changed.connect(_on_reactions)
	Net.chat.notice.connect(_say)
	Net.lobby_changed.connect(_on_lobby)
	Net.state_changed.connect(func(_view: Dictionary): _sync_tabs())
	get_window().files_dropped.connect(_on_files_dropped)
	_colors_key = _member_colors_key()
	_sync_tabs()
	_show_conv.call_deferred()


func _rest_mode() -> int:
	return Mode.CLOSED if docked_top or external_button else Mode.MINI


func _default_place(rect_size: Vector2, parent_size: Vector2) -> Vector2:
	if docked_top:
		return Vector2(parent_size.x - rect_size.x - corner_margin.x, corner_margin.y)
	return (parent_size - rect_size - corner_margin).max(Vector2.ZERO)


func unread() -> int:
	return Net.chat.unread_total()


# --- Постройка ---------------------------------------------------------------------------

func _fill_header() -> void:
	var add := small_button("+", "Написать лично или команде")
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.pressed.connect(_toggle_menu)
	header_extra.add_child(add)
	var games := small_button("♙", "Мини-игры: шахматы, шашки, го")
	games.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	games.pressed.connect(func(): Net.minigames.show_panel())
	header_extra.add_child(games)


func _build_body() -> void:
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()
	_rows.clear()
	_hover_row = null
	var pad := px(6)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = pad
	col.offset_right = -pad
	col.offset_top = px(4)
	col.offset_bottom = -pad
	col.add_theme_constant_override("separation", px(4))
	body.add_child(col)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", px(5))
	_scroll.add_child(_list)
	_notice = _label("", 12, Color("f0b86a"))
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.visible = false
	col.add_child(_notice)
	_reply_bar = HBoxContainer.new()
	_reply_bar.visible = false
	_reply_label = _label("", 12, MUTED)
	_reply_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reply_label.clip_text = true
	_reply_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_reply_bar.add_child(_reply_label)
	var reply_x := small_button("×", "Не отвечать")
	reply_x.pressed.connect(_set_reply.bind({}))
	_reply_bar.add_child(reply_x)
	col.add_child(_reply_bar)
	_attach_bar = HBoxContainer.new()
	_attach_bar.visible = false
	_attach_label = _label("", 12, MUTED)
	_attach_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attach_bar.add_child(_attach_label)
	var attach_x := small_button("×", "Убрать картинку")
	attach_x.pressed.connect(_set_pending.bind(PackedByteArray()))
	_attach_bar.add_child(attach_x)
	col.add_child(_attach_bar)
	_quick = HFlowContainer.new()
	_quick.add_theme_constant_override("h_separation", px(4))
	_quick.add_theme_constant_override("v_separation", px(4))
	_quick.visible = quick_open
	for index in REACTIONS.size():
		var phrase: String = REACTIONS[index]
		var b := small_button("%d. %s" % [index + 1, phrase], "Клавиша %d" % (index + 1))
		b.add_theme_stylebox_override("normal", flat(BG_SOFT, 5, 4))
		b.add_theme_color_override("font_color", INK)
		b.pressed.connect(func():
			Net.chat.send(_quick_conv(), phrase, "emote")
			quick_open = false
			_sync_quick())
		_quick.add_child(b)
	col.add_child(_quick)
	var in_row := HBoxContainer.new()
	in_row.add_theme_constant_override("separation", px(4))
	col.add_child(in_row)
	var clip := small_button("📎", "Картинка или GIF до 2 МБ (ещё: Ctrl+V и перетаскивание файла в окно)")
	clip.pressed.connect(_pick_file)
	in_row.add_child(clip)
	_input = LineEdit.new()
	_input.keep_editing_on_text_submit = true
	_input.placeholder_text = "Сообщение…"
	_input.max_length = 200
	_input.text = _draft
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_font_size_override("font_size", px(13))
	_input.add_theme_color_override("font_color", INK)
	_input.add_theme_color_override("font_placeholder_color", Color(MUTED, 0.7))
	_input.add_theme_stylebox_override("normal", flat(Color(0.05, 0.06, 0.08), px(6), px(6), LINE))
	_input.add_theme_stylebox_override("focus", flat(Color(0.05, 0.06, 0.08), px(6), px(6), ACCENT))
	_input.caret_blink = true
	_input.caret_blink_interval = 0.375
	_input.add_theme_constant_override("caret_width", 2)
	_input.text_submitted.connect(_on_submit)
	_input.text_changed.connect(func(text: String):
		_draft = text
		_sync_caret())
	_input.gui_input.connect(_on_input_key)
	in_row.add_child(_input)
	_sync_caret()
	_quick_btn = small_button("Фразы", "Быстрые реплики одним нажатием (клавиши 1–8)")
	_quick_btn.pressed.connect(func():
		quick_open = not quick_open
		_sync_quick())
	in_row.add_child(_quick_btn)
	# панель действий над сообщением под курсором
	if is_instance_valid(_hover_bar):
		_hover_bar.queue_free()
	_hover_bar = PanelContainer.new()
	_hover_bar.add_theme_stylebox_override("panel", flat(BG_HEAD, px(7), px(2), LINE))
	_hover_bar.visible = false
	_hover_bar.z_index = 2
	add_child(_hover_bar)
	_sync_quick()
	_sync_bars()


func _rescale_body() -> void:
	_close_menu()
	_build_body()
	_shown = ""
	_show_conv()


func _label(text: String, font: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px(font))
	l.add_theme_color_override("font_color", color)
	return l


# --- Вкладки -----------------------------------------------------------------------------

func _sync_tabs() -> void:
	if not _built:
		return
	var list := []
	var chat: Node = Net.chat
	for conv_key: String in chat.tabs():
		var conv: Dictionary = chat.convs[conv_key]
		list.append({
			"id": conv_key,
			"text": chat.title_of(conv_key),
			"closable": conv_key != "all",
			"dot": int(conv.unread) > 0,
			"tip": "Личные сообщения" if conv_key.begins_with("pm:") else ("Видит только ваша команда" if conv_key == "team" else "Общий чат пати"),
		})
	set_tabs(list, str(chat.current))
	mini_dot = unread() > 0
	if _shown != str(chat.current):
		_show_conv()
	_input.editable = chat.can_send(str(chat.current))
	_input.placeholder_text = "Сообщение…" if _input.editable else "Сюда сейчас написать нельзя"


func _show_conv() -> void:
	if not _built or _list == null:
		return
	_shown = str(Net.chat.current)
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	_hover_row = null
	_set_reply({})
	var conv: Dictionary = Net.chat.convs.get(_shown, {})
	for entry: Dictionary in conv.get("entries", []):
		_append(entry)
	_stick = 4


func _toggle_menu() -> void:
	if is_instance_valid(_menu):
		_close_menu()
		return
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", flat(BG_HEAD, px(8), px(6), LINE))
	_menu.z_index = 3
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", px(2))
	_menu.add_child(col)
	var chat: Node = Net.chat
	var any := false
	if int(Net.chat_team()) >= 0:
		any = true
		var team := _menu_item("Команда", ACCENT)
		team.pressed.connect(func():
			chat.open_conv("team")
			_close_menu())
		col.add_child(team)
	if chat.pm_allowed():
		for target: Dictionary in chat.pm_targets():
			any = true
			var peer := int(target.peer)
			var item := _menu_item(str(target.name), Net.color_of(int(target.color)))
			item.pressed.connect(func():
				chat.open_pm(peer)
				_close_menu()
				_input.grab_focus())
			col.add_child(item)
	if not any:
		var why := "В этой партии личные сообщения выключены" if not chat.pm_allowed() else "В пати пока никого, кроме вас"
		col.add_child(_label(why, 12, MUTED))
	add_child(_menu)
	_menu.reset_size()
	_menu.position = Vector2(maxf(0.0, size.x - _menu.size.x - px(6)), head_height() + 2)


func _menu_item(text: String, color: Color) -> Button:
	var b := small_button(text, "")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_color_override("font_color", color.lightened(0.25))
	b.add_theme_color_override("font_hover_color", color.lightened(0.5))
	return b


func _close_menu() -> void:
	if is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null


# --- Сообщения ---------------------------------------------------------------------------

func _on_entry(conv: String, entry: Dictionary) -> void:
	if conv == _shown:
		var at_bottom := _scroll.scroll_vertical >= int(_scroll.get_v_scroll_bar().max_value - _scroll.size.y) - px(30)
		_append(entry)
		if at_bottom or int(entry.get("peer", 0)) == Net.chat.my_peer():
			_stick = 4
	var kind := str(entry.get("kind", ""))
	if kind == "emote":
		Sfx.babble(str(entry["text"]), str(entry.get("voice", entry.get("name", ""))))  # реплика — голосом персонажа игрока
	elif kind != "system":
		Sfx.chat_voice(str(entry["text"]), str(entry.get("voice", entry.get("name", ""))))  # сообщение — голосом автора


func _member_colors_key() -> String:
	var parts := []
	for m: Dictionary in Net.lobby_view.get("members", []):
		parts.append("%s:%s" % [m.get("peer", 0), m.get("color", 0)])
	return ",".join(parts)


## Кто-то сменил цвет — перерисовываем журнал, чтобы и старые сообщения были нового цвета.
func _on_lobby() -> void:
	_sync_tabs()
	var colors := _member_colors_key()
	if colors != _colors_key:
		_colors_key = colors
		_shown = ""
		_show_conv()


## Текущий цвет автора: по peer из списка участников; если его там нет — цвет на момент отправки.
func _color_of(entry: Dictionary) -> String:
	var peer := int(entry.get("peer", 0))
	if peer != 0:
		for m: Dictionary in Net.lobby_view.get("members", []):
			if int(m.get("peer", -1)) == peer and m.get("kind", "") != "local" and m.get("kind", "") != "bot":
				return Net.color_of(int(m.get("color", 0))).lightened(0.2).to_html(false)
	var sent := str(entry.get("color", ""))
	return Color(sent).lightened(0.2).to_html(false) if sent != "" else INK.to_html(false)


static func _safe(text: String) -> String:
	return text.replace("[", "[lb]")


func _append(entry: Dictionary) -> void:
	var kind := str(entry.get("kind", "chat"))
	var id := int(entry.get("id", 0))
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", px(2))
	row.set_meta("entry", entry)
	var reply: Dictionary = entry.get("reply", {})
	if not reply.is_empty():
		var quote := Button.new()
		quote.text = "↪ %s: %s" % [str(reply.get("name", "")), str(reply.get("text", ""))]
		quote.tooltip_text = "Перейти к сообщению"
		quote.alignment = HORIZONTAL_ALIGNMENT_LEFT
		quote.clip_text = true
		quote.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		quote.focus_mode = Control.FOCUS_NONE
		quote.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		quote.add_theme_font_size_override("font_size", px(11))
		quote.add_theme_color_override("font_color", MUTED)
		quote.add_theme_color_override("font_hover_color", INK)
		var quote_box := flat(BG_SOFT, px(4), px(4))
		quote_box.border_color = ACCENT
		quote_box.border_width_left = 2
		for state: String in ["normal", "hover", "pressed"]:
			quote.add_theme_stylebox_override(state, quote_box)
		quote.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		quote.pressed.connect(_jump_to.bind(int(reply.get("id", 0))))
		row.add_child(quote)
	var text := _safe(str(entry.get("text", "")))
	var has_image := entry.has("image")
	if has_image and str(entry.get("text", "")) == str(Net.chat.IMAGE_ONLY):
		text = ""
	var who := "[color=#%s]%s[/color]" % [_color_of(entry), _safe(str(entry.get("name", "")))]
	var peer := int(entry.get("peer", 0))
	if peer > 0 and peer != int(Net.chat.my_peer()) and str(entry.get("scope", "all")) != "pm":
		who = "[url=pm:%d]%s[/url]" % [peer, who]  # щелчок по нику — личная вкладка
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.meta_underlined = false
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_theme_font_size_override("normal_font_size", px(13))
	line.add_theme_font_size_override("bold_font_size", px(13))
	line.add_theme_font_size_override("italics_font_size", px(13))
	# цвет задаём в самой разметке: стили игр перекрашивают default_color под свои светлые панели
	var ink := INK.to_html(false)
	match kind:
		"system":
			line.text = "[color=#%s][i]%s[/i][/color]" % [SYSTEM.to_html(false), text]
		"emote":
			line.text = "[b]%s[/b] [color=#%s]%s[/color]" % [who, EMOTE.to_html(false), text]
		_:
			line.text = "[b]%s:[/b] [color=#%s]%s[/color]" % [who, ink, text]
	line.meta_clicked.connect(_on_meta)
	row.add_child(line)
	if has_image:
		var picture := ChatImage.new()
		picture.hash = str(entry["image"])
		picture.limit = Vector2(base_size.x * k - px(34), px(170))
		picture.clicked.connect(_open_viewer)
		row.add_child(picture)
	var chips := HFlowContainer.new()
	chips.name = "Chips"
	chips.add_theme_constant_override("h_separation", px(3))
	chips.add_theme_constant_override("v_separation", px(3))
	chips.visible = false
	row.add_child(chips)
	_list.add_child(row)
	if id > 0:
		_rows[id] = row
		_fill_chips(id)
	if _list.get_child_count() > int(Net.chat.KEEP):
		var old := _list.get_child(0)
		_rows.erase(int((old.get_meta("entry") as Dictionary).get("id", 0)))
		_list.remove_child(old)
		old.queue_free()


func _on_meta(meta: Variant) -> void:
	var link := str(meta)
	if link.begins_with("pm:"):
		if Net.chat.pm_allowed():
			Net.chat.open_pm(int(link.trim_prefix("pm:")))
			_input.grab_focus()
		else:
			_say("В этой партии личные сообщения выключены")


func _on_reactions(id: int) -> void:
	_fill_chips(id)


func _fill_chips(id: int) -> void:
	var row: Control = _rows.get(id)
	if row == null or not is_instance_valid(row):
		return
	var chips := row.get_node("Chips") as HFlowContainer
	for child: Node in chips.get_children():
		chips.remove_child(child)
		child.queue_free()
	var map: Dictionary = Net.chat.reactions.get(id, {})
	chips.visible = not map.is_empty()
	var me := int(Net.chat.my_peer())
	var keys := map.keys()
	keys.sort()
	for emoji: Variant in keys:
		var who: Array = map[emoji]
		var mine := who.has(me)
		var chip := small_button("%s %d" % [Net.chat.EMOJI[int(emoji)], who.size()], _names(who))
		chip.add_theme_font_size_override("font_size", px(12))
		chip.add_theme_color_override("font_color", INK)
		chip.add_theme_stylebox_override("normal", flat(Color(ACCENT, 0.28) if mine else BG_SOFT, px(8), px(3), ACCENT if mine else Color(0, 0, 0, 0)))
		chip.pressed.connect(func(): Net.chat.react(id, int(emoji)))
		chips.add_child(chip)


func _names(peers: Array) -> String:
	var names := PackedStringArray()
	for peer: Variant in peers:
		for m: Dictionary in Net.lobby_view.get("members", []):
			if int(m.get("peer", 0)) == int(peer):
				names.append(str(m.get("name", "")))
	return ", ".join(names)


func _jump_to(id: int) -> void:
	var row: Control = _rows.get(id)
	if row == null or not is_instance_valid(row):
		_say("Это сообщение уже ушло из журнала")
		return
	_stick = 0
	_scroll.ensure_control_visible(row)
	row.modulate = Color(1.6, 1.6, 1.0)
	create_tween().tween_property(row, "modulate", Color.WHITE, 1.2)


func _set_reply(entry: Dictionary) -> void:
	_reply = entry
	_sync_bars()
	if not entry.is_empty() and is_instance_valid(_input):
		_input.grab_focus()


func _set_pending(bytes: PackedByteArray) -> void:
	_pending_image = bytes
	_sync_bars()


func _sync_bars() -> void:
	if _reply_bar == null:
		return
	_reply_bar.visible = not _reply.is_empty()
	if not _reply.is_empty():
		_reply_label.text = "↪ %s: %s" % [str(_reply.get("name", "")), str(_reply.get("text", ""))]
	_attach_bar.visible = not _pending_image.is_empty()
	if not _pending_image.is_empty():
		var gif: bool = Net.chat.is_gif(_pending_image)
		_attach_label.text = "📎 %s, %d КБ — Enter, чтобы отправить" % ["GIF" if gif else "Картинка", ceili(_pending_image.size() / 1024.0)]


func _say(text: String) -> void:
	if not is_instance_valid(_notice):
		return
	_notice.text = text
	_notice.visible = true
	var stamp := Time.get_ticks_msec()
	_notice.set_meta("stamp", stamp)
	get_tree().create_timer(3.5).timeout.connect(func():
		if is_instance_valid(_notice) and int(_notice.get_meta("stamp", 0)) == stamp:
			_notice.visible = false)


# --- Ввод ----------------------------------------------------------------------------------

func _quick_conv() -> String:
	var now := str(Net.chat.current)
	return now if Net.chat.can_send(now) else "all"


func _on_submit(text: String) -> void:
	# Поглощаем Enter до синхронного Net: экран может пересоздаться.
	get_viewport().set_input_as_handled()
	var extra := {}
	if not _reply.is_empty():
		extra["reply"] = {"id": int(_reply.get("id", 0)), "name": str(_reply.get("name", "")), "text": _snippet(_reply)}
	if not _pending_image.is_empty():
		var hash: String = Net.chat.attach(_pending_image)
		if hash != "":
			extra["image"] = hash
	if text.strip_edges().is_empty() and not extra.has("image"):
		return
	_input.clear()
	_draft = ""
	_sync_caret()  # отправили — курсор пропадает до первого нового символа
	_input.grab_focus()
	_reply = {}
	_pending_image = PackedByteArray()
	_sync_bars()
	Net.chat.send(str(Net.chat.current), text, "chat", extra)


static func _snippet(entry: Dictionary) -> String:
	var text := str(entry.get("text", ""))
	if entry.has("image") and text == "🖼":
		text = "картинка"
	return text if text.length() <= 80 else text.left(77) + "…"


## Пустое поле — курсора нет (прозрачный); есть хоть один символ — обычный цвет курсора.
func _sync_caret() -> void:
	if _input.text.is_empty():
		_input.add_theme_color_override("caret_color", Color(0, 0, 0, 0))
	else:
		_input.add_theme_color_override("caret_color", ACCENT)
		_input.caret_blink = true  # перезапуск мигания: после ввода курсор сразу виден


func _sync_quick() -> void:
	if _quick == null:
		return
	_quick.visible = quick_open
	_quick_btn.text = "Скрыть" if quick_open else "Фразы"


func _on_input_key(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and key_event.keycode == KEY_V and key_event.is_command_or_control_pressed():
		if DisplayServer.clipboard_has_image():
			var bytes: PackedByteArray = Net.chat.prepare_image(DisplayServer.clipboard_get_image())
			if not bytes.is_empty():
				_set_pending(bytes)
				_input.accept_event()


func _pick_file() -> void:
	var filters := PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.gif ; Картинки и GIF"])
	DisplayServer.file_dialog_show("Картинка для чата", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters, _on_file_picked)


func _on_file_picked(status: bool, paths: PackedStringArray, _filter: int) -> void:
	if status and not paths.is_empty():
		_take_file(paths[0])


func _on_files_dropped(files: PackedStringArray) -> void:
	if is_open() and is_visible_in_tree() and not files.is_empty():
		_take_file(files[0])


func _take_file(path: String) -> void:
	var bytes: PackedByteArray = Net.chat.prepare_file(path)
	if not bytes.is_empty():
		_set_pending(bytes)
		_input.grab_focus()


func _open_viewer(hash: String) -> void:
	if is_instance_valid(_viewer):
		_viewer.queue_free()
	var parent := get_parent() as Control
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.z_as_relative = false
	dim.z_index = 120
	dim.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			dim.queue_free())
	var picture := ChatImage.new()
	picture.hash = hash
	picture.limit = parent.size * 0.86
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.centered_in = parent.size
	dim.add_child(picture)
	parent.add_child(dim)
	_viewer = dim


# --- Состояние окна ----------------------------------------------------------------------

func _on_mode() -> void:
	_close_menu()
	if mode != Mode.OPEN:
		quick_open = false
		_sync_quick()
		_input.release_focus()
		_hover_bar.visible = false
	else:
		_stick = 4
		_raise_for_input.call_deferred()


## GUI проверяет порядок узлов отдельно от z_index: поздние панели стола не должны закрывать чат мыши.
func _raise_for_input() -> void:
	if is_open() and is_inside_tree() and not is_queued_for_deletion():
		get_parent().move_child(self, -1)


func _process(delta: float) -> void:
	super._process(delta)
	if not _built or mode != Mode.OPEN:
		return
	if is_visible_in_tree():
		Net.chat.touch_view()
	# щелчок мимо меню «+» закрывает его
	if is_instance_valid(_menu) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mouse := get_global_mouse_position()
		if not _menu.get_global_rect().has_point(mouse) and not _head.get_global_rect().has_point(mouse):
			_close_menu()
	if _stick > 0:
		_stick -= 1
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
	_track_hover()


## Сообщение под курсором получает кнопки «ответить» и «реакция».
func _track_hover() -> void:
	var mouse := get_global_mouse_position()
	var over_bar := _hover_bar.visible and _hover_bar.get_global_rect().grow(4).has_point(mouse)
	var row: Control = _hover_row if over_bar else null
	if row == null and _scroll.get_global_rect().has_point(mouse) and _hover_is_ours():
		for child: Node in _list.get_children():
			var candidate := child as Control
			if candidate.get_global_rect().has_point(mouse):
				var entry: Dictionary = candidate.get_meta("entry")
				if str(entry.get("kind", "")) != "system" and int(entry.get("id", 0)) > 0:
					row = candidate
				break
	if row != _hover_row:
		_hover_row = row
		_emoji_open = false
		_fill_hover_bar()
	_hover_bar.visible = row != null and is_instance_valid(row)
	if _hover_bar.visible:
		_hover_bar.reset_size()
		var rect := row.get_global_rect()
		var scroll_rect := _scroll.get_global_rect()
		var at := Vector2(rect.end.x - _hover_bar.size.x - px(4), rect.position.y - px(6))
		at.y = clampf(at.y, scroll_rect.position.y, scroll_rect.end.y - _hover_bar.size.y)
		at.x = maxf(at.x, scroll_rect.position.x)
		_hover_bar.global_position = at


func _fill_hover_bar() -> void:
	for child: Node in _hover_bar.get_children():
		_hover_bar.remove_child(child)
		child.queue_free()
	if _hover_row == null:
		return
	var entry: Dictionary = _hover_row.get_meta("entry")
	var id := int(entry.get("id", 0))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	_hover_bar.add_child(line)
	if _emoji_open:
		for index in Net.chat.EMOJI.size():
			var emoji := small_button(str(Net.chat.EMOJI[index]), str(Net.chat.EMOJI_TIPS[index]))
			emoji.add_theme_font_size_override("font_size", px(15))
			emoji.pressed.connect(func():
				Net.chat.react(id, index)
				_emoji_open = false
				_fill_hover_bar())
			line.add_child(emoji)
		return
	var answer := small_button("↩", "Ответить")
	answer.pressed.connect(_set_reply.bind(entry))
	line.add_child(answer)
	var smile := small_button("☺", "Реакция")
	smile.pressed.connect(func():
		_emoji_open = true
		_fill_hover_bar())
	line.add_child(smile)


func _unhandled_key_input(event: InputEvent) -> void:
	var ke := event as InputEventKey
	if ke == null or not _built:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	# 1–8 (и на цифровой панели) — быстрая реплика без открытия чата; пока пишут в поле — цифры печатаются
	if ke.pressed and not ke.echo and not _input.has_focus() and Net.in_session():
		var n := -1
		if ke.keycode >= KEY_1 and ke.keycode <= KEY_9:
			n = ke.keycode - KEY_1
		elif ke.keycode >= KEY_KP_1 and ke.keycode <= KEY_KP_9:
			n = ke.keycode - KEY_KP_1
		if n >= 0 and n < REACTIONS.size() and not ke.ctrl_pressed and not ke.alt_pressed:
			Net.chat.send(_quick_conv(), REACTIONS[n], "emote")
			get_viewport().set_input_as_handled()
			return
	if ke.pressed and not ke.echo and ke.keycode in [KEY_ENTER, KEY_KP_ENTER] and not ke.ctrl_pressed and not ke.alt_pressed:
		get_viewport().set_input_as_handled()
		expanded = not expanded
		if expanded:
			_input.grab_focus()


## Ряд кнопок быстрых реакций.
static func reactions_row() -> HBoxContainer:
	var row := K12UI.hbox(4)
	for r in REACTIONS:
		var b := K12UI.button(r, K12UI.CAP)
		b.pressed.connect(func(): Net.send_chat(r, "emote"))
		row.add_child(b)
	return row


## Картинка или гифка сообщения: ждёт загрузку, вписывается в отведённое место, гифка играет, пока видна.
class ChatImage:
	extends Control

	signal clicked(hash: String)

	var hash := ""
	var limit := Vector2(300, 170)
	var centered_in := Vector2.ZERO  # большой просмотр: размер экрана, по центру которого стоять
	var _frames: Array[Texture2D] = []
	var _delays: PackedFloat32Array = []
	var _frame := 0
	var _clock := 0.0
	var _state := "wait"

	func _ready() -> void:
		custom_minimum_size = Vector2(minf(limit.x, 160.0), 44.0)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "Открыть крупно" if centered_in == Vector2.ZERO else ""
		Net.chat.image_ready.connect(_on_ready)
		_take()

	func _on_ready(ready_hash: String) -> void:
		if ready_hash == hash and _state == "wait":
			_take()

	func _take() -> void:
		var resource: Resource = Net.chat.image_texture(hash)
		if resource == null:
			if Net.chat.image_failed(hash):
				_state = "fail"
				queue_redraw()
			return
		if resource is SpriteFrames:
			var sprite := resource as SpriteFrames
			for index in sprite.get_frame_count(&"default"):
				_frames.append(sprite.get_frame_texture(&"default", index))
				_delays.append(maxf(0.02, sprite.get_frame_duration(&"default", index)))
		else:
			_frames.append(resource as Texture2D)
			_delays.append(1.0)
		_state = "ok"
		var natural := _frames[0].get_size()
		var fit := minf(1.0, minf(limit.x / natural.x, limit.y / natural.y))
		custom_minimum_size = (natural * fit).round()
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		if centered_in != Vector2.ZERO:
			size = custom_minimum_size
			position = ((centered_in - size) * 0.5).round()
		set_process(_frames.size() > 1)
		queue_redraw()

	func _process(delta: float) -> void:
		if _frames.size() < 2 or not is_visible_in_tree():
			return
		_clock += delta
		if _clock >= _delays[_frame]:
			_clock = 0.0
			_frame = (_frame + 1) % _frames.size()
			queue_redraw()

	func _draw() -> void:
		if _state == "ok":
			draw_texture_rect(_frames[_frame], Rect2(Vector2.ZERO, custom_minimum_size), false)
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.06))
		var note := "Картинка загружается…" if _state == "wait" else "Картинку не удалось показать"
		draw_string(ThemeDB.fallback_font, Vector2(8, 26), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.72, 0.78))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _state == "ok":
			clicked.emit(hash)
			accept_event()
