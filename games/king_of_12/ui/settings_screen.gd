extends Control
## Общие настройки; в хабе — неоновое оформление, в играх — исходный стиль.

var neon_style := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if neon_style:
		theme = _neon_theme()
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.01, 0.065, 0.72) if neon_style else Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := HubStyle.panel(HubStyle.CYAN) if neon_style else K12UI.panel(Color(0.08, 0.055, 0.035, 0.97), 8, "double")
	if neon_style:
		var frame := HubStyle.box(Color("100b22"), 12, Color(HubStyle.CYAN, 0.7), 1, 0.25)
		frame.set_content_margin_all(24)
		panel.add_theme_stylebox_override("panel", frame)
	panel.custom_minimum_size = Vector2(600 if neon_style else 520, 0)
	center.add_child(panel)
	# заголовок и «Готово» на месте, а сами настройки прокручиваются, если окно ниже панели
	var outer := K12UI.vbox(14)
	panel.add_child(outer)
	if neon_style:
		var header := HubStyle.hbox(16)
		header.add_child(HubStyle.neon_label("НАСТРОЙКИ", 28, HubStyle.PINK))
		var badge := HubStyle.label("ЗВУК / ЭКРАН", 14, HubStyle.CYAN, HORIZONTAL_ALIGNMENT_RIGHT, "medium")
		badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(badge)
		outer.add_child(header)
		var line := HSeparator.new()
		var rule := HubStyle.box(Color(HubStyle.PINK, 0.45), 0, Color.TRANSPARENT, 0, 0.0)
		rule.set_content_margin_all(0)
		rule.content_margin_top = 1
		rule.content_margin_bottom = 1
		line.add_theme_stylebox_override("separator", rule)
		line.custom_minimum_size.y = 2
		outer.add_child(line)
	else:
		outer.add_child(K12UI.title("Настройки", K12UI.H1))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var col := K12UI.vbox(14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	var fit := func():
		if not is_inside_tree():
			return
		var room := maxf(80.0, get_viewport_rect().size.y - (224.0 if neon_style else 230.0))
		scroll.custom_minimum_size = Vector2(col.get_combined_minimum_size().x + 12.0, minf(col.get_combined_minimum_size().y, room))
	get_viewport().size_changed.connect(fit)
	fit.call_deferred()

	if neon_style:
		col.add_child(_section("01 / ЗВУК"))
	col.add_child(_slider("Музыка", Prefs.music_volume, 0.0, 1.0, 0.05, func(v): Prefs.set_value("music_volume", v)))
	col.add_child(_slider("Звуки игры", Prefs.sfx_volume, 0.0, 1.0, 0.05, func(v):
		Prefs.set_value("sfx_volume", v)
		Sfx.play("chip", 0, 0.05, 0.15)))
	col.add_child(_slider("Чат и реплики", Prefs.chat_volume, 0.0, 1.0, 0.05, func(v): Prefs.set_value("chat_volume", v)))
	col.add_child(_slider("Масштаб интерфейса", Prefs.ui_scale, 0.8, 1.4, 0.1, func(v): Prefs.set_value("ui_scale", v), true))

	var mute := CheckBox.new()
	mute.text = "Выключить весь звук"
	mute.add_theme_font_size_override("font_size", 17)
	mute.button_pressed = Prefs.muted
	mute.toggled.connect(func(on): Prefs.set_value("muted", on))
	col.add_child(mute)
	if neon_style:
		col.add_child(_section("02 / ЭКРАН И ГРАФИКА"))
	# экран: окно / полный экран в окне (без рамки) / эксклюзивный; размер — для оконного режима
	var wm := K12UI.hbox(8)
	wm.add_child(_label("Экран:", K12UI.BODY))
	var modes := [["windowed", "Окно", "Обычное окно — размер ниже"], ["borderless", "Полный экран в окне", "Во весь экран без рамки: быстро переключается Alt+Tab, не сворачивается"], ["exclusive", "Полный экран", "Эксклюзивный полный экран — иногда чуть быстрее, но Alt+Tab сворачивает игру"]]
	var rr := K12UI.hbox(8)
	for m in modes:
		var b := _button(m[1], K12UI.CAP)
		b.tooltip_text = m[2]
		UISel.pick(b, Prefs.window_mode == m[0])
		var v: String = m[0]
		b.pressed.connect(func():
			Prefs.set_value("window_mode", v)
			for c in wm.get_children():
				if c is Button:
					UISel.pick(c, modes[c.get_index() - 1][0] == v)
			for c in rr.get_children():
				if c is Button:
					c.disabled = v != "windowed")
		wm.add_child(b)
	col.add_child(wm)
	rr.add_child(_label("Размер окна:", K12UI.BODY))
	for res in Prefs.RESOLUTIONS:
		var b := _button(str(res).replace("x", "×"), K12UI.CAP)
		UISel.pick(b, Prefs.resolution == res)
		b.disabled = Prefs.window_mode != "windowed"
		var rv: String = res
		b.pressed.connect(func():
			Prefs.set_value("resolution", rv)
			for c in rr.get_children():
				if c is Button:
					UISel.pick(c, Prefs.RESOLUTIONS[c.get_index() - 1] == rv))
		rr.add_child(b)
	col.add_child(rr)
	# качество графики (главное меню и 3D-кубики)
	var gq := K12UI.hbox(8)
	gq.add_child(_label("Качество графики:", K12UI.BODY))
	for i in 3:
		var b := _button(["Низкое", "Среднее", "Высокое"][i], K12UI.CAP)
		UISel.pick(b, Prefs.graphics == i)
		b.tooltip_text = ["Без теней и затенения углов, меньше ламп, 3D в 67% разрешения, простое сглаживание — для слабых ПК", "Тень только от главного света, 3D в 80% разрешения, сглаживание 2x", "Все тени и эффекты, полное разрешение, сглаживание 4x"][i]
		var ii := i
		b.pressed.connect(func():
			Prefs.set_value("graphics", ii)
			for c in gq.get_children():
				if c is Button:
					UISel.pick(c, c.get_index() - 1 == ii))
		gq.add_child(b)
	col.add_child(gq)
	var fps := CheckBox.new()
	fps.text = "Показывать FPS"
	fps.add_theme_font_size_override("font_size", 17)
	fps.button_pressed = Prefs.show_fps
	fps.toggled.connect(func(on): Prefs.set_value("show_fps", on))
	col.add_child(fps)
	# логи — чтобы отправить разработчику, если что-то сломалось
	var lr := K12UI.hbox(8)
	lr.add_child(_label("Логи:", K12UI.BODY))
	var lc := _button("Скопировать лог", K12UI.CAP)
	lc.tooltip_text = "Скопировать лог текущего запуска в буфер обмена — вставьте его в сообщение разработчику"
	lc.pressed.connect(func():
		var ok: bool = load("res://hub/crash_report.gd").copy_log()
		lc.text = "Скопировано ✓" if ok else "Лог не найден")
	lr.add_child(lc)
	var lf := _button("Открыть папку с логами", K12UI.CAP)
	lf.tooltip_text = "Там и логи прошлых запусков (godot<дата>.log)"
	lf.pressed.connect(func(): load("res://hub/crash_report.gd").open_folder())
	lr.add_child(lf)
	col.add_child(lr)
	var vs := CheckBox.new()
	vs.text = "Вертикальная синхронизация"
	vs.tooltip_text = "Кадры не чаще частоты монитора, без разрывов картинки"
	vs.add_theme_font_size_override("font_size", 17)
	vs.button_pressed = Prefs.vsync
	vs.toggled.connect(func(on): Prefs.set_value("vsync", on))
	col.add_child(vs)
	var fl := K12UI.hbox(8)
	fl.add_child(_label("Ограничение FPS:", K12UI.BODY))
	for lim in Prefs.FPS_LIMITS:
		var b := _button(str(lim) if lim > 0 else "Нет", K12UI.CAP)
		UISel.pick(b, Prefs.fps_limit == lim)
		var ll: int = lim
		b.pressed.connect(func():
			Prefs.set_value("fps_limit", ll)
			for c in fl.get_children():
				if c is Button:
					UISel.pick(c, Prefs.FPS_LIMITS[c.get_index() - 1] == ll))
		fl.add_child(b)
	col.add_child(fl)
	# тема светлых игр — кнопкой-солнцем/луной рядом с «Правила» и «Настройки» в самих играх

	var close := HubStyle.primary("ГОТОВО", 17, 220) if neon_style else _button("Готово", K12UI.BODY, 200)
	close.custom_minimum_size.y = 42 if neon_style else 0
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(queue_free)
	outer.add_child(close)


func _slider(title: String, value: float, lo: float, hi: float, step: float, on_change: Callable, apply_on_release: bool = false) -> VBoxContainer:
	var box := K12UI.vbox(2)
	var head := K12UI.hbox()
	var t := _label(title, K12UI.BODY)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var val := _label("", K12UI.BODY, HubStyle.CYAN if neon_style else K12UI.GOLD)
	head.add_child(val)
	box.add_child(head)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size.y = 24
	var show := func(v): val.text = ("%d%%" % roundi(v * 100.0))
	show.call(value)
	s.value_changed.connect(func(v):
		show.call(v)
		if not apply_on_release:
			on_change.call(v))
	if apply_on_release:
		s.drag_ended.connect(func(_changed): on_change.call(s.value))
	box.add_child(s)
	return box


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()


## Локальная тема: тонкие дорожки вместо массивной заливки, чёткие неоновые флажки.
func _neon_theme() -> Theme:
	var result := HubStyle.theme().duplicate() as Theme
	for state in ["slider", "grabber_area", "grabber_area_highlight"]:
		var color := Color("29203f") if state == "slider" else HubStyle.PINK
		if state == "grabber_area_highlight":
			color = HubStyle.CYAN
		var track := HubStyle.box(color, 3, Color.TRANSPARENT, 0, 0.0)
		track.set_content_margin_all(0)
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		result.set_stylebox(state, "HSlider", track)
	for icon in ["grabber", "grabber_highlight", "grabber_disabled"]:
		var image := Image.new()
		image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"><rect x="3" y="3" width="12" height="12" rx="3" fill="#f3eaff" stroke="#2ef2ff" stroke-width="2"/></svg>')
		result.set_icon(icon, "HSlider", ImageTexture.create_from_image(image))
	for icon in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		var image := Image.new()
		var mark := '<path d="M5 10l3 3 7-7" fill="none" stroke="#2ef2ff" stroke-width="2"/>' if icon.begins_with("checked") else ""
		image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect x="2" y="2" width="16" height="16" rx="3" fill="#17112b" stroke="#9b5cff" stroke-width="1.5"/>' + mark + '</svg>')
		result.set_icon(icon, "CheckBox", ImageTexture.create_from_image(image))
	result.set_constant("h_separation", "CheckBox", 10)
	return result


func _button(text: String, font_size: int, min_width: int = 0) -> Button:
	return HubStyle.button(text, font_size, min_width) if neon_style else K12UI.button(text, font_size, min_width)


func _label(text: String, font_size: int, color: Color = K12UI.CREAM) -> Label:
	return HubStyle.label(text, font_size, HubStyle.TEXT if color == K12UI.CREAM else color) if neon_style else K12UI.label(text, font_size, color)


func _section(text: String) -> Label:
	var label := HubStyle.label(text, 14, HubStyle.CYAN, HORIZONTAL_ALIGNMENT_LEFT, "medium")
	label.custom_minimum_size.y = 28
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
