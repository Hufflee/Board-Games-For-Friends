## Независимые low-границы SteamBrowse; только mock, без matchmaking/peer/живого Steam.
extends "res://tests/test_steam_public_lobbies.gd"

class AppMock extends SteamMock:
	var app_id := 480
	func getAppID() -> int: return app_id

class ErrorCapture extends Logger:
	var errors: Array[String] = []
	func _log_error(_function: String, _file: String, _line: int, code: String, _rationale: String,
			_notify: bool, kind: int, _traces: Array[ScriptBacktrace]) -> void:
		if kind != 1: errors.append(code)

func browser_node(script: Script) -> Node:
	for node in root.get_children():
		if node.get_script() == script and node._browse: return node
	return null

func _run() -> void:
	var capture := ErrorCapture.new()
	OS.add_logger(capture)
	net = root.get_node("Net")
	net.set_process(false)
	var saved_service: Object = net.steam
	var saved_ok: bool = net.steam_ok
	net.steam = mock
	net.steam_ok = true
	net.view = {"fixture": "view_before_browse", "hand": ["PRIVATE_SENTINEL_NOT_LOGGED"]}
	var previous_view: Dictionary = net.view.duplicate(true)
	mock.rooms[11] = room("Старая служба")
	check(net.request_steam_lobbies(), "Первый mock-запрос принят")
	var old_serial: int = net._steam_lobby_request
	var old_service := mock
	var newer := AppMock.new()
	newer.app_id = 777
	newer.rooms[12] = room("Верная новая пати")
	newer.rooms[12].appid = "777"
	newer.rooms[13] = room("Прежний AppID")
	net.steam = newer
	check(net.request_steam_lobbies() and newer.requests == 1, "Смена Steam во время ожидания начинает новый запрос")
	check(old_service.get_signal_connection_list("lobby_match_list").is_empty(), "Старый source отписан")
	old_service.lobby_match_list.emit([11])
	net._on_steam_lobby_list([11], old_service)
	check(net.steam_lobbies_loading and net.steam_public_lobbies.is_empty(), "Старый/чужой callback не завершает текущий поиск")
	net._on_steam_lobby_timeout(old_serial)
	check(net.steam_lobbies_loading, "Таймер старой службы не завершает новый запрос")
	newer.lobby_match_list.emit([12, 13])
	check(net.steam_public_lobbies.size() == 1 and net.steam_public_lobbies[0].lobby == 12, "Фильтр использует текущий AppID777, не константу480")
	check(newer.filters.has(["appid", "777", 0]), "В SDK запрос передан новый appid")
	# Пере-проверка изменившихся данных перед входом, а не только фильтрация старого списка.
	newer.rooms[12].appid = "480"
	check(not net.join_public_steam_lobby(12) and newer.joins.is_empty(), "AppID изменился после списка — join блокирован")
	newer.rooms[12].appid = "777"
	newer.rooms[12].game = "other"
	check(not net.join_public_steam_lobby(12) and newer.joins.is_empty(), "Tag изменился после списка — join блокирован")
	newer.rooms[12].game = net.LOBBY_TAG
	var script: Script = load("res://hub/steam_invite.gd")
	var connections: int = net.get_signal_connection_list("steam_lobbies_changed").size()
	script.open_browser()
	await frames()
	var browser := browser_node(script)
	check(browser != null and net.steam_lobbies_loading, "Окно открыто во время запроса")
	var serial: int = net._steam_lobby_request
	var requests: int = newer.requests
	var weak: WeakRef = weakref(browser)
	browser.queue_free()
	await frames()
	check(not is_instance_valid(weak.get_ref()) and net.get_signal_connection_list("steam_lobbies_changed").size() == connections, "Освобождённое окно отписано, объект действительно удалён")
	newer.lobby_match_list.emit([12])
	check(not net.steam_lobbies_loading and net.steam_public_lobbies[0].lobby == 12, "Закрытие UI не ломает безопасное завершение запроса/кеш")
	script.open_browser()
	await frames()
	browser = browser_node(script)
	for i in 8: net.request_steam_lobbies()
	check(newer.requests == requests + 1, "Восемь refresh не создают перекрывающихся запросов")
	newer.lobby_match_list.emit([12])
	check(newer.requests == requests + 2 and net.steam_lobbies_loading, "Refresh объединён ровно в один следующий")
	var active_serial: int = net._steam_lobby_request
	net._on_steam_lobby_timeout(serial)
	check(net.steam_lobbies_loading, "Старый таймер окна не завершает объединённый запрос")
	net._on_steam_lobby_timeout(active_serial)
	check(not net.steam_lobbies_loading and not net.steam_lobbies_error.is_empty() and not browser._refresh.disabled, "Timeout разблокирует UI refresh и показывает ошибку")
	var error: String = net.steam_lobbies_error
	newer.lobby_match_list.emit([12])
	check(net.steam_lobbies_error == error, "Поздний callback после timeout без нового запроса игнорируется")
	net.request_steam_lobbies()
	newer.lobby_match_list.emit([])
	check(net.steam_public_lobbies.is_empty() and net.steam_lobbies_error.is_empty(), "Повтор после timeout принимает пустую выдачу")
	browser.queue_free()
	await frames()
	# Недоступность Steam между request и callback.
	net.request_steam_lobbies()
	net.steam_ok = false
	check(not net.request_steam_lobbies() and not net.steam_lobbies_loading, "Потеря Steam снимает loading с явной ошибкой")
	newer.lobby_match_list.emit([12])
	check(not net.steam_lobbies_error.is_empty() and net.steam_public_lobbies.is_empty(), "Callback после потери Steam не возвращает старые строки")
	check(net.view == previous_view, "Поиск/timeout/cancel/changedSteam не меняют view и приватную руку")
	check(capture.errors.is_empty(), "Нет ошибок вызовов к freed UI/source")
	net.view = {}
	net.steam = saved_service
	net.steam_ok = saved_ok
	OS.remove_logger(capture)
	print("STEAM BROWSE LOW: checks=", checks, " failures=", failures)
	await root.get_node("Sfx").request_quit(1 if failures else 0)
