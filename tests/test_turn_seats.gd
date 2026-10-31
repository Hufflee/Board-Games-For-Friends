extends SceneTree
## Тест TurnSeats на синтетических view. Запуск:
## godot --headless --audio-driver Dummy --path . --script res://tests/test_turn_seats.gd

var _fails := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("ПРОВАЛ: ", msg)


func _init() -> void:
	var pl3 := [{"team": 0}, {"team": 1}, {"team": 0}]
	check(TurnSeats.acting("poker", {"phase": "hand", "to_act": 2}) == [2], "покер: ходит to_act")
	check(TurnSeats.acting("poker", {"phase": "showdown", "to_act": 2}).is_empty(), "покер: вскрытие — пусто")
	check(TurnSeats.acting("brodilka", {"phase": "roll", "turn": 1, "waiting": -1}) == [1], "бродилка: ходит turn")
	check(TurnSeats.acting("brodilka", {"phase": "prompt", "turn": 1, "waiting": 0}) == [0], "бродилка: выбор у waiting")
	check(TurnSeats.acting("perudo", {"phase": "roll", "counts": [5, 0, 5], "shaken": [true, false, false]}) == [2], "перудо: трясут живые, не потрясшие")
	check(TurnSeats.acting("perudo", {"phase": "bid", "turn": 1}) == [1], "перудо: ставка у turn")
	check(TurnSeats.acting("gloom", {"phase": "trim", "trim_left": [0, 2]}) == [0, 2], "gloom: trim_left")
	check(TurnSeats.acting("gloomier", {"phase": "play", "current": 1}) == [1], "gloomier как gloom")
	check(TurnSeats.acting("things_in_rings", {"phase": "blind", "blind_waiting": [1, 2], "actor": -1}) == [1, 2], "TIR: blind — кто не поставил")
	check(TurnSeats.acting("things_in_rings", {"phase": "place", "actor": 0}) == [0], "TIR: place — actor")
	check(TurnSeats.acting("things_in_rings", {"phase": "postgame", "actor": 0}).is_empty(), "TIR: postgame — пусто")
	check(TurnSeats.acting("wavelength", {"phase": "guess", "players": pl3, "active_team": 0, "psychic": 0}) == [2], "wavelength: угадывает команда без телепата")
	check(TurnSeats.acting("tip_top", {"phase": "answer", "players": pl3, "captain": 0, "answered": [1]}) == [2], "tip_top: не ответившие")
	check(TurnSeats.acting("king_of_12", {"phase": "select", "players": pl3, "active": [], "chosen": [true, false, false]}) == [1, 2], "k12: не выбравшие")
	check(TurnSeats.acting("king_of_12", {"phase": "oracle", "players": pl3, "pending": {"seat": 1}}) == [1], "k12: pending.seat")
	check(TurnSeats.acting("the_gang", {"phase": "rank", "players": pl3, "chips": [0, 2, 0]}) == [0, 2], "the_gang: без фишки")
	check(TurnSeats.acting("phantom_ink", {"phase": "object", "team": 0, "roles": [0, 1, 2, 3]}) == [1, 3], "phantom_ink: object — духи")
	check(TurnSeats.acting("phantom_ink", {"phase": "turn", "team": 1, "roles": [0, 1, 2, 3]}) == [2], "phantom_ink: turn — живой команды")
	check(TurnSeats.acting("stillion", {"phase": "fuse", "target": 1}) == [1], "stillion: цель пушки")
	check(TurnSeats.acting("poker", {"phase": "game_over", "to_act": 1}).is_empty(), "game_over — пусто")
	check(TurnSeats.acting("unknown", {"phase": "x", "players": pl3}).is_empty(), "неизвестная игра — пусто")
	check(TurnSeats.is_mine({"game": "poker", "phase": "hand", "to_act": 2, "you": 2}), "is_mine: моё место")
	check(not TurnSeats.is_mine({"game": "poker", "phase": "hand", "to_act": 2, "you": 1}), "is_mine: чужое")
	check(not TurnSeats.is_mine({"game": "poker", "phase": "hand", "to_act": 2, "you": -1}), "is_mine: зритель")
	check(TurnSeats.is_mine({"game": "stillion", "phase": "fuse", "target": 0, "seat": 0}), "is_mine: seat")
	print("TurnSeats: ", "OK" if _fails == 0 else "ПРОВАЛОВ %d" % _fails)
	quit(1 if _fails > 0 else 0)
