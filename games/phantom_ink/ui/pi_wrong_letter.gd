extends RefCounted
## Зачёркивание последней неверной буквы по её реальной ширине, без комбинируемого символа.

static func wire(button: Button, letter_index: int) -> void:
	button.draw.connect(func(): _paint(button, letter_index))


static func _paint(button: Button, letter_index: int) -> void:
	if letter_index < 0 or letter_index >= button.text.length():
		return
	var font := button.get_theme_font("font")
	var font_size := button.get_theme_font_size("font_size")
	var style := button.get_theme_stylebox("disabled" if button.disabled else "normal")
	var left := style.get_content_margin(SIDE_LEFT)
	var prefix_width := font.get_string_size(button.text.left(letter_index), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var glyph_width := font.get_string_size(button.text.substr(letter_index, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := left + prefix_width - 1.0
	var right := minf(button.size.x - style.get_content_margin(SIDE_RIGHT), x + glyph_width + 3.0)
	if right > x:
		var color := button.get_theme_color("font_disabled_color" if button.disabled else "font_color")
		button.draw_line(Vector2(x, button.size.y * 0.5), Vector2(right, button.size.y * 0.5), color, 2.5, true)
