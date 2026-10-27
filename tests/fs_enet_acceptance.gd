extends SceneTree
## Два настоящих процесса Net/ENet. Управление JSON-командами из build/fs_acceptance.
## FS_ROLE=host|client, FS_PORT=24687, FS_RUN=имя каталога; APPDATA задаёт запускающий скрипт.
var net: Node
var role := OS.get_environment("FS_ROLE")
var folder := "res://build/fs_acceptance/" + OS.get_environment("FS_RUN")
var last_command := -1
var elapsed := 0.0
var journal: FileAccess

func _initialize() -> void:
	boot.call_deferred()

func boot() -> void:
	net = root.get_node("Net")
	DirAccess.make_dir_recursive_absolute(folder)
	journal = FileAccess.open(folder + "/" + role + "-states.jsonl", FileAccess.WRITE)
	net.my_name = "Проверка-хост" if role == "host" else "Проверка-клиент"
	net.state_changed.connect(on_state)
	net.chat_received.connect(on_chat)
	var port := int(OS.get_environment("FS_PORT"))
	var result: int = net.host_enet(port, "four_souls") if role == "host" else net.join_enet("127.0.0.1", port)
	print("ПОДКЛЮЧЕНИЕ ", role, " ", result, " ПРОФИЛЬ ", OS.get_user_data_dir())

func on_state(view: Dictionary) -> void:
	journal.store_line(JSON.stringify(view))
	journal.flush()

func on_chat(entry: Dictionary) -> void:
	var output := FileAccess.open(folder + "/" + role + "-chat.jsonl", FileAccess.READ_WRITE)
	if output == null:
		output = FileAccess.open(folder + "/" + role + "-chat.jsonl", FileAccess.WRITE)
	output.seek_end()
	output.store_line(JSON.stringify(entry))

