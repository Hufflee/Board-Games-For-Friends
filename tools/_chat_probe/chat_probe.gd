extends Control
## Служебная сцена: окно «Общение» (чат и мини-игры) с поддельными собеседниками — снимки в build/shots.
## Запуск: APPDATA=<пустая папка> godot --audio-driver Dummy --path . res://tools/_chat_probe/chat_probe.tscn
## GIF для проверки — build/shots/test.gif (если есть).

var _out := ""
var _held := false


## Подделка верхней полосы: окно берёт у неё кнопку для свёрнутого вида.
class FakeBar:
	extends Control
	var _make_button := func(text: String, font: int) -> Button:
		var b := Button.new()
		b.text = text
		b.add_theme_font_size_override("font_size", font)
		var box := StyleBoxFlat.new()
		box.bg_color = Color("c9a25a")
		box.set_corner_radius_all(4)
		box.set_content_margin_all(8)
		b.add_theme_stylebox_override("normal", box)
		b.add_theme_color_override("font_color", Color("2a1c0c"))
		return b


func _ready() -> void:
	_out = ProjectSettings.globalize_path("res://build/shots/")
	var bg := ColorRect.new()
	bg.color = Color("5b6f63")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + name + ".png")
	print("SHOT ", name)


## kind: 0 — движение, 1 — нажатие, 2 — отпускание левой кнопки.
func _mouse(at: Vector2, kind: int) -> void:
	var event: InputEventMouse
	if kind == 0:
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT if _held else 0
		event = motion
	else:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = kind == 1
		_held = kind == 1
		event = button
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	Net.host_offline("")
	Net.party_game = OS.get_environment("PROBE_GAME")
	Net.members[2] = {"name": "Костя", "color": 3}
	Net.members[3] = {"name": "Юля", "color": 5}
	Net.lobby_view = {"members": [
		{"name": "Я", "kind": "host", "peer": 1, "color": 0},
		{"name": "Костя", "kind": "player", "peer": 2, "color": 3},
		{"name": "Юля", "kind": "player", "peer": 3, "color": 5}]}
	var proxy := K12ChatPanel.new()
	add_child(proxy)
	var panel: Control = Net.chat.panel()
	await _wait(0.6)
	await _key(KEY_Z)
	print("Z_OPEN ", panel.mode == 0 and panel.view == "chat")
	var net_chat: Node = Net.chat
	Net.send_chat("Привет всем! Кто в шахматы?")
	net_chat._add("all", {"id": 900, "name": "Костя", "peer": 2, "text": "Я за, только доиграем раунд [проверка скобок]", "kind": "chat", "color": "4363d8"})
	net_chat._add("all", {"id": 901, "name": "Юля", "peer": 3, "text": "Блефую!", "kind": "emote", "color": "911eb4"})
	net_chat._add("all", {"id": 902, "name": "", "seat": -1, "text": "Костя зовёт вас сыграть: шахматы.", "kind": "system"})
	net_chat._apply_react(900, {0: [1, 2], 6: [3]})
	net_chat.send("all", "Отлично, жду", "chat", {"reply": {"id": 900, "name": "Костя", "text": "Я за, только доиграем раунд"}})
	var gif_path := _out + "test.gif"
	if FileAccess.file_exists(gif_path):
		var started := Time.get_ticks_msec()
		var hash: String = net_chat.attach(net_chat.prepare_file(gif_path))
		net_chat.send("all", "", "chat", {"image": hash})
		for i in 100:
			await _wait(0.1)
			if not net_chat.image_frames(hash).is_empty() or net_chat.image_failed(hash):
				break
		var data: Dictionary = net_chat.image_frames(hash)
		print("GIF frames=", (data.get("frames", []) as Array).size(), " failed=", net_chat.image_failed(hash), " ms=", Time.get_ticks_msec() - started)
	net_chat._apply_pm({"id": 950, "name": "Костя", "peer": 2, "to": 1, "text": "Го 1 на 1 после партии?", "kind": "chat", "scope": "pm", "color": "4363d8"})
	await _wait(0.6)
	await _shot("comms_chat")
	var head: Control = panel._head
	var grab := head.global_position + Vector2(head.size.x * 0.8, head.size.y * 0.5)
	var before := panel.position
	await _mouse(grab, 1)
	await _mouse(grab + Vector2(-150, -100), 0)
	await _mouse(grab + Vector2(-300, -200), 0)
	await _mouse(grab + Vector2(-300, -200), 2)
	print("DRAG ", before, " -> ", panel.position)
	await _key(KEY_X)
	print("X_GAMES ", panel.mode == 0 and panel.view == "mg")
	await _wait(0.3)
	await _shot("comms_games")
	var mg: Node = Net.minigames
	mg.start_local("chess")
	var id: String = mg.current
	for action: Array in [[52, 36], [12, 28], [62, 45], [1, 18]]:
		mg.move(id, {"from": action[0], "to": action[1]})
	await _wait(0.4)
	await _shot("comms_chess")
	await _key(KEY_X)
	print("X_MINI ", panel.mode == 1)
	await _wait(0.3)
	await _shot("comms_mini_plain")
	var bar := FakeBar.new()
	bar.add_to_group("top_bar")
	add_child(bar)
	await _wait(0.8)
	await _shot("comms_mini_game_button")
	await _key(KEY_Z)
	await _wait(0.4)
	await _shot("comms_chat_again")
	get_tree().quit()
