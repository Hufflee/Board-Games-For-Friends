extends Control
## Стол «Стиллиона»: игроки по кругу, в центре пушка (STCannon), сверху вопрос, снизу поле ответа,
## справа — уже названные ответы. Состояние приходит с хоста (Net.state_changed); фитиль между
## обновлениями досчитывается локально, чтобы пушка надувалась плавно.

const SND := "res://games/stillion/audio/"

var app: Node
var _v: Dictionary = {}
var _top: TopBar
var _stage: Control  # область сцены: пушка + игроки
## Реплики пушки пока горит фитиль (закипает) …
const CANNON_CAPTIONS := [
	"Мистер Пушка теряет терпение", "Мистер Пушка ждёт ответа",
	"Мистер Пушка начинает закипать", "Не испытывайте терпение Мистера Пушки",
	"Мистер Пушка уже краснеет", "Мистер Пушка готовит сюрприз", "Мистер Пушка сейчас бабахнет!"
]
## … и после выстрела (уже бахнул и ворчит).
const CANNON_AFTER_BOOM := [
	"Мистер Пушка недоволен", "Вы разозлили Мистера Пушку", "Мистер Пушка сердится всерьёз",
	"Мистер Пушка предупреждал", "Мистер Пушка не любит ждать"
]
var _cannon_caption: Label
var _caption_target := -1
var _caption_q := -1
var _caption_index := -1
var _caption_boom := -1  # номер события выстрела, для которого уже выбрана реплика «после»
var _boom_index := -1
var _cannon: STCannon
var _seats: Array = []  # Control на каждого игрока
var _q_cat: Label
var _q_text: Label
var _q_bar: ProgressBar
var _answer: LineEdit
var _appeal: Button
var _send: Button
var _who: Label
var _used_box: VBoxContainer
var _fx: Control  # всплывающие надписи
var _fuse_t0 := 0.0
const FUSE_DB := -16.0  # громкость фитиля, когда пушка надута до предела
var _since_state := 0.0  # сколько фитиль горел у нас после последнего состояния (на паузе не растёт)
var _last_no := -1
var _q_no := -1
var _q_shown := ""  # текст вопроса на карточке (для анимации появления после «Новый вопрос!»)
var _prev_phase := ""
var _snd: Dictionary = {}
var _fuse_snd: AudioStreamPlayer
var _over: Control


