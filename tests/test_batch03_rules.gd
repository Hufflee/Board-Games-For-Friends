extends SceneTree
## Адресные проверки03.11: случайная выборка Word Slam, таймер Чернил и повторный вход Steam.
const WS := preload("res://games/word_slam/logic/ws_rules.gd")
const Data := preload("res://games/word_slam/logic/ws_data.gd")
const PI := preload("res://games/phantom_ink/logic/pi_rules.gd")
var checks := 0
var errors := 0

class SteamSession extends RefCounted:
	var online := false
	func loggedOn() -> bool: return online
	func getSteamID() -> int: return 123 if online else 0
	func getPersonaName() -> String: return "Друг"

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for category: String in Data.CATEGORIES:
		var pool := Data.story_pool(category)
		check(pool.size() == Data.STORY[category].size() * (1 if category == "other" else 3), "Пул категории ровно утроен: " + category)
		var unique := {}
		for word: String in pool: unique[word] = true
		check(unique.size() == pool.size(), "В пуле нет повторов: " + category)
	var players := [{"name": "А", "team": 0}, {"name": "Б", "team": 0}, {"name": "В", "team": 1}, {"name": "Г", "team": 1}]
	for seed_value: int in range(1, 11):
		var game := WS.new()
		game.new_game(players, false, 3, false, false, seed_value, "basic")
		var previous := JSON.stringify(game.catalog_order)
		for category: String in Data.CATEGORIES:
			check(game.catalog_order[category].size() == Data.STORY[category].size(), "Размер выдачи сохранён: " + category)
		check(game.reroll(game.drawer()) and JSON.stringify(game.catalog_order) != previous, "Смена слова выбирает новый случайный набор")
		for seat: int in game.storytellers: game.set_ready(seat)
		var missing := ""
		for index: int in Data.story_pool("noun").size():
			if not game.catalog_order.noun.has("noun:%d" % index): missing = "noun:%d" % index; break
		check(not game.set_holders(game.storytellers[0], [[missing], []]), "Не выданную подсказку нельзя добавить поддельным действием")
	var pi := PI.new()
	pi.new_game(players, [0, 1, 2, 3], 4)
	pi.phase = "turn"
	pi.turn_time = 45
	pi.time_left = 45
	check(pi.tick(2) and pi.time_left == 43, "Таймер обсуждения действительно считает секунды")
	pi.turn_time = 0
	pi.tick(2)
	check(pi.time_left == 43, "Отключённый таймер не идёт")
	pi.turn_time = 45
	pi.phase = "object"
	pi.tick(2)
	check(pi.time_left == 43, "Выбор тайного слова не ограничен таймером обсуждения")
	var net := root.get_node("Net")
	net.host_offline("phantom_ink")
	net.set_bots(3)
	check(net.start_game().is_empty(), "Чернила запущены через настоящий Net")
	net.phantom.phase = "turn"
	net.host_tools.set_timer(true, 45)
	net._process(2)
	check(net.phantom.time_left == 43 and net.view.turn_total == 45 and net.view.turn_left == 43 and net.view.clock, "Панель хоста включает реальные часы Чернил и передаёт остаток клиенту")
	net.host_tools.set_timer(false, 45)
	check(net.phantom.turn_time == 0 and net.view.turn_total == 0, "Отключение убирает часы Чернил из view")
	net.leave()
	net.host_offline("cg")
	net.set_bots(1)
	check(net.start_game().is_empty(), "Пользовательская игра запущена через Net")
	net.host_tools.set_timer(true, 45)
	check(net.cg.state.turn_seconds == 45 and net.cg.state.timer_left == 45, "Панель обновляет сериализуемый таймер пользовательской игры")
	net.leave()
	net.host_offline("word_slam")
	net.set_bots(3)
	check(net.start_game().is_empty(), "Word Slam запущен через Net")
	net.host_tools.set_timer(true, 45)
	check(net.turn_limit() == 45 and net.view.turn_total == 45 and net.settings.ws_time == 45, "Подготовка и объяснение Word Slam используют один настроенный таймер")
	net.leave()
	var original_steam: Object = net.steam
	var original_ready: bool = net._steam_initialized
	var probe := SteamSession.new()
	net.steam = probe
	net._steam_initialized = true
	net.refresh_steam_session()
	check(not net.steam_ok, "Steam без входа недоступен")
	probe.online = true
	net.refresh_steam_session()
	check(net.steam_ok and net.my_steam_id == 123, "Вход Steam в запущенной игре обновляет сессию")
	net.refresh_steam_session()
	check(net.steam_ok, "Повторная проверка сессии идемпотентна")
	net.steam = original_steam
	net._steam_initialized = original_ready
	print("BATCH03 RULES: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
