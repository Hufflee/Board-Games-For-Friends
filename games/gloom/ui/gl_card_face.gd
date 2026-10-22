class_name GLCardFace
extends Control
## Лицо карты в руке: прозрачная карта на «стекле» (светло-серая подложка), чтобы её было видно на
## тёмном столе. card < 0 — рубашка. Механика руки — общая (K12TableCard).

const SIZE := Vector2(112, 161)

var card := -1
var marked := false:  # выбрана для сброса / передачи
	set(v):
		marked = v
		queue_redraw()


func _init(c: int = -1) -> void:
	card = c
	size = SIZE
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if card < 0:
		draw_texture_rect(GLStyle.tex("back"), r, false)
		return
	var glass := StyleBoxFlat.new()
	glass.bg_color = Color(0.81, 0.79, 0.82, 0.14)  # почти прозрачное «стекло» под прозрачной картой
	glass.set_corner_radius_all(6)
	glass.shadow_color = Color(0, 0, 0, 0.4)
	glass.shadow_size = 6
	glass.shadow_offset = Vector2(0, 3)
	draw_style_box(glass, r)
	draw_texture_rect(GLStyle.card_tex(card), r, false)
	if marked:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(GLStyle.BLOOD, 0.22)
		sb.border_color = GLStyle.BLOOD_LIGHT
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(6)
		draw_style_box(sb, r)
