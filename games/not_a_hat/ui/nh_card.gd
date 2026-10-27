class_name NHCard
extends Control
## Карточка «Это не шляпа!»: лицом — белая с чёрным рисунком и подписью; рубашкой — розовая
## с белой стрелкой, куда её передавать (влево / вправо).

const Flip := preload("res://hub/card_flip.gd")
var _flip: Node
var _front_gift := -1

var gift := -1  # -1 — рубашкой вверх
var dir := 1  # -1 — стрелка влево, 1 — вправо
var glow := 0.0:  # подсветка (сейчас передаётся / вскрыта)
	set(v):
		glow = v
		queue_redraw()


func _init(g: int = -1, d: int = 1) -> void:
	gift = g
	_front_gift = g
	dir = d
	custom_minimum_size = NHStyle.CARD
	size = NHStyle.CARD
	mouse_filter = Control.MOUSE_FILTER_PASS
	pivot_offset = NHStyle.CARD * 0.5


func _ready() -> void:
	_flip = Flip.attach(self, _show_side, gift >= 0)


func set_card(g: int, d: int, animate: bool = false) -> void:
	if g >= 0:
		_front_gift = g
	dir = d
	if is_instance_valid(_flip):
		if animate:
			_flip.flip_to(g >= 0)
			if not _flip.busy:
				_show_side(_flip.face_up)
		else:
			_flip.set_face(g >= 0)
	else:
		gift = g
	tooltip_text = NHData.gift_name(g) if g >= 0 else ("Рубашка: передаётся " + ("влево" if d < 0 else "вправо"))
	queue_redraw()


func _show_side(up: bool) -> void:
	gift = _front_gift if up else -1
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if glow > 0.01:
		draw_style_box(NHStyle.box(Color(NHStyle.ACCENT, 0.8 * glow), 16, NHStyle.INK, 0, 0.0), r.grow(6))
	if gift >= 0:
		draw_style_box(NHStyle.box(NHStyle.PAPER, 12, NHStyle.INK, 3, 0.25), r)
		var tex := NHStyle.icon(gift)
		if tex:
			var s := minf(r.size.x - 22, r.size.y - 40)
			draw_texture_rect(tex, Rect2(Vector2((r.size.x - s) * 0.5, 10), Vector2(s, s)), false)
		var f := NHStyle.font("bold")
		var name := NHData.gift_name(gift)
		var fs := 13 if name.length() <= 11 else 11
		draw_string(f, Vector2(4, r.size.y - 10), name, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 8, fs, NHStyle.INK)
	else:
		draw_style_box(NHStyle.box(NHStyle.PINK, 12, NHStyle.INK, 3, 0.25), r)
		var inner := r.grow(-8)
		draw_style_box(NHStyle.box(Color.TRANSPARENT, 8, Color(1, 1, 1, 0.85), 2, 0.0), inner)
		# надпись и стрелка направления
		var f := NHStyle.font("bold")
		draw_string(f, Vector2(0, 34), "ЭТО НЕ", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, Color.WHITE)
		draw_string(f, Vector2(0, 50), "ШЛЯПА!", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, Color.WHITE)
		var c := Vector2(r.size.x * 0.5, r.size.y * 0.7)
		var w := 26.0 * dir
		draw_line(c - Vector2(w, 0), c + Vector2(w, 0), Color.WHITE, 5.0, true)
		draw_colored_polygon(PackedVector2Array([c + Vector2(w + 8 * dir, 0), c + Vector2(w - 6 * dir, -10), c + Vector2(w - 6 * dir, 10)]), Color.WHITE)
