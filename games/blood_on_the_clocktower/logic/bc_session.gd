extends RefCounted
## Сетевой адаптер Clocktower: секретная подготовка рассказчика и ключи возвращения на место.
const ID := "blood_on_the_clocktower"
const Setup := preload("res://games/blood_on_the_clocktower/logic/bc_setup.gd")
const Rules := preload("res://games/blood_on_the_clocktower/logic/bc_rules.gd")
const Data := preload("res://games/blood_on_the_clocktower/logic/bc_data.gd")
var net: Node
var setup_private: Dictionary = {}
var setup_view: Dictionary = {}
var setup_key := ""
var setup_revision := 0
var setup_error := ""
var seat_tokens: Dictionary = {}
## Ключ возвращения на место хранится и на диске: после вылета самой игры перезапущенный клиент
## отправит его в hello и сядет на своё место с той же ролью, а не станет зрителем.
## Ключ случайный (48 hex) и принимается хостом только для отключившегося места текущей партии.
const RESUME_FILE := "user://bc_resume.cfg"
const RESUME_HOURS := 12
var _resume_token := ""
var resume_token: String:
	get:
		if _resume_token.is_empty():
			_resume_token = _load_token()
		return _resume_token
	set(value):
		if value == _resume_token:
			return
		_resume_token = value
		_save_token(value)

func _load_token() -> String:
	var file := ConfigFile.new()
	if file.load(RESUME_FILE) != OK:
		return ""
	var saved := int(file.get_value("resume", "time", 0))
	if Time.get_unix_time_from_system() - saved > RESUME_HOURS * 3600:
		return ""
	var token := str(file.get_value("resume", "token", ""))
	return token if token.length() == 48 else ""

func _save_token(token: String) -> void:
	var file := ConfigFile.new()
	file.set_value("resume", "token", token)
	file.set_value("resume", "time", int(Time.get_unix_time_from_system()))
	file.save(RESUME_FILE)

func _init(owner: Node) -> void:
	net = owner

func reset_match() -> void:
	seat_tokens.clear()

func reset_lobby() -> void:
	setup_private.clear()
	setup_view.clear()
	setup_key = ""
	setup_error = ""
	setup_revision += 1

func story_index() -> int:
	return clampi(int(net.settings.get("bc_storyteller", 0)), 0, maxi(0, int(net.player_total()) - 1))

func story_peer() -> int:
	var index := story_index()
	return int(net.join_order[index]) if index < net.join_order.size() else 0

func is_story_lobby() -> bool:
	if net.mode == "offline":
		return net.is_host()
	var members: Array = net.lobby_view.get("members", [])
	var index := int(net.lobby_view.get("settings", {}).get("bc_storyteller", 0))
	return index >= 0 and index < members.size() and int(members[index].get("peer", 0)) == net.multiplayer.get_unique_id()

func prepare_lobby() -> void:
	if not net.is_host() or net.party_game != ID or net.in_game:
		return
	var edition := str(net.settings.get("bc_edition", "tb"))
	if not Data.EDITIONS.has(edition):
		edition = "tb"
		net.settings["bc_edition"] = edition
	net.settings["bc_storyteller"] = story_index()
	var count: int = net.player_total() - 1
	var key := "%s/%d/%d" % [edition, count, story_peer() if net.mode != "offline" else story_index()]
	if key != setup_key:
		setup_key = key
		setup_private = Setup.suggest(edition, count)
		setup_revision += 1
		setup_error = ""
	if net.mode == "offline" or story_peer() == 1:
		setup_view = _setup_packet()
	else:
		setup_view.clear()

func send_setup() -> void:
	if not net.is_host() or net.party_game != ID or net.in_game:
		return
	var peer := story_peer()
	if net.mode != "offline" and peer > 1:
		net._rpc_bc_setup_data.rpc_id(peer, _setup_packet())

func _setup_packet() -> Dictionary:
	return {"options": setup_private.duplicate(true), "revision": setup_revision, "key": setup_key, "error": setup_error}

func receive_setup(packet: Dictionary) -> void:
	if net.party_game != ID or not is_story_lobby():
		setup_view.clear()
		return
	setup_view = packet.duplicate(true)
	net.lobby_changed.emit()

func public_settings() -> Dictionary:
	var result: Dictionary = net.settings.duplicate(true)
	for key: String in result.keys():
		if key.begins_with("bc_") and not key in ["bc_edition", "bc_storyteller", "bc_timer"]:
			result.erase(key)
	return result

