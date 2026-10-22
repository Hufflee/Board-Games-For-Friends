class_name TTAnswerFace
extends Control
## Лицо карты-ответа: белый «пузырь» с хвостиком, кружок цвета автора, имя, текст ответа
## и плашка номера (пока не выложен — «?»).

const SIZE := Vector2(190, 118)

var author := ""
var author_color := Color.WHITE
var text := ""
var number := -1  # -1 — номер скрыт
var called := -1  # эксперт: номер, который назвал капитан (пока настоящий скрыт)
var selected := false:  # эксперт: капитан выбрал карту, чтобы назвать ей номер
	set(v):
		selected = v
		queue_redraw()
var pop := 0.0:  # 0…1 — вспышка при открытии номера
	set(v):
		pop = v
		queue_redraw()


func _init(who: String = "", col: Color = Color.WHITE, answer_text: String = "", n: int = -1) -> void:
	author = who
	author_color = col
	text = answer_text
	number = n
	size = SIZE
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := Rect2(Vector2(2, 2), size - Vector2(6, 18))
	# тень и хвостик пузыря
	var tail := PackedVector2Array([r.position + Vector2(26, r.size.y - 2), r.position + Vector2(18, r.size.y + 14), r.position + Vector2(48, r.size.y - 2)])
	draw_colored_polygon(tail + PackedVector2Array([]), TTStyle.INK)
	var sb := TTStyle.box(TTStyle.WHITE, 14, TTStyle.accent() if selected else TTStyle.INK, 5 if selected else 3, 0.35)
	draw_style_box(sb, r)
	var inner := PackedVector2Array([r.position + Vector2(28, r.size.y - 4), r.position + Vector2(22, r.size.y + 8), r.position + Vector2(44, r.size.y - 4)])
	draw_colored_polygon(inner, TTStyle.WHITE)
	# автор
	draw_circle(r.position + Vector2(16, 16), 7, TTStyle.INK)
	draw_circle(r.position + Vector2(16, 16), 5.5, author_color)
	draw_string(TTStyle.font("bold"), r.position + Vector2(28, 21), author, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 70, 12, Color(TTStyle.INK, 0.65))
	# текст ответа
	var fs := 15 if text.length() < 40 else 12
	draw_multiline_string(TTStyle.font("bold"), r.position + Vector2(10, 42), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 20, fs, 4, TTStyle.INK)
	# номер
	var badge := Rect2(Vector2(r.end.x - 40, r.position.y - 6), Vector2(40, 34)).grow(pop * 6.0)
	var bc := TTStyle.bg() if number < 0 else TTStyle.lo_color().lerp(TTStyle.hi_color(), (number - 1) / 9.0)
	draw_style_box(TTStyle.box(bc, 9, TTStyle.INK, 3, 0.0), badge)
	draw_string(TTStyle.font("title"), badge.position + Vector2(0, badge.size.y * 0.72), "?" if number < 0 else str(number), HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 18 + int(pop * 6), TTStyle.WHITE)
	# эксперт: названный капитаном номер — жёлтым кружком слева от плашки
	if called > 0:
		var c := Vector2(badge.position.x - 16, badge.get_center().y)
		draw_circle(c, 14, TTStyle.INK)
		draw_circle(c, 12, TTStyle.YELLOW)
		draw_string(TTStyle.font("title"), c + Vector2(-12, 6), str(called), HORIZONTAL_ALIGNMENT_CENTER, 24, 14, TTStyle.INK)
