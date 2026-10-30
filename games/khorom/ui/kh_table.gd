extends Control
## «Хором!»: стол. Слева игроки и очки, сверху карточка раунда, в центре блокноты.
## Пишу — мой блокнот на весь центр; готов — все блокноты уменьшаются и встают рядом (чужие строки под пластинками).
## Открытие — блокнот того, кто ходит, крупнее в 1,5 раза.
const Style := preload("res://games/khorom/ui/kh_style.gd")
const Notebook := preload("res://games/khorom/ui/kh_notebook.gd")
const LEFT_W := 208.0
const GAP := 16.0
var app: Node
var view: Dictionary = {}
var _top: TopBar
var _left: VBoxContainer
var _card: PanelContainer
var _card_kind: Label
var _card_topic: Label
var _area: Control
var _fall: Control
var _bottom: HBoxContainer
var _caption: Label
var _books := {}
var _book_key := ""
var _time_left := 0.0
var _dark := false

func _ready() -> void:
	_dark = Prefs.dark_theme()
	_top = TopBar.make(self, "Хором!", Style.button, null, Style.ink(), Style.HEAD)
	for item: Array in [["Правила", app.show_rules], ["Настройки", app.show_settings]]:
		var b := Style.button(item[0], 16)
		b.pressed.connect(item[1])
		_top.actions.add_child(b)
	_top.actions.add_child(ThemeToggle.make(Style.button, 16))
	Prefs.changed.connect(_theme_changed)
	var leave := Style.button("Выйти", 16)
	LeaveGuard.wire(leave, "Выйти?", "Вернуться к выбору игры.", app.back_to_hub)
	_top.actions.add_child(leave)
	_left = Style.column(8)
	_left.name = "Players"
	add_child(_left)
	_card = PanelContainer.new()
	_card.name = "RoundCard"
	_card.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT, 12, 12))
	var card_col := Style.column(2)
	card_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.add_child(card_col)
	_card_kind = Style.section("")
	_card_kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_col.add_child(_card_kind)
	_card_topic = Style.heading("")
	_card_topic.name = "Topic"
	_card_topic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_topic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_topic.custom_minimum_size.x = 440
	card_col.add_child(_card_topic)
	add_child(_card)
	_area = Control.new()
	_area.name = "Books"
	_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_area)
	_bottom = Style.row(16)
	_bottom.name = "Actions"
	_bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_bottom)
	_fall = Control.new()
	_fall.name = "FallLayer"
	_fall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fall.z_index = 50
	add_child(_fall)
	resized.connect(_layout)
	Net.state_changed.connect(_state)
	if not Net.view.is_empty():
		_state(Net.view)

func _theme_changed() -> void:
	if _dark == Prefs.dark_theme():
		return
	_dark = Prefs.dark_theme()
	get_tree().root.theme = Style.theme()
	app.theme = get_tree().root.theme
	app.show_table()

func _send(kind: String, payload: Dictionary = {}) -> void:
	payload["revision"] = int(view.get("revision", -1))
	Net.send_action(kind, payload)

func _me() -> int:
	return int(view.get("you", -1))

func _i_wrote() -> bool:
	var me := _me()
	return me >= 0 and bool(view.books[me].ready)

func _state(next: Dictionary) -> void:
	if not next.has("books"):
		return
	view = next
	_time_left = float(view.get("time_left", 0.0))
	var key := str([view.get("round_no"), view.get("you"), view.get("kind"), view.players.size(), Net.game_id])
	if key != _book_key:
		_book_key = key
		for book: Control in _books.values():
			_area.remove_child(book)  # сразу из дерева: новые блокноты получат те же имена
			book.queue_free()
		_books.clear()
		for seat: int in view.players.size():
			var book: Control = Notebook.new()
			book.setup(seat, seat == _me(), str(view.kind), view.topics)
			book.fall_layer = _fall
			book.write_row.connect(func(row: int, text: String): _send("write", {"row": row, "text": text}))
			book.reveal_row.connect(func(row: int): _send("reveal", {"row": row}))
			book.mark_row.connect(func(row: int): _send("mark", {"row": row}))
			_area.add_child(book)
			_books[seat] = book
	_rebuild()
	_layout()

