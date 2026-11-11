extends Control
## Служебная сцена: чат со вкладками и окно мини-игр с поддельными собеседниками — снимки в build/shots.
## Запуск: APPDATA=<пустая папка> godot --audio-driver Dummy --path . res://tools/_chat_probe/chat_probe.tscn

var _out := ""
var _held := false


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


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	Net.host_offline("")
	Net.members[2] = {"name": "Костя", "color": 3}
	Net.members[3] = {"name": "Юля", "color": 5}
	Net.lobby_view = {"members": [
		{"name": "Я", "kind": "host", "peer": 1, "color": 0},
		{"name": "Костя", "kind": "player", "peer": 2, "color": 3},
		{"name": "Юля", "kind": "player", "peer": 3, "color": 5}]}
	var chat := K12ChatPanel.new()
	chat.expanded = true
	add_child(chat)
	await _wait(0.3)
	var net_chat: Node = Net.chat
	Net.send_chat("Привет всем! Кто в шахматы?")
	net_chat._add("all", {"id": 900, "name": "Костя", "peer": 2, "text": "Я за, только доиграем раунд [проверка скобок]", "kind": "chat", "color": "4363d8"})
	net_chat._add("all", {"id": 901, "name": "Юля", "peer": 3, "text": "Блефую!", "kind": "emote", "color": "911eb4"})
	net_chat._apply_react(900, {0: [1, 2], 6: [3]})
	net_chat.send("all", "Отлично, жду", "chat", {"reply": {"id": 900, "name": "Костя", "text": "Я за, только доиграем раунд"}})
	var image := Image.create(320, 180, false, Image.FORMAT_RGB8)
	for y in 180:
		for x in 320:
			image.set_pixel(x, y, Color(x / 320.0, y / 180.0, 0.6))
	var hash: String = net_chat.attach(net_chat.prepare_image(image))
	net_chat.send("all", "", "chat", {"image": hash})
	net_chat._apply_pm({"id": 950, "name": "Костя", "peer": 2, "to": 1, "text": "Го 1 на 1 после партии?", "kind": "chat", "scope": "pm", "color": "4363d8"})
	net_chat._apply_pm({"id": 951, "name": "Юля", "peer": 3, "to": 1, "text": "а я с вами", "kind": "chat", "scope": "pm", "color": "911eb4"})
	await _wait(0.6)
	await _shot("chat_all")
	# наведение на сообщение, перенос за полосу, размер за уголок — настоящими событиями мыши
	var row: Control = chat._list.get_child(1)
	Input.warp_mouse(row.get_global_rect().get_center())
	await _mouse(row.get_global_rect().get_center(), 0)
	await _wait(0.3)
	print("HOVER_BAR ", chat._hover_bar.visible)
	await _shot("chat_hover")
	var head: Control = chat._head
	var grab := head.global_position + Vector2(head.size.x * 0.62, head.size.y * 0.5)
	var before := chat.position
	await _mouse(grab, 1)
	await _mouse(grab + Vector2(-150, -100), 0)
	await _mouse(grab + Vector2(-300, -200), 0)
	await _mouse(grab + Vector2(-300, -200), 2)
	print("DRAG ", before, " -> ", chat.position)
	var corner := chat.global_position + chat.size - Vector2(5, 5)
	await _mouse(corner, 1)
	await _mouse(corner + Vector2(60, 60), 0)
	await _mouse(corner + Vector2(136, 132), 0)
	await _mouse(corner + Vector2(136, 132), 2)
	await _wait(0.3)
	print("RESIZE k=", chat.k, " size=", chat.size)
	await _shot("chat_big")
	net_chat.select("pm:2")
	await _wait(0.4)
	await _shot("chat_pm")
	chat.set_mode(1)
	await _wait(0.3)
	await _shot("chat_mini")
	chat.set_mode(0)
	var mg: Node = Net.minigames
	mg.show_panel()
	await _wait(0.4)
	await _shot("mg_lobby")
	mg.start_local("chess")
	var id: String = mg.current
	for action: Array in [[52, 36], [12, 28], [62, 45], [1, 18]]:
		mg.move(id, {"from": action[0], "to": action[1]})
	await _wait(0.4)
	await _shot("mg_chess")
	mg.start_local("checkers")
	mg.move(str(mg.current), {"from": 40, "to": 33})
	await _wait(0.3)
	await _shot("mg_checkers")
	mg.start_local("go", {"size": 13})
	for at: int in [42, 43, 55, 30, 84, 100]:
		mg.move(str(mg.current), {"at": at})
	await _wait(0.3)
	await _shot("mg_go")
	var panel: Control = mg._panel
	Input.warp_mouse(panel.global_position + panel.size * 0.5)
	panel._zoom = 1.0
	panel._apply()
	await _wait(0.3)
	await _shot("mg_go_zoom")
	mg.select(id)
	await _wait(0.3)
	await _shot("mg_chess_zoom")
	get_tree().quit()