func _ready() -> void:
	add_child(STStyle.Backdrop.new())
	for n in ["boom", "deflate", "ding", "buzz"]:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = load(SND + n + ".wav")
		add_child(p)
		_snd[n] = p
	_fuse_snd = AudioStreamPlayer.new()
	_fuse_snd.bus = "SFX"
	_fuse_snd.volume_db = FUSE_DB
	var loop: AudioStreamWAV = load(SND + "fuse.wav")
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = loop.get_length() * loop.mix_rate
	_fuse_snd.stream = loop
	add_child(_fuse_snd)
	# сцена
	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.offset_top = TopBar.HEIGHT + 110
	_stage.offset_right = -250
	_stage.offset_bottom = -96
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_cannon = STCannon.new()
	_stage.add_child(_cannon)
	_cannon_caption = STStyle.label("", 19, STStyle.PAPER, HORIZONTAL_ALIGNMENT_CENTER, "bold")
	_cannon_caption.add_theme_color_override("font_outline_color", STStyle.INK)
	_cannon_caption.add_theme_constant_override("outline_size", 6)
	_cannon_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cannon_caption.visible = false
	_stage.add_child(_cannon_caption)
	_stage.resized.connect(_layout)
	# вопрос
	var qwrap := MarginContainer.new()
	qwrap.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	qwrap.offset_top = TopBar.HEIGHT + 4
	qwrap.offset_left = 120
	qwrap.offset_right = -370
	add_child(qwrap)
	var qcard := STStyle.panel(12)
	qwrap.add_child(qcard)
	var qcol := STStyle.vbox(4)
	qcard.add_child(qcol)
	_q_cat = STStyle.label("", STStyle.CAP, STStyle.RED, HORIZONTAL_ALIGNMENT_CENTER, "bold")
	qcol.add_child(_q_cat)
	_q_text = STStyle.label("", STStyle.H2, Color(0, 0, 0, 0), HORIZONTAL_ALIGNMENT_CENTER, "bold")
	_q_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	qcol.add_child(_q_text)
	_q_bar = ProgressBar.new()
	_q_bar.show_percentage = false
	_q_bar.custom_minimum_size.y = 8
	_q_bar.max_value = STRules.FUSE_START
	var fill := StyleBoxFlat.new()
	fill.bg_color = STStyle.MUSTARD
	fill.set_corner_radius_all(4)
	_q_bar.add_theme_stylebox_override("fill", fill)
	var bgq := StyleBoxFlat.new()
	bgq.bg_color = Color(STStyle.ink(), 0.15)
	bgq.set_corner_radius_all(4)
	_q_bar.add_theme_stylebox_override("background", bgq)
	_q_bar.tooltip_text = "Сколько времени осталось до выстрела"
	qcol.add_child(_q_bar)
	# уже названные
	var side := STStyle.panel(12)
	side.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -240
	side.offset_right = -16
	side.offset_top = TopBar.HEIGHT + 4
	side.offset_bottom = -96
	add_child(side)
	var scol := STStyle.vbox(8)
	side.add_child(scol)
	scol.add_child(
		STStyle.label("Уже назвали", STStyle.BODY, Color(0, 0, 0, 0), HORIZONTAL_ALIGNMENT_LEFT, "title")
	)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scol.add_child(scroll)
	_used_box = STStyle.vbox(6)
	_used_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_used_box)
	var legend := STStyle.hbox(4)
	for r in STQuestions.RARITIES:
		legend.add_child(STStyle.rarity_chip(r, ["1", "2", "3", "4"][STQuestions.RARITIES.find(r)]))
	var lg := STStyle.label("очки шкалы", STStyle.CAP, STStyle.muted())
	legend.add_child(lg)
	scol.add_child(legend)
	_appeal = STStyle.button("Оспорить ответ", STStyle.CAP)
	_appeal.tooltip_text = "Повторная подробная проверка Jev: один раз для отклонённого ответа. Фитиль на время проверки остановлен."
	_appeal.visible = false
	_appeal.pressed.connect(func(): Net.send_action("st_appeal", {"as": int(_v.target)}))
	scol.add_child(_appeal)
	# поле ответа
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", STStyle.box(STStyle.paper(), 14, 4, 5, 12))
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 120
	bottom.offset_right = -370
	bottom.offset_top = -84
	bottom.offset_bottom = -12
	add_child(bottom)
	var brow := STStyle.hbox(12)
	bottom.add_child(brow)
	_who = STStyle.label("", STStyle.BODY, Color(0, 0, 0, 0), HORIZONTAL_ALIGNMENT_LEFT, "bold")
	_who.custom_minimum_size.x = 210
	_who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brow.add_child(_who)
	_answer = LineEdit.new()
	_answer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_answer.placeholder_text = "Печатайте ответ и жмите Enter"
	_answer.add_theme_font_size_override("font_size", 22)
	_answer.max_length = 60
	_answer.text_submitted.connect(func(_t): _submit())
	brow.add_child(_answer)
	_send = STStyle.primary("Ответить!", STStyle.BODY, 150)
	_send.pressed.connect(_submit)
	brow.add_child(_send)
	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)
	add_child(STStyle.FilmFX.new())
	# плёнка z=50 покрывает сцену, служебные окна и пауза остаются выше
	# В светлой теме тёмные часы/название не должны теряться на красном занавесе.
	var top_background: StyleBox = null
	if not STStyle.dark():
		var paper_strip := StyleBoxFlat.new()
		paper_strip.bg_color = STStyle.paper()
		paper_strip.content_margin_left = 16
		paper_strip.content_margin_right = 12
		paper_strip.content_margin_top = 6
		paper_strip.content_margin_bottom = 6
		top_background = paper_strip
	_top = TopBar.make(
		self, "Стиллион", func(t, z): return STStyle.button(t, z), top_background, STStyle.ink(), STStyle.font("title")
	)
	STStyle.restyle_chat(_top.chat)
	for entry in [["Правила", app.show_rules], ["Настройки", app.show_settings]]:
		var b := STStyle.button(entry[0], STStyle.CAP)
		b.pressed.connect(entry[1])
		_top.actions.add_child(b)
	var theme_btn := STStyle.button("☾" if not STStyle.dark() else "☀", STStyle.CAP)
	theme_btn.tooltip_text = "Светлая / тёмная тема"
	theme_btn.pressed.connect(
		func():
			Prefs.set_value("theme_mode", "light" if STStyle.dark() else "dark")
			app.restyle()
	)
	_top.actions.add_child(theme_btn)
	var leave := STStyle.button("Выйти", STStyle.CAP)
	leave.theme_type_variation = "QuietButton"
	LeaveGuard.wire(
		leave, "Выйти из партии?", "Игра закончится, вы вернётесь в меню.", func(): app.back_to_hub()
	)
	_top.actions.add_child(leave)
	Net.state_changed.connect(_on_state)
	_on_state(Net.view)


