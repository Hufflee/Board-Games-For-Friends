extends Control
## Гримуар рассказчика (и снимок Шпиона) в виде старой записной книги: разворот на кожаном переплёте,
## записи рукописным шрифтом, иконки ролей «чернилами», кляксы и наброски на полях.
## Ассеты — tools/bc_grimoire_art.py. Таблица мест — слева, «Эта ночь» и журнал действий — справа.
const Data := preload("res://games/blood_on_the_clocktower/logic/bc_data.gd")
const Art := preload("res://games/blood_on_the_clocktower/ui/bc_art.gd")
const Status := preload("res://games/blood_on_the_clocktower/ui/bc_status.gd")
const DIR := "res://games/blood_on_the_clocktower/art/"
const BOOK_SIZE := Vector2(1600, 1000)
const INK := Color("2b1b12")
const INK_FADED := Color(0.17, 0.11, 0.07, 0.62)
const INK_RED := Color("7a1a1a")
const INK_BLUE := Color("1f3550")

signal closed

var book: TextureRect
var left_page: Control
var right_page: Control
var title: Label
var subtitle: Label
var entries_box: GridContainer
var notes: RichTextLabel
var _entries_key := ""
static var _hand: FontFile

## Рукописный шрифт (Marck Script, OFL): из импорта, а без него — прямо из файла.
static func hand_font() -> Font:
	if _hand == null:
		var path := DIR + "fonts/MarckScript-Regular.ttf"
		var loaded: Variant = load(path) if ResourceLoader.exists(path) else null
		if loaded is FontFile:
			_hand = loaded
		else:
			_hand = FontFile.new()
			_hand.load_dynamic_font(path)
	return _hand

static func _ink_label(text: String, size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", hand_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	return label

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.66)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_close())
	add_child(dim)
	book = TextureRect.new()
	book.name = "Book"
	book.texture = Art.texture(DIR + "grimoire/book.png")
	book.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	book.stretch_mode = TextureRect.STRETCH_SCALE
	book.mouse_filter = MOUSE_FILTER_STOP
	add_child(book)
	# Кляксы и наброски — под текстом, бледно, как на настоящих страницах.
	_sketch("grimoire/clock.png", Vector2(0.745, 0.60), 0.20, 0.38, -0.12)
	_sketch("grimoire/moon.png", Vector2(0.075, 0.80), 0.10, 0.45, 0.2)
	_sketch("grimoire/blot_3.png", Vector2(0.885, 0.86), 0.06, 0.75, 1.9)
	left_page = Control.new()
	left_page.name = "LeftPage"
	book.add_child(left_page)
	right_page = Control.new()
	right_page.name = "RightPage"
	book.add_child(right_page)
	var left := VBoxContainer.new()
	left.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	left.add_theme_constant_override("separation", 4)
	left_page.add_child(left)
	title = _ink_label("Гримуар", 40)
	left.add_child(title)
	subtitle = _ink_label("", 20, INK_FADED)
	left.add_child(subtitle)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	entries_box = GridContainer.new()
	entries_box.name = "Entries"
	entries_box.columns = 2
	entries_box.size_flags_horizontal = SIZE_EXPAND_FILL
	entries_box.add_theme_constant_override("h_separation", 16)
	entries_box.add_theme_constant_override("v_separation", 6)
	scroll.add_child(entries_box)
	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	right.add_theme_constant_override("separation", 4)
	right_page.add_child(right)
	var head := HBoxContainer.new()
	right.add_child(head)
	var records := _ink_label("Альманах", 34)
	records.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(records)
	var close := Button.new()
	close.name = "CloseGrimoire"
	close.text = "закрыть ✕"
	close.flat = true
	close.add_theme_font_override("font", hand_font())
	close.add_theme_font_size_override("font_size", 22)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		close.add_theme_color_override(state, INK_RED if state != "font_color" else INK)
	close.pressed.connect(_close)
	head.add_child(close)
	notes = RichTextLabel.new()
	notes.name = "GrimoireNotes"
	notes.bbcode_enabled = false
	notes.scroll_following = true
	notes.size_flags_vertical = SIZE_EXPAND_FILL
	notes.add_theme_font_override("normal_font", hand_font())
	notes.add_theme_font_size_override("normal_font_size", 19)
	notes.add_theme_color_override("default_color", INK)
	notes.add_theme_constant_override("line_separation", -2)
	right.add_child(notes)
	# Подписи пером на полях.
	_margin_note("не верь никому…", Vector2(0.60, 0.885), -0.06, 20)
	_margin_note("Равенсвуд-Блафф", Vector2(0.30, 0.055), 0.0, 18)
	resized.connect(_layout)
	_layout()

