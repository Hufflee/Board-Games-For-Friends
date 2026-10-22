class_name PlayerTag
extends Button
## Ник игрока с его цветом (кружок). По своему нику можно кликнуть — цвет сменится на случайный;
## хост так же меняет цвет «местным» игрокам. Работает в любой теме: шрифт и цвет текста задаёт игра.

static var _dots := {}

var local_i := -1


## m — запись участника из Net.lobby_view["members"]; members — весь список (чтобы найти номер «местного»).
static func make(m: Dictionary, members: Array, font_size: int = 16, text_color: Color = Color.WHITE, suffix: String = "") -> PlayerTag:
	var t := PlayerTag.new()
	t.flat = true
	t.text = str(m["name"]) + suffix
	t.add_theme_font_size_override("font_size", font_size)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		t.add_theme_color_override(k, text_color)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.08) if st in ["hover", "pressed"] else Color.TRANSPARENT
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 4
		sb.content_margin_right = 6
		t.add_theme_stylebox_override(st, sb)
	t.icon = dot(Net.color_of(int(m.get("color", 0))), font_size)
	t.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var mine: bool = m.get("peer", -2) == Net.multiplayer.get_unique_id() and m["kind"] != "local"
	if m["kind"] in ["local", "bot"] and Net.is_host():
		var k := 0
		for x in members:
			if x == m:
				break
			if x["kind"] in ["local", "bot"]:
				k += 1
		t.local_i = k
		mine = true
	t.disabled = not mine
	if mine:
		t.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		t.tooltip_text = "Нажмите, чтобы сменить цвет"
		t.pressed.connect(func():
			Sfx.play("chip", -8)
			Net.reroll_color(t.local_i))
	return t


## Ник за игровым столом: players — игроки партии (view["players"]), seat — чей ник, my_seat — моё место.
## Свой ник (а на одном компьютере хосту — ники «местных» игроков) можно нажать — цвет сменится.
## can_change = false — цвет менять нельзя (например, в «Перудо» по нему окрашены стакан и кости).
static func make_seat(players: Array, seat: int, my_seat: int, font_size: int = 16, text_color: Color = Color.WHITE, suffix: String = "", can_change: bool = true) -> PlayerTag:
	var p: Dictionary = players[seat]
	var m := {"name": p["name"], "color": p.get("color", 0), "kind": "local" if p.get("local", false) else "player", "peer": -2}
	if seat == my_seat and not p.get("local", false) and can_change:
		m["peer"] = Net.multiplayer.get_unique_id()
	if not can_change:
		m["kind"] = "player"  # «местного» игрока тоже не перекрашивать
	var t := make(m, [], font_size, text_color, suffix)
	if p.get("local", false) and Net.is_host() and can_change:
		var humans := 0
		for q in players:
			if not q.get("local", false) and not q.get("bot", false):
				humans += 1
		t.local_i = seat - humans
	return t


## Кружок цвета игрока (иконка).
static func dot(c: Color, font_size: int = 16) -> Texture2D:
	var d := clampi(int(font_size * 0.8), 10, 28)
	var key := "%s/%d" % [c.to_html(), d]
	if _dots.has(key):
		return _dots[key]
	var img := Image.create(d * 2, d * 2, false, Image.FORMAT_RGBA8)
	var r := float(d)
	for y in d * 2:
		for x in d * 2:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - dist, 0.0, 1.0)
			if a <= 0.0:
				continue
			var col := Color.WHITE if dist > r - 2.5 else c
			img.set_pixel(x, y, Color(col, a))
	var tex := ImageTexture.create_from_image(img)
	tex.set_size_override(Vector2i(d, d))
	_dots[key] = tex
	return tex
