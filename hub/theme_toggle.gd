class_name ThemeToggle
extends Button
## Кнопка темы рядом с «Правила» / «Настройки» в светлых играх: солнце — светлая тема, луна — тёмная.
## Нажатие переключает Prefs.theme_mode; игра сама пересобирает экран в новой палитре (Prefs.changed).

var _hover := false


## Кнопка в стиле игры: make_button — как у игры (HCStyle.button и т. п.), текст не нужен.
static func make(make_button: Callable, size: int) -> ThemeToggle:
	var proto: Button = make_button.call(" ", size)
	var t := ThemeToggle.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		if proto.has_theme_stylebox_override(st):
			t.add_theme_stylebox_override(st, proto.get_theme_stylebox(st))
	t.theme_type_variation = proto.theme_type_variation
	var side := maxf(proto.get_combined_minimum_size().y, 34)
	t.custom_minimum_size = Vector2(side, side)
	t.size_flags_horizontal = Control.SIZE_SHRINK_END  # квадратная коробочка со значком — не растягивается в столбике кнопок
	proto.free()
	return t


func _ready() -> void:
	text = ""
	tooltip_text = "Тёмная тема" if not Prefs.dark_theme() else "Светлая тема"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())
	pressed.connect(func():
		Sfx.play("click", -6)
		Prefs.set_value("theme_mode", "light" if Prefs.dark_theme() else "dark"))


func _draw() -> void:
	var col := get_theme_color("font_hover_color" if _hover else "font_color", "Button")
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.2
	if Prefs.dark_theme():
		# луна: круг, из которого «вырезан» круг цветом фона кнопки
		draw_circle(c, r * 1.15, col)
		var bg := get_theme_stylebox("normal", "Button")
		var bgc: Color = (bg as StyleBoxFlat).bg_color if bg is StyleBoxFlat else Color(0, 0, 0)
		draw_circle(c + Vector2(r * 0.55, -r * 0.4), r * 0.95, Color(bgc, 1.0))
	else:
		# солнце: круг и восемь лучей
		draw_circle(c, r * 0.75, col)
		for i in 8:
			var a := TAU * i / 8.0
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * r * 1.15, c + d * r * 1.7, col, maxf(1.5, r * 0.22), true)
