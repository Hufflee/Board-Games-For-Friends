extends SceneTree
## Стикеры хаба по сети: два настоящих ENet-процесса (ROLE=host / ROLE=client, отдельные APPDATA, Dummy-звук).
## Проверяет: стикеры коробок видны другу; на чужую доску клеить можно, на свою — нет; снять можно только своё;
## поддельный «хозяйский» RPC от клиента не проходит.
## Запуск (из корня, bash):
##   G=<godot>; P=build/probe/stickers_enet; mkdir -p $P/host $P/client
##   APPDATA=$P/host ROLE=host $G --headless --audio-driver Dummy --path . --script res://tests/test_hub_stickers_enet.gd &
##   APPDATA=$P/client ROLE=client $G --headless --audio-driver Dummy --path . --script res://tests/test_hub_stickers_enet.gd
const FOLDER := "res://build/probe/stickers_enet/"
const PORT := 25493

var role := OS.get_environment("ROLE")
var poster_hash := ""
var net: Node
var st: Node
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ОШИБКА [%s]: %s" % [role, message])


func until(test: Callable, message: String, seconds: float = 10.0) -> void:
	var started := Time.get_ticks_msec()
	while not test.call() and Time.get_ticks_msec() - started < seconds * 1000.0:
		await create_timer(0.05).timeout
	check(bool(test.call()), message)


func marker(name: String) -> void:
	var file := FileAccess.open(FOLDER + name + ".tmp", FileAccess.WRITE)
	file.store_string("готово")
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(FOLDER + name + ".tmp"), ProjectSettings.globalize_path(FOLDER + name + ".txt"))


func seen(name: String) -> bool:
	return FileAccess.file_exists(FOLDER + name + ".txt")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	net = root.get_node("Net")
	st = net.stickers
	st.local = {"boxes": {}, "board": []}
	# Оба процесса на одном компьютере видят один и тот же Steam-аккаунт: разводим их по нику без Steam ID.
	net.my_steam_id = 0
	net.my_name = "Хост" if role == "host" else "Клиент"
	if role == "host":
		for name in ["joined", "client_box_seen", "client_added", "client_removed", "forged", "board_moved", "client_pos_ok", "poster_hash", "client_poster", "early_poster", "done"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(FOLDER + name + ".txt"))
		await _host()
	else:
		await create_timer(0.8).timeout
		await _client()
	print("СТИКЕРЫ ENet [%s]: %d проверок, %d ошибок" % [role, checks, failures])
	net.leave()
	await create_timer(0.3).timeout
	quit(1 if failures > 0 else 0)