func _on_state(v: Dictionary) -> void:
	if v.is_empty() or v.get("game", "") != "stillion":
		return
	var first := _v.is_empty()
	_v = v
	_fuse_t0 = float(v.fuse_t)
	_since_state = 0.0
	_build_seats()
	_update_question()
	_update_used()
	_update_input()
	var last: Dictionary = v.get("last", {})
	if not first and int(last.get("no", -1)) != _last_no:
		_play_event(last)
	_last_no = int(last.get("no", -1))
	if v.phase == "new_q" and _prev_phase != "new_q" and not first:
		_popup(_stage.size * Vector2(0.5, 0.3), "Новый вопрос!", STStyle.MUSTARD, 52)
	_prev_phase = str(v.phase)
	var tgt: int = v.target
	_top.info.text = "Победа!" if v.phase == "game_over" else "Пушка целится: %s" % str(v.players[tgt].name)
	if v.phase == "game_over":
		_show_over()


func _process(delta: float) -> void:
	if _v.is_empty():
		return
	var phase: String = _v.phase
	var burning := phase == "fuse" and not _game_paused()  # на паузе хоста время стоит и у нас
	if burning:
		_since_state += delta
	var t := _fuse_t0 + (_since_state if phase == "fuse" else 0.0)
	var fuse_len := float(_v.fuse_len)
	_cannon.inflate = (
		clampf(t / fuse_len, 0.0, 1.0)
		if phase in ["fuse", "check"]
		else (0.0 if phase != "boom" else _cannon.inflate)
	)
	_cannon.burning = burning
	# шипение фитиля: в начале вдвое тише, с надуванием пушки — громче (до FUSE_DB)
	_fuse_snd.volume_db = FUSE_DB + linear_to_db(lerpf(0.5, 1.0, _cannon.inflate))
	if burning and not _fuse_snd.playing:
		_fuse_snd.play()
	elif not burning and _fuse_snd.playing:
		_fuse_snd.stop()
	var left := fuse_len - t
	_cannon.fuse_left = maxf(0.0, left)
	_cannon.fuse_duration = fuse_len
	_update_cannon_caption(t, fuse_len, phase)
	_q_bar.max_value = fuse_len
	_q_bar.value = clampf(left, 0.0, fuse_len)
	_q_bar.modulate.a = 0.0 if phase == "new_q" else 1.0  # фитиль появляется вместе с вопросом
	if _seats.size() > int(_v.target):
		_cannon.aim = (_seat_center(int(_v.target)) - _cannon.position - _cannon.size * 0.5).angle()


