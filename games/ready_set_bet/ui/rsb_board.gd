class_name RSBBoard
extends Control
## Поле ставок на зелёном сукне: пари (5 карт), ставки на цвет, сетка В ТРОЙКЕ / В ДВОЙКЕ / ПОБЕДА
## на 9 лошадей и экзотические финиши. Жетоны на ячейках, подсветка допустимых ячеек при перетаскивании.

signal spot_clicked(spot: String, at: Vector2)
signal spot_hovered(spot: String)

const PAD := 8.0
const PROPS_H := 60.0
const COLORS_H := 42.0
const HEADER_H := 20.0
const EXOTIC_H := 96.0
const ICON_W := 82.0
const COL_COLORS := [Color("dcc68b"), Color("dcc68b"), Color("f2f2f2"), Color("f2f2f2"), Color("f6e45c"), Color("f6e45c"), Color("f6e45c")]

var v := {}  # вид партии
var highlight := {}  # spot -> true (можно положить перетаскиваемый жетон)
var hover := ""
var _rects := {}  # spot -> Rect2
var _grid_top := 0.0
var _row_h := 40.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_relayout)


func set_view(view: Dictionary) -> void:
	v = view
	_relayout()


func spot_rect(spot: String) -> Rect2:
	return _rects.get(spot, Rect2())


func spot_at(p: Vector2) -> String:
	for s in _rects:
		if (_rects[s] as Rect2).has_point(p):
			return s
	return ""


func _relayout() -> void:
	_rects.clear()
	var w := size.x - PAD * 2.0
	# пари
	var label_w := 62.0
	var pw := (w - label_w - 6.0 * 5) / 5.0
	for i in v.get("props", []).size():
		_rects["prop_%d" % i] = Rect2(PAD + label_w + 6.0 + i * (pw + 6.0), PAD, pw, PROPS_H)
	# цвета
	var cy := PAD + PROPS_H + 6.0
	var gw := w - ICON_W
	var cwid := (gw - 3 * 6.0) / 4.0
	var ids := ["color_blue", "color_orange", "color_red", "seven_5th"]
	for i in 4:
		_rects[ids[i]] = Rect2(PAD + i * (cwid + 6.0), cy, cwid, COLORS_H)
	# сетка
	_grid_top = cy + COLORS_H + 6.0 + HEADER_H
	_row_h = (size.y - _grid_top - EXOTIC_H - PAD - 8.0) / 9.0
	var sw := gw / 7.0
	for h in 9:
		var y := _grid_top + h * _row_h
		for c in 7:
			var id := ""
			if c < 2:
				id = "s_%d_%d" % [h, c]
			elif c < 4:
				id = "p_%d_%d" % [h, c - 2]
			else:
				id = "w_%d_%d" % [h, c - 4]
			_rects[id] = Rect2(PAD + c * sw + 1, y + 1, sw - 2, _row_h - 2)
	# экзотика
	var ey := size.y - PAD - EXOTIC_H
	var ew := (w - 3 * 8.0) / 4.0
	for j in v.get("exotics", []).size():
		var card := Rect2(PAD + j * (ew + 8.0), ey, ew, EXOTIC_H)
		var d := 30.0
		for k in 3:
			var cx := card.position.x + card.size.x * (0.25 + 0.25 * k)
			_rects["ex_%d_%d" % [j, k]] = Rect2(cx - d * 0.5, card.end.y - d - 6.0, d, d)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var s := spot_at(event.position)
		if s != hover:
			hover = s
			spot_hovered.emit(s)
			queue_redraw()
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if s != "" else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var s := spot_at(event.position)
		if s != "":
			spot_clicked.emit(s, event.global_position)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover != "":
		hover = ""
		spot_hovered.emit("")
		queue_redraw()


func _get_tooltip(at_position: Vector2) -> String:
	var s := spot_at(at_position)
	if s == "" or v.is_empty():
		return ""
	var info := spot_info(s)
	var text: String = info["title"]
	text += "\nВыигрыш: номинал жетона × %d" % info["mult"]
	text += "\nПроигрыш: " + ("−$%d" % info["loss"] if info["loss"] > 0 else "без штрафа")
	if s.begins_with("ex_"):
		text += "\n" + RSBData.EXOTICS[v["exotics"][int(s.split("_")[1])]]["text"] + "\nНе больше одного вашего жетона на карту."
	for b in v.get("bets", {}).get(s, []):
		text += "\nЖетон «%d» — %s" % [b["v"], v["players"][b["seat"]]["name"]]
	return text


