extends SceneTree
## Двухпроцессная проверка чата и мини-игр по ENet: личное сообщение с картинкой и ответом, реакция,
## приглашение в шахматы, по ходу с каждой стороны.
## Запуск (два процесса): PROBE_ROLE=host|client PROBE_PORT=24701 godot --headless --path . --script res://tools/_chat_probe/net_probe.gd

var role := OS.get_environment("PROBE_ROLE")
var net: Node
var chat: Node
var mg: Node
var failed := 0
var checks := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failed += 1
		print("ОШИБКА[%s]: %s" % [role, msg])


func _initialize() -> void:
	boot.call_deferred()


func until(cond: Callable, what: String, seconds: float = 12.0) -> bool:
	var left := seconds
	while left > 0.0:
		if cond.call():
			return true
		await create_timer(0.1).timeout
		left -= 0.1
	check(false, "не дождались: " + what)
	return false


func boot() -> void:
	net = root.get_node("Net")
	chat = net.chat
	mg = net.minigames
	net.my_name = "Хост" if role == "host" else "Гость"
	var port := int(OS.get_environment("PROBE_PORT"))
	if role == "host":
		net.host_enet(port, "")
	else:
		net.join_enet("127.0.0.1", port)
	await until(func(): return chat.pm_targets().size() == 1, "второй участник пати", 20.0)
	await create_timer(0.5).timeout
	if role == "client":
		await client()
	else:
		await host()
	print("PROBE %s: проверок %d, ошибок %d" % [role, checks, failed])
	await create_timer(1.0).timeout
	net.leave()
	quit(1 if failed > 0 else 0)


func pm_entries() -> Array:
	for key: String in chat.convs:
		if key.begins_with("pm:"):
			return chat.convs[key].entries
	return []


func client() -> void:
	chat.send("all", "общий привет")
	chat.open_pm(1)
	var image := Image.create(64, 48, false, Image.FORMAT_RGB8)
	image.fill(Color(0.2, 0.6, 0.9))
	var hash: String = chat.attach(chat.prepare_image(image))
	check(hash.length() == 64, "картинка подготовлена")
	chat.send("pm:1", "личное", "chat", {"image": hash, "reply": {"id": 1, "name": "Хост", "text": "цитата"}})
	await until(func(): return pm_entries().size() == 1, "своё личное сообщение вернулось")
	var entry: Dictionary = pm_entries()[0] if not pm_entries().is_empty() else {}
	check(str(entry.get("image", "")) == hash and (entry.get("reply", {}) as Dictionary).get("text", "") == "цитата", "в личном есть картинка и цитата")
	var id := int(entry.get("id", 0))
	await until(func(): return chat.reactions.has(id), "реакция хоста на личное")
	check((chat.reactions.get(id, {}) as Dictionary).has(0), "реакция — первый смайлик")
	await until(func(): return (chat.convs["all"].entries as Array).any(func(e): return str(e.get("text", "")) == "ответ всем"), "общий ответ хоста дошёл")
	var with_image: Array = (chat.convs["all"].entries as Array).filter(func(e): return e.has("image"))
	check(with_image.size() == 1, "сообщение хоста с GIF пришло")
	if not with_image.is_empty():
		var gif_hash := str(with_image[0].image)
		await until(func(): return not chat.image_frames(gif_hash).is_empty() or chat.image_failed(gif_hash), "GIF хоста скачан и разобран", 40.0)
		check((chat.image_frames(gif_hash).get("frames", []) as Array).size() > 1, "GIF хоста играет у гостя")
	mg.invite(1, "chess")
	await until(func(): return mg.sessions.size() == 1, "партия создана")
	await play()


func host() -> void:
	await until(func(): return pm_entries().size() == 1, "личное сообщение гостя")
	var entry: Dictionary = pm_entries()[0] if not pm_entries().is_empty() else {}
	check(str(entry.get("text", "")) == "личное" and entry.has("image"), "личное пришло с картинкой")
	await until(func(): return not chat.image_frames(str(entry.get("image", ""))).is_empty(), "картинка гостя доехала до хоста по кускам")
	var gif: PackedByteArray = chat.prepare_file(ProjectSettings.globalize_path("res://build/shots/big.gif"))
	check(gif.size() > 300000, "большой GIF подготовлен")
	chat.send("all", "", "chat", {"image": chat.attach(gif)})
	check((chat.convs["all"].entries as Array).any(func(e): return str(e.get("text", "")) == "общий привет"), "общее сообщение гостя дошло")
	check(chat.unread_total() >= 2, "есть непрочитанные")
	chat.react(int(entry.get("id", 0)), 0)
	chat.send("all", "ответ всем")
	await until(func(): return mg.invites_in.size() == 1, "приглашение в шахматы")
	if not mg.invites_in.is_empty():
		mg.answer(str(mg.invites_in[0].id), true)
	await until(func(): return mg.sessions.size() == 1, "партия создана")
	await play()


func play() -> void:
	if mg.sessions.is_empty():
		return
	var id: String = mg.sessions.keys()[0]
	var seat := int(mg.sessions[id].seat)
	await until(func(): return int(mg.sessions[id].state.turn) == seat, "мой ход")
	mg.move(id, {"from": 52, "to": 36} if seat == 0 else {"from": 12, "to": 28})
	await until(func(): return int(mg.sessions[id].state.moves) == 2, "оба хода сделаны")
	check(int(mg.sessions[id].state.board[36]) == 1 and int(mg.sessions[id].state.board[28]) == 9, "пешки на e4 и e5")
	if seat == 1:
		mg.move(id, {"from": 28, "to": 29})
		await create_timer(0.5).timeout
		check(int(mg.sessions[id].state.moves) == 2, "чужой и незаконный ход отклонён")