func configure(peer: int, candidate: Dictionary, revision: int) -> void:
	if not net.is_host() or net.party_game != ID or net.in_game or revision != setup_revision:
		return
	if net.mode != "offline" and peer != story_peer():
		return
	if net.mode == "offline" and peer != 1:
		return
	# Владелец 07.11: игру настраивает рассказчик — и сценарий тоже, а не только состав.
	if candidate.has("bc_timer"):
		net.settings["bc_timer"] = bool(candidate.bc_timer)
		net._broadcast_lobby()
		return
	if candidate.has("bc_edition"):
		var edition := str(candidate.bc_edition)
		if Data.EDITIONS.has(edition) and edition != str(net.settings.get("bc_edition", "tb")):
			net.settings["bc_edition"] = edition
			setup_key = ""
			prepare_lobby()
			net._broadcast_lobby()
			send_setup()
		return
	var accepted: Dictionary = {}
	for key: String in ["bc_roles", "bc_bluffs", "bc_drunk_role", "bc_lunatic_role", "bc_godfather_delta"]:
		if candidate.has(key):
			accepted[key] = candidate[key].duplicate(true) if candidate[key] is Array or candidate[key] is Dictionary else candidate[key]
	if not accepted.get("bc_roles") is Array or not accepted.get("bc_bluffs") is Array:
		setup_error = "Нужны списки ролей и блефов."
	elif accepted.has("bc_godfather_delta") and not accepted.bc_godfather_delta is int:
		setup_error = "Изменение состава Крёстным отцом должно быть числом."
	elif accepted.bc_roles.size() > 15 or accepted.bc_bluffs.size() != 3:
		setup_error = "Проверьте число ролей и трёх блефов."
	else:
		var people: Array = []
		for i in net.player_total():
			people.append({"name": "Участник %d" % i})
		var options := accepted.duplicate(true)
		options["bc_edition"] = str(net.settings.get("bc_edition", "tb"))
		options["bc_storyteller"] = story_index()
		setup_error = Rules.new().new_game(people, options, 1)
		if setup_error.is_empty():
			setup_private = accepted
			setup_revision += 1
	if net.mode == "offline" or story_peer() == 1:
		setup_view = _setup_packet()
		net.lobby_changed.emit()
	send_setup()

func create(players: Array) -> String:
	if net.mode != "offline" and int(net.bots) > 0:
		return "Дополнительные местные места доступны только в соло-проверке."
	if setup_private.is_empty():
		prepare_lobby()
	var options := setup_private.duplicate(true)
	options["bc_edition"] = str(net.settings.get("bc_edition", "tb"))
	options["bc_timer"] = bool(net.settings.get("bc_timer", false))
	options["bc_storyteller"] = net._new_seat(story_index())
	net.bc = Rules.new()
	var error: String = net.bc.new_game(players, options)
	if not error.is_empty():
		net.bc = null
		return error
	seat_tokens.clear()
	for i in players.size():
		seat_tokens[i] = Crypto.new().generate_random_bytes(24).hex_encode()
	net.bc_view_seat = int(options.bc_storyteller)
	net.host_tools.reset()
	return ""

func lobby_received() -> void:
	if net.party_game != ID or not is_story_lobby():
		setup_view.clear()

func handle_action(peer: int, seat: int, kind: String, arg: Variant) -> void:
	if net.mode == "offline" and peer == 1:
		if kind == "view_seat":
			if arg is Dictionary and arg.get("seat") is int and arg.seat >= -1 and arg.seat < net.bc.players.size():
				net.bc_view_seat = int(arg.seat)
				net._push_state()
			return
		seat = int(net.bc_view_seat)
	# Экран победы открывает только хост, когда все рассмотрели раскрытые роли.
	if kind == "show_victory":
		if peer == 1 and net.bc.phase == "game_over" and not net.bc.victory_open:
			net.bc.victory_open = true
			net.bc.public_revision += 1
			net._push_state()
		return
	if net.bc.action(seat, kind, arg):
		net._push_state()

func view(seat: int, local: bool) -> Dictionary:
	var actual := int(net.bc_view_seat) if local else seat
	var result: Dictionary = net.bc.get_view(actual)
	result["hotseat"] = local
	result["disconnected"] = net.disconnected.keys()
	if not local and actual >= 0:
		result["resume_token"] = str(seat_tokens.get(actual, ""))
	return result

func resume_seat(token: String) -> int:
	if token.length() != 48:
		return -1
	for seat: int in net.disconnected:
		if str(seat_tokens.get(seat, "")) == token:
			return seat
	return -1