func spot_info(s: String) -> Dictionary:
	var p := s.split("_")
	match p[0]:
		"s", "p", "w":
			var table: Array = {"s": RSBData.SHOW, "p": RSBData.PLACE, "w": RSBData.WIN}[p[0]]
			var h := int(p[1])
			var name: String = {"s": "в тройке (1–3 место)", "p": "в двойке (1–2 место)", "w": "победит"}[p[0]]
			return {"mult": table[h][int(p[2])][0], "loss": table[h][int(p[2])][1], "title": "Лошадь %s %s" % [RSBData.HORSES[h], name]}
		"color", "seven":
			var c: Dictionary = RSBData.COLOR_BETS[s]
			return {"mult": c["mult"], "loss": c["loss"], "title": c["name"]}
		"prop":
			var pr: Dictionary = RSBData.PROPS[v["props"][int(p[1])]]
			return {"mult": pr["mult"], "loss": pr["loss"], "title": "Пари: " + RSBRules.prop_title(pr) + " (ничья — проигрыш)"}
		"ex":
			var ex: Dictionary = RSBData.EXOTICS[v["exotics"][int(p[1])]]
			return {"mult": ex["mult"], "loss": ex["loss"], "title": "Экзотика: " + ex["name"]}
	return {"mult": 0, "loss": 0, "title": s}


# --- Рисование ----------------------------------------------------------------------

func _draw() -> void:
	if v.is_empty():
		return
	var tfont := RSBStyle.font("title")
	var bfont := RSBStyle.font("bold")
	# сукно
	draw_style_box(RSBStyle.box(RSBStyle.FELT, 8, RSBStyle.INK_ART, 3, Color(0, 0, 0, 0.35), 8), Rect2(Vector2.ZERO, size))
	var inner := StyleBoxFlat.new()
	inner.draw_center = false
	inner.border_color = Color(1, 1, 1, 0.12)
	inner.set_border_width_all(1)
	inner.set_corner_radius_all(6)
	draw_style_box(inner, Rect2(Vector2(4, 4), size - Vector2(8, 8)))
	# пари
	var plabel := Rect2(PAD, PAD, 56, PROPS_H)
	draw_style_box(RSBStyle.box(RSBStyle.FELT_DARK, 5, RSBStyle.GOLD, 2), plabel)
	draw_string(tfont, plabel.position + Vector2(0, 26), "ПАРИ", HORIZONTAL_ALIGNMENT_CENTER, plabel.size.x, 14, RSBStyle.GOLD)
	draw_string(bfont, plabel.position + Vector2(0, 44), "по 1 жетону", HORIZONTAL_ALIGNMENT_CENTER, plabel.size.x, 10, Color(RSBStyle.GOLD, 0.7))
	for i in v["props"].size():
		_draw_prop(i, _rects["prop_%d" % i])
	# цвета
	var cnames := {"color_blue": ["СИНИЕ", "победят"], "color_orange": ["ОРАНЖЕВЫЕ", "победят"], "color_red": ["КРАСНЫЕ", "победят"], "seven_5th": ["7 — ПЯТОЙ", "или хуже"]}
	var ccol := {"color_blue": RSBStyle.HORSE_COLORS["blue"], "color_orange": RSBStyle.HORSE_COLORS["orange"], "color_red": RSBStyle.HORSE_COLORS["red"], "seven_5th": Color("1b1b1b")}
	for id in cnames:
		var r: Rect2 = _rects[id]
		draw_style_box(RSBStyle.box(ccol[id], 5, Color(1, 1, 1, 0.8), 2), r)
		var txt := Color.WHITE if id != "color_orange" else RSBStyle.INK_ART
		draw_string(tfont, r.position + Vector2(8, 18), cnames[id][0], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 50, 14, txt)
		draw_string(bfont, r.position + Vector2(8, 34), cnames[id][1], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 50, 11, Color(txt, 0.8))
		var c: Dictionary = RSBData.COLOR_BETS[id]
		_mult(r, c["mult"], c["loss"], txt, 22, true)
	# заголовки колонок и рамки групп
	var gw := size.x - PAD * 2.0 - ICON_W
	var sw := gw / 7.0
	var hy := _grid_top - HEADER_H
	var heads := [["В ТРОЙКЕ", 0, 2], ["В ДВОЙКЕ", 2, 2], ["ПОБЕДА", 4, 3]]
	for hd in heads:
		var x: float = PAD + hd[1] * sw
		var wd: float = hd[2] * sw
		var col: Color = COL_COLORS[hd[1]]
		draw_string(tfont, Vector2(x, hy + 15), hd[0], HORIZONTAL_ALIGNMENT_CENTER, wd, 14, col)
		var fr := StyleBoxFlat.new()
		fr.draw_center = false
		fr.border_color = Color(col, 0.85)
		fr.set_border_width_all(2)
		draw_style_box(fr, Rect2(x, _grid_top - 1, wd, _row_h * 9 + 2))
	for h in 9:
		var y := _grid_top + h * _row_h
		if h in [2, 7]:
			for k in int(gw / 8):
				draw_line(Vector2(PAD + k * 8, y), Vector2(PAD + k * 8 + 4, y), Color(1, 1, 1, 0.35), 1.0)
		for c in 6:
			var lx := PAD + (c + 1) * sw
			draw_line(Vector2(lx, y + 3), Vector2(lx, y + _row_h - 3), Color(COL_COLORS[c], 0.35), 1.0)
		if h > 0:
			draw_line(Vector2(PAD, y), Vector2(PAD + gw, y), Color(1, 1, 1, 0.12), 1.0)
		# лошадь справа
		var t: Texture2D = RSBStyle.tex("horse_%d" % h)
		var ih := _row_h * 0.92
		var iw := ih * t.get_width() / t.get_height()
		draw_texture_rect(t, Rect2(Vector2(PAD + gw + 6, y + (_row_h - ih) * 0.5), Vector2(iw, ih)), false)
	for id in _rects:
		var p: PackedStringArray = id.split("_")
		if p[0] in ["s", "p", "w"]:
			var info := spot_info(id)
			var col_i := (0 if p[0] == "s" else (2 if p[0] == "p" else 4)) + int(p[2])
			_mult(_rects[id], info["mult"], info["loss"], COL_COLORS[col_i], int(clampf(_row_h * 0.55, 14, 24)), false)
	# экзотика
	for j in v["exotics"].size():
		_draw_exotic(j)
	# подсветка, итоги, жетоны
	var res_mode: bool = v.get("phase", "") in ["results", "vip", "game_over"] and not v.get("places", {}).is_empty()
	for id in _rects:
		var r: Rect2 = _rects[id]
		if highlight.has(id):
			var hb := StyleBoxFlat.new()
			hb.bg_color = Color(RSBStyle.GOLD, 0.18 if id != hover else 0.4)
			hb.border_color = RSBStyle.GOLD
			hb.set_border_width_all(2)
			hb.set_corner_radius_all(5)
			draw_style_box(hb, r.grow(1))
		elif id == hover and v.get("phase", "") == "race":
			draw_rect(r, Color(1, 1, 1, 0.12))
		if res_mode and v.get("bets", {}).has(id):
			var won := _spot_won(id)
			var rb := StyleBoxFlat.new()
			rb.draw_center = false
			rb.border_color = Color("6dff8a") if won else RSBStyle.RED
			rb.set_border_width_all(3)
			rb.set_corner_radius_all(5)
			draw_style_box(rb, r.grow(2))
	for id in v.get("bets", {}):
		if not _rects.has(id):
			continue
		var r: Rect2 = _rects[id]
		var list: Array = v["bets"][id]
		for k in list.size():
			var b: Dictionary = list[k]
			var d := minf(r.size.y, r.size.x) * 0.92
			var c := r.get_center() + Vector2(k * d * 0.35, -k * d * 0.15)
			draw_circle(c + Vector2(1.5, 2.5), d * 0.5, Color(0, 0, 0, 0.35))
			draw_texture_rect(RSBStyle.token_tex(b["seat"], b["v"], b["bonus"]), Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d)), false)


