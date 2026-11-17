## Склонение числительных и показ полного текста обрезанных подписей.
class_name UIText
extends RefCounted


static func full_on_hover(control: Control) -> void:
	if not (control is Label or control is Button) or control.has_node("FullTextOnHover"):
		return
	var watcher := FullTextOnHover.new()
	watcher.name = "FullTextOnHover"
	control.add_child(watcher)


## Информационная кнопка сохраняет обычный вид и перестаёт принимать нажатия.
static func display_only(button: Button) -> void:
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_ARROW
	var normal := button.get_theme_stylebox("normal")
	for state: String in ["hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, normal)


## Включает табличные цифры, если шрифт их поддерживает. Иначе резервирует ширину строки.
static func stable_numbers(label: Label, sample: String) -> void:
	var base := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	var variation: FontVariation
	if base is FontVariation:
		variation = base.duplicate() as FontVariation
	else:
		variation = FontVariation.new()
		variation.base_font = base
	var features := variation.opentype_features.duplicate()
	features["tnum"] = 1
	variation.opentype_features = features
	var one := variation.get_string_size("1111", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var zero := variation.get_string_size("0000", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if is_equal_approx(one, zero):
		label.add_theme_font_override("font", variation)
	var font := label.get_theme_font("font")
	var width := 0.0
	for digit in "0123456789":
		var candidate := ""
		for character in sample:
			candidate += digit if character == "0" else character
		width = maxf(width, font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	label.custom_minimum_size.x = maxf(label.custom_minimum_size.x, ceilf(width))


static func plural(n: int, one: String, few: String, many: String, with_number := true) -> String:
	var last := absi(n % 10)
	var ending := absi(n % 100)
	var word := many
	if last == 1 and ending != 11:
		word = one
	elif last in [2, 3, 4] and ending not in [12, 13, 14]:
		word = few
	return "%d %s" % [n, word] if with_number else word


class FullTextOnHover extends Node:
	var _control: Control
	var _previous_text := ""
	var _base_tooltip := ""
	var _last_tooltip := ""
	var _tooltip_target: Control


	func _ready() -> void:
		_control = get_parent() as Control
		_base_tooltip = _control.tooltip_text
		_last_tooltip = _base_tooltip
		_tooltip_target = _control
		if _control is Button and _control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			_tooltip_target = Control.new()
			_tooltip_target.mouse_filter = Control.MOUSE_FILTER_PASS
			_tooltip_target.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_control.add_child.call_deferred(_tooltip_target)
		_control.resized.connect(_update)
		_control.theme_changed.connect(_update)
		_control.visibility_changed.connect(_visibility_changed)
		if _control is Label and _control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			_control.mouse_filter = Control.MOUSE_FILTER_PASS
		_visibility_changed()


	func _visibility_changed() -> void:
		set_process(_control.is_visible_in_tree())
		if is_processing():
			_update()


	func _process(_delta: float) -> void:
		if _control.get("text") != _previous_text:
			_update()


	func _update() -> void:
		_previous_text = _control.get("text")
		if _control.tooltip_text != _last_tooltip:
			_base_tooltip = _control.tooltip_text
		if _control is Label and (_control as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
			var label := _control as Label
			_set_tooltip(label.get_line_count() > label.get_visible_line_count())
			return
		var available := _control.size.x
		if _control is Button:
			available -= _control.get_theme_stylebox("normal").get_minimum_size().x
			var button := _control as Button
			if button.icon != null:
				var icon_width := float(button.icon.get_width())
				var limit := button.get_theme_constant("icon_max_width")
				available -= minf(icon_width, limit) if limit > 0 else icon_width
				available -= button.get_theme_constant("h_separation")
		var font := _control.get_theme_font("font")
		var font_size := _control.get_theme_font_size("font_size")
		for line in _previous_text.split("\n"):
			if font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available:
				_set_tooltip(true)
				return
		_set_tooltip(false)


	func _set_tooltip(clipped: bool) -> void:
		_last_tooltip = _previous_text if clipped else _base_tooltip
		if clipped and not _base_tooltip.is_empty() and not _base_tooltip.contains(_previous_text):
			_last_tooltip += "\n" + _base_tooltip
		_control.tooltip_text = _last_tooltip
		_tooltip_target.tooltip_text = _last_tooltip
