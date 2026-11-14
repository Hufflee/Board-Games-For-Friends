extends SceneTree
## Бот пользовательской игры: случайный допустимый ход доигрывает примеры и игры из шаблонов без ошибок правил.
## Запуск: APPDATA=<папка в build> godot --headless --audio-driver Dummy --path . --script res://tests/test_custom_bot.gd
const Rules := preload("res://games/custom/logic/cg_rules.gd")
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

## Все места — боты; до 600 ходов. Возвращает {moves, over, error}.
func play(data: Dictionary, seed_value: int) -> Dictionary:
	var r := Rules.new()
	var players: Array = []
	for seat in int(data.meta.get("players", [2, 8])[1]):
		players.append({"name": "Бот %d" % seat, "team": seat % 2, "bot": true})
	if not r.load_definition(data).is_empty() or not r.new_game(players, {"seed": seed_value}).is_empty():
		return {"moves": 0, "over": false, "error": "старт: " + r.last_error}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var moves := 0
	for step in 600:
		if r.phase == "game_over":
			break
		var moved := false
		for seat in r.players.size():
			var choice: Dictionary = Bot.choose(r, seat, rng)
			if choice.is_empty():
				continue
			if not r.act(seat, str(choice.kind), choice.data):
				return {"moves": moves, "over": false, "error": "%s: %s" % [str(choice), r.last_error]}
			moves += 1
			moved = true
			break
		if not moved:
			r.tick(1.0)
	return {"moves": moves, "over": r.phase == "game_over", "error": ""}

func _run() -> void:
	var games: Array = []
	for example: String in ["card_race", "higher_lower", "dice_bid"]:
		games.append([example, JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/%s.json" % example))])
	var Templates: GDScript = load("res://editor/ed_templates.gd")
	var Document: GDScript = load("res://editor/ed_document.gd")
	for spec: Dictionary in Templates.KITS:
		games.append(["шаблон «%s»" % spec.title, Templates.apply_kit(Document.blank(), str(spec.id)).data])
	for entry: Array in games:
		for seed_value: int in [1, 2]:
			var result := play(entry[1], seed_value)
			check(str(result.error).is_empty(), "%s (зерно %d): ход бота без ошибки — %s" % [entry[0], seed_value, result.error])
			check(int(result.moves) >= 3 or bool(result.over), "%s (зерно %d): боты ходят (%d ходов)" % [entry[0], seed_value, int(result.moves)])
		print("  %s: партия ботов — %s" % [entry[0], str(play(entry[1], 3))])
	# Бот и вопросы: ask_number/ask_player отвечаются допустимо.
	var rules := Rules.new()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/card_race.json"))
	data.rules.chains = [{"event": {"type": "start"}, "blocks": [{"op": "ask_number", "player": {"op": "actor"}, "min": 2, "max": 4}, {"op": "ask_player", "player": {"op": "actor"}}, {"op": "phase", "phase": "turn"}]}]
	check(rules.load_definition(data).is_empty() and rules.new_game([{"name": "А", "bot": true}, {"name": "Б", "bot": true}], {"seed": 5}).is_empty(), "Партия с вопросами")
	var rng := RandomNumberGenerator.new()
	var number := Bot.choose(rules, 0, rng)
	check(number.kind == "answer" and int(number.data.value) >= 2 and int(number.data.value) <= 4 and rules.act(0, "answer", number.data), "Бот отвечает числом в границах")
	var who := Bot.choose(rules, 0, rng)
	check(who.kind == "answer" and rules.act(0, "answer", who.data), "Бот выбирает игрока")
	check(rules.players[0].bot == true, "Правила помнят, что место — бот")
	print("CUSTOM BOT: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors > 0 else 0)
