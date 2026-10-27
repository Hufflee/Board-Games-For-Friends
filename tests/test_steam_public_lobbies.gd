extends SceneTree
## Публичные пати Steam: mock-служба, асинхронный refresh, фильтрация и настоящий ввод браузера.
## Dummy/свой APPDATA; в графике сохраняет кадры двух тем. Живые Steam/сокеты не проверяет.

class SteamMock extends RefCounted:
	signal lobby_match_list(lobbies: Array)
	var requests := 0
	var filters: Array = []
	var rooms: Dictionary = {}
	var joins: Array[int] = []
	var created: Array = []
	var friends_read := 0
	var invites: Array = []
	func getAppID() -> int:
		return 480
	func addRequestLobbyListDistanceFilter(value: int) -> void:
		filters.append(["distance", value])
	func addRequestLobbyListStringFilter(key: String, value: String, comparison: int) -> void:
		filters.append([key, value, comparison])
	func addRequestLobbyListResultCountFilter(value: int) -> void:
		filters.append(["limit", value])
	func requestLobbyList() -> void:
		requests += 1
	func getLobbyData(id: int, key: String) -> String:
		return str(rooms.get(id, {}).get(key, ""))
	func getNumLobbyMembers(id: int) -> int:
		return int(rooms.get(id, {}).get("members", 0))
	func getLobbyMemberLimit(id: int) -> int:
		return int(rooms.get(id, {}).get("capacity", 0))
	func createLobby(kind: int, capacity: int) -> void:
		created.append([kind, capacity])
	func leaveLobby(_id: int) -> void:
		pass
	func joinLobby(id: int) -> void:
		joins.append(id)
	func setLobbyData(id: int, key: String, value: String) -> void:
		if not rooms.has(id):
			rooms[id] = {}
		rooms[id][key] = value
	func setLobbyJoinable(id: int, value: bool) -> void:
		rooms[id]["joinable"] = value
	func inviteUserToLobby(id: int, friend: int) -> bool:
		invites.append([id, friend])
		return true
	func getFriendCount(_flags: int) -> int:
		friends_read += 1
		return 0

var checks := 0
var failures := 0
var net: Node
var mock := SteamMock.new()
var messages: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ПРОВАЛ: ", message)


func frames() -> void:
	for i: int in 3:
		await process_frame


func click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	Input.warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await frames()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
		await frames()


