extends Control
## Рисует 2D-поезд и синхронную врезку по снимкам событий хоста.
## Вид — CEStyle (вестерн-плакат): пустыня днём / ночь под луной, вагоны из досок,
## подписи бандитов над фигурками, своя фигурка — с латунным кольцом и меткой «ВЫ».

const ART := "res://games/colt_express/art/"
var detail := false
var state: Dictionary = {}
var time := 0.0
var scroll := 0.0  # пройденный пейзажем путь, px: растёт только во время показа действий (стол двигает сам)
var _tags: Array[Rect2] = []  # подписи над фигурками в этом кадре — новые не налезают на прежние
var textures: Dictionary = {}  # держим ссылки: текстура, загруженная только внутри _draw, освобождается до отрисовки


func present(next: Dictionary, elapsed: float) -> void:
	state = next
	time = elapsed
	queue_redraw()


func _draw() -> void:
	if state.is_empty():
		return
	var ink := CEStyle.c("ink")
	var accent := CEStyle.c("brass")
	var clip: Dictionary = state.get("clip", {})
	var before: Dictionary = clip.get("from", state.board)
	var after: Dictionary = clip.get("to", state.board)
	var t := clampf(time / float(clip.get("duration", 1.0)), 0, 1)
	if detail:
		_draw_detail(clip, before, after, t, accent, ink)
		return
	var time_car: bool = before.get("time_car", false)
	var spacing := (size.x - 32.0) / (int(state.cars) + 1 + int(time_car))
	var has_coach: bool = int(before.get("coach", -1)) >= 0
	var rail := size.y * (0.60 if has_coach else 0.80)
	var car_h := clampf(size.y * 0.30, 64, 96)
	var roof := rail - car_h
	CEStyle.draw_scenery(self, Rect2(Vector2.ZERO, size), roof + 10, rail, scroll)
	_tags.clear()
	for car in range(-1 if time_car else 0, int(state.cars) + 1):
		var cx := _center(car, spacing)
		if car < int(state.cars):
			# сцепка с вагоном позади
			draw_line(Vector2(cx + spacing * 0.3, rail - 12), Vector2(cx + spacing * 0.7, rail - 12), CEStyle.c("wood_dark"), 4)
		CEStyle.draw_wagon(self, cx, roof, rail, spacing - 16.0, car == 0)
		var label := "МАШИНА ВРЕМЕНИ" if car == -1 else ("ПАРОВОЗ" if car == 0 else "ВАГОН %d" % car)
		if before.get("prison", false) and car == int(state.cars):
			label = "ТЮРЬМА"
			for bar in 5:
				var x := cx + (bar - 2) * 9.0
				draw_line(Vector2(x, roof + 12), Vector2(x, rail - 20), Color("2a201b"), 3)
		if car == -1:
			draw_rect(Rect2(cx - spacing * 0.36, roof + 14, spacing * 0.72, 20), Color("64788b"))
		_caption(Vector2(cx, rail + 26), label)
	var actors: Dictionary = {}
	for b: Dictionary in before.bandits:
		if b.car == -4:
			continue
		var target := _find(after, b.id)
		var origin := _spot(b, before, spacing, roof, rail)
		var destination := _spot(target, after, spacing, roof, rail) if not target.is_empty() else origin
		actors[b.id] = [origin, destination]
	var h := clampf(spacing * 0.40, 30, 54)
	for item: Dictionary in (before.loot if t < 0.55 else after.loot):
		var x := _center(before.coach if item.car == -2 else item.car, spacing) - spacing * 0.36 + (int(item.index) % 4) * 15.0
		var y := rail + 31 if item.car == -2 else (roof - 7 if item.roof else rail - 24)
		CEStyle.draw_loot(self, Vector2(x, y), item.kind)
	for id in actors:
		var pos := _movement(actors[id][0], actors[id][1], t)
		if _find(before, id).car != -2 and _find(after, id).get("car", 0) != -2 and (t < 0.75 or not _find(after, id).is_empty()):
			_actor(id, pos, h)
	var marshal_from := Vector2(_center(before.marshal, spacing), rail - 16)
	var marshal_to := Vector2(_center(after.marshal, spacing), rail - 16)
	if int(before.marshal) >= 0:
		_actor(6, _movement(marshal_from, marshal_to, t), h)
	var horses_from: Array = before.get("horses", [])
	var horses_to: Array = after.get("horses", [])
	for i in horses_from.size():
		if i >= horses_to.size() and t >= 0.55:
			continue
		var x := lerpf(_center(horses_from[i], spacing), _center(horses_to[i] if i < horses_to.size() else horses_from[i], spacing), t)
		draw_string(CEStyle.font("regular"), Vector2(x - 10, rail + 52), "♞", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ink)
	if has_coach:
		var coach_x := lerpf(_center(before.coach, spacing), _center(after.coach, spacing), t)
		var coach_y := rail + 76
		CEStyle.draw_wagon(self, coach_x, coach_y - 46, coach_y, spacing * 0.8, false)
		_caption(Vector2(coach_x, coach_y + 20), "ДИЛИЖАНС")
		if not after.guard:
			_actor(6, Vector2(coach_x, coach_y - 45), h * 0.72)
		else:
			_actor(6, Vector2(coach_x, roof + 1), h * 0.72)
		for id in actors:
			var old := _find(before, id)
			var current := _find(after, id)
			if old.car == -2 or current.get("car", 0) == -2:
				_actor(id, _movement(actors[id][0], actors[id][1], t), h)
	_effect(clip, actors, t, accent)
	# таблички уровней — поверх вагонов, у левого края
	_plate(Vector2(6, roof - 30), "КРЫША")
	_plate(Vector2(6, roof + 34), "САЛОН")