func _sketch(path: String, at: Vector2, width: float, alpha: float, angle: float) -> void:
	var image := TextureRect.new()
	image.texture = Art.texture(DIR + path)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.modulate.a = alpha
	image.mouse_filter = MOUSE_FILTER_IGNORE
	image.set_meta("at", at)
	image.set_meta("width", width)
	image.rotation = angle
	image.add_to_group("grimoire_sketch")
	book.add_child(image)

func _margin_note(text: String, at: Vector2, angle: float, size: int) -> void:
	var note := _ink_label(text, size, INK_FADED)
	note.rotation = angle
	note.set_meta("at", at)
	note.add_to_group("grimoire_sketch")
	book.add_child(note)

## Книга вписывается в окно с полями; страницы — доли разворота, текст масштабируется вместе с книгой.
func _layout() -> void:
	if book == null: return
	var room := size - Vector2(48, 48)
	var scale := minf(room.x / BOOK_SIZE.x, room.y / BOOK_SIZE.y)
	var shown := BOOK_SIZE * scale
	book.position = (size - shown) / 2
	book.size = shown
	left_page.position = shown * Vector2(0.065, 0.075)
	left_page.size = shown * Vector2(0.405, 0.85)
	right_page.position = shown * Vector2(0.535, 0.075)
	right_page.size = shown * Vector2(0.40, 0.85)
	for node: Node in get_tree().get_nodes_in_group("grimoire_sketch") if is_inside_tree() else []:
		if not book.is_ancestor_of(node): continue
		var item := node as Control
		var at: Vector2 = item.get_meta("at")
		if item is TextureRect:
			var side: float = shown.x * float(item.get_meta("width"))
			item.size = Vector2(side, side)
			item.pivot_offset = item.size / 2
			item.position = shown * at - item.size / 2
		else:
			item.position = shown * at

func _close() -> void:
	hide()
	closed.emit()

## Записи о местах: иконка чернилами, ник и роль (зло — красными чернилами), погибшие зачёркнуты.
func set_entries(entries: Array, players: Array, day: int, night: bool) -> void:
	subtitle.text = ("Ночь %d" if night else "День %d") % maxi(day, 1 if night else 0)
	var key := var_to_str(entries)
	if key == _entries_key: return
	_entries_key = key
	for child: Node in entries_box.get_children():
		entries_box.remove_child(child)
		child.queue_free()
	for item: Dictionary in entries:
		entries_box.add_child(_entry(item, players))

func _entry(item: Dictionary, players: Array) -> Control:
	var row := HBoxContainer.new()
	row.name = "Seat_%d" % int(item.seat)
	row.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	var role := str(item.role)
	var icon := TextureRect.new()
	icon.texture = Art.texture(DIR + "roles_ink/%s.png" % role)
	icon.custom_minimum_size = Vector2(46, 46)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	var alive := bool(item.get("alive", true))
	if not alive: icon.modulate.a = 0.4
	row.add_child(icon)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	text.mouse_filter = MOUSE_FILTER_IGNORE
	text.add_theme_font_override("normal_font", hand_font())
	text.add_theme_font_size_override("normal_font_size", 18)
	text.add_theme_constant_override("line_separation", -4)
	text.add_theme_color_override("default_color", INK)
	var seat := int(item.seat)
	var nick := str(players[seat].name) if seat >= 0 and seat < players.size() else "?"
	var role_name := str(Data.catalog().get(role, {}).get("name", role))
	var shown := str(item.get("shown_role", role))
	var evil := str(item.get("side", "")) == "evil"
	var color := (INK_RED if evil else INK_BLUE).to_html(false)
	var line := "%s — [color=#%s]%s[/color]" % [_escape(nick), color, role_name]
	if shown != role:
		line += " [color=#%s](думает: %s)[/color]" % [INK_FADED.to_html(false), str(Data.catalog().get(shown, {}).get("name", shown))]
	if not alive:
		line = "[s]%s[/s] ✝" % line
	var marks: Array[String] = []
	if not bool(item.get("healthy", true)): marks.append("способность нарушена")
	var described := Status.describe(item.get("status", {}), players)
	if not described.is_empty(): marks.append(described.replace("\n", "; "))
	if not marks.is_empty():
		line += "\n[font_size=15][color=#%s]%s[/color][/font_size]" % [INK_FADED.to_html(false), _escape(", ".join(marks))]
	text.text = line
	text.tooltip_text = "%s — %s%s" % [nick, role_name, ("\n" + ", ".join(marks)) if not marks.is_empty() else ""]
	row.add_child(text)
	return row

static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
