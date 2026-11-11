extends Control
## Служебная сцена: окно «Общение» раскрывается от свёрнутой кнопки в сторону, где есть место, и берёт
## цвет с кнопки верхней полосы. Снимки — build/shots/side_*.png.
## Запуск: APPDATA=<пустая папка> godot --audio-driver Dummy --resolution 1280x720 --path . res://tools/_chat_probe/side_probe.tscn


## Подделка верхней полосы: окно берёт у неё кнопку.
class FakeBar:
	extends Control
	var _make_button := func(text: String, font: int) -> Button:
		var b := Button.new()
		b.text = text
		b.add_theme_font_size_override("font_size", font)
		if OS.get_environment("PROBE_THEME") == "1":
			return b  # вид кнопки целиком из темы игры, как в «Длине волны»
		var box := StyleBoxFlat.new()
		box.bg_color = Color("1f4a55")
		box.set_corner_radius_all(8)
		box.set_content_margin_all(9)
		b.add_theme_stylebox_override("normal", box)
		b.add_theme_color_override("font_color", Color("e8f1f2"))
		return b


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("163740")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if OS.get_environment("PROBE_THEME") == "1":
		bg.color = Color("3f9aa0")
		var look := Theme.new()
		var white := StyleBoxFlat.new()
		white.bg_color = Color.WHITE
		white.border_color = Color.BLACK
		white.set_border_width_all(3)
		white.set_corner_radius_all(12)
		white.set_content_margin_all(10)
		for state: String in ["normal", "hover", "pressed"]:
			look.set_stylebox(state, "Button", white)
		look.set_color("font_color", "Button", Color.BLACK)
		get_tree().root.theme = look
	var bar := FakeBar.new()
	bar.add_to_group("top_bar")
	add_child(bar)
	var sample: Button = bar._make_button.call("Общение", 14)
	sample.position = Vector2(780, 6)
	add_child(sample)
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/shots/") + name + ".png")


func _run() -> void:
	Net.host_offline("")
	Net.lobby_view = {"members": [{"name": "Я", "kind": "host", "peer": 1, "color": 0}]}
	add_child(K12ChatPanel.new())
	var panel: Control = Net.chat.panel()
	await get_tree().create_timer(1.0).timeout
	panel.attention()
	await get_tree().create_timer(0.3).timeout
	var mini_rect := Rect2(panel.position, panel.size)
	await _shot("side_mini_corner")
	panel.toggle()
	Net.send_chat("Проверка цвета окна")
	await get_tree().create_timer(0.4).timeout
	var open_rect := Rect2(panel.position, panel.size)
	print("CORNER mini=", mini_rect, " open=", open_rect, " same_corner=", mini_rect.end.is_equal_approx(open_rect.end))
	await _shot("side_open_corner")
	panel.toggle()
	await get_tree().create_timer(0.3).timeout
	print("BACK ", Rect2(panel.position, panel.size).is_equal_approx(mini_rect))
	# кнопку уносят в левый верхний угол — окно раскрывается вправо и вниз
	panel._pos = Vector2(30, 80)
	panel._placed = true
	panel._apply()
	var top_left := panel.position
	panel.toggle()
	await get_tree().create_timer(0.3).timeout
	print("TOPLEFT same_origin=", panel.position.is_equal_approx(top_left), " ", panel.position)
	# правый верхний угол — влево и вниз
	panel.toggle()
	panel._pos = Vector2(1280 - 110, 80)
	panel._apply()
	await get_tree().create_timer(0.2).timeout
	var right_edge := panel.position.x + panel.size.x
	panel.toggle()
	await get_tree().create_timer(0.3).timeout
	print("TOPRIGHT right_edge_kept=", is_equal_approx(panel.position.x + panel.size.x, right_edge), " top_kept=", is_equal_approx(panel.position.y, 80.0))
	await _shot("side_open_top_right")
	get_tree().quit()