func _host() -> void:
	check(net.host_enet(PORT, "") == OK, "ENet-сервер запущен")
	await until(func(): return net.members.size() == 2, "клиент подключён")
	var client := 0
	for peer: Variant in net.members:
		if int(peer) != 1:
			client = int(peer)
	marker("joined")
	check(st.add_box_sticker("machi_koro", "fire", 0.3, 0.4, 0.1), "свой стикер на коробку")
	check(not st.request_board_add(1, 0, "gg", 0.5, 0.5, 0.0), "на свою доску клеить нельзя (хост)")
	await until(func(): return seen("client_box_seen"), "клиент увидел стикер коробки хоста")
	await until(func(): return seen("client_added"), "клиент наклеил стикер на доску хоста")
	await until(func(): return st.local.board.size() == 1, "на доске хоста один стикер друга")
	if st.local.board.size() == 1:
		check(str(st.local.board[0][5]) != st.my_author_key(), "автор — клиент, а не хост")
		check(str(st.local.board[0][1]) == "crown", "наклеен выбранный стикер")
		check(is_equal_approx(float(st.local.board[0][2]), 0.1) and is_equal_approx(float(st.local.board[0][4]), 1.0), "место и поворот от автора применены у хозяина")
	# Хозяин не может «перехватить» чужой стикер: правка с его ключом отклоняется.
	if not st.local.board.is_empty():
		st._owner_update(st.my_author_key(), 0, str(st.local.board[0][0]), 0.5, 0.5, 0.0, 1.0)
		check(is_equal_approx(float(st.local.board[0][2]), 0.1), "чужой ключ автора не двигает стикер")
	check(st.add_box_sticker("machi_koro", "gg", 0.5, 0.5, 0.0), "второй стикер на коробку")
	st.update_box_sticker("machi_koro", 1, 0.99, 0.1, 3.5, 9.0)
	var big: Array = st.box_stickers("machi_koro")[1]
	check(is_equal_approx(float(big[4]), 2.0) and absf(float(big[3])) <= PI, "размер и поворот на коробке ограничены")
	check(st.request_board_add(client, 0, "pixel_heart", 0.2, 0.3, 0.0), "хост клеит стикер на доску клиента")
	await until(func(): return seen("client_removed"), "клиент снял свой стикер")
	await until(func(): return st.local.board.is_empty(), "стикер клиента снят с доски хоста")
	if not st.local.board.is_empty():
		print("ОТЛАДКА доска хоста: ", st.local.board)
	await until(func(): return seen("forged"), "клиент отправил поддельный запрос")
	await create_timer(0.6).timeout
	check(st.local.board.is_empty(), "поддельный «хозяйский» RPC клиента не наклеил стикер")
	# Не больше 6 стикеров одного автора на доске; у другого автора свой лимит.
	for i in 8:
		st._owner_add("steam:77", "Друг", 0, "gg", 0.1 * i, 0.5, 0.0)
	st._owner_add("steam:78", "Соня", 0, "fire", 0.5, 0.5, 0.0)
	check(st.local.board.filter(func(e): return str(e[5]) == "steam:77").size() == 6, "от одного друга не больше 6 стикеров")
	check(st.local.board.size() == 7, "лимит считается отдельно для каждого автора")
	st.local.board.clear()
	# Перевешенная доска видна другу.
	st.set_board_pos(Vector2(-1.5, 1.8))
	# Плакат хоста со своей картинкой — клиент должен скачать её через хоста по хэшу.
	var picture := Image.create(900, 500, false, Image.FORMAT_RGB8)
	picture.fill(Color(0.2, 0.6, 0.9))
	poster_hash = st.set_poster_picture(2, picture, Vector2(0.9, 1.7))
	var file := FileAccess.open(FOLDER + "poster_hash.tmp", FileAccess.WRITE)
	file.store_string(poster_hash)
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(FOLDER + "poster_hash.tmp"), ProjectSettings.globalize_path(FOLDER + "poster_hash.txt"))
	marker("board_moved")
	await until(func(): return seen("client_pos_ok"), "клиент увидел новое место доски")
	await until(func(): return seen("client_poster"), "клиент поставил свою картинку на плакат")
	var client_hash := FileAccess.get_file_as_string(FOLDER + "client_poster.txt")
	var got: Texture2D = null
	var since := Time.get_ticks_msec()
	while got == null and Time.get_ticks_msec() - since < 10000:
		got = st.poster_texture(client_hash)
		await create_timer(0.1).timeout
	check(got != null and got.get_height() == 700, "хост получил картинку плаката клиента")
	var early_hash := FileAccess.get_file_as_string(FOLDER + "early_poster.txt")
	var early: Texture2D = null
	since = Time.get_ticks_msec()
	while early == null and Time.get_ticks_msec() - since < 10000:
		early = st.poster_texture(early_hash)
		await create_timer(0.1).timeout
	check(early != null and early.get_width() == 640, "картинка, поставленная до входа в пати, тоже дошла до хоста")
	marker("done")


