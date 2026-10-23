extends Control
## Стол «Большой бродилки»: поле (зум колесом, перетаскивание мышью, камера сама едет к фишке хода),
## фишки шагают по клеткам; справа — игроки и журнал; снизу — кнопка фазы и карты Лавки; в центре —
## окно выбора, вытянутая карта и кубики. Состояние — из Net.view, действия — Net.send_action.

const PerudoDieView := preload("res://games/perudo/ui/d6_view.gd")

var app: Node

const SIDE_W := 300.0
const PAD := 12.0
const STEP_TIME := 0.3  # шаг персонажа по клетке — не спеша, чтобы успеть сосчитать клетки
const AFTER_DIE := 0.35  # пауза между остановкой кубика и первым шагом
const CARD_FIRST := 1800  # мс: вытянутую карту сначала читают, потом персонаж идёт по её эффекту
const AFTER_STEP := 0.8  # пауза после последнего шага: видно, на какую клетку встал, — потом её эффект
## Печатные места на поле (пиксели art/board.webp, 3402×3600): колоды и три ячейки Тадам.
const DECK_RECTS := [Rect2(341, 48, 472, 651), Rect2(848, 48, 472, 651), Rect2(1352, 48, 467, 651)]
const SLOT_RECTS := [Rect2(1853, 48, 462, 651), Rect2(2352, 48, 469, 651), Rect2(2853, 48, 467, 651)]
const MAP_W := 940.0  # ширина поля в MapFull (с запасом справа — там надписи «Смерч» и «Дань»)
const MAP_H := 905.0
## Надписи на поле (пиксели board.webp) и поворот, чтобы читать ровно: наведение — крупно в центре экрана.
const LABELS := [
	[Rect2(470, 1150, 240, 740), PI / 2], [Rect2(1040, 1590, 230, 610), PI / 2],  # жвачка, кубик удачи
	[Rect2(3280, 1310, 240, 840), -PI / 2], [Rect2(3380, 2300, 154, 800), -PI / 2],  # смерч, дань
	[Rect2(400, 680, 760, 240), 0.0], [Rect2(1820, 730, 800, 230), 0.0],  # финиш-сейф, удачный расклад
	[Rect2(1600, 1710, 800, 180), 0.0], [Rect2(1370, 1975, 1070, 250), 0.0],  # телепорт, кубики по цвету клетки
	[Rect2(1350, 2600, 640, 200), 0.0], [Rect2(450, 2630, 420, 150), 0.0],  # перекрёсток, нееет
	[Rect2(260, 3225, 790, 260), 0.0], [Rect2(1390, 3120, 530, 170), 0.0],  # шахта, велосипед
	[Rect2(1520, 3320, 440, 140), 0.0], [Rect2(2110, 3080, 1080, 290), 0.0],  # старт, схватка
]
const BOTTOM_OVER := 0.0  # насколько поле можно увести вверх за нижний край (под панелью хода — старт)
const TOP_OVER := 40.0

var _v := {}
var _board: Control  # окно на поле (обрезает)
var _map: Control  # само поле, масштабируется и двигается
var _tex_size := Vector2.ONE
var _zoom := 0.3
var _fit := 0.2
var _dragging := false
var _press_at := Vector2.ZERO
var _drag_last := Vector2.ZERO
var _manual_until := 0  # мс: до этого времени камера не едет сама (игрок двигал поле)
var _ui_waits := false  # пришло новое состояние, но персонаж ещё идёт — эффект клетки покажем, когда дойдёт
var _tex_scale := 1.0  # во сколько раз картинка поля плотнее его координат (апскейл ×2 — 2.0)
const BOARD_W := 3534.0  # ширина поля в координатах (пиксели исходной board.webp)
const LABEL_DELAY := 2000  # мс: подсказка по надписи на поле — только если держать курсор 2 с
var _label_wait := -1  # над какой надписью курсор (ждём LABEL_DELAY)
var _label_since := 0
var _cam_tween: Tween

var _pawns: Array = []  # Pawn по местам
var _shown: Array[int] = []  # клетка, где фишка нарисована
var _slots: Array = []  # TextureRect ячеек Тадам
var _deck_labels: Array = []
var _traps: Control
var _step_hl: Control  # подсветка клеток, куда можно пойти после броска (щёлкнуть, чтобы идти)
var _step_cells: Array = []
const STEP_HL := Color(0.35, 0.85, 0.3, 0.4)  # зелёный, прозрачность 60 %

var _side: VBoxContainer
var _top: TopBar
var _bar_buttons: HBoxContainer
var _players_box: VBoxContainer
var _tadam_row: HBoxContainer  # ряд Тадам мини-картами (на поле он вверху и часто за кадром)
var _log_text: RichTextLabel
var _bar: PanelContainer
var _bar_box: VBoxContainer
var _dialog: PanelContainer
var _fx: Control
var _preview: TextureRect  # крупный просмотр карты при наведении (как в Gloom)
var _label_view: TextureRect  # надпись с поля — крупно в центре
var _label_i := -1
var _dice_box: HBoxContainer
var _dice3d: Array = []  # два TossDie (2D-кубики с физикой монетки; 3D K12Die3D(6) пока не используем)
var _thrown_mine := false  # свой бросок улетел, ждём результат с хоста