func _mult(r: Rect2, mult: int, loss: int, col: Color, fs: int, right: bool) -> void:
	var tfont := RSBStyle.font("title")
	var txt := "%d×" % mult
	if right:
		draw_string(tfont, Vector2(r.end.x - 52, r.position.y + r.size.y * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_RIGHT, 40, fs, col)
	else:
		draw_string(tfont, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, col)
	if loss > 0:
		var rad := 7.5
		var c := Vector2(r.end.x - rad - 2, r.end.y - rad - 2)
		draw_circle(c, rad, RSBStyle.RED)
		draw_circle(c, rad, Color.WHITE, false, 1.0, true)
		draw_string(RSBStyle.font("bold"), c + Vector2(-rad, 4), "−%d" % loss, HORIZONTAL_ALIGNMENT_CENTER, rad * 2, 10, Color.WHITE)


func _draw_prop(i: int, r: Rect2) -> void:
	var pr: Dictionary = RSBData.PROPS[v["props"][i]]
	draw_style_box(RSBStyle.box(Color("2c7a49"), 5, Color("8fd18f"), 2), r)
	var ih := r.size.y * 0.5
	var t: Texture2D = RSBStyle.tex("horse_%d" % pr["a"])
	var iw := ih * t.get_width() / t.get_height()
	var x := r.position.x + 4
	var y := r.position.y + 4
	draw_texture_rect(t, Rect2(x, y, iw, ih), false)
	x += iw + 2
	draw_string(RSBStyle.font("title"), Vector2(x, y + ih * 0.75), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, RSBStyle.GOLD)
	x += 12
	if pr.has("group"):
		var hs := []
		for h in 9:
			if h != pr["a"] and RSBData.HORSE_COLOR[h] == pr["group"]:
				hs.append(h)
		var sh := ih * (0.62 if hs.size() > 2 else 0.8)
		for k in hs.size():
			var tt: Texture2D = RSBStyle.tex("horse_%d" % hs[k])
			var sw := sh * tt.get_width() / tt.get_height()
			draw_texture_rect(tt, Rect2(x + (k % 2) * sw * 0.8, y + (k / 2) * sh * 0.85 - (2 if hs.size() > 2 else 0), sw, sh), false)
	else:
		var tb: Texture2D = RSBStyle.tex("horse_%d" % pr["b"])
		draw_texture_rect(tb, Rect2(x, y, iw, ih), false)
	var mr := Rect2(r.position.x + 4, r.end.y - 22, 34, 18)
	draw_style_box(RSBStyle.box(Color("1b4d2c"), 3, RSBStyle.GOLD, 1), mr)
	draw_string(RSBStyle.font("title"), mr.position + Vector2(0, 14), "%d×" % pr["mult"], HORIZONTAL_ALIGNMENT_CENTER, mr.size.x, 13, RSBStyle.GOLD)
	if pr["loss"] > 0:
		var c := Vector2(r.position.x + 52, r.end.y - 13)
		draw_circle(c, 8, RSBStyle.RED)
		draw_string(RSBStyle.font("bold"), c + Vector2(-8, 4), "−%d" % pr["loss"], HORIZONTAL_ALIGNMENT_CENTER, 16, 10, Color.WHITE)


func _draw_exotic(j: int) -> void:
	var ex: Dictionary = RSBData.EXOTICS[v["exotics"][j]]
	var w := (size.x - PAD * 2.0 - 3 * 8.0) / 4.0
	var r := Rect2(PAD + j * (w + 8.0), size.y - PAD - EXOTIC_H, w, EXOTIC_H)
	var tint: Color = {"exotic_red": Color("b8433f"), "exotic_blue": Color("3f63a8"), "exotic_green": Color("3f8a52"), "exotic_purple": Color("7a4a9a"), "exotic_navy": Color("3a3f6e")}[ex["art"]]
	draw_style_box(RSBStyle.box(Color("f3e9d2"), 6, tint, 3, Color(0, 0, 0, 0.3), 3), r)
	draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, 18)), tint)
	draw_string(RSBStyle.font("title"), r.position + Vector2(6, 17), ex["name"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 70, 13, Color.WHITE)
	draw_string(RSBStyle.font("title"), Vector2(r.end.x - 60, r.position.y + 17), "%d×  −%d" % [ex["mult"], ex["loss"]], HORIZONTAL_ALIGNMENT_RIGHT, 54, 13, RSBStyle.GOLD)
	var lines := ex["text"] as String
	draw_multiline_string(RSBStyle.font("regular"), r.position + Vector2(6, 33), lines, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, 9, 2, Color(RSBStyle.INK_ART, 0.8))
	for k in 3:
		var sr: Rect2 = _rects["ex_%d_%d" % [j, k]]
		draw_circle(sr.get_center(), sr.size.x * 0.5, Color(tint, 0.12))
		draw_arc(sr.get_center(), sr.size.x * 0.5, 0, TAU, 32, tint, 2.0, true)


## Выиграла ли ячейка (на экране итогов) — то же, что считает хост.
func _spot_won(id: String) -> bool:
	var places: Dictionary = v["places"]
	var pos: Array = v["pos"]
	var p := id.split("_")
	var first: int = places["first"]
	match p[0]:
		"s":
			var h := int(p[1])
			return h == first or places["second"].has(h) or places["third"].has(h)
		"p":
			var h := int(p[1])
			return h == first or places["second"].has(h)
		"w":
			return int(p[1]) == first
		"color":
			return RSBData.HORSE_COLOR[first] == p[1]
		"seven":
			return pos.filter(func(x): return x > pos[4]).size() >= 4
		"prop":
			var pr: Dictionary = RSBData.PROPS[v["props"][int(p[1])]]
			if pr.has("group"):
				for h in 9:
					if h != pr["a"] and RSBData.HORSE_COLOR[h] == pr["group"] and pos[h] >= pos[pr["a"]]:
						return false
				return true
			return pos[pr["a"]] > pos[pr["b"]]
		"ex":
			var r := RSBRules.new()
			r.pos = pos
			r.places = places
			return r.exotic_wins(RSBData.EXOTICS[v["exotics"][int(p[1])]]["id"])
	return false