func _client() -> void:
	# Картинка плаката поставлена ДО входа в пати (баг 0.9.0: друзья её не видели).
	var early := Image.create(640, 360, false, Image.FORMAT_RGB8)
	early.fill(Color(0.3, 0.9, 0.4))
	var early_hash: String = st.set_poster_picture(1, early, Vector2(-0.5, 1.6))
	var hf := FileAccess.open(FOLDER + "early_poster.tmp", FileAccess.WRITE)
	hf.store_string(early_hash)
	hf.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(FOLDER + "early_poster.tmp"), ProjectSettings.globalize_path(FOLDER + "early_poster.txt"))
	check(net.join_enet("127.0.0.1", PORT) == OK, "клиент подключается")
	await until(func(): return seen("joined") and net.multiplayer.get_unique_id() > 1, "подключение подтверждено")
	var me: int = net.multiplayer.get_unique_id()
	await until(func(): return not st.room_of(1).boxes.get("machi_koro", []).is_empty(), "видна коробка хоста со стикером")
	marker("client_box_seen")
	check(not st.request_board_add(me, 0, "gg", 0.5, 0.5, 0.0), "на свою доску клеить нельзя (клиент)")
	check(st.request_board_add(1, 0, "crown", 0.6, 0.4, 0.2), "запрос стикера на доску хоста")
	await until(func(): return st.my_board_stickers(1).size() == 1, "свой стикер виден на доске хоста")
	if st.my_board_stickers(1).size() == 1:
		st.request_board_update(1, 0, str(st.my_board_stickers(1)[0][0]), 0.1, 0.9, 1.0, 1.7)
	await until(func(): return st.my_board_stickers(1).size() == 1 and is_equal_approx(float(st.my_board_stickers(1)[0][7]), 1.7), "свой стикер на доске друга сдвинут, повёрнут, увеличен")
	if st.my_board_stickers(1).size() != 1 or not is_equal_approx(float(st.my_board_stickers(1)[0][7]), 1.7):
		print("ОТЛАДКА доска хоста у клиента: ", st.room_of(1).get("board"), " мой ключ: ", st.my_author_key())
	marker("client_added")
	await until(func(): return st.local.board.size() == 1, "хост наклеил стикер на мою доску")
	if st.local.board.size() == 1:
		check(st.my_board_stickers(me).is_empty(), "чужой стикер на моей доске — не «мой»")
	var mine: Array = st.my_board_stickers(1)
	if not mine.is_empty():
		st.request_board_remove(1, 0, str(mine[0][0]))
	await until(func(): return st.my_board_stickers(1).is_empty(), "свой стикер снят с доски хоста")
	marker("client_removed")
	# Подделка: клиент сам вызывает RPC, который хост шлёт хозяину доски.
	st._rpc_owner_add.rpc_id(1, "steam:999", "Хакер", 0, "skull", 0.5, 0.5, 0.0)
	marker("forged")
	await until(func(): return seen("board_moved") and st.board_pos(1).is_equal_approx(Vector2(-1.5, 1.8)), "доска хоста перевешена и у клиента")
	check(st.board_pos(me) == load("res://hub/stickers.gd").BOARD_DEFAULT, "своя доска клиента — на месте по умолчанию")
	var expected := FileAccess.get_file_as_string(FOLDER + "poster_hash.txt")
	await until(func(): return (st.room_of(1).get("posters", []) as Array).size() == 3 and str(st.room_of(1).posters[2][2]) == expected, "у клиента виден плакат хоста со своей картинкой")
	var texture: Texture2D = null
	var started := Time.get_ticks_msec()
	while texture == null and Time.get_ticks_msec() - started < 10000:
		texture = st.poster_texture(expected)
		await create_timer(0.1).timeout
	check(texture != null and texture.get_width() == 900, "картинка плаката скачана через хоста и проверена по хэшу")
	# Своя картинка клиента — хост получает её кусками и может показать (и раздать другим).
	var own_picture := Image.create(400, 700, false, Image.FORMAT_RGB8)
	own_picture.fill(Color(0.9, 0.3, 0.4))
	var client_hash: String = st.set_poster_picture(0, own_picture, Vector2(-1.0, 1.5))
	var f := FileAccess.open(FOLDER + "client_poster.tmp", FileAccess.WRITE)
	f.store_string(client_hash)
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(FOLDER + "client_poster.tmp"), ProjectSettings.globalize_path(FOLDER + "client_poster.txt"))
	marker("client_pos_ok")
	await until(func(): return seen("done"), "хост завершил проверки", 15.0)
