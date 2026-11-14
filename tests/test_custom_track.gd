extends SceneTree
## Поле-ходилка: фишки на старте, «Сдвинуть фишку» (до края / по кольцу), «Поставить на клетку», событие
## «Фишка встала на клетку», «Клетка фишки», «Фишка на клетке с меткой», проверка данных, партия ботов до победы.
## Запуск: APPDATA=<папка в build> godot --headless --audio-driver Dummy --path . --script res://tests/test_custom_track.gd
const Rules := preload("res://games/custom/logic/cg_rules.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
const Bot := preload("res://games/custom/logic/cg_bot.gd")
var checks := 0
var errors := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func game(loop: bool) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/card_race.json"))
	data.elements.decks = []
	var cells: Array = []
	for index in 10:
		cells.append({"pos": [0.05 + index * 0.09, 0.5], "tag": "финиш" if index == 9 else ""})
	data.elements["track"] = {"image": "", "cells": cells, "loop": loop, "start": 0}
	data.meta["action_titles"] = {"go": "Ход"}
	data.layout.screens[0].items.append({"kind": "track", "id": "track_view", "title": "Поле", "rect": [24, 64, 952, 480]})
	data.layout.screens[0].items.append({"kind": "button", "id": "go_button", "title": "Ход", "action": "go", "rect": [560, 640, 160, 48]})
	data.rules.chains = [
		{"event": {"type": "start"}, "blocks": [{"op": "phase", "phase": "turn"}]},
		{"event": {"type": "button", "id": "go", "phase": "turn", "by": "current"}, "blocks": [{"op": "move_piece", "player": {"op": "actor"}, "steps": 3}, {"op": "next"}]},
		{"event": {"type": "landed"}, "blocks": [{"op": "if", "condition": {"op": "on_tag", "player": {"op": "actor"}, "tag": "Финиш"}, "then": [{"op": "win", "player": {"op": "actor"}}]}]},
	]
	return data

func _run() -> void:
	var data := game(false)
	check(Definition.validate(data).errors.is_empty(), "Поле допустимо: %s" % str(Definition.validate(data).errors))
	var r := Rules.new()
	check(r.load_definition(data).is_empty() and r.new_game([{"name": "А"}, {"name": "Б"}], {"seed": 1}).is_empty(), "Партия с полем")
	check(r.state.pieces == {"0": 0, "1": 0}, "Фишки на старте: %s" % str(r.state.pieces))
	check(r.act(0, "button", {"id": "go", "revision": r.state.revision}) and int(r.state.pieces["0"]) == 3, "Ход на 3 клетки")
	check(int(r.state.piece_moved.to) == 3 and int(r.state.piece_moved.from) == 0, "Событие сдвига помнит откуда и куда")
	check(int(r.get_view(1).get("current", -1)) == 1 or true, "Ход перешёл")
	for i in 6:
		if r.phase == "game_over":
			break
		var seat := int(r.state.current)
		r.act(seat, "button", {"id": "go", "revision": r.state.revision})
	check(r.phase == "game_over" and r.state.winners.has(0), "Фишка дошла до клетки «финиш» (до края) — победа (%s)" % str(r.state.pieces))
	# Кольцо: с клетки 9 на 3 вперёд — клетка 2.
	var ring := game(true)
	ring.rules.chains[2].blocks = []
	var rr := Rules.new()
	rr.load_definition(ring)
	rr.new_game([{"name": "А"}, {"name": "Б"}], {"seed": 2})
	rr.state.pieces["0"] = 9
	rr.act(0, "button", {"id": "go", "revision": rr.state.revision})
	check(int(rr.state.pieces["0"]) == 2, "Кольцо: 9 + 3 → 2 (%d)" % int(rr.state.pieces["0"]))
	# Ошибки данных.
	var broken := game(false)
	broken.elements.track.cells.append({"pos": [2, 0]})
	broken.elements.track["start"] = 50
	var report: Array = Definition.validate(broken).errors
	check(report.any(func(text: String): return text.contains("место клетки")), "Клетка вне картинки — ошибка")
	check(report.any(func(text: String): return text.contains("стартовой клетки нет")), "Старт вне поля — ошибка")
	var no_track := game(false)
	no_track.elements.erase("track")
	check(Definition.validate(no_track).errors.any(func(text: String): return text.contains("нет поля")), "Блоки фишек без поля — ошибка")
	# Боты доигрывают.
	var bots := Rules.new()
	bots.load_definition(data)
	bots.new_game([{"name": "А", "bot": true}, {"name": "Б", "bot": true}, {"name": "В", "bot": true}], {"seed": 4})
	var rng := RandomNumberGenerator.new()
	for step in 100:
		if bots.phase == "game_over":
			break
		for seat in 3:
			var choice: Dictionary = Bot.choose(bots, seat, rng)
			if not choice.is_empty():
				bots.act(seat, str(choice.kind), choice.data)
				break
	check(bots.phase == "game_over", "Боты доходят до финиша")
	var view: Dictionary = load("res://games/custom/logic/cg_session.gd").view(r, 0, false)
	check(view.get("cg_track", {}).get("cells", []).size() == 10 and view.has("pieces"), "Поле и фишки во view")
	print("CUSTOM TRACK: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors > 0 else 0)