# --- игроки ---------------------------------------------------------------------------


func _build_seats() -> void:
	var pl: Array = _v.players
	if _seats.size() != pl.size():
		for s in _seats:
			(s as Control).queue_free()
		_seats.clear()
		for i in pl.size():
			var seat := Seat.new()
			seat.index = i
			seat.compact_answers = pl.size() >= 7
			_stage.add_child(seat)
			_seats.append(seat)
		_layout()
	for i in pl.size():
		var seat: Seat = _seats[i]
		seat.data = pl[i]
		seat.max_lives = int(_v.max_lives)
		seat.meter_max = int(_v.meter_max)
		seat.targeted = i == int(_v.target) and _v.phase != "game_over"
		seat.mine = i == int(_v.get("seat", -1)) and Net.mode != "offline"
		seat.queue_redraw()


## Игроки по эллипсу вокруг пушки; первый — снизу, дальше по часовой стрелке.
func _layout() -> void:
	var sz := _stage.size
	var crowd := _seats.size() > 5
	var cs := Vector2(
		minf(sz.x * (0.26 if crowd else 0.3), 340.0), minf(sz.y * (0.32 if crowd else 0.36), 220.0)
	)
	_cannon.size = cs
	_cannon.position = sz * 0.5 - cs * 0.5
	_cannon_caption.position = Vector2(maxf(0.0, sz.x * 0.5 - 220.0), maxf(4.0, _cannon.position.y - 28.0))
	_cannon_caption.size = Vector2(minf(440.0, sz.x), 28.0)
	for i in _seats.size():
		var seat: Seat = _seats[i]
		seat.size = Seat.SIZE
		seat.scale = Vector2.ONE * _seat_k()
		seat.position = _seat_pos(i)


## Левый верхний угол места: по эллипсу, но целиком внутри сцены; первый — снизу, дальше по часовой.
## Одна реплика на наведение, появляется вместе с началом смены выражений.
func _update_cannon_caption(elapsed: float, duration: float, phase: String) -> void:
	var target: int = int(_v.target)
	var question_no: int = int(_v.question.no)
	if target != _caption_target or question_no != _caption_q:
		_caption_target = target
		_caption_q = question_no
		_caption_index = (_caption_index + randi_range(1, CANNON_CAPTIONS.size() - 1)) % CANNON_CAPTIONS.size()
		_cannon_caption.text = CANNON_CAPTIONS[_caption_index]
	if phase == "boom":
		# после выстрела — одна реплика «после», своя на каждый выстрел
		var no := int(_v.get("last", {}).get("no", -1))
		if no != _caption_boom:
			_caption_boom = no
			_boom_index = (_boom_index + randi_range(1, CANNON_AFTER_BOOM.size() - 1)) % CANNON_AFTER_BOOM.size()
		_cannon_caption.text = CANNON_AFTER_BOOM[_boom_index]
		_cannon_caption.visible = true
		return
	_cannon_caption.text = CANNON_CAPTIONS[_caption_index]
	var start := maxf(0.0, duration - 3.0) * STCannon.TIMING_ADVANCE
	_cannon_caption.visible = phase in ["fuse", "check"] and elapsed > start


func _seat_pos(i: int) -> Vector2:
	var n := maxi(1, _seats.size())
	var sz := _stage.size
	var a := PI * 0.5 + TAU * i / n + (PI / n if n % 2 == 0 and n > 2 else 0.0)  # y вниз: π/2 — низ; при чётном числе — по диагоналям, никто не стоит под вопросом
	var half := (sz - Seat.SIZE * _seat_k()) * 0.5
	var pos := half + Vector2(cos(a) * half.x * 0.96, sin(a) * half.y)
	# Восемь мест: оставляем воздух между ответом нижнего соседа и шкалой верхнего.
	if n == 8:
		if i in [1, 6]:
			pos.y += 12.0
		elif i in [2, 5]:
			pos.y -= 12.0
	return pos


