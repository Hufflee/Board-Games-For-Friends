extends Control
## Плавающая лента публичных действий. Источник слева, фактический результат справа.

const LIMIT := 12
const STEP := 34.0
const CHIP := Vector2(30, 30)
const TITLES := {
	"attack": "Атака", "player_attack": "Атака игрока", "purchase": "Покупка",
	"item": "Активация предмета", "trigger": "Срабатывание способности",
	"loot": "Розыгрыш добычи", "character_loot": "Активация персонажа",
	"roll": "Бросок кубика", "effect_roll": "Бросок по эффекту",
	"event": "Событие", "room": "Новая комната", "reward": "Награда",
	"death": "Смерть", "discard": "Сброс", "trade": "Передача монет",
	"draw": "Добор", "coins": "Монеты", "gain_item": "Получение предмета",
	"damage": "Урон", "heal": "Лечение", "soul": "Получение души", "shield": "Защита",
}
const ICONS := {
	"attack": '<path d="m5 19 4-4m-4 0 4 4m-1-5L18 4l2 0v3L10 17"/>',
	"purchase": '<path d="M4 9h16l-2 10H6L4 9Zm4 0 4-5 4 5m-6 4v2m4-2v2"/>',
	"card": '<rect x="6" y="3" width="12" height="18" rx="2"/><path d="m12 8 3 4-3 4-3-4 3-4Z"/>',
	"item": '<path d="m12 3 2 6 6 3-6 2-2 7-2-7-6-2 6-3 2-6Z"/>',
	"roll": '<rect x="4" y="4" width="16" height="16" rx="3"/><path d="M8 8h.1m4 4h.1m4 4h.1"/>',
	"event": '<path d="M12 3 3 20h18L12 3Zm0 6v5m0 3h.1"/>',
	"death": '<path d="M5 11a7 7 0 0 1 14 0c0 2-1 3-3 4v4H8v-4c-2-1-3-2-3-4Zm4 0h.1m6 0h.1m-3 6v2"/>',
	"draw": '<path d="M6 4h12v16H6V4Zm3 8h6m-3-3v6"/>',
	"discard": '<path d="M5 7h14M8 7V4h8v3M7 7l1 13h8l1-13m-7 3v7m4-7v7"/>',
	"coins": '<circle cx="12" cy="12" r="8"/><path d="M15 8h-3a4 4 0 0 0 0 8h3m-2-10v12"/>',
	"soul": '<path d="M5 11a7 7 0 0 1 14 0v9l-3-2-4 2-4-2-3 2v-9Zm4 0h.1m6 0h.1"/>',
	"heal": '<path d="M12 20 4 12a5 5 0 0 1 8-6 5 5 0 0 1 8 6l-8 8Z"/>',
}
static var _icon_cache: Dictionary = {}
var _rail: Control
var _cards: Dictionary = {}
var _entries: Dictionary = {}
var _order: Array = []
var _popup: PanelContainer
var _hovered := -1


func _ready() -> void:
	name = "ActionFeed"
	custom_minimum_size = Vector2(130, 36)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail = Control.new()
	_rail.clip_contents = true
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rail)
	_rail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_arrange)


func sync(history: Array) -> void:
	var next := {}
	_order = []
	for entry: Dictionary in history.slice(maxi(0, history.size() - LIMIT)):
		var seq := int(entry.seq)
		_order.append(seq)
		next[seq] = entry
	var refresh_popup: bool = next.get(_hovered) != _entries.get(_hovered)
	_entries = next
	for key in _cards.keys():
		if not _entries.has(key):
			var old: Button = _cards[key]
			old.queue_free()
			_cards.erase(key)
	for seq: int in _order:
		if not _cards.has(seq):
			_add_chip(seq)
	_arrange()
	if not _entries.has(_hovered):
		close_popup()
	elif refresh_popup:
		show_entry(_hovered)


func _add_chip(seq: int) -> void:
	var button := Button.new()
	button.icon = _icon(str(_entries[seq].kind))
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_HELP
	for state in ["normal", "hover", "pressed"]:
		var tint := FSStyle.COAL.darkened(0.1) if state == "normal" else FSStyle.COAL.lerp(FSStyle.GOLD, 0.25)
		var panel := FSStyle.box(Color(tint, 0.92), Color(FSStyle.PAPER, 0.21))
		panel.set_content_margin_all(6)
		button.add_theme_stylebox_override(state, panel)
	button.size = CHIP
	button.position = Vector2(_rail.size.x, 3)
	_rail.add_child(button)
	_cards[seq] = button
	button.mouse_entered.connect(func(): show_entry(seq))
	button.mouse_exited.connect(func():
		if _hovered == seq:
			close_popup())


