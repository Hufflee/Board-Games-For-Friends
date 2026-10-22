class_name K12Plate
extends PanelContainer
## Табличка игрока у края стола: аватар, имя, группа, жетоны-монеты, звёзды побед,
## сыгранные в раунде карты, статус, рубашки карт в руке.

var compact := false  # горизонтальная табличка для верхнего места


func _init(is_compact: bool = false) -> void:
	compact = is_compact
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true


func _draw() -> void:
	draw_style_box(K12UI.frame("small", Color(_border, 0.9)), Rect2(Vector2(2, 2), size - Vector2(4, 4)))


var _border := K12UI.GOLD


func set_data(d: Dictionary) -> void:
	var border: Color = d.get("border", Color("8a6b45"))
	_border = border if border != Color("8a6b45") else K12UI.GOLD_DARK
	queue_redraw()
	var sb := K12UI.box(Color(0.07, 0.05, 0.03, 0.86), 6)
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 6
	add_theme_stylebox_override("panel", sb)
	K12UI.clear(self)
	var col := K12UI.vbox(2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	modulate = Color(1, 1, 1, 0.45) if d.get("inactive", false) else Color.WHITE
	var head := K12UI.hbox(6)
	head.add_child(Avatar.make(d.get("avatar"), str(d["name"])))
	if d.get("crown", false):
		head.add_child(K12UI.label("♛", K12UI.BODY, K12UI.GOLD))
	var name_l: Control
	if d.has("players"):
		name_l = PlayerTag.make_seat(d["players"], d["seat"], d["my_seat"], 17, K12UI.GOLD if d.get("me", false) else K12UI.CREAM, "  (вы)" if d.get("me", false) else "")
	else:
		name_l = K12UI.label(d["name"], K12UI.BODY, K12UI.GOLD if d.get("me", false) else K12UI.CREAM)
	name_l.set("clip_text", true)
	name_l.set("text_overrun_behavior", TextServer.OVERRUN_TRIM_ELLIPSIS)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_l)
	var stars := K12UI.label("★".repeat(d["wins"]) + "☆".repeat(maxi(0, 2 - d["wins"])), K12UI.BODY, K12UI.GOLD)
	stars.tooltip_text = d.get("under_tip", "Победы в раундах")
	stars.mouse_filter = Control.MOUSE_FILTER_PASS
	if d.get("group", -1) >= 0:
		var g := K12UI.label("Гр.%d" % (d["group"] + 1), K12UI.CAP, Color.WHITE)
		g.add_theme_stylebox_override("normal", K12UI.box(GROUP_COLORS[d["group"] % GROUP_COLORS.size()], 6))
		head.add_child(g)
	head.add_child(stars)
	col.add_child(head)

	var row := K12UI.hbox(6)
	var coins := Coins.new()
	coins.tokens = d["tokens"]
	row.add_child(coins)
	var pts := K12UI.label("%d ПО" % d["points"], K12UI.CAP, K12UI.CREAM)
	row.add_child(pts)
	if d.get("hand", -1) >= 0:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		var backs := Backs.new()
		backs.count = d["hand"]
		row.add_child(backs)
	col.add_child(row)

	var played: Array = d.get("played", [])
	if not played.is_empty():
		var prow := K12UI.hbox(2)
		for c in played:
			var pic := TextureRect.new()
			pic.texture = K12UI.art(c)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.custom_minimum_size = Vector2(18, 18)
			pic.tooltip_text = "Сыграна в этом раунде: " + K12Cards.card_name(c)
			pic.mouse_filter = Control.MOUSE_FILTER_PASS
			prow.add_child(pic)
		col.add_child(prow)

	var st := K12UI.label(d.get("status", ""), K12UI.CAP, d.get("status_color", K12UI.MUTED))
	st.clip_text = true
	st.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(st)


const GROUP_COLORS := [Color("2a6fa8"), Color("8a3b3b"), Color("3b7a45"), Color("7a5a2a")]


## Аватар Steam или кружок с первой буквой имени.
class Avatar:
	extends Control
	var tex: Texture2D
	var letter := ""

	static func make(t, player_name: String) -> Avatar:
		var a := Avatar.new()
		a.tex = t
		a.letter = player_name.left(1).to_upper()
		a.custom_minimum_size = Vector2(26, 26)
		a.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return a

	func _draw() -> void:
		if tex:
			draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
			draw_rect(Rect2(Vector2.ZERO, size), Color("c9a35a"), false, 1.5)
			return
		var c := size / 2.0
		draw_circle(c, 13, Color("4a3423"))
		draw_arc(c, 13, 0, TAU, 32, Color("c9a35a"), 1.5, true)
		var font := ThemeDB.fallback_font
		var ts := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		draw_string(font, c + Vector2(-ts.x / 2, 5), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, K12UI.CREAM)


class Coins:
	extends Control
	var tokens: Array = []

	func _ready() -> void:
		custom_minimum_size = Vector2(maxi(1, tokens.size()) * 15 + 8, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if tokens.is_empty():
			draw_arc(Vector2(12, 12), 9, 0, TAU, 24, Color(1, 1, 1, 0.25), 1.5, true)
			return
		var font := ThemeDB.fallback_font
		for i in tokens.size():
			var c := Vector2(12 + i * 15, 12)
			var two: bool = tokens[i] == 2
			draw_circle(c + Vector2(1, 2), 10, Color(0, 0, 0, 0.4))
			draw_circle(c, 10, Color("e8c26a") if two else Color("c9cfd6"))
			draw_circle(c, 7.5, Color("c99a3a") if two else Color("9aa3ad"))
			var t := str(tokens[i])
			draw_string(font, c + Vector2(-4, 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("3a2a1c"))


class Backs:
	extends Control
	var count := 0

	func _ready() -> void:
		custom_minimum_size = Vector2(26 + maxi(0, count - 1) * 7, 26)
		mouse_filter = Control.MOUSE_FILTER_PASS
		tooltip_text = "Карт в руке: %d" % count

	func _draw() -> void:
		for i in count:
			K12TableCard.draw_back(self, Rect2(Vector2(i * 7, 0), Vector2(16, 26)))
