class_name RSBTrack
extends Control
## Беговая дорожка: 9 дорожек × 15 клеток, стартовые ворота с бонусами, красная линия после 9-й клетки,
## клетчатый финиш. Лошади плавно скачут к своим клеткам; бонусный ход — всплывающее «+N!».

const GATE := 100.0  # ширина стартовых ворот
const FINISH_W := 26.0
const HEAD := 18.0  # строка с номерами клеток

var pos: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0]
var places := {}
var crossed: Array = []
var _disp: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _hop: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _flash_lane := -1
var _flash_t := 0.0
var _pops: Array = []  # [{lane, text, t}]
var _line_flash := 0.0


func set_state(v: Dictionary, animate: bool = true) -> void:
	var new_pos: Array = v["pos"]
	var lr: Dictionary = v.get("last_roll", {})
	places = v.get("places", {})
	if v.get("crossed", []).size() > crossed.size():
		_line_flash = 1.2
	crossed = v.get("crossed", []).duplicate()
	for h in 9:
		if not animate or new_pos[h] < pos[h]:
			_disp[h] = float(new_pos[h])
		elif new_pos[h] > pos[h]:
			_hop[h] = 1.0
	if animate and not lr.is_empty() and new_pos != pos:
		_flash_lane = int(lr["horse"])
		_flash_t = 1.0
		if lr.get("bonus", false):
			_pops.append({"lane": _flash_lane, "text": "+%d!" % (int(lr["move"]) - 1), "t": 1.4})
	pos = new_pos.duplicate()
	queue_redraw()


func _process(delta: float) -> void:
	var busy := false
	for h in 9:
		var target := float(pos[h])
		if absf(_disp[h] - target) > 0.001:
			_disp[h] = move_toward(_disp[h], target, delta * maxf(4.0, (target - _disp[h]) * 5.0))
			busy = true
		if _hop[h] > 0.0:
			_hop[h] = maxf(0.0, _hop[h] - delta * 2.6)
			busy = true
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta * 1.5)
		busy = true
	if _line_flash > 0.0:
		_line_flash = maxf(0.0, _line_flash - delta)
		busy = true
	for p in _pops:
		p["t"] -= delta
	_pops = _pops.filter(func(p): return p["t"] > 0.0)
	if busy or not _pops.is_empty():
		queue_redraw()


func lane_h() -> float:
	return (size.y - HEAD) / 9.0


func cell_w() -> float:
	return (size.x - GATE - FINISH_W) / RSBData.FINISH


func horse_point(h: int, at: float) -> Vector2:
	var lh := lane_h()
	var x := GATE + (at - 0.5) * cell_w() if at > 0.0 else GATE - 21.0
	return Vector2(x, HEAD + (h + 0.5) * lh)


func _draw() -> void:
	var lh := lane_h()
	var cw := cell_w()
	var font := RSBStyle.font("bold")
	var tfont := RSBStyle.font("title")
	# рамка
	draw_style_box(RSBStyle.box(RSBStyle.FELT_DARK, 6, RSBStyle.INK_ART, 3, Color(0, 0, 0, 0.3), 6), Rect2(Vector2(-4, -4), size + Vector2(8, 8)))
	# номера клеток
	for i in RSBData.FINISH:
		var x := GATE + i * cw
		var col := RSBStyle.GOLD if i < RSBData.RED_LINE else Color("ffb38a")
		draw_string(font, Vector2(x, HEAD - 4), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, cw, 11, col)
	# дорожки
	for h in 9:
		var y := HEAD + h * lh
		var dirt := RSBStyle.DIRT if h % 2 == 0 else RSBStyle.DIRT.darkened(0.08)
		if h == _flash_lane and _flash_t > 0.0:
			dirt = dirt.lerp(Color("f5d08a"), 0.35 * _flash_t)
		draw_rect(Rect2(GATE, y, cw * RSBData.FINISH, lh), dirt)
		for i in range(1, RSBData.FINISH):
			draw_line(Vector2(GATE + i * cw, y + 2), Vector2(GATE + i * cw, y + lh - 2), Color(0, 0, 0, 0.18), 1.0)
		draw_line(Vector2(GATE, y), Vector2(GATE + cw * RSBData.FINISH, y), Color(1, 0.9, 0.7, 0.35), 1.0)
		# стартовые ворота: бонус и номер
		draw_rect(Rect2(0, y, GATE, lh), RSBStyle.FELT)
		draw_line(Vector2(0, y), Vector2(GATE, y), Color(1, 1, 1, 0.2), 1.0)
		var b: int = RSBData.BONUS[h]
		var hc: Color = RSBStyle.HORSE_COLORS[RSBData.HORSE_COLOR[h]]
		var badge := Rect2(36, y + lh * 0.5 - 9, 24, 18)
		draw_style_box(RSBStyle.box(hc if b > 0 else Color("333333"), 3, Color.WHITE, 1), badge)
		draw_string(font, badge.position + Vector2(0, 13), "+%d" % b if b > 0 else "—", HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 11, Color.WHITE)
		draw_string(tfont, Vector2(2, y + lh * 0.5 + 6), RSBData.HORSES[h], HORIZONTAL_ALIGNMENT_CENTER, 32, 13 if h in [0, 8] else 16, RSBStyle.CREAM_ART)
	# красная линия
	var lx := GATE + RSBData.RED_LINE * cw
	var lw := 3.0 + 3.0 * _line_flash
	draw_line(Vector2(lx, HEAD - 2), Vector2(lx, size.y), Color(1, 0.15, 0.1, 0.9), lw)
	# финиш: клетчатая колонна
	var fx := GATE + RSBData.FINISH * cw
	var sq := FINISH_W / 3.0
	var rows := int(ceil((size.y - HEAD) / sq))
	for r in rows:
		for c in 3:
			draw_rect(Rect2(fx + c * sq, HEAD + r * sq, sq, minf(sq, size.y - HEAD - r * sq)), Color.WHITE if (r + c) % 2 == 0 else Color("111111"))
	# места на финише
	if not places.is_empty():
		var marks := {}
		marks[places["first"]] = "1"
		for h in places.get("second", []):
			marks[h] = "2"
		for h in places.get("third", []):
			if not marks.has(h):
				marks[h] = "3"
		for h in marks:
			var p := horse_point(h, float(pos[h])) + Vector2(cw * 0.5 + 18, 0)
			var col: Color = {"1": RSBStyle.GOLD, "2": Color("d9d9d9"), "3": Color("d79a5b")}[marks[h]]
			draw_circle(p, 10, RSBStyle.INK_ART)
			draw_circle(p, 8.5, col)
			draw_string(tfont, p + Vector2(-8, 5), marks[h], HORIZONTAL_ALIGNMENT_CENTER, 16, 13, RSBStyle.INK_ART)
	# лошади
	for h in 9:
		var t: Texture2D = RSBStyle.tex("horse_%d" % h)
		var hh := lh * 1.05
		var w := hh * t.get_width() / t.get_height()
		var p := horse_point(h, _disp[h])
		p.y -= sin(_hop[h] * PI) * 6.0
		draw_texture_rect(t, Rect2(p - Vector2(w * 0.55, hh * 0.55), Vector2(w, hh)), false)
	# всплывающие бонусы
	for pp in _pops:
		var a := clampf(pp["t"], 0.0, 1.0)
		var p := horse_point(pp["lane"], float(pos[pp["lane"]])) + Vector2(10, -lh * 0.4 - (1.4 - pp["t"]) * 16)
		draw_string(tfont, p + Vector2(1, 1), pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0, 0, 0, a))
		draw_string(tfont, p, pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(RSBStyle.GOLD, a))