## Чем больше игроков, тем мельче места — чтобы круг не слипался.
func _seat_k() -> float:
	return 1.0 if _seats.size() <= 4 else (0.85 if _seats.size() <= 6 else 0.74)


## Куда целится пушка и где всплывают надписи — туловище персонажа.
func _seat_center(i: int) -> Vector2:
	return _seat_pos(i) + Seat.SIZE * _seat_k() * Vector2(0.5, 0.42)


# --- вопрос, ответы, ввод -------------------------------------------------------------


func _game_paused() -> bool:
	return Net.paused if Net.is_host() else bool(_v.get("game_paused", false))


## Карточка вопроса; во время паузы «Новый вопрос!» вопрос скрыт (хост его ещё не присылает).
func _update_question() -> void:
	var q: Dictionary = _v.question
	if _v.phase == "new_q":
		_q_cat.text = ""
		_q_text.text = "Новый вопрос!"
		_q_shown = ""
		return
	_q_cat.text = str(q.cat).to_upper()
	_q_text.text = str(q.text)
	if str(q.text) != _q_shown:
		if _q_no >= 0:
			Sfx.play("card_flip", -6)
		_q_text.pivot_offset = _q_text.size * 0.5
		_q_text.scale = Vector2(1.2, 1.2)
		(
			create_tween()
			. tween_property(_q_text, "scale", Vector2.ONE, 0.35)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_OUT)
		)
		_q_shown = str(q.text)
	_q_no = int(q.no)


func _update_used() -> void:
	STStyle.clear(_used_box)
	var used: Array = _v.used
	for k in range(used.size() - 1, -1, -1):
		var u: Dictionary = used[k]
		var row := STStyle.hbox(6)
		var chip := STStyle.rarity_chip(str(u.rarity), "")
		chip.custom_minimum_size.x = 12
		(chip.get_child(0) as Label).text = " "
		chip.tooltip_text = STQuestions.RARITY_NAMES.get(str(u.rarity), "")
		row.add_child(chip)
		var l := STStyle.label(str(u.name), STStyle.CAP, Color(0, 0, 0, 0), HORIZONTAL_ALIGNMENT_LEFT, "bold")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.tooltip_text = (
			"%s · %s" % [STQuestions.RARITY_NAMES.get(str(u.rarity), ""), str(_v.players[int(u.seat)].name)]
		)
		row.add_child(l)
		_used_box.add_child(row)
	if used.is_empty():
		_used_box.add_child(STStyle.label("Пока никто не ответил", STStyle.CAP, STStyle.muted()))


## Отвечать может тот, в кого целится пушка (на одном компьютере — любой, за того игрока).
func _can_answer() -> bool:
	if _v.phase != "fuse" or bool(_v.get("spectator", false)) or Net.paused or bool(_v.get("game_paused", false)):
		return false
	var tgt: int = _v.target
	if bool(_v.players[tgt].bot):
		return false
	return Net.mode == "offline" or tgt == int(_v.get("seat", -1))


func _update_input() -> void:
	var tgt: int = _v.target
	var name := str(_v.players[tgt].name)
	var can := _can_answer()
	_appeal.visible = bool(_v.get("can_appeal", false)) and not bool(_v.get("spectator", false)) and (Net.mode == "offline" or int(_v.get("seat", -1)) == tgt)
	var local_seat := int(_v.get("seat", -1))
	var may_prepare: bool = not bool(_v.get("spectator", false)) and _v.phase != "game_over" and (Net.mode == "offline" or (local_seat >= 0 and local_seat < _v.players.size() and bool(_v.players[local_seat].get("alive", false))))
	_answer.editable = may_prepare
	_answer.placeholder_text = "Печатайте ответ и жмите Enter" if can else "Можно подготовить ответ заранее…"
	_send.disabled = not can
	if _v.phase == "new_q":
		_who.text = "Приготовьтесь!"
	elif _v.phase == "check":
		_who.text = "Подробно перепроверяем…" if _v.get("appeal_checking", false) else "Проверяем ответ…"
	elif _v.phase == "game_over":
		_who.text = "Игра окончена"
	elif bool(_v.players[tgt].bot):
		_who.text = "%s думает…" % name
	elif can:
		_who.text = ("Отвечает %s!" % name) if Net.mode == "offline" else "Ваш ответ!"
	else:
		_who.text = "Отвечает %s" % name
	if can and not _answer.has_focus() and get_viewport().gui_get_focus_owner() == null and not _top.chat.expanded:
		_answer.grab_focus()