func _rebuild() -> void:
	var people: Array = view.players
	var phase := str(view.phase)
	var me := _me()
	var turn := int(view.turn)
	var leader := int(view.leader)
	# Левая панель: игроки и очки.
	Style.clear(_left)
	_left.add_child(Style.section("Игроки · очки"))
	# Таблица очков: имя и пометки слева, сумма за партию крупно справа, рядом — сколько набирается в этом раунде.
	var best := 0
	for seat: int in people.size():
		best = maxi(best, int(view.scores[seat]))
	for seat: int in people.size():
		var marks := ""
		if seat == leader:
			marks = "ведущий"
		if phase == "write" and bool(view.books[seat].ready):
			marks += (" · " if marks != "" else "") + "готов"
		elif phase == "reveal" and seat == turn:
			marks += (" · " if marks != "" else "") + "открывает"
		var b := Style.button("", 12)
		b.name = "Seat%d" % seat
		b.custom_minimum_size.y = 48
		Style.pick(b, seat == me)
		b.disabled = not bool(view.get("hotseat", false)) or seat == me
		b.pressed.connect(func(): Net.send_action("view_seat", {"seat": seat}))
		var line := Style.row(8)
		line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 12
		line.offset_right = -12
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var names := Style.column(0)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.alignment = BoxContainer.ALIGNMENT_CENTER
		var nick := Style.label(str(people[seat].name), 16, Style.ACCENT if seat == turn and phase == "reveal" else Color.TRANSPARENT)
		nick.clip_text = true
		names.add_child(nick)
		if marks != "":
			var sub := Style.label(marks, 12, Style.muted())
			sub.clip_text = true
			names.add_child(sub)
		line.add_child(names)
		var gain := int(view.books[seat].points)
		if phase in ["reveal", "round_end"] and gain != 0:
			var plus := Style.label("%+d" % gain, 12, Style.GOOD if gain > 0 else Style.BAD)
			plus.name = "Gain"
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			plus.size_flags_vertical = Control.SIZE_FILL
			line.add_child(plus)
		var total := Style.heading(str(int(view.scores[seat])), 28 if int(view.scores[seat]) == best and best > 0 else 16)
		total.name = "Score"
		total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		total.size_flags_vertical = Control.SIZE_FILL
		total.custom_minimum_size.x = 28
		total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(total)
		for child: Node in line.find_children("*", "Control", true, false):
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(line)
		_left.add_child(b)
	if bool(view.get("hotseat", false)):
		var hint := Style.label("Один компьютер: передайте экран и нажмите своё имя.", 12, Style.muted())
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_left.add_child(hint)
	_left.add_child(Style.section("Раунд %d из %d" % [int(view.round_no) + 1, int(view.total_rounds)]))
	var rule := Style.label(str(KHData.KIND_HINTS.get(str(view.kind), "")), 12, Style.muted())
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left.add_child(rule)
	# Карточка раунда: название сверху, тема посередине.
	_card_kind.text = str(view.kind_name)
	if str(view.kind) == "blitz":
		var row := int(view.blitz_row)
		_card_topic.text = "%s · тема %d из 6" % [view.topics[row], row + 1] if phase == "reveal" else "6 тем — по строкам"
	else:
		_card_topic.text = str(view.topics[0])
	# Блокноты.
	for seat: int in _books:
		var book: Control = _books[seat]
		var data: Dictionary = view.books[seat]
		var status := ""
		if phase == "write":
			status = "готов" if bool(data.ready) else "пишет · %d/6" % int(data.filled)
		else:
			status = "%+d за раунд" % int(data.points) if phase != "game_over" else ""
		book.apply(data, {
			"title": str(people[seat].name) + (" · ведущий" if seat == leader else ""),
			"status": status,
			"editable": seat == me and phase == "write" and not bool(data.ready),
			"active": phase == "reveal" and seat == turn,
			"plates": true,
			"marking": phase in ["reveal", "round_end"],
		})
	# Подпись фазы и действия.
	Style.clear(_bottom)
	_caption = Style.label(_phase_text(), 16)
	_caption.name = "PhaseCaption"
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bottom.add_child(_caption)
	if phase == "write" and me >= 0:
		var ready := Style.button("Изменить ответы" if _i_wrote() else "Готов")
		ready.name = "Ready"
		ready.custom_minimum_size.x = 200
		if not _i_wrote():
			ready.theme_type_variation = "SelectedButton"
		ready.pressed.connect(func():
			_flush_edits()
			_send("unready" if _i_wrote() else "ready"))
		_bottom.add_child(ready)
	elif phase == "reveal" and turn == me:
		var pass_button := Style.button("Передать ход")
		pass_button.name = "Pass"
		pass_button.pressed.connect(func(): _send("pass"))
		_bottom.add_child(pass_button)
	elif phase == "round_end" and Net.is_host():
		var last := int(view.round_no) + 1 >= int(view.total_rounds)
		var next := Style.button("Подвести итоги" if last else "Следующий раунд")
		next.name = "NextRound"
		next.custom_minimum_size.x = 220
		next.theme_type_variation = "SelectedButton"
		next.pressed.connect(func(): _send("next"))
		_bottom.add_child(next)

## Недописанное в полях ввода — сразу хосту, прежде чем нажать «Готов».
func _flush_edits() -> void:
	var me := _me()
	if not _books.has(me):
		return
	var book: Control = _books[me]
	for row: int in 6:
		var edit: LineEdit = book._edits[row]
		if edit != null and edit.editable:
			book._timers[row].stop()
			_send("write", {"row": row, "text": edit.text})