func _process(delta: float) -> bool:
	if net == null:
		return false
	elapsed += delta
	if elapsed < 0.025:
		return false
	elapsed = 0.0
	var path := folder + "/" + role + "-command.json"
	if FileAccess.file_exists(path):
		var command = JSON.parse_string(FileAccess.get_file_as_string(path))
		if command is Dictionary and int(command.id) > last_command:
			last_command = int(command.id)
			print("КОМАНДА ", JSON.stringify(command))
			match str(command.kind):
				"passive_fixture":
					if role == "host" and net.fours != null and OS.get_environment("FS_PASSIVE_FIXTURE") == "1":
						prepare_passive_fixture(str(command.arg))
				"start": print("СТАРТ ", net.start_game())
				"pause": net.set_paused(bool(command.arg))
				"chat": net.send_chat(str(command.arg))
				"leave": net.leave()
				"join": net.join_enet("127.0.0.1", int(OS.get_environment("FS_PORT")))
				"quit": quit()
				_: net.send_action(str(command.kind), integer_arguments(command.get("arg")))
	var snapshot := {"command":last_command,"in_game":net.in_game,"members":net.members.size(),"view":net.view}
	if role == "host" and net.fours != null:
		# Только наблюдение для проверки приватности, без записи в объект правил.
		snapshot["audit_hands"] = net.fours.hands
		snapshot["disconnected"] = net.disconnected
		snapshot["seat_peers"] = net.seat_peers
		snapshot["audit_players"] = net.fours.players
	var out := FileAccess.open(folder + "/" + role + "-snapshot.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(snapshot))
	out.close()
	return false

## Только подготовка отдельного регрессионного запуска, не сетевое действие игры.
func prepare_passive_fixture(stage: String) -> void:
	var g: FSRules = net.fours
	if stage == "ownership":
		g._starting_choices.clear()
		g.current = 0
		g.phase = "effect"
		g.resolving = {"kind": "item", "card": 13, "owner": 0}
		g.items = [[FSData.item_entry(16), FSData.item_entry(128)], []]
		g.attack = [1, 1]
		g.max_hp = [3, 3]
		g.hp = [3, 3]
		g.hands = [[475], [476]]
		g.coins = [3, 3]
		g.bank = 94
		g.room = -1
		g.bonuses.clear()
		g.stack.clear()
		g.next_action = {}
		g._refresh_passive_stats()
	elif stage == "roll":
		g.items[1].append(FSData.item_entry(165))
		g.current = 1
		g.phase = "priority"
		g.stack = [{"kind": "effect_roll", "owner": 1, "value": 5}]
		g.paused_effects = [{"effect": {"kind": "item", "card": 165, "owner": 1},
			"resume": "turn", "peek": {}, "roller": 1}]
		g._after_stack = "effect"
	elif stage == "manual_resume":
		g.current = 1
		g.phase = "effect"
		g.resolving = {"kind": "reward", "card": 387, "owner": 1, "slot": 0}
		g.items = [[FSData.item_entry(180)], []]
		g.hp = [2, 2]
		g.max_hp = [2, 2]
		g.attack = [1, 1]
		g.coins = [3, 3]
		g.bank = 94
		g.stack.clear()
		g.paused_effects.clear()
		g._death_queue.clear()
		g.next_action = {}
		g._after_stack = "turn"
		g.battle = 0
		g.monsters[0].id = 387
		g.monsters[0].hp = 0
		g.monsters[0].death_pending = true
	elif stage == "soul_loss":
		g.current = 0
		g.phase = "effect"
		g.resolving = {"kind": "reward", "card": 389, "owner": 0}
		g.stack.clear()
		g.next_action = {}
		g._after_stack = "turn"
		g.souls = [0, 2]
		g.soul_cards = [[], [{"id": 454, "value": 2}]]
	elif stage in ["conquest", "pride", "pride_discard", "expansion", "global_horf", "global_keeper", "global_fatty"]:
		g.current = 1
		g.phase = "turn"
		g.items = [[], []]
		g.hp = [2, 5]
		g.max_hp = [2, 5]
		g.attack = [1, 2]
		g.dead = [false, false]
		g.curses = [[], []]
		g.hands = [[475,476,477], [478]]
		g.stack.clear()
		g.resolving = {}
		g.next_action = {}
		g.paused_effects.clear()
		g._death_queue.clear()
		g._after_stack = "turn"
		g.battle = -1
		g.battle_player = -1
		g.required_player_attacks = 0
		g.discard_choice = {}
		g.monster_slots = 2
		g.required_deck_attacks = 0
		g.attack_left = 1
		g.attacked = false
		g.monsters = [{"id":450,"hp":3,"dc":4,"at":1},{"id":451,"hp":3,"dc":4,"at":1}]
		g.decks.monster = [450,451,450,451]
		if stage == "conquest":
			g.required_player_attacks = 1
			var rng := RandomNumberGenerator.new()
			for seed_value in range(1,101):
				rng.seed = seed_value
				if rng.randi_range(1,6) == 4:
					g._rng.seed = seed_value
					break
		elif stage == "pride":
			g.monsters[0].id = 396
			g.action(1,"attack",{"slot":0})
			g._finish_responses()
		elif stage == "pride_discard":
			g.battle = 0
			g._after_stack = "battle_roll"
			g._push({"kind":"forced_discard","owner":1,"target":0,"card":396,"amount":2},"battle_roll")
			g._finish_responses()
		elif stage.begins_with("global_"):
			g.current = 0
			g.phase = "effect"
			g._after_stack = "turn"
			g.coins = [3,3]
			g.bank = 94
			g.hp = [5,5]
			g.max_hp = [5,5]
			g.hands = [[475],[478,479]]
			g.resolving = {"kind":"item","card":13,"owner":1}
			var id: int = {"global_horf":440,"global_keeper":445,"global_fatty":439}[stage]
			var value: int = {"global_horf":2,"global_keeper":4,"global_fatty":5}[stage]
			g.monsters = [{"id":id,"hp":4,"dc":4,"at":1}]
			var rng := RandomNumberGenerator.new()
			for seed_value in range(1,101):
				rng.seed = seed_value
				if rng.randi_range(1,6) == value:
					g._rng.seed = seed_value
					break
		else:
			g.phase = "effect"
			g.battle = 0
			g.monsters[0] = {"id":360,"hp":0,"dc":4,"at":1}
			g.resolving = {"kind":"reward","card":360,"owner":1,"slot":0}
	elif stage in ["ambush", "peep"]:
		g.current = 1
		g.phase = "turn"
		g.items = [[], []]
		g.hp = [2, 2]
		g.dead = [false, false]
		g.curses = [[], []]
		g.stack.clear()
		g.resolving = {}
		g.next_action = {}
		g._death_queue.clear()
		g._after_stack = "turn"
		g.battle = -1
		g.deck_attacks = 0
		g.required_deck_attacks = 0
		g.attack_left = 1
		g.attacked = false
		g.monsters = [{"id": 450, "hp": 3, "dc": 4, "at": 1}, {"id": 451, "hp": 3, "dc": 4, "at": 1}]
		g.decks.monster = [450, 282, 451]
		if stage == "ambush":
			g._push({"kind": "event", "card": 715, "owner": 1}, "turn")
		else:
			g.monsters[0] = {"id": 429, "hp": 0, "dc": 4, "at": 1}
			g.battle = 0
			g._continue_stack()
		g._finish_responses()
	g.revision += 1
	net._push_state()

## JSON читает числа как float; UI отправляет целочисленные индексы и id карт.
func integer_arguments(value):
	if value is float:
		return int(value)
	if value is Dictionary:
		for key in value:
			value[key] = integer_arguments(value[key])
	if value is Array:
		for i in value.size():
			value[i] = integer_arguments(value[i])
	return value