func _submit() -> void:
	var text := _answer.text.strip_edges()
	if text.is_empty() or not _can_answer():
		return
	_answer.text = ""
	Net.send_action("st_answer", {"text": text, "as": int(_v.target)})


# --- события --------------------------------------------------------------------------


func _play_event(e: Dictionary) -> void:
	var seat := int(e.get("seat", 0))
	match str(e.get("kind", "")):
		"ok":
			_cannon.deflate()
			_snd.ding.play()
			_snd.deflate.play()
			var r := str(e.get("rarity", "c"))
			var txt := "%s  +%d" % [STQuestions.RARITY_NAMES.get(r, ""), int(STRules.POINTS.get(r, 1))]
			if bool(e.get("typo", false)):
				txt = "«%s»  ·  %s" % [str(e.get("name", "")), txt]
			_popup(
				_seat_center(seat) + Vector2(0, -60),
				txt,
				STStyle.RARITY_COLORS.get(r, STStyle.PAPER).lightened(0.3 if r == "s" else 0.0)
			)
			if bool(e.get("healed", false)):
				_popup(_seat_center(seat) + Vector2(0, -100), "+1 жизнь!", STStyle.GREEN)
		"boom":
			_cannon.fire()
			_snd.boom.play()
			_bang(_seat_center(seat))
			_shake()
			if bool(e.get("out", false)):
				_popup(_seat_center(seat) + Vector2(0, 10), "выбывает", STStyle.PAPER)
		"wrong":
			_snd.buzz.play()
			_flash_note("«%s» — не подходит!" % str(e.get("text", "")))
			_shake_input()
		"used":
			_snd.buzz.play()
			_flash_note("«%s» уже называли!" % str(e.get("name", "")))
			_shake_input()


## Короткое сообщение красным на месте «Отвечает …» (на 2,5 с).
func _flash_note(text: String) -> void:
	_who.text = text
	_who.add_theme_color_override("font_color", STStyle.RED)
	var no := _last_no
	get_tree().create_timer(2.5).timeout.connect(
		func():
			if not is_instance_valid(_who):
				return
			_who.add_theme_color_override("font_color", STStyle.ink())
			if _last_no == no:
				_update_input()
	)


func _bang(at: Vector2) -> void:
	# Взрыв соединяет пушку с целью и накрывает персонажа, но не служебный интерфейс.
	var layer := Control.new()
	layer.position = _stage.position
	layer.size = _stage.size
	layer.clip_contents = true
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(layer)
	var burst := preload("res://games/stillion/ui/st_bang.gd").new()
	layer.add_child(burst)
	var cannon_center := _cannon.position + _cannon.size * 0.5
	var direction := at - cannon_center
	# Весь спрайт горизонтален; увеличиваем равномерно до охвата пушки и персонажа.
	var required := Vector2(maxf(420.0, absf(direction.x) + 240.0), maxf(240.0, absf(direction.y) + 200.0))
	var aspect: float = burst.texture.get_width() / float(burst.texture.get_height())
	burst.size = Vector2(maxf(required.x, required.y * aspect), maxf(required.y, required.x / aspect))
	burst.position = (at + cannon_center) * 0.5 - burst.size * 0.5
	burst.pivot_offset = burst.size * 0.5
	burst.scale = Vector2.ONE * 0.35
	var tween := create_tween()
	tween.tween_property(burst, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.85)
	tween.tween_property(burst, "modulate:a", 0.0, 0.3)
	tween.tween_callback(layer.queue_free)


