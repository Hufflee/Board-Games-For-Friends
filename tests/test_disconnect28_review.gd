extends SceneTree
## Независимые границы лога/кольца/синхронного close. Steam только mock, без native/сокетов.
var checks := 0
var errors := 0
class SteamMock extends RefCounted:
	var closing := Callable()
	var calls := 0
	func leaveLobby(_id: int) -> void:
		calls += 1
		if closing.is_valid():
			closing.call()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	await process_frame
	var net: Node = root.get_node("Net")
	var diag: Node = root.get_node("Diag")
	net.set_process(false)
	var safe: GDScript = load("res://hub/connection_diagnostics.gd")
	var cleaned: Dictionary = safe.safe_event({"событие":"event", "описание":"x".repeat(600), "handle":"не int", "состояние":4, "remote_steam_id":999, "hand":["LOW_PRIVATE_CARD"], "данные":{"connection_state":4,"address":"LOW_PRIVATE_ADDRESS","token":"LOW_PRIVATE_TOKEN","end_reason":5003,"nested":{"hand":[1]}}})
	check(cleaned.описание.length() == 512 and cleaned.состояние == 4 and not cleaned.has("handle"), "Типы/длины технических полей ограничены")
	check(cleaned.данные == {"connection_state":4,"end_reason":5003} and not cleaned.has("hand") and not cleaned.has("remote_steam_id"), "Секретные/неизвестные поля не сохраняются")
	var wrong: Dictionary = diag._safe_details({"причина":[],"лобби_до_выхода":"bad","была_партия":1,"транспорт":["bad",{"событие":"x","secret":"LOW_PRIVATE_EVENT"}],"unknown":"LOW_PRIVATE_UNKNOWN"})
	check(not wrong.has("причина") and not wrong.has("лобби_до_выхода") and not wrong.has("была_партия") and not wrong.has("unknown"), "Неверные типы новых whitelist-полей отклоняются")
	check(wrong.транспорт == [{"событие":"x"}], "Не-Dictionary транспорт и неизвестные поля отбрасываются")
	var old_steam: Object = net.steam
	var old_ok: bool = net.steam_ok
	var mock := SteamMock.new()
	net.steam = mock
	net.steam_ok = true
	var closed := []
	net.session_closed.connect(func(reason): closed.append(reason))
	net.mode = "steam"
	net.party_game = "the_gang"
	net.game_id = "low-ring-match"
	net.lobby_id = 28991
	net.in_game = true
	net.view = {"phase":"rank","hand":["LOW_PRIVATE_CARD"]}
	for i in 21:
		net._on_steam_connection_status(i, {"connection_state":3,"end_reason":5003,"end_debug":"safe-%d"%i,"address":"LOW_PRIVATE_ADDRESS","hand":["LOW_PRIVATE_CARD"]}, 2)
	check(net._steam_transport_events.size() == 16 and net._steam_transport_events[0].handle == 5 and net._steam_transport_events[-1].handle == 20, "Кольцо хранит последние16 из21, не первые")
	check(net.in_game and net.mode == "steam" and closed.is_empty(), "Сами Steam diagnostic callbacks не закрывают игру")
	mock.closing = func():
		net._on_steam_message_failure(999, 987654321, 5, "close callback")
		net._on_connection_failed()
		net._on_server_disconnected()
		net.leave("вложенный leave")
	net._on_connection_failed()
	check(mock.calls == 1 and closed.size() == 1 and not net._leaving, "Синхронные close callbacks/leave защищены от рекурсии")
	check(net.last_disconnect.причина.begins_with("connection_failed") and net.last_disconnect.лобби_до_выхода == 28991 and net.last_disconnect.партия_до_выхода == "low-ring-match", "Исходная причина/лобби/партия не затёрты reentrant callback")
	check(net.last_disconnect.транспорт.size() == 16 and net.last_disconnect.транспорт[0].handle == 5 and net._steam_transport_events.is_empty(), "Снимок транспорта переживает очистку текущего буфера")
	var previous: Dictionary = net.last_disconnect.duplicate(true)
	net._on_server_disconnected()
	net._on_connection_failed()
	net._on_steam_connection_status(99, {"end_reason":999}, 4)
	net._on_steam_message_failure(999, 987654321, 5, "late")
	check(closed.size() == 1 and net.last_disconnect == previous and net._steam_transport_events.is_empty(), "Поздние callbacks после очистки не повторяют закрытие и не меняют снимок")
	diag.mark("LOW privacy fixture", {"транспорт":[cleaned],"unknown":"LOW_PRIVATE_UNKNOWN","причина":"безопасная причина"})
	var log := FileAccess.get_file_as_string(diag.session.log)
	check(log.contains("5003") and log.contains("28991") and log.contains("connection_failed") and log.contains("low-ring-match"), "Реальный файл содержит исходный код/причину/идентичность")
	check(not log.contains("LOW_PRIVATE_CARD") and not log.contains("LOW_PRIVATE_ADDRESS") and not log.contains("LOW_PRIVATE_UNKNOWN") and not log.contains("LOW_PRIVATE_TOKEN"), "Новый путь не выносит fixture-секреты в реальный файл")
	# Переключение режима: старые Steam diagnostics не загрязняют новый ENet/offline-сеанс.
	net.mode = "offline"
	net.party_game = "the_gang"
	net._on_steam_connection_status(100, {"end_reason":5003}, 5)
	net._on_steam_message_failure(5003, 987654321, 5, "old steam")
	check(net._steam_transport_events.is_empty() and net.mode == "offline", "Старые Steam события игнорируются в другом режиме")
	net.leave("low завершение")
	net.steam = old_steam
	net.steam_ok = old_ok
	print("DISCONNECT LOW28: проверок=", checks, " ошибок=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