func _arrange() -> void:
	if not is_instance_valid(_rail) or not is_inside_tree() or size.x <= 1.0:
		return
	for index in _order.size():
		var chip: Button = _cards[_order[index]]
		var x := size.x - CHIP.x - STEP * (_order.size() - 1 - index)
		if is_equal_approx(float(chip.get_meta("target_x", -999.0)), x):
			continue
		chip.set_meta("target_x", x)
		var tween: Tween = chip.get_meta("move") if chip.has_meta("move") else null
		if tween != null and tween.is_valid():
			tween.kill()
		tween = chip.create_tween()
		tween.tween_property(chip, "position:x", x, 0.17).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		chip.set_meta("move", tween)


func show_entry(seq: int) -> void:
	if not _entries.has(seq) or Net.paused:
		return
	close_popup()
	_hovered = seq
	var entry: Dictionary = _entries[seq]
	var card := int(entry.card)
	var results: Array = entry.results
	var author: Dictionary = entry.author
	var panel := FSStyle.panel()
	panel.name = "ActionDetail"
	panel.z_index = 69
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_popup = panel
	var col := FSStyle.vbox(8)
	panel.add_child(col)
	var title := FSStyle.label(str(TITLES.get(entry.kind, "Действие")), FSStyle.BODY, true)
	col.add_child(title)
	var row := FSStyle.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var source := FSStyle.vbox(4)
	row.add_child(source)
	if not author.is_empty():
		var nick := FSStyle.label(str(author.name), FSStyle.CAP)
		nick.custom_minimum_size.x = 100
		nick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		source.add_child(nick)
		_art(source, int(author.char), Vector2(28, 39))
	if card >= 0:
		_art(source, card, Vector2(112, 154))
	if not results.is_empty():
		var effects := FSStyle.vbox(4)
		row.add_child(effects)
		for result: Dictionary in results.slice(0, 4):
			var line := FSStyle.hbox(8)
			effects.add_child(line)
			var target: Dictionary = result.get("target", {})
			var result_card := int(result.get("card", -1))
			var portrait := int(target.get("char", -1))
			if result_card >= 0 and result_card != card:
				_art(line, result_card, Vector2(90, 118) if results.size() == 1 else Vector2(42, 57))
			elif portrait >= 0 and str(target.get("name", "")) != str(author.get("name", "")):
				_art(line, portrait, Vector2(42, 57))
			var result_label := FSStyle.label(_result_text(result), FSStyle.CAP)
			result_label.custom_minimum_size.x = 142
			result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.add_child(result_label)
		if results.size() > 4:
			effects.add_child(FSStyle.label("Ещё результатов: %d · см. журнал" % (results.size() - 4), FSStyle.CAP))
	_ignore_mouse(panel)
	_position_popup.call_deferred(panel, seq)


func close_popup() -> void:
	_hovered = -1
	if is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null


func _position_popup(panel: PanelContainer, seq: int) -> void:
	if not is_instance_valid(panel) or panel != _popup or not _cards.has(seq):
		return
	panel.reset_size()
	var chip: Control = _cards[seq]
	var viewport := get_viewport_rect().size
	var right := viewport.x - global_position.x - panel.size.x - 16.0
	var left := 16.0 - global_position.x
	panel.position = Vector2(clampf(chip.position.x + CHIP.x * 0.5 - panel.size.x * 0.5, left, maxf(left, right)),
		maxf(12.0 - global_position.y, -panel.size.y - 6.0))


func _art(parent: Control, id: int, dimensions: Vector2) -> void:
	if id < 0:
		return
	var picture := TextureRect.new()
	picture.texture = FSData.texture(id)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = dimensions
	picture.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(picture)


func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Control in control.get_children():
		_ignore_mouse(child)


func _result_text(result: Dictionary) -> String:
	var amount := int(result.get("amount", 0))
	var card := int(result.get("card", -1))
	var target: Dictionary = result.get("target", {})
	var text: String = {
		"aim": "Цель атаки", "blind_monster": "Верх колоды монстров",
		"price": "Цена: %d¢" % amount, "die": "Выпало: %d" % amount,
		"draw": "Добыча: +%d" % amount, "coins": "%+d¢" % amount,
		"damage": "Урон: %d" % amount, "heal": "Здоровье: +%d" % amount,
		"gain_item": "Получен предмет", "soul": "Души: +%d" % amount,
		"shield": "Щит: +%d" % amount, "cancelled": "Эффект отменён",
	}.get(result.kind, "")
	if card >= 0:
		text += "\n" + FSData.title(card)
	if not target.is_empty():
		text += "\n" + str(target.name)
	return text


func _icon(kind: String) -> Texture2D:
	var key: String = {
		"player_attack": "attack", "effect_roll": "roll", "trigger": "item",
		"character_loot": "item", "loot": "card", "room": "event", "reward": "soul",
		"trade": "coins", "gain_item": "purchase", "damage": "attack",
	}.get(kind, kind)
	if not _icon_cache.has(key):
		var ink := "#d97d68" if key in ["attack", "death", "event"] else "#e4c99b"
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24"><g fill="none" stroke="%s" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % [ink, ICONS.get(key, ICONS.card)]
		var image := Image.new()
		image.load_svg_from_string(svg)
		_icon_cache[key] = ImageTexture.create_from_image(image)
	return _icon_cache[key]