func _popup(at: Vector2, text: String, color: Color, font_size: int = 28) -> void:
	var l := STStyle.label(text, font_size, color, HORIZONTAL_ALIGNMENT_CENTER, "bold")
	l.add_theme_color_override("font_outline_color", STStyle.INK)
	l.add_theme_constant_override("outline_size", 12)
	_fx.add_child(l)
	l.reset_size()
	var p := _stage.position + at - l.size * 0.5
	p.y = maxf(p.y, _stage.position.y + 8.0)  # не наезжать на карточку вопроса
	p.x = clampf(p.x, 8.0, size.x - 260.0 - l.size.x)
	l.position = p
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(0.4, 0.4)
	var t := create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.9)
	t.parallel().tween_property(l, "position:y", l.position.y - 40, 1.3)
	t.tween_property(l, "modulate:a", 0.0, 0.3)
	t.tween_callback(l.queue_free)


func _shake() -> void:
	var home := Vector2(_stage.offset_left, _stage.offset_top)  # сцена стоит на якорях — трясём вокруг её места
	var t := create_tween()
	for i in 6:
		t.tween_property(_stage, "position", home + Vector2(randf_range(-12, 12), randf_range(-8, 8)), 0.04)
	t.tween_property(_stage, "position", home, 0.05)


func _shake_input() -> void:
	var t := create_tween()
	var x := _answer.position.x
	for i in 4:
		t.tween_property(_answer, "position:x", x + (8 if i % 2 == 0 else -8), 0.04)
	t.tween_property(_answer, "position:x", x, 0.04)


func _show_over() -> void:
	if is_instance_valid(_over):
		return
	_over = Control.new()
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over.z_index = 60
	add_child(_over)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over.add_child(center)
	var card := STStyle.panel(28)
	center.add_child(card)
	var col := STStyle.vbox(16)
	card.add_child(col)
	var w := int(_v.winner)
	col.add_child(
		STStyle.label("Последний на ногах", STStyle.BODY, STStyle.muted(), HORIZONTAL_ALIGNMENT_CENTER)
	)
	col.add_child(
		STStyle.label(
			str(_v.players[w].name) if w >= 0 else "Никто не уцелел!",
			STStyle.H1,
			STStyle.RED,
			HORIZONTAL_ALIGNMENT_CENTER,
			"title"
		)
	)
	var row := STStyle.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if Net.is_host():
		var again := STStyle.primary("Ещё раз!", STStyle.BODY, 180)
		again.pressed.connect(
			func():
				Net.end_game()
				Net.start_game.call_deferred()
		)
		row.add_child(again)
		var lobby := STStyle.button("В лобби", STStyle.BODY, 140)
		lobby.pressed.connect(func(): Net.end_game())
		row.add_child(lobby)
	else:
		row.add_child(STStyle.label("Ждём ведущего…", STStyle.BODY, STStyle.muted()))
	col.add_child(row)


