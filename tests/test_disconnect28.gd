extends SceneTree
## Удалённые RoomPanel и сохранение причины разрыва до очистки; транспортные события подготовлены.
class Capture:
	extends Logger
	var failures: Array = []
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _notify: bool, type: int, _traces: Array[ScriptBacktrace]) -> void:
		if type != 1:
			failures.append(code + rationale)
class SteamMock:
	extends RefCounted
	var leaves: Array = []
	var closing := Callable()
	func leaveLobby(id: int) -> void:
		leaves.append(id)
		if closing.is_valid():
			closing.call()
var checks := 0
var errors := 0
var capture := Capture.new()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	await process_frame
	var net = root.get_node("Net")
	net.set_process(false)
	OS.add_logger(capture)
	var room_type = load("res://hub/room_panel.gd")
	var before: int = net.status_changed.get_connections().size()
	for i in 12:
		var panel: Control = room_type.make("the_gang", func(t, _s):
			var button := Button.new()
			button.text = t
			return button, func(t, _s):
				var label := Label.new()
				label.text = t
				return label)
		root.add_child(panel)
		net.status_changed.emit("Статус%d" % i)
		check(panel.get("_status").text == "Статус%d" % i, "Живая панель получила статус")
		panel.queue_free()
		await process_frame
		net.status_changed.emit("Повторный вход")
	check(net.status_changed.get_connections().size() == before, "Обработчики удалённых панелей не накапливаются")
	check(capture.failures.is_empty(), "Повторный вход не обращается к freed capture")
	var safe = load("res://hub/connection_diagnostics.gd")
	var clean: Dictionary = safe.safe_state({"connection_state": 5, "end_reason": 5003, "end_debug": "timeout", "address": "PRIVATE", "secret_cards": ["PRIVATE"], "description": "x".repeat(900)})
	check(clean.end_reason == 5003 and clean.end_debug == "timeout", "Код и описание транспорта сохранены")
	check(not clean.has("address") and not clean.has("secret_cards"), "Игровые данные и адрес не попадают в событие")
	check(clean.description.length() == 512, "Размер описания ограничен")
	var old_steam: Object = net.steam
	var old_ok: bool = net.steam_ok
	var steam := SteamMock.new()
	net.steam = steam
	net.steam_ok = true
	steam.closing = net._on_server_disconnected
	var closed: Array = []
	net.session_closed.connect(func(reason): closed.append(reason))
	net.mode = "steam"
	net.party_game = "the_gang"
	net.game_id = "prepared-match28"
	net.lobby_id = 28001
	net.in_game = true
	net.view = {"phase": "estimate"}
	net._on_steam_connection_status(77, {"connection_state": 5, "end_reason": 5003, "end_debug": "timeout"}, 3)
	check(net.in_game and net.mode == "steam", "Диагностический callback не отключает игрока")
	net._on_server_disconnected()
	check(closed.size() == 1, "Потеря связи выдаёт одно уведомление, включая reentrant close")
	check(net.mode == "" and net.view.is_empty() and net.lobby_id == 0, "Сеть очищена после сохранения причины")
	check(net.last_disconnect.партия_до_выхода == "prepared-match28" and net.last_disconnect.лобби_до_выхода == 28001, "Старые партия и лобби не потеряны")
	check(net.last_disconnect.транспорт[0].данные.end_reason == 5003, "Код доступен после leave")
	check(net.last_disconnect.причина.contains("server_disconnected"), "Источник разрыва записан явно")
	var diag = root.get_node("Diag")
	var report: String = FileAccess.get_file_as_string(diag.session.log)
	check(report.contains("5003") and report.contains("server_disconnected"), "Код и причина записаны в реальный файл, не только в переменную Net")
	check(report.contains("лобби_до_выхода") and report.contains("28001"), "Идентификатор до очистки доступен в сохранённом логе")
	net._on_server_disconnected()
	check(closed.size() == 1, "Поздний повторный callback не создаёт ложный выход")
	check(steam.leaves == [28001], "LeaveLobby вызван один раз")
	net.mode = "steam"
	net.party_game = "gloom"
	net.lobby_id = 28002
	net.leave("Проверяемый добровольный выход")
	check(closed.size() == 1 and net.last_disconnect.причина == "Проверяемый добровольный выход", "Добровольный выход отличается от потери связи")
	net.steam = old_steam
	net.steam_ok = old_ok
	OS.remove_logger(capture)
	print("DISCONNECT28: проверок=", checks, " ошибок=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