func _phase_text() -> String:
	var people: Array = view.players
	match str(view.phase):
		"write":
			if _i_wrote():
				return "Ждём остальных…"
			return "Запишите до 6 ответов" if str(view.kind) != "blitz" else "По ответу на каждую тему"
		"reveal":
			var turn := int(view.turn)
			if turn == _me():
				return "Ваш ход: откройте ответы глазиком"
			return "Открывает: %s" % people[turn].name if turn >= 0 else ""
		"round_end":
			return "Раунд окончен — отметьте совпадения" if Net.is_host() else "Раунд окончен · ждём хоста"
		"game_over":
			return "Партия окончена"
	return ""

func _process(delta: float) -> void:
	if view.is_empty():
		return
	var text := "Итоги партии" if str(view.phase) == "game_over" else "Раунд %d/%d · %s" % [int(view.round_no) + 1, int(view.total_rounds), view.kind_name]
	if str(view.phase) == "write" and _time_left > 0.0:
		_time_left = maxf(0.0, _time_left - delta)
		text += " · %d:%02d" % [int(_time_left) / 60, int(_time_left) % 60]
	_top.info.text = text

## Раскладка: карточка сверху, блокноты в центре (подбираем масштаб, чтобы все влезли), действия снизу.
func _layout() -> void:
	if view.is_empty() or not is_inside_tree():
		return
	var top := TopBar.HEIGHT + GAP
	_left.position = Vector2(GAP, top)
	_left.size = Vector2(LEFT_W, 0)
	_left.custom_minimum_size.x = LEFT_W
	var center_x := LEFT_W + GAP * 2
	var center_w := size.x - center_x - GAP
	_card.custom_minimum_size = Vector2(minf(480.0, center_w), 0)
	_card.size = Vector2(minf(480.0, center_w), 0)
	_card.reset_size()
	_card.position = Vector2(center_x + (center_w - _card.size.x) * 0.5, top)
	_fall.position = Vector2.ZERO
	_fall.size = size
	_bottom.size = Vector2(center_w, 44)
	_bottom.position = Vector2(center_x, size.y - GAP - 44)
	var area_top := _card.position.y + _card.size.y + GAP
	var area := Rect2(center_x, area_top, center_w, _bottom.position.y - GAP - area_top)
	_area.position = Vector2.ZERO
	_area.size = size
	var phase := str(view.phase)
	var me := _me()
	var shown: Array = []
	if phase == "write" and me >= 0 and not _i_wrote():
		shown = [me]
	else:
		for seat: int in _books:
			shown.append(seat)
	for seat: int in _books:
		_books[seat].visible = shown.has(seat)
	var active := int(view.turn) if phase == "reveal" else -1
	var placement := _fit(shown, active, area)
	for seat: int in placement:
		var book: Control = _books[seat]
		var target: Array = placement[seat]
		if book.has_meta("placed"):
			var tween := book.create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tween.tween_property(book, "position", target[0], 0.25)
			tween.tween_property(book, "scale", target[1], 0.25)
		else:
			book.position = target[0]
			book.scale = target[1]
			book.set_meta("placed", true)

## Наибольший масштаб, при котором блокноты рядами влезают в область; активный — ×1,5.
func _fit(seats: Array, active: int, area: Rect2) -> Dictionary:
	var base: Vector2 = Notebook.SIZE
	var best := {}
	var low := 0.1
	var high := 1.0 if active < 0 or seats.size() == 1 else 1.0 / 1.5
	for _i: int in 18:
		var s := high if best.is_empty() and _i == 0 else (low + high) * 0.5
		var rows := _rows(seats, active, s, area.size.x)
		var height := 0.0
		for row: Array in rows:
			height += row[1]
		height += GAP * maxf(0.0, rows.size() - 1)
		if height <= area.size.y:
			best = {"s": s, "rows": rows, "h": height}
			low = s
			if _i == 0:
				break
		else:
			high = s
	if best.is_empty():
		best = {"s": low, "rows": _rows(seats, active, low, area.size.x), "h": area.size.y}
	var result := {}
	var y := area.position.y + (area.size.y - float(best.h)) * 0.5
	for row: Array in best.rows:
		var x := area.position.x + (area.size.x - float(row[2])) * 0.5
		for seat: int in row[0]:
			var k: float = float(best.s) * (1.5 if seat == active else 1.0)
			result[seat] = [Vector2(x, y + (float(row[1]) - base.y * k) * 0.5), Vector2.ONE * k]
			x += base.x * k + GAP
		y += float(row[1]) + GAP
	return result

## Ряды по ширине: [места, высота ряда, ширина ряда].
func _rows(seats: Array, active: int, s: float, width: float) -> Array:
	var base: Vector2 = Notebook.SIZE
	var rows := []
	var current := []
	var row_w := 0.0
	var row_h := 0.0
	for seat: int in seats:
		var k := s * (1.5 if seat == active else 1.0)
		var w := base.x * k
		if not current.is_empty() and row_w + GAP + w > width:
			rows.append([current, row_h, row_w])
			current = []
			row_w = 0.0
			row_h = 0.0
		row_w += (GAP if not current.is_empty() else 0.0) + w
		row_h = maxf(row_h, base.y * k)
		current.append(seat)
	if not current.is_empty():
		rows.append([current, row_h, row_w])
	return rows