var _bar_key := ""
var _roll_no := -1  # какой бросок уже показан (номер из правил); -1 — ещё ни одного состояния
var _card_key := ""
var _walk_after := 0  # мс: раньше этого персонажи не идут (показывается вытянутая карта)
var _celebrated := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(BRStyle.Backdrop.new())

	_board = Control.new()
	_board.clip_contents = true
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	_board.gui_input.connect(_on_board_input)
	_board.mouse_exited.connect(func():
		# курсор ушёл с поля — подсказка по надписи не нужна
		_label_wait = -1
		_label_i = -1
		_label_view.visible = false)
	add_child(_board)
	var under := ColorRect.new()  # вокруг поля, когда оно показано целиком, — тёмное дерево, а не доски фона
	under.color = BRStyle.WOOD_DARK.darkened(0.25)
	under.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(under)
	_map = Control.new()
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_map)
	var bg := TextureRect.new()
	bg.texture = load("res://games/brodilka/art/board.webp")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# поле апскейлено: координаты (клетки, колоды, надписи, фишки) — в пикселях исходника BOARD_W
	_tex_scale = bg.texture.get_size().x / BOARD_W
	_tex_size = bg.texture.get_size() / _tex_scale
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.size = _tex_size
	_map.size = _tex_size
	_map.add_child(bg)
	for i in 3:
		# сколько карт в колоде — золотые цифры на деревянном жетоне
		var lbl := BRStyle.label("", 72, BRStyle.GOLD, HORIZONTAL_ALIGNMENT_CENTER, "bold")
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_outline_color", BRStyle.WOOD_DARK)
		lbl.add_theme_constant_override("outline_size", 16)
		var badge := BRStyle.box(BRStyle.WOOD, 60, BRStyle.WOOD_DARK, 8, 0.45)
		lbl.add_theme_stylebox_override("normal", badge)
		var r := _px_rect(DECK_RECTS[i])
		lbl.size = Vector2(150, 120)
		lbl.position = Vector2(r.get_center().x - 75, r.end.y - 100)
		_map.add_child(lbl)
		_deck_labels.append(lbl)
	for i in 3:
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var r := _px_rect(SLOT_RECTS[i])
		tr.position = r.position
		tr.size = r.size
		tr.mouse_filter = Control.MOUSE_FILTER_PASS
		_hoverable(tr)
		_map.add_child(tr)
		_slots.append(tr)
	_traps = Control.new()
	_traps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.add_child(_traps)
	_step_hl = Control.new()
	_step_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_step_hl.draw.connect(func():

		for c in _step_cells:
			var at := _cell_px(int(c))
			_step_hl.draw_circle(at, 82.0, STEP_HL)
			_step_hl.draw_arc(at, 82.0, 0.0, TAU, 56, Color(STEP_HL, 0.9), 7.0, true))
	_map.add_child(_step_hl)
	_step_hl.size = _tex_size  # на всё поле: слой нулевого размера движок мог не выводить
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fsb := StyleBoxFlat.new()
	fsb.draw_center = false
	fsb.border_color = BRStyle.WOOD_DARK
	fsb.set_border_width_all(6)
	# прямые углы и без тени: скруглённая рамка оставляла по углам выглядывающие края карты и досок
	frame.add_theme_stylebox_override("panel", fsb)
	_board.add_child(frame)
	# управление видом: зум, всё поле, к фишке (поле ещё тащится мышью, стрелками и WASD)
	var cam := BRStyle.hbox(6)
	cam.position = Vector2(14, 14)
	for spec in [["−", "Отдалить (колесо мыши)"], ["+", "Приблизить (колесо мыши)"], ["Всё поле", "Показать поле целиком"], ["К персонажу", "Камера к персонажу того, кто ходит"]]:
		var b := BRStyle.button(spec[0], BRStyle.CAP)
		b.tooltip_text = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		var what: String = spec[0]
		b.pressed.connect(func(): _cam_button(what))
		cam.add_child(b)
	var hint := BRStyle.label("Тащи поле мышью · колесо — зум", BRStyle.CAP, BRStyle.PARCH)
	hint.add_theme_color_override("font_outline_color", BRStyle.WOOD_DARK)
	hint.add_theme_constant_override("outline_size", 5)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cam.add_child(hint)
	_board.add_child(cam)

	# правая колонка: кнопки, игроки, журнал
	_side = BRStyle.vbox(10)
	add_child(_side)
	var buttons := HBoxContainer.new()  # кнопки игры — в верхней полосе (TopBar)
	buttons.add_theme_constant_override("separation", 6)
	var rules := BRStyle.button("Правила", 14)
	rules.pressed.connect(func(): app.show_rules())
	buttons.add_child(rules)
	var settings := BRStyle.button("Настройки", 14)
	settings.pressed.connect(func(): app.show_settings())
	buttons.add_child(settings)
	var leave: Button
	if Net.is_party() and Net.is_host():
		leave = BRStyle.button("Завершить", BRStyle.CAP)
		LeaveGuard.wire(leave, "Завершить партию для всех?", "Все вернутся в лобби игры, пати сохранится.", Net.end_game)
	elif Net.is_party():
		leave = BRStyle.button("Покинуть", BRStyle.CAP)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из партии и из пати.", func(): app.leave_party())
	else:
		leave = BRStyle.button("Выйти", BRStyle.CAP)
		LeaveGuard.wire(leave, "Выйти из партии?", "Игра закончится, вы вернётесь в меню.", func(): app.back_to_menu())
	leave.theme_type_variation = "QuietButton"
	buttons.add_child(leave)
	_bar_buttons = buttons
	var pp := BRStyle.panel(12)
	_players_box = BRStyle.vbox(6)
	pp.add_child(_players_box)
	_side.add_child(pp)
	var tp := BRStyle.panel(10)
	var tcol := BRStyle.vbox(6)
	tp.add_child(tcol)
	tcol.add_child(BRStyle.label("ТАДАМ · действуют на всех", BRStyle.CAP, BRStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	_tadam_row = BRStyle.hbox(8)
	_tadam_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tcol.add_child(_tadam_row)
	_side.add_child(tp)
	var lp := BRStyle.panel(12)
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lcol := BRStyle.vbox(6)
	lp.add_child(lcol)
	lcol.add_child(BRStyle.label("ЖУРНАЛ", BRStyle.CAP, BRStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	_log_text = RichTextLabel.new()
	_log_text.bbcode_enabled = true
	_log_text.scroll_following = true
	_log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_text.add_theme_font_size_override("normal_font_size", BRStyle.CAP)
	_log_text.add_theme_font_size_override("bold_font_size", BRStyle.CAP)
	_log_text.add_theme_color_override("default_color", BRStyle.INK)
	lcol.add_child(_log_text)
	_side.add_child(lp)

	# нижняя панель хода (поверх поля)
	_bar = BRStyle.panel(14)
	_bar_box = BRStyle.vbox(8)
	_bar.add_child(_bar_box)
	add_child(_bar)
	_dice_box = BRStyle.hbox(12)
	_dice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dice_box)
	_dialog = BRStyle.panel(22)
	_dialog.visible = false
	add_child(_dialog)
	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.visible = false
	_preview.z_index = 60
	add_child(_preview)
	_label_view = TextureRect.new()
	_label_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_label_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_label_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_view.visible = false
	add_child(_label_view)

	# общая полоса сверху: название, фаза, часы, чат, пауза, пригласить, зритель + кнопки игры
	# полоса — те же доски фона (прозрачная), снизу только тонкая тень-разделитель
	var bar_sb := StyleBoxFlat.new()
	bar_sb.bg_color = Color(0, 0, 0, 0.0)
	bar_sb.border_color = Color(0, 0, 0, 0.28)
	bar_sb.content_margin_left = 16
	bar_sb.content_margin_right = 12
	bar_sb.content_margin_top = 6
	bar_sb.content_margin_bottom = 6
	_top = TopBar.make(self, "Большая бродилка", func(t, z): return BRStyle.button(t, z), bar_sb, BRStyle.PARCH, BRStyle.font("bold"))
	_top.info.add_theme_font_override("font", BRStyle.font("bold"))  # как в Hues and Cues: ход — крупно и жирно
	for c in _bar_buttons.get_children():
		_bar_buttons.remove_child(c)
		_top.actions.add_child(c)
	BRStyle.restyle_chat(_top.chat)

	ChatBubbles.attach(self, func(t: String) -> Control:
		var b := BRStyle.label(t, BRStyle.CAP, BRStyle.INK, HORIZONTAL_ALIGNMENT_CENTER)
		b.add_theme_stylebox_override("normal", BRStyle.box(BRStyle.parch(), 8, BRStyle.WOOD, 2, 0.35))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = 240
		return b, Vector2(-SIDE_W - 260, 70))
	resized.connect(_layout)
	_layout.call_deferred()
	Net.state_changed.connect(_on_state)
	if not Net.view.is_empty():
		_on_state.call_deferred(Net.view)


# --- Раскладка и камера ------------------------------------------------------------

func _layout() -> void:
	var top := TopBar.HEIGHT + PAD
	var h := size.y - TopBar.HEIGHT - PAD * 2
	_board.position = Vector2(PAD, top)
	_board.size = Vector2(size.x - SIDE_W - PAD * 3, h)
	_side.position = Vector2(size.x - SIDE_W - PAD, top)
	_side.size = Vector2(SIDE_W, h)
	_fit = minf(_board.size.x / _tex_size.x, _board.size.y / _tex_size.y)
	_zoom = clampf(_zoom, _fit, 0.75)
	if _zoom < _fit * 1.01 or _map.scale.x == 1.0:
		_zoom = _fit * 1.7
	_map.scale = Vector2.ONE * _zoom
	_place_bar()
	_clamp_map()
	_focus(false)


func _place_bar() -> void:
	_bar.reset_size()
	var bs := _bar.get_combined_minimum_size()
	_bar.size = bs
	# панель хода — в правом нижнем углу поля: там нет дорожки, старт с фишками остаётся на виду
	_bar.position = Vector2(_board.position.x + _board.size.x - bs.x - 14, _board.position.y + _board.size.y - bs.y - 14)
	_place_dice()
	if _dialog.visible:
		_dialog.reset_size()
		var ds := _dialog.get_combined_minimum_size()
		_dialog.size = ds
		_dialog.position = _board.position + (_board.size - ds) * 0.5
		if _dialog.get_meta("kind", "") in ["trap", "die"]:
			_dialog.position.y = _board.position.y + 56.0  # выбор клетки на поле — окно сверху, поле открыто


## Центр клетки на поле (пиксели текстуры поля).
func _cell_px(i: int) -> Vector2:
	var p: Vector2 = BRBoard.cell(i).pos
	return Vector2(p.x * 1280.0 / MAP_W * _tex_size.x, p.y * _tex_size.y)


## Печатное место на поле → прямоугольник на текстуре (чуть внутрь рамки ячейки).
func _px_rect(r: Rect2) -> Rect2:
	return r.grow(-10)


func _clamp_map() -> void:
	var ms := _tex_size * _zoom
	var p := _map.position
	p.x = (_board.size.x - ms.x) * 0.5 if ms.x <= _board.size.x else clampf(p.x, _board.size.x - ms.x, 0.0)
	# снизу поле можно «поднять» над панелью хода, сверху — чуть опустить
	p.y = clampf(p.y, _board.size.y - ms.y - BOTTOM_OVER, TOP_OVER) if ms.y > _board.size.y else clampf(p.y, _board.size.y - ms.y - BOTTOM_OVER, TOP_OVER)
	_map.position = p


## Камера к фишке текущего игрока (если игрок сам не двигал поле только что).
func _focus(animate: bool = true, seat: int = -1) -> void:
	if _v.is_empty() or Time.get_ticks_msec() < _manual_until:
		return
	var s := seat if seat >= 0 else int(_v["turn"])
	if s >= _v["players"].size():
		return
	var target_cell: int = int(_v["players"][s]["pos"])
	var want := _board.size * 0.5 - _cell_px(target_cell) * _zoom
	var old := _map.position
	_map.position = want
	_clamp_map()
	want = _map.position
	if not animate:
		return
	_map.position = old
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = create_tween()
	_cam_tween.tween_property(_map, "position", want, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Наведение на надпись поля: её кусок картинки — крупно и ровно в центре экрана.
func _hover_label(at: Vector2) -> void:
	var p := (at - _map.position) / _zoom
	var hit := -1
	for i in LABELS.size():
		if (LABELS[i][0] as Rect2).has_point(p):
			hit = i
			break
	if hit == _label_wait:
		return
	# сменилась надпись под курсором — прежняя подсказка прячется, новая покажется через LABEL_DELAY
	_label_wait = hit
	_label_since = Time.get_ticks_msec()
	_label_i = -1
	_label_view.visible = false


## Курсор держится над надписью LABEL_DELAY — крупно в центре экрана.
func _check_label() -> void:
	if _label_wait < 0 or _label_i == _label_wait or Time.get_ticks_msec() - _label_since < LABEL_DELAY:
		return
	if _dragging:
		_label_since = Time.get_ticks_msec()
		return
	var hit := _label_wait
	_label_i = hit
	var r: Rect2 = LABELS[hit][0]
	var rot: float = LABELS[hit][1]
	var at_tex := AtlasTexture.new()
	at_tex.atlas = (_map.get_child(0) as TextureRect).texture
	at_tex.region = Rect2(r.position * _tex_scale, r.size * _tex_scale)
	var upright := r.size if rot == 0.0 else Vector2(r.size.y, r.size.x)  # размер после поворота
	var k := minf(size.x * 0.6 / upright.x, size.y * 0.45 / upright.y)
	_label_view.texture = at_tex
	_label_view.size = r.size * k
	_label_view.pivot_offset = _label_view.size * 0.5
	_label_view.rotation = rot
	_label_view.position = size * 0.5 - _label_view.size * 0.5
	_label_view.visible = true


## Какая из подсвеченных клеток хода под точкой поля (индекс в prompt.data.cells), -1 — никакая.
func _step_at(at: Vector2) -> int:
	if _step_cells.is_empty() or _dice_rolling():
		return -1
	var mpd := (at - _map.position) / _zoom
	var best := -1
	var dist := 110.0
	for k in _step_cells.size():
		var dd := _cell_px(int(_step_cells[k])).distance_to(mpd)
		if dd < dist:
			dist = dd
			best = k
	return best


## Клик по полю: если просят тянуть карту — клик по нужной колоде тянет её.
func _click_board(at: Vector2) -> void:
	var p: Dictionary = _v.get("prompt", {})
	if p.is_empty() or int(p["seat"]) != _actor():
		return
	if str(p.get("kind", "")) == "die":
		# бросок: щёлкнули по одной из подсвеченных клеток — персонаж идёт туда
		var best_d := _step_at(at)
		if best_d >= 0:
			_step_cells = []
			_step_hl.queue_redraw()
			_board.mouse_default_cursor_shape = Control.CURSOR_ARROW
			_dialog.visible = false
			_send("br_answer", {"i": best_d})
		return
	if str(p.get("kind", "")) == "trap":
		# монета-ловушка: ближайшая к щелчку свободная клетка
		var mp0 := (at - _map.position) / _zoom
		var cells: Array = p.get("data", {}).get("cells", [])
		var best := -1
		var best_d := 90.0
		for k in cells.size():
			var dd := _cell_px(int(cells[k])).distance_to(mp0)
			if dd < best_d:
				best_d = dd
				best = k
		if best >= 0:
			_dialog.visible = false
			_send("br_answer", {"i": best + 1})
		return
	if str(p.get("kind", "")) != "draw":
		return
	var what := str(p.get("data", {}).get("what", ""))
	var deck: int = {"good": 0, "bad": 0, "shop": 1, "tadam": 2}.get(what, -1)
	var mp := (at - _map.position) / _zoom
	if deck >= 0 and (DECK_RECTS[deck] as Rect2).has_point(mp):
		_dialog.visible = false
		_send("br_answer", {"i": 0})


func _cam_button(what: String) -> void:
	match what:
		"−", "+":
			_zoom_at(_board.size * 0.5, 1.25 if what == "+" else 1.0 / 1.25)
		"Всё поле":
			_zoom_at(_board.size * 0.5, _fit / _zoom)
			_manual_until = Time.get_ticks_msec() + 60000  # смотрим поле — камера не дёргается минуту
		"К персонажу":
			_manual_until = 0
			if _zoom < _fit * 1.5:
				_zoom = _fit * 1.7
				_map.scale = Vector2.ONE * _zoom
			_focus(true)


func _zoom_at(at: Vector2, k: float) -> void:
	if _cam_tween:
		_cam_tween.kill()
	var old := _zoom
	_zoom = clampf(_zoom * k, _fit, 0.75)
	var anchor := (at - _map.position) / old
	_map.scale = Vector2.ONE * _zoom
	_map.position = at - anchor * _zoom
	_clamp_map()
	_manual_until = maxi(_manual_until, Time.get_ticks_msec() + 5000)


## Стрелки / WASD двигают поле.
func _process(delta: float) -> void:
	_check_label()
	if _step_hl:
		var show := not _dice_rolling()
		if show != _step_hl.visible:
			_step_hl.visible = show
			if show:
				_step_hl.queue_redraw()  # скрытый слой не перерисовывается — клетки могли смениться, пока кубик катился
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return  # пишут в чат
	var d := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	for pair in [[KEY_A, Vector2.LEFT], [KEY_D, Vector2.RIGHT], [KEY_W, Vector2.UP], [KEY_S, Vector2.DOWN]]:
		if Input.is_physical_key_pressed(pair[0]):
			d += pair[1]
	if d == Vector2.ZERO:
		return
	if _cam_tween:
		_cam_tween.kill()
	_map.position -= d.normalized() * 700.0 * delta
	_clamp_map()
	_manual_until = Time.get_ticks_msec() + 5000


func _on_board_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_at(mb.position, 1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				_press_at = mb.position
			elif mb.button_index == MOUSE_BUTTON_LEFT and mb.position.distance_to(_press_at) < 6.0:
				_click_board(mb.position)
			_dragging = mb.pressed
			_drag_last = mb.position
			_board.mouse_default_cursor_shape = Control.CURSOR_DRAG if mb.pressed else Control.CURSOR_ARROW
	elif e is InputEventMouseMotion and not _dragging:
		_hover_label((e as InputEventMouseMotion).position)
		# над клеткой, куда можно пойти, — курсор «рука» (можно щёлкнуть)
		_board.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _step_at((e as InputEventMouseMotion).position) >= 0 else Control.CURSOR_ARROW
	elif e is InputEventMouseMotion and _dragging:
		var mm := e as InputEventMouseMotion
		if _cam_tween:
			_cam_tween.kill()
		_map.position += mm.position - _drag_last
		_drag_last = mm.position
		_clamp_map()
		_manual_until = Time.get_ticks_msec() + 5000


# --- Роли ---------------------------------------------------------------------------

func _hotseat() -> bool:
	return Net.mode == "offline"


func _name(s: int) -> String:
	return str(_v["players"][s]["name"]) if s >= 0 and s < _v["players"].size() else "?"


## Кто сейчас действует за этим экраном (на одном компьютере — тот, от кого ждут хода).
func _actor() -> int:
	if not _hotseat():
		return int(_v["seat"])
	var p: Dictionary = _v.get("prompt", {})
	return int(p["seat"]) if not p.is_empty() else int(_v["turn"])


func _send(kind: String, arg: Dictionary = {}) -> void:
	if _hotseat():
		arg["as"] = _actor()
	Net.send_action(kind, arg)


func _color(s: int) -> Color:
	return BRStyle.PAWNS[s % BRStyle.PAWNS.size()]


# --- Состояние ----------------------------------------------------------------------

func _on_state(v: Dictionary) -> void:
	if v.get("game", "") != "brodilka":
		return
	var first := _v.is_empty()
	_v = v
	# новая карта «Хорошо/Плохо» или «Тадам» — сначала показываем её, потом персонаж идёт по её эффекту
	if not first and _card_id() != _card_key and _card_key != "":
		_show_card()
		_walk_after = Time.get_ticks_msec() + CARD_FIRST
	_sync_pawns(first)
	_show_roll()
	# хост уже посчитал эффект клетки, но показываем его, когда персонаж дошёл: пока идут — ждём
	if not first and _anyone_walking():
		_ui_waits = true
		return
	_apply_ui()


## Всё, что меняет клетка: Тадам, ловушки, монеты, журнал, карта, панель хода, выбор, итоги.
func _apply_ui() -> void:
	_ui_waits = false
	_sync_slots()
	_sync_traps()
	_update_players()
	_update_log()
	_show_card()
	_update_bar()
	_update_dialog()
	if _v["phase"] == "game_over" and not _celebrated:
		_celebrated = true
		_show_results()


func _anyone_walking() -> bool:
	for pw in _pawns:
		if (pw as Pawn).walking:
			return true
	return false


func _sync_pawns(first: bool) -> void:
	var pl: Array = _v["players"]
	while _pawns.size() < pl.size():
		var i := _pawns.size()
		var pw := Pawn.new()
		pw.setup(BRStyle.pawn_tex(i), _color(i))
		pw.nick = str(pl[i]["name"])
		_map.add_child(pw)
		_pawns.append(pw)
		_shown.append(int(pl[i]["pos"]))
		pw.position = _pawn_spot(i, _shown[i])
	var moved := -1
	for s in pl.size():
		var to: int = int(pl[s]["pos"])
		_pawns[s].active = s == int(_v["turn"]) and _v["phase"] != "game_over"
		_pawns[s].nick = str(pl[s]["name"])
		_pawns[s].stuck = pl[s]["stuck"]
		if first:
			_shown[s] = to
			_pawns[s].position = _pawn_spot(s, to)
			continue
		if to != _shown[s]:
			_walk(s, _shown[s], to)
			_shown[s] = to
			moved = s
	# раздвигаем фишки на одной клетке
	for s in pl.size():
		if s != moved and not _pawns[s].walking:
			var spot := _pawn_spot(s, _shown[s])
			if _pawns[s].position.distance_to(spot) > 1.0:
				create_tween().tween_property(_pawns[s], "position", spot, 0.25)
	_focus(not first, moved)


## Место фишки на клетке: несколько фишек на одной клетке стоят рядом.
func _pawn_spot(s: int, cell: int) -> Vector2:
	var same: Array[int] = []
	for o in _shown.size():
		if _shown[o] == cell:
			same.append(o)
	var k := same.find(s)
	var n := maxi(same.size(), 1)
	var off := (k - (n - 1) * 0.5) * 70.0 if k >= 0 else 0.0
	return _cell_px(cell) + Vector2(off - Pawn.W * 0.5, -Pawn.H + 30)


func _walk(s: int, from: int, to: int) -> void:
	var pw: Pawn = _pawns[s]
	pw.walking = true
	# сначала кубик долетает и показывает число, потом короткая пауза — и только тогда персонаж идёт
	if _dice_rolling():
		var waited := 0.0
		while _dice_rolling() and waited < 4.0:  # страховка: не ждём кубик вечно
			waited += get_process_delta_time()
			await get_tree().process_frame
		await get_tree().create_timer(AFTER_DIE).timeout
	while Time.get_ticks_msec() < _walk_after:  # сначала читают вытянутую карту
		await get_tree().process_frame
	if not is_instance_valid(pw):
		return
	var t := create_tween()
	if to > from and to - from <= 14:
		for c in range(from + 1, to + 1):
			var p := _cell_px(c) + Vector2(-Pawn.W * 0.5, -Pawn.H + 30)
			t.tween_property(pw, "position", p + Vector2(0, -36), STEP_TIME * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			t.tween_property(pw, "position", p, STEP_TIME * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			t.tween_callback(func(): Sfx.play("pawn_step", -10, 0.12, 0.05))  # приземлился на клетку — «тук»
	else:
		# назад, телепорт, смерч — прыжок по дуге
		var a := pw.position
		var b := _pawn_spot(s, to)
		var lift := minf(300.0, a.distance_to(b) * 0.4) + 60.0
		t.tween_method(func(k: float):
			pw.position = a.lerp(b, k) + Vector2(0, -sin(k * PI) * lift), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_SINE)
	t.tween_callback(func():
		pw.walking = false
		pw.position = _pawn_spot(s, to)
		Sfx.play("card_place", -8)
		# дошёл последний — короткая пауза, чтобы увидеть, куда наступил, и срабатывает клетка
		if _ui_waits and not _anyone_walking():
			get_tree().create_timer(AFTER_STEP).timeout.connect(func():
				if _ui_waits and not _anyone_walking():
					_apply_ui()))


## Кубик ещё в руке или катится (результат пока не виден).
func _dice_rolling() -> bool:
	for d in _dice3d:
		if (d as TossDie).state in ["dragging", "flying"]:
			return true
	return false


func _sync_slots() -> void:
	var td: Array = _v["tadam"]
	for i in 3:
		var tr: TextureRect = _slots[i]
		var id: int = int(td[i])
		tr.texture = load(BRData.tadam_image(id)) if id >= 0 else null
		tr.tooltip_text = ""
	BRStyle.clear(_tadam_row)
	for i in 3:
		var id: int = int(td[i])
		var mini := TextureRect.new()
		mini.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mini.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mini.custom_minimum_size = Vector2(46, 64) if _v["players"].size() > 5 else Vector2(62, 86)
		mini.texture = load(BRData.tadam_image(id)) if id >= 0 else load("res://games/brodilka/art/cards/tadam_back.webp")
		mini.modulate.a = 1.0 if id >= 0 else 0.25
		mini.tooltip_text = "" if id >= 0 else "Пустая ячейка"
		if id >= 0:
			_hoverable(mini)
		_tadam_row.add_child(mini)
	var dk: Array = _v.get("decks", [0, 0, 0])
	for i in 3:
		_deck_labels[i].text = str(dk[i])


func _sync_traps() -> void:
	BRStyle.clear(_traps)
	for c in _v.get("traps", []):
		var coin := BRStyle.Coin.new()
		coin.size = Vector2(70, 70)
		coin.position = _cell_px(int(c)) - Vector2(35, 35)
		coin.tooltip_text = "Монета-ловушка: остановившийся здесь пропускает ход"
		_traps.add_child(coin)


func _update_players() -> void:
	BRStyle.clear(_players_box)
	var pl: Array = _v["players"]
	var compact := pl.size() > 5  # 6–8 игроков — строки ниже, чтобы влез журнал
	for s in pl.size():
		var p: Dictionary = pl[s]
		var row := PanelContainer.new()
		var cur: bool = s == int(_v["turn"]) and _v["phase"] != "game_over"
		var sb := BRStyle.box(Color(BRStyle.GREEN, 0.28) if cur else Color(0, 0, 0, 0.0), 8, BRStyle.GREEN_DARK if cur else Color(BRStyle.WOOD, 0.25), 2 if cur else 1, 0.0)
		sb.set_content_margin_all(3 if compact else 6)
		row.add_theme_stylebox_override("panel", sb)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.tooltip_text = "Показать персонажа на поле"
		var seat := s
		row.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_manual_until = 0
				_focus(true, seat))
		var h := BRStyle.hbox(8)
		row.add_child(h)
		var face := TextureRect.new()
		face.texture = BRStyle.pawn_tex(s)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.custom_minimum_size = Vector2(24, 32) if compact else Vector2(34, 46)
		h.add_child(face)
		var col: BoxContainer = BRStyle.hbox(8) if compact else BRStyle.vbox(2)  # компактно — всё в одну строку
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nm := BRStyle.label(str(p["name"]), BRStyle.CAP if compact else BRStyle.BODY, BRStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold")
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if compact:
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.clip_text = true
		col.add_child(nm)
		var info := BRStyle.hbox(6)
		info.add_child(BRStyle.coin_label(int(p["coins"]), BRStyle.CAP))
		var st := []
		if p["stuck"]:
			st.append("жвачка")
		if int(p["skip"]) > 0:
			st.append("пропуск хода")
		if not compact:
			st.append("клетка %d" % int(p["pos"]))
		info.add_child(BRStyle.label(" · ".join(st), BRStyle.CAP, BRStyle.MUTED))
		col.add_child(info)
		h.add_child(col)
		for c in p["shop"]:
			var card := TextureRect.new()
			card.texture = load(BRData.shop_image(int(c)))
			card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			card.custom_minimum_size = Vector2(22, 31) if compact else Vector2(30, 42)
			card.mouse_filter = Control.MOUSE_FILTER_PASS
			_hoverable(card)
			h.add_child(card)
		_players_box.add_child(row)


func _update_log() -> void:
	var lines := []
	for e in _v["log"]:
		var s := int(e["seat"])
		lines.append("[b][color=#%s]%s[/color][/b] %s" % [_color(s).darkened(0.35).to_html(false), _name(s), e["text"]])
	_log_text.text = "\n".join(lines)


## Наведение на карту — она показывается крупно рядом (как в Gloom). Берётся текстура самой карты.
func _hoverable(tr: TextureRect) -> void:
	tr.mouse_entered.connect(func():
		if tr.texture == null:
			return
		var h := minf(size.y * 0.6, 440.0)
		var sz := Vector2(h * 0.72, h)
		var r := Rect2(tr.global_position, tr.size * tr.get_global_transform().get_scale())  # карты на поле масштабированы
		var x := r.end.x + 14 if r.get_center().x < size.x * 0.5 else r.position.x - sz.x - 14
		_preview.texture = tr.texture
		_preview.size = sz
		_preview.position = Vector2(clampf(x, 8, size.x - sz.x - 8), clampf(r.get_center().y - sz.y * 0.5, 8, size.y - sz.y - 8))
		_preview.visible = true)
	tr.mouse_exited.connect(func(): _preview.visible = false)


# --- Кубики и карты -----------------------------------------------------------------

## Кубики — TossDie (спрайт кубика «Перудо» + физика монетки): твой бросок — кубики яркие, их надо
## схватить, потянуть и отпустить; результат приходит с хоста, потом кубик возвращается на место. Не твой — полупрозрачные; чужие броски
## (и боты, и доплата на финише) показываются тем же полётом.
func _ensure_dice() -> void:
	if not _dice3d.is_empty():
		return
	for i in 2:
		var d := TossDie.new()
		add_child(d)
		move_child(d, _bar.get_index())  # над полем, под панелью хода и окнами
		var di := i
		d.thrown.connect(func(vel: Vector2): _on_die_thrown(di, vel))
		_dice3d.append(d)


func _dice_count() -> int:
	return 1 if str(_v.get("dice", "light")) in ["light", "finish"] else 2


func _my_roll() -> bool:
	return _v.get("phase", "") == "roll" and int(_v["turn"]) == _actor() and _v.get("prompt", {}).is_empty() and not bool(_v.get("spectator", false))


func _place_dice() -> void:
	if _dice3d.is_empty():
		return
	var n := _dice_count()
	for i in 2:
		var d: TossDie = _dice3d[i]
		d.home = Vector2(_bar.position.x + _bar.size.x * 0.5 + (i - (n - 1) * 0.5) * 84.0, _bar.position.y - 46.0)
		d.area = Rect2(_board.position, _board.size)
		if d.state in ["idle", "waiting"]:
			d.position = d.home - d.size * 0.5


func _update_dice() -> void:
	_ensure_dice()
	var n := _dice_count()
	var mine := _my_roll()
	for i in 2:
		var d: TossDie = _dice3d[i]
		d.visible = i < n or d.is_busy()
		if mine and not _thrown_mine and d.state == "idle":
			d.wait_for_roll()
		d.draggable = mine and not _thrown_mine and d.state == "waiting"
	_place_dice()


func _on_die_thrown(i: int, vel: Vector2) -> void:
	if not _my_roll() or _thrown_mine:
		return
	_thrown_mine = true
	for d in _dice3d:
		d.draggable = false
	if _dice_count() == 2:
		(_dice3d[1 - i] as TossDie).throw(vel.rotated(randf_range(-0.35, 0.35)) * randf_range(0.85, 1.1))
	_send("br_roll")


func _show_roll() -> void:
	_update_dice()
	var roll: Array = _v.get("last_roll", [])
	# новый бросок — только новый номер из правил (а не любое обновление: иначе кубик бросался заново
	# и «менял» значение, а первый бросок партии не получал результата и катился без конца)
	var no := int(_v.get("roll_no", 0))
	if no == _roll_no:
		return
	var first := _roll_no < 0  # открыли стол посреди партии — старый бросок не показываем
	_roll_no = no
	if roll.is_empty():
		return
	for i in mini(roll.size(), 2):
		var d: TossDie = _dice3d[i]
		d.visible = true
		var face := int(roll[i])
		if d.state == "flying":
			d.set_result(face)  # свой бросок — кубик остановится на выпавшем
		elif first:
			continue
		else:
			var vel := (d.area.get_center() - d.home).normalized().rotated(randf_range(-0.7, 0.7)) * randf_range(800.0, 1300.0)
			d.throw(vel, face)
	_thrown_mine = false


## Ключ последней вытянутой карты (по её номеру) — «none», если карт ещё не тянули.
func _card_id() -> String:
	var c: Dictionary = _v.get("last_card", {})
	return "none" if c.is_empty() else "%d/%s/%d" % [int(c.get("no", 0)), c["deck"], int(c["id"])]


func _show_card() -> void:
	var c: Dictionary = _v.get("last_card", {})
	# крупно — только новая карта (по её номеру); при входе в партию прежнюю не показываем
	var key := _card_id()
	if key == _card_key:
		return
	var fresh := _card_key != ""
	_card_key = key
	if not fresh or c.is_empty():
		return
	var path := BRData.gb_image(int(c["id"])) if c["deck"] == "gb" else BRData.tadam_image(int(c["id"]))
	var tr := TextureRect.new()
	tr.texture = load(path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var h := minf(_board.size.y * 0.62, 420.0)
	tr.size = Vector2(h * 0.72, h)
	tr.pivot_offset = tr.size * 0.5
	tr.position = _board.position + (_board.size - tr.size) * 0.5 - Vector2(0, 30)
	if c["deck"] == "gb" and c.get("side", "good") == "bad":
		tr.rotation = PI  # «Плохо» напечатано вверх ногами — переворачиваем карту
	tr.scale = Vector2(0.3, 0.3)
	tr.modulate.a = 0.0
	_fx.add_child(tr)
	Sfx.play("card_place", -2)
	var t := create_tween()
	t.set_parallel()
	t.tween_property(tr, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(tr, "modulate:a", 1.0, 0.2)
	t.set_parallel(false)
	t.tween_interval(3.6)  # вдвое дольше, чтобы все успели прочитать
	t.tween_property(tr, "modulate:a", 0.0, 0.35)
	t.tween_callback(tr.queue_free)
	# клик по карте — убрать её раньше
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	tr.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tr.tooltip_text = "Щёлкни, чтобы убрать"
	tr.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			t.kill()
			_walk_after = 0  # убрали карту — персонаж идёт сразу
			var f := tr.create_tween()
			f.tween_property(tr, "modulate:a", 0.0, 0.2)
			f.tween_callback(tr.queue_free))


# --- Панель хода --------------------------------------------------------------------

func _dice_text(mode: String) -> String:
	return {"light": "1 кубик", "grey": "2 кубика — выбери один", "black": "2 кубика — сумма", "finish": "бросок на финиш: нужна 6"}.get(mode, "")


func _update_bar() -> void:
	var me := _actor()
	var turn := int(_v["turn"])
	var phase: String = _v["phase"]
	var used: Array = _v.get("used", [])
	var my_shop: Array = _v["players"][me]["shop"] if me < _v["players"].size() else []
	var key := "%s/%d/%d/%d/%s/%s/%d" % [phase, turn, me, int(_v["players"][me]["coins"]) if me < _v["players"].size() else 0, str(used), str(my_shop), _v["log"].size()]
	if key == _bar_key:
		return
	_bar_key = key
	BRStyle.clear(_bar_box)
	_bar.visible = phase != "game_over"
	if phase == "game_over":
		return
	var mine := turn == me
	var who := "Твой ход" if mine and not _hotseat() else "Ход: " + _name(turn)
	if _top:
		var nm := "клеток до финиша: %d" % (BRBoard.finish() - int(_v["players"][turn]["pos"]))
		_top.info.text = who
		_top.info.tooltip_text = nm
	var head := BRStyle.hbox(10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	var dot := ColorRect.new()
	dot.color = _color(turn)
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(dot)
	head.add_child(BRStyle.label(who, BRStyle.BODY, BRStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
	if phase == "roll":
		head.add_child(BRStyle.label("· " + _dice_text(str(_v.get("dice", ""))), BRStyle.BODY, BRStyle.MUTED))
	_bar_box.add_child(head)
	var row := BRStyle.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if phase == "roll" and mine:
		var mode := str(_v.get("dice", ""))
		row.add_child(BRStyle.label("Схвати кубик%s мышью и брось ↑" % ("и" if mode in ["grey", "black"] else ""), BRStyle.BODY, BRStyle.GREEN_DARK, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
	elif phase == "free" and mine:
		for i in my_shop.size():
			var c: Dictionary = BRData.SHOP[int(my_shop[i])]
			if c.kind != "active":
				continue
			var cb := BRStyle.button("%s%s" % [c.name, (" · %d" % int(c.cost)) if int(c.cost) > 0 else ""], BRStyle.CAP)
			cb.tooltip_text = c.text
			cb.disabled = used.has(c.id) or int(_v["players"][me]["coins"]) < int(c.cost) or not _card_usable(me, c.id)
			var idx := i
			var id: String = c.id
			cb.pressed.connect(func(): _use_card(idx, id))
			row.add_child(cb)
		var end := BRStyle.primary("Закончить ход", BRStyle.BODY, 200)
		end.pressed.connect(func(): _send("br_end"))
		row.add_child(end)
	else:
		var p: Dictionary = _v.get("prompt", {})
		var wait_seat := int(p["seat"]) if not p.is_empty() else turn
		row.add_child(BRStyle.label("Ждём: %s…" % _name(wait_seat), BRStyle.BODY, BRStyle.MUTED))
	_bar_box.add_child(row)
	_place_bar.call_deferred()


## Цели активной карты Лавки (как BRRules.use_targets — считаем на клиенте).
func _use_targets(me: int, id: String) -> Array[int]:
	if id in BRRules.SELF_CARDS:
		return []
	var a := _view_arrays()
	return BRRules.card_targets(me, id, a[0], a[1], a[2], a[3])


func _card_usable(me: int, id: String) -> bool:
	var a := _view_arrays()
	return BRRules.card_usable(me, id, a[0], a[1], a[2], a[3])


## Из вида партии — позиции, «Жвачка», карты Лавки и монеты по местам (как у BRRules).
func _view_arrays() -> Array:
	var p := []
	var st := []
	var sh := []
	var cn := []
	for pl in _v["players"]:
		p.append(int(pl["pos"]))
		st.append(bool(pl["stuck"]))
		sh.append(pl["shop"])
		cn.append(int(pl["coins"]))
	return [p, st, sh, cn]


func _use_card(idx: int, id: String) -> void:
	var targets := _use_targets(_actor(), id)
	if id in BRRules.SELF_CARDS or targets.size() <= 1:
		_send("br_use", {"idx": idx, "target": targets[0] if targets.size() == 1 else -1})
		return
	_open_dialog("На кого сыграть «%s»?" % BRData.SHOP[BRData.shop_index(id)].name, targets.map(func(s): return _name(s)), func(k: int):
		_send("br_use", {"idx": idx, "target": targets[k]}), true)


# --- Окно выбора --------------------------------------------------------------------

func _update_dialog() -> void:
	var p: Dictionary = _v.get("prompt", {})
	var cells: Array = []
	if not p.is_empty() and str(p.get("kind", "")) == "die" and int(p["seat"]) == _actor():
		cells = p.get("data", {}).get("cells", [])
	if cells != _step_cells:
		_step_cells = cells
		_step_hl.queue_redraw()
		if cells.is_empty() and not _dragging:
			_board.mouse_default_cursor_shape = Control.CURSOR_ARROW
	if p.is_empty() or int(p["seat"]) != _actor() or _v["phase"] == "game_over":
		if _dialog.get_meta("local", false):
			return
		_dialog.visible = false
		return
	_open_dialog(str(p["text"]), p["options"], func(k: int): _send("br_answer", {"i": k}), false, str(p.get("kind", "")), p.get("data", {}))


func _open_dialog(text: String, options: Array, on_pick: Callable, local: bool, kind: String = "", data: Dictionary = {}) -> void:
	BRStyle.clear(_dialog)
	_dialog.set_meta("local", local)
	_dialog.set_meta("kind", kind)
	var col := BRStyle.vbox(14)
	col.custom_minimum_size.x = 420
	_dialog.add_child(col)
	if _hotseat():
		col.add_child(BRStyle.label("Выбирает: " + _name(_actor()), BRStyle.CAP, BRStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	if kind == "draw":
		text += "
(кнопкой ниже или щелчком по колоде на поле)"
	if kind == "die":
		options = []  # клетку выбирают щелчком по подсвеченной клетке поля
	if kind == "trap":
		options = [options[0]]  # клетку выбирают щелчком по полю, кнопка — «куда-нибудь перед соперником»
	var t := BRStyle.label(text, BRStyle.BODY, BRStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, "bold")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(t)
	# Лавка Джо: открытые карты картинками — щёлкни, чтобы взять (наведение — крупно)
	if kind == "buy" and data.has("offer"):
		var cards := BRStyle.hbox(16)
		cards.alignment = BoxContainer.ALIGNMENT_CENTER
		var offer: Array = data["offer"]
		for j in offer.size():
			var tr := TextureRect.new()
			tr.texture = BRStyle.shop_card_tex(BRData.shop_image(int(offer[j])))
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.custom_minimum_size = Vector2(150, 215)
			tr.mouse_filter = Control.MOUSE_FILTER_STOP
			tr.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			_hoverable(tr)
			var jj := j + 1
			tr.gui_input.connect(func(e: InputEvent):
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					_preview.visible = false
					_dialog.visible = false
					on_pick.call(jj))
			# карта со скруглёнными углами, тонкой деревянной рамкой и тенью — лежит на окне, а не торчит жёлтым прямоугольником
			var frame := PanelContainer.new()
			var fsb := BRStyle.box(BRStyle.WOOD_DARK, 12, BRStyle.WOOD_DARK, 0, 0.35)
			fsb.set_content_margin_all(0)
			frame.add_theme_stylebox_override("panel", fsb)
			frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame.add_child(tr)
			cards.add_child(frame)
		col.add_child(cards)
		options = [options[0]]  # дальше — только «Ничего не брать»
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for k in options.size():
		var label := str(options[k])
		if kind == "die":
			label = "Идти на " + label
		# главный вариант — первый «положительный» (не «ничего», не «нет»)
		var main: bool = k == (1 if options.size() > 1 and kind in ["buy", "yesno", "boost"] else 0) and kind not in ["tornado", "pay", "target", "duel_target", "steal", "burn", "discard", "duel_prize"] 			and not (kind == "buy" and data.has("offer"))  # в Лавке главное — сами карты, «ничего не брать» тихая
		var b := BRStyle.primary(label, BRStyle.BODY) if main else BRStyle.button(label, BRStyle.BODY)
		var kk := k
		b.pressed.connect(func():
			_dialog.visible = false
			_dialog.set_meta("local", false)
			on_pick.call(kk))
		flow.add_child(b)
	col.add_child(flow)
	if local:
		var cancel := BRStyle.button("Отмена", BRStyle.CAP)
		cancel.theme_type_variation = "QuietButton"
		cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cancel.pressed.connect(func():
			_dialog.visible = false
			_dialog.set_meta("local", false))
		col.add_child(cancel)
	_dialog.visible = true
	_place_bar.call_deferred()


# --- Итоги --------------------------------------------------------------------------

func _show_results() -> void:
	var w := int(_v["winner"])
	Sfx.victory()
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := BRStyle.panel(28)
	center.add_child(panel)
	var col := BRStyle.vbox(16)
	col.custom_minimum_size.x = 440
	panel.add_child(col)
	var face := TextureRect.new()
	face.texture = BRStyle.pawn_tex(maxi(w, 0))
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.custom_minimum_size = Vector2(0, 180)
	col.add_child(face)
	col.add_child(BRStyle.label("Победа: %s!" % _name(w), BRStyle.H1, BRStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, "title"))
	var why := ""
	for e in _v["log"]:
		if int(e["seat"]) == w and str(e["text"]).begins_with("ПОБЕДА"):
			why = str(e["text"]).trim_prefix("ПОБЕДА — ")
	if why != "":
		col.add_child(BRStyle.label(why, BRStyle.BODY, BRStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var row := BRStyle.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if Net.is_host():
		var again := BRStyle.primary("Новая партия", BRStyle.BODY, 190)
		again.pressed.connect(Net.end_game)
		row.add_child(again)
		var back := BRStyle.button("К выбору игры" if Net.is_party() else "В меню", BRStyle.BODY, 190)
		back.pressed.connect(func(): app.back_to_menu())
		row.add_child(back)
	else:
		var leave := BRStyle.button("Покинуть пати", BRStyle.BODY, 190)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
		row.add_child(leave)
	col.add_child(row)


## Фишка: персонаж с листа, под ним тень и кольцо цвета игрока; фишка хода покачивается.
class Pawn:
	extends Control

	const W := 150.0
	const IDLE_ALPHA := 0.85  # не ходят — чуть прозрачнее и темнее, но хорошо видны на поле
	const IDLE_TINT := Color(0.72, 0.7, 0.68)
	const H := 240.0

	var color := Color.WHITE
	var walking := false
	var stuck := false:
		set(v):
			stuck = v
			queue_redraw()
	var active := false:
		set(v):
			if v == active:
				return
			active = v
			_bob()
			# ходящий — яркий и поверх всех, остальные полупрозрачные (фишки часто стоят кучей)
			if v:
				_to_front()
			_tex.modulate = Color.WHITE if v else IDLE_TINT  # картинка темнее — выделяется на светлом поле
			create_tween().tween_property(self, "modulate:a", 1.0 if v else IDLE_ALPHA, 0.25)
			queue_redraw()
	var nick := "":
		set(v):
			nick = v
			if _nick:
				_nick.text = v
	var _nick: Label
	var _tex: TextureRect
	var _bob_tween: Tween

	func setup(tex: Texture2D, c: Color) -> void:
		color = c
		size = Vector2(W, H)
		modulate.a = IDLE_ALPHA
		mouse_filter = Control.MOUSE_FILTER_PASS  # наведение — показать ник; перетаскивание поля идёт дальше
		mouse_entered.connect(func():
			_nick.visible = true
			_to_front())
		mouse_exited.connect(func():
			_nick.visible = false
			if not active:
				var p := get_parent()
				for n in p.get_children():  # ходящий снова поверх остальных
					if n is Pawn and n.active:
						n._to_front())
		_nick = Label.new()
		_nick.text = nick
		_nick.visible = false
		_nick.add_theme_font_size_override("font_size", 40)
		_nick.add_theme_font_override("font", BRStyle.font("bold"))
		_nick.add_theme_color_override("font_color", BRStyle.PARCH)
		_nick.add_theme_color_override("font_outline_color", BRStyle.WOOD_DARK)
		_nick.add_theme_constant_override("outline_size", 14)
		_nick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_nick.position = Vector2(-120, -58)
		_nick.size = Vector2(W + 240, 56)
		_nick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_nick)
		_tex = TextureRect.new()
		_tex.texture = tex
		_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_tex.size = Vector2(W, H - 14)
		_tex.pivot_offset = Vector2(W * 0.5, H - 14)
		_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tex.modulate = IDLE_TINT
		add_child(_tex)
		move_child(_nick, -1)  # ник — поверх картинки

	## Поверх других фишек — порядком на поле, а не z_index (тот поднял бы фишку и над окнами интерфейса).
	func _to_front() -> void:
		if get_parent():
			get_parent().move_child(self, -1)

	func _bob() -> void:
		if _bob_tween:
			_bob_tween.kill()
		_tex.position.y = 0
		if not active:
			return
		_bob_tween = create_tween().set_loops()
		_bob_tween.tween_property(_tex, "position:y", -14.0, 0.45).set_trans(Tween.TRANS_SINE)
		_bob_tween.tween_property(_tex, "position:y", 0.0, 0.45).set_trans(Tween.TRANS_SINE)

	func _draw() -> void:
		var c := Vector2(W * 0.5, H - 14)
		draw_set_transform(c, 0, Vector2(1, 0.38))
		draw_circle(Vector2.ZERO, W * 0.42, Color(0, 0, 0, 0.35))
		draw_arc(Vector2.ZERO, W * 0.44, 0, TAU, 40, Color("e88cc8") if stuck else color, 10.0 if active else 6.0, true)
		draw_set_transform(Vector2.ZERO)
