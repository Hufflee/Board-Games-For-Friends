extends SceneTree
## Конечная матрица преобразования итогов всех 17 записей хаба. Запуск headless с Dummy.
var checks := 0
var errors := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)
func _run() -> void:
	var adapter: Script = load("res://hub/victory_result.gd")
	var helper: Script = load("res://hub/victory_screen.gd")
	check(helper.can_instantiate(), "Общий экран компилируется")
	var players := []
	for seat: int in 10:
		players.append({"name": "Игрок %d" % seat, "team": seat % 2})
	for entry: Dictionary in load("res://hub/games.gd").LIST:
		var id: String = entry.id
		var view := {"players": players, "phase": "game_over", "winner": 1, "winners": [1], "won": true,
			"roles": [0, 1, 2, 3, 0, 1, 2, 3, 0, 1], "mode": "teams"}
		var expected: Array = [1]
		if id in ["tip_top", "tip_top_18", "the_gang"]:
			expected = range(10)
		elif id in ["dangerous_words", "wavelength", "word_slam"]:
			expected = [1, 3, 5, 7, 9]
		elif id == "phantom_ink":
			expected = [2, 3, 6, 7]
		var out: Dictionary = adapter.resolve(id, view)
		check(out.finished and out.winners == expected, "%s: победившие места %s != %s" % [id, out.winners, expected])
		check(out.winners.size() + out.others.size() == 10, "%s: все участники учтены ровно один раз" % id)
		view.phase = "play"
		check(not adapter.resolve(id, view).finished, "%s: не показывать промежуточный результат" % id)
	for id: String in ["tip_top", "tip_top_18", "the_gang", "hues_and_cues"]:
		var out: Dictionary = adapter.resolve(id, {"players": players, "phase": "game_over", "won": false, "winners": [], "coop": true})
		check(out.winners.is_empty() and out.others.size() == 10, "%s: кооперативный проигрыш" % id)
	var pi: Dictionary = adapter.resolve("phantom_ink", {"players": players, "phase": "game_over", "winner": -1, "roles": [0, 1, 2, 3]})
	check(pi.winners.is_empty(), "Чернила: никто не угадал")
	var wl: Dictionary = adapter.resolve("wavelength", {"players": players, "phase": "game_over", "winner": 0, "coop": true, "scores": [16, 0]})
	check(wl.winners == range(10), "Длина волны: кооперативный результат")
	check(adapter.resolve("wavelength", {"players": players, "phase": "game_over", "winner": 0, "coop": true, "scores": [15, 0]}).winners.is_empty(), "Длина волны: ниже цели без победы")
	var ws: Dictionary = adapter.resolve("word_slam", {"players": players, "phase": "game_over", "winners": [1, 3], "mode": "solo"})
	check(ws.winners == [1, 3] and not ws.team, "Word Slam: индивидуальное равенство")
	var tie: Dictionary = adapter.resolve("gloom", {"players": players, "phase": "game_over", "winners": [1, 2, 2, -1, 99]})
	check(tie.winners == [1, 2], "Равенство и фильтрация невалидных/повторных мест")
	check(not adapter.resolve("the_gang", {}).finished, "Пустой view")
	print("VICTORY ADAPTER ", checks, "/", errors)
	root.get_node("Sfx").stop_audio()
	quit(1 if errors else 0)