func room(name: String, count: int = 2, capacity: int = 10) -> Dictionary:
	return {"game": "bgff_party", "appid": "480", "host": name, "members": count, "capacity": capacity}


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/batch27_lobbies"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots/batch27-lobbies"))
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.set_process(false)
	var saved_service: Object = net.steam
	var saved_ok: bool = net.steam_ok
	if Engine.has_singleton("Steam"):
		var binding: Object = Engine.get_singleton("Steam")
		check(binding.has_method("addRequestLobbyListResultCountFilter"), "Установленный GodotSteam поддерживает размер выдачи")
	net.steam = mock
	net.steam_ok = true
	net.status_changed.connect(func(text: String): messages.append(text))
	net.host_steam("")
	check(mock.created == [[2, 10]], "Новая пати создаётся публичной с прежней вместимостью10")
	net._publish_steam_lobby(900)
	check(mock.rooms[900].game == net.LOBBY_TAG and mock.rooms[900].appid == "480", "Публикуются тег игры и текущий appid")
	check(mock.rooms[900].joinable, "Пати доступна для входа")
	net.lobby_id = 105
	mock.rooms[101] = room("Незнакомый игрок")
	mock.rooms[102] = room("Другое приложение")
	mock.rooms[102].appid = "999"
	mock.rooms[103] = room("Чужой тег")
	mock.rooms[103].game = "other"
	mock.rooms[104] = room("Полная комната", 10)
	mock.rooms[105] = room("Своя комната")
	mock.rooms[106] = {"game": "bgff_party"}
	mock.rooms[107] = room("Пока нет данных", 0, 0)
	check(net.request_steam_lobbies(), "Асинхронный поиск принят")
	check(net.steam_lobbies_loading and net.steam_public_lobbies.is_empty(), "До callback список не выдумывается")
	check(net.lobby_id == 105, "Поиск не покидает текущую пати")
	check(mock.filters == [["distance", 3], ["game", "bgff_party", 0], ["appid", "480", 0], ["limit", 5000]], "Поиск глобальный с точными фильтрами приложения и расширенной выдачей")
	await frames()
	mock.lobby_match_list.emit([101, 102, 103, 104, 105, 106, 107, 101, 0, "не-id"])
	check(not net.steam_lobbies_loading, "Callback завершил ожидание")
	check(net.steam_public_lobbies.size() == 3, "Отброшены чужие appid/тег, своя комната, дубли и неверные значения")
	check(mock.friends_read == 0, "Общий список не ограничивается друзьями")
	check(not net.steam_public_lobbies[0].full, "Комната незнакомого игрока доступна")
	check(not net.join_public_steam_lobby(104) and mock.joins.is_empty(), "Полная комната не запускает вход")
	check(not net.join_public_steam_lobby(999), "Нельзя войти через браузер в отсутствующую строку")
	mock.rooms[101].members = 10
	check(not net.join_public_steam_lobby(101), "Повторно проверяется комната, заполнившаяся после callback")
	mock.rooms[101].members = 2
	var before := mock.requests
	net.request_steam_lobbies()
	for i: int in 4:
		net.request_steam_lobbies()
	check(mock.requests == before + 1, "Повторный refresh не создаёт перекрывающиеся поиски")
	mock.lobby_match_list.emit([101])
	check(mock.requests == before + 2 and net.steam_lobbies_loading, "Повторы объединены ровно в один следующий запрос")
	mock.rooms[108] = room("Свежая пати")
	mock.lobby_match_list.emit([108])
	check(net.steam_public_lobbies.size() == 1 and net.steam_public_lobbies[0].lobby == 108, "Показан результат последнего refresh")
	check(mock.filters.size() == mock.requests * 4, "Фильтры повторяются при каждом запросе")
	check(mock.get_signal_connection_list("lobby_match_list").size() == 1, "Callback не подписывается повторно")
	mock.lobby_match_list.emit([101])
	check(net.steam_public_lobbies[0].lobby == 108, "Незапрошенный поздний callback игнорируется")
	net.request_steam_lobbies()
	var serial: int = net._steam_lobby_request
	net._on_steam_lobby_timeout(serial - 1)
	check(net.steam_lobbies_loading, "Таймер прошлого запроса не завершает новый")
	net._on_steam_lobby_list([101], SteamMock.new())
	check(net.steam_lobbies_loading, "Callback другой службы не принят")
	net._on_steam_lobby_timeout(serial)
	check(not net.steam_lobbies_loading and not net.steam_lobbies_error.is_empty(), "Тайм-аут показан и позволяет повторить поиск")
	mock.lobby_match_list.emit([101])
	check(not net.steam_lobbies_error.is_empty(), "Callback после тайм-аута без нового запроса не принят")
	net.request_steam_lobbies()
	mock.lobby_match_list.emit([])
	check(net.steam_public_lobbies.is_empty() and net.steam_lobbies_error.is_empty(), "Повтор после тайм-аута возвращает пустой корректный список")
	await _ui()
	net.join_steam(333)
	check(mock.joins.back() == 333 and net.last_join.lobby == 333, "Прежний вход по коду сохраняется")
	net._on_join_requested(444, 777)
	check(mock.joins.back() == 444, "Запрос входа из приглашения сохраняется")
	net.lobby_id = 444
	check(net.invite_friend(777) and mock.invites.back() == [444, 777], "Отправка приглашения сохраняется")
	net._on_lobby_joined(444, 0, false, 4)
	check(messages.back().contains("полное"), "Отказ Steam при полном лобби показан без запуска peer")
	net.lobby_id = 0
	net.steam_ok = false
	check(not net.request_steam_lobbies() and not net.steam_lobbies_error.is_empty(), "Нет Steam — явное сообщение без запроса")
	net.steam = saved_service
	net.steam_ok = saved_ok
	print("STEAM ПУБЛИЧНЫЕ ПАТИ: проверок=", checks, " ошибок=", failures)
	await root.get_node("Sfx").request_quit(1 if failures else 0)


func _ui() -> void:
	var script: Script = load("res://hub/steam_invite.gd")
	script.open_browser()
	await frames()
	var browser: Node
	for node: Node in root.get_children():
		if node.get_script() == script and node._browse:
			browser = node
	check(is_instance_valid(browser), "Открывается общий браузер")
	var count := mock.requests
	script.open_browser()
	check(mock.requests == count, "Повторное открытие не создаёт второе окно/поиск")
	await click(browser._refresh)
	check(mock.requests == count, "Настоящий клик не запускает disabled refresh во время ожидания")
	mock.lobby_match_list.emit([101, 104, 107])
	await frames()
	check(not browser._refresh.disabled and browser._list.get_child_count() == 3, "Callback обновляет открытое окно")
	var full: Button = browser._list.get_child(2).get_child(2)
	var joins := mock.joins.size()
	await click(full)
	check(mock.joins.size() == joins and full.disabled, "Мышь не входит в полную комнату")
	for mode: String in ["light", "dark"]:
		root.get_node("Prefs").theme_mode = mode
		root.get_node("Prefs").changed.emit()
		await frames()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			check(image.save_png("res://build/shots/batch27-lobbies/" + mode + ".png") == OK, "Снимок браузера: " + mode)
	await click(browser._refresh)
	check(net.steam_lobbies_loading and mock.requests == count + 1, "Настоящий refresh запустил новый поиск")
	browser.queue_free()
	await frames()
	mock.lobby_match_list.emit([])
	check(not is_instance_valid(browser), "Закрытое окно не получает callback")
	script.open_browser()
	await frames()
	for node: Node in root.get_children():
		if node.get_script() == script and node._browse:
			browser = node
	mock.lobby_match_list.emit([101])
	await frames()
	var join: Button = browser._list.get_child(0).get_child(2)
	mock.rooms[101].members = 10
	await click(join)
	check(is_instance_valid(browser) and mock.joins.size() == joins, "Настоящий клик проверяет заполнение после получения списка")
	mock.rooms[101].members = 2
	await click(join)
	check(mock.joins.back() == 101 and not is_instance_valid(browser), "Настоящий клик входит в публичную пати незнакомого игрока")