## Игрок у пушки: собственный рисованный персонаж, имя, жизни-сердечки и шкала ответов.
class Seat:
	extends Control
	const SIZE := Vector2(150, 190)
	var index := 0
	var data: Dictionary = {}
	var max_lives := 3
	var meter_max := 6
	var targeted := false
	var mine := false
	var _portrait: TextureRect
	var _last_answer: Label
	var compact_answers := false  # больше воздуха между ответом и шкалой верхнего соседа
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_portrait = preload("res://games/stillion/ui/st_portrait.gd").new()
		_portrait.index = index
		_portrait.size = Vector2(85, 113)
		_portrait.position = Vector2(SIZE.x * 0.5 - 42.5, 22)
		add_child(_portrait)
		_last_answer = STStyle.label("", 13 if compact_answers else 16, Color("b8b2a6"), HORIZONTAL_ALIGNMENT_CENTER, "bold")
		_last_answer.position = Vector2(0, 8 if compact_answers else -1)
		_last_answer.size = Vector2(SIZE.x, 20 if compact_answers else 26)
		_last_answer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_last_answer.add_theme_color_override("font_outline_color", Color("39342f"))
		_last_answer.add_theme_constant_override("outline_size", 2 if compact_answers else 3)
		add_child(_last_answer)

	func _process(delta: float) -> void:
		_t += delta
		_last_answer.text = str(data.get("last_answer", ""))
		if is_instance_valid(_portrait):
			_portrait.modulate = Color.WHITE if bool(data.get("alive", true)) else Color(0.45, 0.42, 0.4, 0.8)
		if targeted:
			queue_redraw()

	func _draw() -> void:
		var ink := STStyle.INK
		var alive := bool(data.get("alive", true))
		var cx := SIZE.x * 0.5
		# прожектор на цели
		if targeted:
			var r := 70.0 + sin(_t * 6.0) * 4.0
			draw_circle(Vector2(cx, 90), r, Color(1, 0.92, 0.6, 0.28))
			draw_arc(Vector2(cx, 90), r, 0, TAU, 40, Color(STStyle.RED, 0.9), 4.0, true)
		# тень и персонаж
		draw_set_transform(Vector2(cx, 128), 0.0, Vector2(1, 0.3))
		draw_circle(Vector2.ZERO, 40, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# табличка с именем
		var plate := Rect2(4, 130, SIZE.x - 8, 26)
		var sb := STStyle.box(STStyle.MUSTARD if mine else STStyle.paper(), 8, 3, 3, 4)
		draw_style_box(sb, plate)
		var f := STStyle.font("bold")
		var nm := str(data.get("name", ""))
		var fs := 15
		var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(
			f,
			Vector2(cx - minf(tw, plate.size.x - 10) * 0.5, plate.position.y + 19),
			nm,
			HORIZONTAL_ALIGNMENT_LEFT,
			plate.size.x - 10,
			fs,
			STStyle.INK if mine else STStyle.ink()
		)
		# сердечки
		var lives := int(data.get("lives", 0))
		for k in max_lives:
			_heart(Vector2(cx + (k - (max_lives - 1) * 0.5) * 24, 168), 9.0, k < lives)
		# Рисованная шкала: бумажная рамка, тень и шероховатые сегменты цвета редкости.
		var bar := Rect2(6, 180, SIZE.x - 12, 9)
		var track := STStyle.box(Color("70604b"), 4, 2, 0, 1)
		draw_style_box(track, bar.grow(2))
		var x := bar.position.x
		for r: String in data.get("parts", []):
			var w := minf(bar.size.x * float(STRules.POINTS.get(r, 1)) / float(meter_max), bar.end.x - x)
			if w <= 0.0:
				break
			# Общая рамка рисуется один раз: цветные части стыкуются без зазоров.
			draw_rect(Rect2(x, bar.position.y, w, bar.size.y), STStyle.RARITY_COLORS.get(r, STStyle.PAPER))
			x += w
		var edge := STStyle.box(Color.TRANSPARENT, 4, 2, 0, 0)
		draw_style_box(edge, bar.grow(2))
		if not alive:
			draw_line(Vector2(cx - 30, 40), Vector2(cx + 30, 110), STStyle.RED, 8.0, true)
			draw_line(Vector2(cx + 30, 40), Vector2(cx - 30, 110), STStyle.RED, 8.0, true)

	func _heart(c: Vector2, r: float, full: bool) -> void:
		var pts := PackedVector2Array()
		for i in 40:
			var t := TAU * i / 40.0
			var x := 16.0 * pow(sin(t), 3)
			var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
			pts.append(c + Vector2(x, y) * r / 16.0)
		draw_colored_polygon(pts, STStyle.RED if full else Color(0.3, 0.27, 0.24, 0.6))
		pts.append(pts[0])
		draw_polyline(pts, STStyle.INK, 2.0, true)
