class_name RSBVipFace
extends Control
## Лицо VIP-карты: кремовая карточка с полосатой рамкой, заголовок, рисунок и текст эффекта.

const SIZE := Vector2(150, 214)

var card := -1


func _init(card_index: int = -1) -> void:
	card = card_index
	size = SIZE
	custom_minimum_size = SIZE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var v: Dictionary = RSBData.VIP[card]
	var tint := _tint(v)
	draw_style_box(RSBStyle.box(Color("fbf3dd"), 10, RSBStyle.INK_ART, 2, Color(0, 0, 0, 0.35), 6), r)
	# полосатая рамка как на билетах
	var inner := r.grow(-7)
	var stripes := StyleBoxFlat.new()
	stripes.draw_center = false
	stripes.border_color = tint
	stripes.set_border_width_all(3)
	stripes.set_corner_radius_all(6)
	draw_style_box(stripes, inner)
	var head := Rect2(inner.position + Vector2(3, 3), Vector2(inner.size.x - 6, 22))
	draw_rect(head, tint)
	draw_string(RSBStyle.font("title"), head.position + Vector2(0, 16), "V I P", HORIZONTAL_ALIGNMENT_CENTER, head.size.x, 14, Color.WHITE)
	var tw := inner.size.x - 12
	var tfont := RSBStyle.font("title")
	var tfs := fit_size(tfont, RSBData.vip_title(v), tw, 36.0, 14, 9)
	draw_multiline_string(tfont, Vector2(inner.position.x + 6, head.end.y + 4 + tfs), RSBData.vip_title(v), HORIZONTAL_ALIGNMENT_CENTER, tw, tfs, 2, RSBStyle.INK_ART)
	# рисунок
	var pic_c := Vector2(r.size.x * 0.5, 98)
	match v["kind"]:
		"bonus":
			var t: Texture2D = RSBStyle.tex("bonus_%s_%d" % [v["color"], v["value"]])
			draw_texture_rect(t, Rect2(pic_c - Vector2(26, 26), Vector2(52, 52)), false)
		"piggy":
			draw_texture_rect(RSBStyle.tex("token_gray_%d" % clampi(v["value"], 2, 5)), Rect2(pic_c - Vector2(30, 22), Vector2(40, 40)), false)
			draw_texture_rect(RSBStyle.tex("token_pink_%d" % clampi(v["value"], 2, 5)), Rect2(pic_c - Vector2(8, 30), Vector2(40, 40)), false)
		"snake":
			draw_texture_rect(RSBStyle.tex("dice"), Rect2(pic_c - Vector2(30, 22), Vector2(60, 44)), false)
		"comp", "risky", "highroller", "comeback", "early", "insure", "late":
			var chip: String = {"comp": "chip_25", "risky": "chip_5", "highroller": "chip_100", "comeback": "chip_1", "early": "chip_5", "insure": "chip_25", "late": "chip_1"}[v["kind"]]
			draw_texture_rect(RSBStyle.tex(chip), Rect2(pic_c - Vector2(24, 24), Vector2(48, 48)), false)
		"fan":
			var h: int = {"blue": 7, "orange": 6, "red": 3}[v["color"]]
			var t: Texture2D = RSBStyle.tex("horse_%d" % h)
			draw_texture_rect(t, Rect2(pic_c - Vector2(34, 24), Vector2(68, 48)), false)
	# текст эффекта — подбираем размер, чтобы влез в низ карты
	var body := RSBData.vip_text(v)
	var bfont := RSBStyle.font("regular")
	var top := 136.0
	var bfs := fit_size(bfont, body, tw, inner.end.y - 4 - top, 11, 6)
	draw_multiline_string(bfont, Vector2(inner.position.x + 6, top + bfs), body, HORIZONTAL_ALIGNMENT_CENTER, tw, bfs, -1, RSBStyle.INK_ART)


## Самый крупный размер шрифта (от big до small), при котором текст в ширину width влезает в высоту max_h.
static func fit_size(font: Font, text: String, width: float, max_h: float, big: int, small: int) -> int:
	for fs in range(big, small - 1, -1):
		if font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, width, fs).y <= max_h:
			return fs
	return small


static func _tint(v: Dictionary) -> Color:
	match v["kind"]:
		"bonus":
			return Color("2b2b2b") if v["color"] == "black" else Color("8a8a8a")
		"piggy":
			return Color("3a7d44")
		"comp", "highroller":
			return Color("b8892c")
		"fan":
			return RSBStyle.HORSE_COLORS[v["color"]].darkened(0.15)
	return RSBStyle.RED


## Рубашка VIP-карты для общей карты-контрола (K12TableCard.back_drawer).
static func draw_back(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_style_box(RSBStyle.box(RSBStyle.FELT, 10, RSBStyle.GOLD, 3, Color(0, 0, 0, 0.35), 6), r)
	ci.draw_texture_rect(RSBStyle.tex("vip_back"), r.grow(-10), false)