## Табличка уровня у левого края поезда.
func _plate(pos: Vector2, text: String) -> void:
	var f := CEStyle.font("title")
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CEStyle.CAP).x + 14
	var box := StyleBoxFlat.new()
	box.bg_color = Color(CEStyle.c("panel"), 0.85)
	box.set_corner_radius_all(4)
	draw_style_box(box, Rect2(pos, Vector2(w, 22)))
	draw_string(f, pos + Vector2(7, 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, CEStyle.CAP, CEStyle.c("muted"))


## Подпись вагона под рельсом, по центру.
func _caption(center: Vector2, text: String) -> void:
	var f := CEStyle.font("title")
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CEStyle.CAP).x
	draw_string(f, Vector2(center.x - w / 2, center.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, CEStyle.CAP, Color(CEStyle.c("ink"), 0.85))


func _center(car: int, spacing: float) -> float:
	return 16.0 + (float(state.cars) - car + 0.5) * spacing


func _find(board: Dictionary, id: int) -> Dictionary:
	for b: Dictionary in board.bandits:
		if b.id == id:
			return b
	return {}


func _spot(b: Dictionary, board: Dictionary, spacing: float, roof: float, rail: float) -> Vector2:
	var ids: Array[int] = []
	for other: Dictionary in board.bandits:
		if other.car == b.car and other.roof == b.roof:
			ids.append(other.id)
	var slot := float(ids.find(b.id)) - (ids.size() - 1) * 0.5
	# ноги — ровно на полу салона (верх нижней балки, rail − 16) или на крыше (верх кромки, roof),
	# как рисует CEStyle.draw_wagon; дилижанс стоит на rail + 76 (его крыша — rail + 30, пол — rail + 60)
	if b.car == -2:
		return Vector2(_center(board.coach, spacing) + slot * 16, rail + 31 if b.roof else rail + 60)
	if b.get("cell", false):
		return Vector2(_center(b.car, spacing) - spacing * 0.23 + slot * 12, rail - 16)
	return Vector2(_center(b.car, spacing) + slot * minf(26, spacing / maxi(2, ids.size())), roof + 1 if b.roof else rail - 16)


func _movement(a: Vector2, b: Vector2, t: float) -> Vector2:
	if a.is_equal_approx(b):
		return a
	var hops := 3.0 if absf(a.x - b.x) > 25 else 2.0
	return a.lerp(b, t) - Vector2(0, absf(sin(t * PI * hops)) * 8)


## Свой бандит: место игрока совпадает с местом этого view (зритель — никто).
func _mine(id: int) -> bool:
	if state.get("spectator", false) or id == 6:
		return false
	var b := _find(state.board, id)
	return not b.is_empty() and int(b.get("seat", -9)) == int(state.get("seat", -1))


func _actor(id: int, pos: Vector2, h: float) -> void:
	var prefix := "character" if state.get("sprites", false) and id < 6 else "meeple"
	var key := "%s_%d" % [prefix, id]
	if not textures.has(key):
		textures[key] = load(ART + key + ".png")
	var art: Texture2D = textures[key]
	if art == null:
		return
	var w := h * art.get_width() / art.get_height()
	var me := _mine(id)
	draw_circle(pos + Vector2(0, 1), 9, CEStyle.c("shadow"))
	if me:
		draw_arc(pos - Vector2(0, h * 0.5), h * 0.6, 0, TAU, 40, Color(CEStyle.c("brass"), 0.9), 3, true)
	draw_texture_rect(art, Rect2(pos - Vector2(w / 2, h), Vector2(w, h)), false)
	if detail:
		return
	var name := _name(id)
	if me:
		name = "ВЫ · " + name
	var f := CEStyle.font("bold")
	var tw := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10
	var box := StyleBoxFlat.new()
	box.bg_color = CEStyle.c("accent") if me else Color(CEStyle.c("panel"), 0.92)
	box.set_corner_radius_all(4)
	var r := Rect2(pos + Vector2(-tw / 2, -h - 19), Vector2(tw, 17))
	# несколько бандитов рядом — подписи лесенкой вверх, чтобы не наползали
	var moved := true
	while moved:
		moved = false
		for other: Rect2 in _tags:
			if other.grow(1).intersects(r):
				r.position.y = other.position.y - 19
				moved = true
	_tags.append(r)
	draw_style_box(box, r)
	draw_string(f, r.position + Vector2(5, 13), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CEStyle.c("accent_ink") if me else CEStyle.c("ink"))


func _name(id: int) -> String:
	if id == 6:
		return "Маршал"
	if id == 7:
		return "Мэй"
	return CERules.NAMES[id] if id >= 0 and id < CERules.NAMES.size() else "?"


func _effect(clip: Dictionary, actors: Dictionary, t: float, accent: Color) -> void:
	if clip.is_empty() or not clip.applied or not actors.has(clip.card.id) or not actors.has(clip.target):
		return
	var a: Vector2 = actors[clip.card.id][0] - Vector2(0, 22)
	var b: Vector2 = actors[clip.target][0] - Vector2(0, 22)
	if clip.card.kind == "shoot":
		_shot(a, b, t, accent)
		var second: int = clip.get("second_target", -1)
		if actors.has(second):
			_shot(a, actors[second][0] - Vector2(0, 22), maxf(0, t - 0.12), accent)
	elif clip.card.kind == "punch" and t < 0.45:
		draw_arc(a.lerp(b, 0.7), 14, 0, TAU, 18, CEStyle.c("accent"), 4, true)


func _shot(a: Vector2, b: Vector2, t: float, accent: Color) -> void:
	var head := a.lerp(b, clampf(t * 1.35, 0, 1))
	var tail := head.move_toward(a, 40)
	draw_line(tail, head, Color(accent, 0.85), 3, true)
	draw_circle(head, 4.5, Color("fff0c0"))
	if t < 0.23:
		draw_circle(a, 9, Color(1, 0.9, 0.6, 0.85))


## Нижняя врезка «Кадр»: крупно только участники действия, на прозрачном фоне (рамку даёт панель стола).
func _draw_detail(clip: Dictionary, before: Dictionary, after: Dictionary, t: float, accent: Color, ink: Color) -> void:
	if clip.is_empty():
		return
	var actors: Dictionary = {}
	var ground := size.y - 18.0
	draw_line(Vector2(size.x * 0.05, ground + 2), Vector2(size.x * 0.95, ground + 2), Color(CEStyle.c("wood_dark"), 0.6), 3)
	for id in [clip.card.id, clip.target, clip.get("second_target", -1)]:
		var source := _find(before, id)
		if id < 0 or source.is_empty():
			continue
		var target := _find(after, id)
		if target.is_empty():
			target = source
		var a := Vector2(size.x * (0.35 if source.car < int(clip.from.bandits[0].car) else 0.65), ground)
		if clip.target >= 0:
			var other := _find(before, clip.target if id == clip.card.id else clip.card.id)
			var left: bool = source.car > other.car or (source.car == other.car and id == clip.card.id)
			a.x = size.x * (0.25 if left else 0.75)
		var b := a + Vector2((source.car - target.car) * 30, (-24 if target.roof else 24) if source.roof != target.roof else 0)
		actors[id] = [a, b]
		_actor(id, _movement(a, b, t), 64)
	if clip.card.kind == "marshal" or clip.card.kind == "event":
		var a := Vector2(size.x * 0.5, ground)
		_actor(6, _movement(a, a + Vector2((before.marshal - after.marshal) * 40, 0), t), 64)
	_effect(clip, actors, t, accent)
