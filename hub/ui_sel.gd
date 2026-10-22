class_name UISel
## Выбранный вариант в ряду кнопок-переключателей (режим, время хода, скорость…):
## по гайдам UI выбранное выделяется заливкой акцентом, а не выглядит «неактивным».
## Стиль задаёт тема каждой игры — вариация «SelectedButton».


static func pick(b: Button, on: bool) -> void:
	b.disabled = on
	b.theme_type_variation = "SelectedButton" if on else ""
	b.mouse_default_cursor_shape = Control.CURSOR_ARROW if on else Control.CURSOR_POINTING_HAND
