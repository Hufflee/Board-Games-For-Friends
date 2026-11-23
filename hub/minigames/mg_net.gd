extends Node
## Мини-игры внутри пати (узел /root/Net/MiniGames, создаёт Net).
##
## Один на один (шахматы, шашки, го, 4 в ряд): приглашение → согласие → партия. Партии живут на хосте пати:
## он проверяет ходы правилами (hub/minigames/logic) и рассылает обоим игрокам снимок. Времени на ход нет.
## Партий может быть несколько; они не зависят от основной игры и переживают смену экрана. Окно — общее
## «Общение» (hub/comms_panel.gd), поле — hub/minigames/mg_board.gd. Без пати — партия «за обоих» на этом компьютере.
## После смены хоста игроки сами возвращают свои партии новому хосту (по никам).
##
## Общие комнаты (шарики, звёздочки): одна на пати, входят и выходят в любой момент (вкладка = «я в комнате»).
## Считает хост, участникам — снимки; без пати комната работает здесь же, вы в ней одни.
## Соло (сапёр): только на этом компьютере, без сети.

signal changed  # партии, приглашения, выбранная вкладка
signal notice(text: String)
signal won(id: String)  # я победил в партии — окно сыплет конфетти и звенит

const GAMES := ["chess", "checkers", "go", "connect4"]  # один на один, по приглашению
const ROOMS := ["balls", "race", "stars", "blackjack"]  # общие комнаты
const SOLO := ["mines"]
const TITLES := {"chess": "Шахматы", "checkers": "Шашки", "go": "Го", "connect4": "4 в ряд",
	"balls": "Сумо", "race": "Гонка", "stars": "Лови звёздочку", "blackjack": "Блэкджек", "mines": "Сапёр"}
const RULES := {
	"chess": preload("res://hub/minigames/logic/mg_chess.gd"),
	"checkers": preload("res://hub/minigames/logic/mg_checkers.gd"),
	"go": preload("res://hub/minigames/logic/mg_go.gd"),
	"connect4": preload("res://hub/minigames/logic/mg_connect4.gd"),
	"mines": preload("res://hub/minigames/logic/mg_mines.gd"),
}
const Balls := preload("res://hub/minigames/logic/mg_balls.gd")
const Race := preload("res://hub/minigames/logic/mg_race.gd")
const Stars := preload("res://hub/minigames/logic/mg_stars.gd")
const Blackjack := preload("res://hub/minigames/logic/mg_blackjack.gd")
const StarOverlay := preload("res://hub/minigames/mg_star_overlay.gd")
const ROOM_STEP := 1.0 / 30.0  # шаг физики комнаты на хосте
const ROOM_TICK := 1.0 / 15.0  # как часто хост рассылает положение шариков
const BEST_PATH := "user://minigames.cfg"
const MAX_SESSIONS := 8  # партий у одного игрока

var sessions: Dictionary = {}  # id → {id, game, opts, peers, names, state, seat, dot, gone, local, orphan}
var order: Array[String] = []  # вкладки слева направо
var current := ""  # выбранная вкладка: id партии или "" — экран «новая партия»
var invites_in: Array = []  # [{id, from, name, game, opts}]
var invites_out: Array = []  # [{id, to, name, game}]

var _host_sessions: Dictionary = {}  # хост: id → {game, opts, peers, names, state, left}
var _host_invites: Dictionary = {}  # хост: id → {from, to, game, opts}
var _restored: Dictionary = {}  # хост: метка возвращённой партии → новый id
var _next := 1
var _salt := randi() % 100000  # номера партий разных хостов не совпадают (после смены хоста старые ещё живы у игроков)
var _local_next := 1
var _clock := 0.0
# общие комнаты
var _rooms: Dictionary = {}  # хост (или без пати — здесь): игра → {state, members: {peer: true}, acc, tick, seq}
var _room_rng := RandomNumberGenerator.new()
var _overlay: CanvasLayer  # звёздочки поверх всего экрана
var _steer_sent := 0.0


func _ready() -> void:
	name = "MiniGames"
	multiplayer.peer_disconnected.connect(_on_peer_gone)


func _net() -> Node:
	return get_parent()


func my_peer() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1


func _online() -> bool:
	var net := _net()
	return net.is_party() and multiplayer.multiplayer_peer != null


func _member(peer: int) -> Dictionary:
	var members: Dictionary = _net().members
	return members.get(peer, {})


func _name_of(peer: int) -> String:
	return str(_member(peer).get("name", "Игрок"))


static func title(game: String) -> String:
	return str(TITLES.get(game, game))


## Кого можно позвать: [{peer, name, color}].
func targets() -> Array:
	return _net().chat.pm_targets() if _online() else []


# --- Окно ----------------------------------------------------------------------------------

func _ensure_panel() -> Control:
	return _net().chat.panel()


## Открыть окно «Общение» на мини-играх (кнопки «Мини-игры» в верхней полосе и в главном меню, клавиша X).
func show_panel() -> void:
	_ensure_panel().call("open_games")


func toggle_panel() -> void:
	_ensure_panel().call("toggle_games")


func _panel_watching(id: String) -> bool:
	return bool(_ensure_panel().call("watching", id))


func select(id: String) -> void:
	current = id if sessions.has(id) else ""
	if sessions.has(id):
		sessions[id].dot = false
	changed.emit()


func dots() -> int:
	var count := invites_in.size()
	for id: String in sessions:
		if bool(sessions[id].dot):
			count += 1
	return count


# --- Приглашения ---------------------------------------------------------------------------

static func _clean_opts(game: String, opts: Dictionary) -> Dictionary:
	if game == "go":
		var size := int(opts.get("size", 9))
		return {"size": size if size in [9, 13, 19] else 9}
	if game == "mines":
		return {"mode": "deep" if str(opts.get("mode", "")) == "deep" else "classic"}
	return {}


func invite(peer: int, game: String, opts: Dictionary = {}) -> void:
	if game not in GAMES:
		return
	if sessions.size() >= MAX_SESSIONS:
		notice.emit("Слишком много партий — закройте лишние вкладки")
		return
	if not _online() or _member_view(peer).is_empty():
		notice.emit("Этого игрока нет в пати")
		return
	if _net().is_host():
		_host_invite(my_peer(), peer, game, opts)
	else:
		_rpc_invite_up.rpc_id(1, peer, game, opts)


func _member_view(peer: int) -> Dictionary:
	for target: Dictionary in targets():
		if int(target.peer) == peer:
			return target
	return {}


## Партия «за обоих» на этом компьютере — без сети.
func start_local(game: String, opts: Dictionary = {}) -> void:
	if (game not in GAMES and game not in SOLO) or sessions.size() >= MAX_SESSIONS:
		return
	var id := "local%d" % _local_next
	_local_next += 1
	var clean := _clean_opts(game, opts)
	sessions[id] = {"id": id, "game": game, "opts": clean, "peers": [0, 0], "names": ["Вы", "Вы"],
		"state": RULES[game].new_state(clean), "seat": 0, "dot": false, "gone": false, "local": true, "orphan": false,
		"solo": game in SOLO}
	order.push_front(id)
	current = id
	changed.emit()
	show_panel()


@rpc("any_peer", "reliable")
func _rpc_invite_up(to: int, game: String, opts: Dictionary) -> void:
	if _net().is_host():
		_host_invite(multiplayer.get_remote_sender_id(), to, game, opts)


func _host_invite(from: int, to: int, game: String, opts: Dictionary) -> void:
	if from == to or game not in GAMES or _member(from).is_empty() or _member(to).is_empty():
		return
	var pending := 0
	for id: String in _host_invites:
		var invite_data: Dictionary = _host_invites[id]
		if int(invite_data.from) == from:
			pending += 1
			if int(invite_data.to) == to and str(invite_data.game) == game:
				_tell(from, "Приглашение уже отправлено — ждём ответа")
				return
	if pending >= 6 or _count_sessions(from) >= MAX_SESSIONS:
		_tell(from, "Слишком много приглашений и партий сразу")
		return
	var invite_id := "i%d_%d" % [_salt, _next]
	_next += 1
	var clean := _clean_opts(game, opts)
	_host_invites[invite_id] = {"from": from, "to": to, "game": game, "opts": clean}
	_send(to, "_rpc_invite", [invite_id, from, _name_of(from), game, clean])
	_send(from, "_rpc_invite_sent", [invite_id, to, _name_of(to), game])


func _count_sessions(peer: int) -> int:
	var count := 0
	for id: String in _host_sessions:
		if (_host_sessions[id].peers as Array).has(peer):
			count += 1
	return count


## Хост: вызвать метод у участника — у себя напрямую, у остальных по сети.
func _send(peer: int, method: String, args: Array) -> void:
	if peer == my_peer():
		callv(method, args)
	elif not _member(peer).is_empty():
		match args.size():
			1:
				rpc_id(peer, method, args[0])
			2:
				rpc_id(peer, method, args[0], args[1])
			4:
				rpc_id(peer, method, args[0], args[1], args[2], args[3])
			5:
				rpc_id(peer, method, args[0], args[1], args[2], args[3], args[4])


func _tell(peer: int, text: String) -> void:
	_send(peer, "_rpc_notice", [text])


@rpc("authority", "reliable")
func _rpc_notice(text: String) -> void:
	notice.emit(text)


@rpc("authority", "reliable")
func _rpc_invite(id: String, from: int, from_name: String, game: String, opts: Dictionary) -> void:
	invites_in.append({"id": id, "from": from, "name": from_name, "game": game, "opts": opts})
	Sfx.play("click", -4.0)
	var chat: Node = _net().chat
	chat._add("all", {"name": "", "seat": -1, "text": "%s зовёт вас сыграть: %s. Ответить — в окне «Мини-игры»." % [from_name, _game_line(game, opts)], "kind": "system"})
	changed.emit()
	_ensure_panel().call("attention")


@rpc("authority", "reliable")
func _rpc_invite_sent(id: String, to: int, to_name: String, game: String) -> void:
	invites_out.append({"id": id, "to": to, "name": to_name, "game": game})
	changed.emit()


static func _game_line(game: String, opts: Dictionary) -> String:
	return "%s %d×%d" % [title(game), int(opts.get("size", 9)), int(opts.get("size", 9))] if game == "go" else title(game).to_lower()


func answer(id: String, yes: bool) -> void:
	if _net().is_host():
		_host_answer(my_peer(), id, yes)
	else:
		_rpc_answer_up.rpc_id(1, id, yes)


## Отозвать своё приглашение.
func cancel_invite(id: String) -> void:
	answer(id, false)


@rpc("any_peer", "reliable")
func _rpc_answer_up(id: String, yes: bool) -> void:
	if _net().is_host():
		_host_answer(multiplayer.get_remote_sender_id(), id, yes)


func _host_answer(sender: int, id: String, yes: bool) -> void:
	if not _host_invites.has(id):
		_send(sender, "_rpc_invite_closed", [id, ""])
		return
	var invite_data: Dictionary = _host_invites[id]
	var from := int(invite_data.from)
	var to := int(invite_data.to)
	if sender != to and not (sender == from and not yes):
		return
	_host_invites.erase(id)
	if not yes:
		_send(from, "_rpc_invite_closed", [id, "" if sender == from else "%s не хочет играть сейчас" % _name_of(to)])
		_send(to, "_rpc_invite_closed", [id, ""])
		return
	if _member(from).is_empty() or _count_sessions(from) >= MAX_SESSIONS or _count_sessions(to) >= MAX_SESSIONS:
		_send(to, "_rpc_invite_closed", [id, "Партию начать не удалось"])
		_send(from, "_rpc_invite_closed", [id, ""])
		return
	_send(from, "_rpc_invite_closed", [id, ""])
	_send(to, "_rpc_invite_closed", [id, ""])
	var game := str(invite_data.game)
	var peers := [from, to]
	if randi() % 2 == 1:
		peers = [to, from]
	var session_id := "s%d_%d" % [_salt, _next]
	_next += 1
	_host_sessions[session_id] = {"game": game, "opts": invite_data.opts, "peers": peers, "names": [_name_of(int(peers[0])), _name_of(int(peers[1]))],
		"state": RULES[game].new_state(invite_data.opts), "left": []}
	_push(session_id, true)


@rpc("authority", "reliable")
func _rpc_invite_closed(id: String, why: String) -> void:
	invites_in = invites_in.filter(func(item: Dictionary) -> bool: return str(item.id) != id)
	invites_out = invites_out.filter(func(item: Dictionary) -> bool: return str(item.id) != id)
	if why != "":
		notice.emit(why)
	changed.emit()


# --- Партии --------------------------------------------------------------------------------

## Хост: разослать снимок партии обоим игрокам.
func _push(id: String, fresh: bool = false, replaces: Array = []) -> void:
	var session: Dictionary = _host_sessions[id]
	var state: Dictionary = (session.state as Dictionary).duplicate()
	state.erase("reps")  # счётчик повторений нужен только хосту
	var data := {"game": session.game, "opts": session.opts, "peers": session.peers, "names": session.names,
		"state": state, "gone": not (session.left as Array).is_empty(), "fresh": fresh, "replaces": replaces}
	for peer: Variant in session.peers:
		if not (session.left as Array).has(int(peer)):
			_send(int(peer), "_rpc_session", [id, data])


@rpc("authority", "reliable")
func _rpc_session(id: String, data: Dictionary) -> void:
	var me := my_peer()
	var seat := (data.get("peers", []) as Array).find(me)
	if seat < 0:
		return
	for old: Variant in data.get("replaces", []):
		# партия вернулась от нового хоста под новым номером — подменяем вкладку на месте
		if sessions.has(str(old)) and str(old) != id:
			var at := order.find(str(old))
			sessions.erase(str(old))
			if at >= 0:
				order[at] = id
			if current == str(old):
				current = id
	var known: Dictionary = sessions.get(id, {})
	var state: Dictionary = data.get("state", {})
	var moved := not known.is_empty() and int(state.get("moves", 0)) != int((known.state as Dictionary).get("moves", 0))
	var their_move := moved and (int(state.get("turn", 0)) == seat or bool(state.get("over", false)))
	var ended := bool(state.get("over", false)) and not known.is_empty() and not bool((known.state as Dictionary).get("over", false))
	sessions[id] = {"id": id, "game": str(data.get("game", "")), "opts": data.get("opts", {}), "peers": data.get("peers", []),
		"names": data.get("names", []), "state": state, "seat": seat, "dot": bool(known.get("dot", false)),
		"gone": bool(data.get("gone", false)), "local": false, "orphan": false}
	if not order.has(id):
		order.push_front(id)
	if known.is_empty() and bool(data.get("fresh", false)):
		current = id
		show_panel()
	elif their_move or ended or (bool(data.get("gone", false)) and not bool(known.get("gone", false))):
		# соперник сходил: вкладка — в крайние левые, точка мигает, пока на партию не посмотрят
		order.erase(id)
		order.push_front(id)
		if not _panel_watching(id):
			sessions[id].dot = true
		if their_move:
			Sfx.play("chip", -8.0)
		_ensure_panel().call("attention")
	changed.emit()
	if ended and int(state.get("winner", -1)) == seat:
		won.emit(id)


## Ход в партии: словарь хода правил игры или {"resign": true}.
func move(id: String, action: Dictionary) -> void:
	if not sessions.has(id):
		return
	var session: Dictionary = sessions[id]
	if bool(session.local):
		var view: Dictionary = _net().view
		if (_net().is_host() and _net().minigames_locked_now(my_peer())) or bool(view.get("minigames_blocked", false)):
			notice.emit("Мини-игры приостановлены до конца вашего хода")
			return
		var state: Dictionary = session.state
		var error := _apply(str(session.game), state, int(state.turn), action)
		if error != "":
			if str(session.game) != "mines" or not (error.begins_with("Флажков вокруг") or error in ["Клетка уже открыта", "Вокруг всё открыто"]):
				notice.emit(error)
		else:
			Sfx.play("chip", -8.0)
			if bool(state.get("over", false)) and int(state.get("winner", -1)) in [0, 1]:
				won.emit(id)  # за обоих — любая победа; в сапёре winner 0 — поле разминировано
			if str(session.game) == "mines" and str(state.mode) == "deep":
				_save_best("mines_layers", int(state.depth))
			elif str(session.game) == "mines" and bool(state.over) and int(state.winner) == 0:
				var record := best_time(BEST_TIME_KEY)
				state.record = record <= 0.0 or float(state.elapsed) < record
				if bool(state.record):
					_save_best_time(BEST_TIME_KEY, float(state.elapsed))
		changed.emit()
		return
	if bool(session.orphan):
		notice.emit("Партия возвращается после смены хоста — секунду")
		return
	if _net().is_host():
		_host_move(my_peer(), id, action)
	else:
		_rpc_move_up.rpc_id(1, id, action)


static func _apply(game: String, state: Dictionary, seat: int, action: Dictionary) -> String:
	if bool(action.get("resign", false)):
		if bool(state.over):
			return "Партия окончена"
		state.over = true
		state.winner = 1 - seat
		state.reason = "Соперник сдался"
		state.moves = int(state.moves) + 1
		return ""
	return str(RULES[game].apply(state, seat, action))


@rpc("any_peer", "reliable")
func _rpc_move_up(id: String, action: Dictionary) -> void:
	if _net().is_host():
		_host_move(multiplayer.get_remote_sender_id(), id, action)


func _host_move(sender: int, id: String, action: Dictionary) -> void:
	if not bool(action.get("resign", false)) and _net().minigames_locked_now(sender):
		_tell(sender, "Мини-игры приостановлены до конца вашего хода")
		return
	if not _host_sessions.has(id):
		return
	var session: Dictionary = _host_sessions[id]
	var seat := (session.peers as Array).find(sender)
	if seat < 0:
		return
	var error := _apply(str(session.game), session.state, seat, action)
	if error != "":
		_tell(sender, error)
		return
	_push(id)


## Закрыть вкладку: партия для меня закончена, соперник увидит, что я вышел.
func close(id: String) -> void:
	if not sessions.has(id):
		return
	var session: Dictionary = sessions[id]
	sessions.erase(id)
	order.erase(id)
	if current == id:
		current = order[0] if not order.is_empty() else ""
	changed.emit()
	if bool(session.get("room", false)):
		_leave_room(str(session.game))
		return
	if bool(session.local) or bool(session.orphan):
		return
	if _net().is_host():
		_host_leave(my_peer(), id)
	elif _online():
		_rpc_leave_up.rpc_id(1, id)


@rpc("any_peer", "reliable")
func _rpc_leave_up(id: String) -> void:
	if _net().is_host():
		_host_leave(multiplayer.get_remote_sender_id(), id)


func _host_leave(sender: int, id: String) -> void:
	if not _host_sessions.has(id):
		return
	var session: Dictionary = _host_sessions[id]
	if not (session.peers as Array).has(sender) or (session.left as Array).has(sender):
		return
	(session.left as Array).append(sender)
	if (session.left as Array).size() >= 2:
		_host_sessions.erase(id)
		return
	_push(id)


func _on_peer_gone(peer: int) -> void:
	if not _net().is_host():
		return
	for id: String in _host_invites.keys():
		var invite_data: Dictionary = _host_invites[id]
		if int(invite_data.from) == peer or int(invite_data.to) == peer:
			_host_invites.erase(id)
			_send(int(invite_data.from), "_rpc_invite_closed", [id, ""])
			_send(int(invite_data.to), "_rpc_invite_closed", [id, ""])
	for id: String in _host_sessions.keys():
		if (_host_sessions[id].peers as Array).has(peer):
			_host_leave(peer, id)
	for game: String in _rooms.keys():
		_host_room_leave(peer, game)


# --- Смена хоста и выход из пати -----------------------------------------------------------

## Хост сменился: приглашения сгорают, партии ждут возвращения новому хосту.
func reset_party() -> void:
	_host_sessions.clear()
	_host_invites.clear()
	_restored.clear()
	invites_in.clear()
	invites_out.clear()
	_rooms.clear()
	for id: String in sessions:
		if not bool(sessions[id].local):
			sessions[id].orphan = true
	changed.emit()


func _process(delta: float) -> void:
	_rooms_process(delta)
	_mines_clock(delta)
	_clock += delta
	if _clock < 1.0:
		return
	_clock = 0.0
	if not _online():
		# вышли из пати: сетевые партии закрыть, локальные оставить
		var dropped := false
		for id: String in sessions.keys():
			if not bool(sessions[id].local) and not _offline_room(id):
				sessions.erase(id)
				order.erase(id)
				dropped = true
		if dropped or not invites_in.is_empty() or not invites_out.is_empty():
			invites_in.clear()
			invites_out.clear()
			_host_sessions.clear()
			_host_invites.clear()
			if not sessions.has(current):
				current = order[0] if not order.is_empty() else ""
			changed.emit()
		return
	if targets().is_empty() and not _net().is_host():
		return  # список пати ещё не пришёл
	for id: String in sessions.keys():
		var session: Dictionary = sessions[id]
		if bool(session.get("room", false)) and not bool(session.get("online", false)):
			# комната без пати, а мы уже в пати: входим в общую комнату хоста
			session.online = true
			session.orphan = true
			_rooms.erase(str(session.game))
		if not bool(session.orphan):
			continue
		if bool(session.get("room", false)):
			_join_up(str(session.game))
			continue
		var data :={"game": session.game, "opts": session.opts, "names": session.names, "state": session.state}
		if _net().is_host():
			_host_restore(my_peer(), id, data)
		else:
			_rpc_restore_up.rpc_id(1, id, data)


@rpc("any_peer", "reliable")
func _rpc_restore_up(token: String, data: Dictionary) -> void:
	if _net().is_host():
		_host_restore(multiplayer.get_remote_sender_id(), token, data)


## Новый хост принимает партию от её игрока: находит обоих по никам и продолжает с присланной позиции.
func _host_restore(sender: int, token: String, data: Dictionary) -> void:
	var game := str(data.get("game", ""))
	var names: Array = data.get("names", [])
	var state: Dictionary = data.get("state", {})
	if game not in GAMES or names.size() != 2 or not state.has("board") or not state.has("turn"):
		return
	var peers := []
	for nick: Variant in names:
		var found := 0
		for peer: Variant in _net().members:
			if _name_of(int(peer)) == str(nick):
				found = int(peer)
		peers.append(found)
	if not peers.has(sender) or int(peers[0]) == int(peers[1]) or peers.has(0):
		return  # соперник ещё не вернулся в пати — игрок спросит снова через секунду
	# оба игрока присылают партию под одним и тем же старым номером — берём первую, второму отвечаем ею же
	var label := "%s|%s|%s|%s" % [token, game, str(names[0]), str(names[1])]
	if _restored.has(label):
		var existing := str(_restored[label])
		if _host_sessions.has(existing):
			_push(existing, false, [token])
		return
	var session_id := "s%d_%d" % [_salt, _next]
	_next += 1
	_restored[label] = session_id
	if game == "chess" and not state.has("reps"):
		state["reps"] = {}
	_host_sessions[session_id] = {"game": game, "opts": _clean_opts(game, data.get("opts", {})), "peers": peers, "names": names, "state": state, "left": []}
	_push(session_id, false, [token])


# --- Общие комнаты (шарики, звёздочки) -----------------------------------------------------

static func room_id(game: String) -> String:
	return "room_" + game


func in_room(game: String) -> bool:
	return sessions.has(room_id(game))


func _offline_room(id: String) -> bool:
	var session: Dictionary = sessions.get(id, {})
	return bool(session.get("room", false)) and not bool(session.get("online", false))


## Комнату считает этот компьютер: хост пати или игра без пати.
func _room_host() -> bool:
	return not _online() or _net().is_host()


## Войти в общую комнату (вкладка появляется сразу, снимок приходит от хоста).
func join_room(game: String) -> void:
	if game not in ROOMS:
		return
	var id := room_id(game)
	if not sessions.has(id):
		sessions[id] = {"id": id, "game": game, "opts": {}, "peers": [], "names": [], "state": {}, "seat": 0, "dot": false,
			"gone": false, "local": false, "orphan": false, "room": true, "online": _online()}
		order.push_front(id)
	current = id
	_join_up(game)
	changed.emit()
	show_panel()


func _join_up(game: String) -> void:
	if _room_host():
		_host_room_join(my_peer(), game)
	else:
		_rpc_room_join_up.rpc_id(1, game)


func _leave_room(game: String) -> void:
	if _room_host():
		_host_room_leave(my_peer(), game)
	elif _online():
		_rpc_room_leave_up.rpc_id(1, game)
	_sync_overlay()


@rpc("any_peer", "reliable")
func _rpc_room_join_up(game: String) -> void:
	if _net().is_host():
		_host_room_join(multiplayer.get_remote_sender_id(), game)


@rpc("any_peer", "reliable")
func _rpc_room_leave_up(game: String) -> void:
	if _net().is_host():
		_host_room_leave(multiplayer.get_remote_sender_id(), game)


func _room_name(peer: int) -> String:
	return _name_of(peer) if _online() else str(_net().my_name)


func _host_room_join(peer: int, game: String) -> void:
	if game not in ROOMS or (_online() and _member(peer).is_empty()):
		return
	if not _rooms.has(game):
		var fresh: Dictionary = Balls.new_state() if game == "balls" else (Blackjack.new_state() if game == "blackjack" else Stars.new_state())
		if game == "race":
			fresh = Race.new_state(_room_rng)
		_rooms[game] = {"state": fresh, "acc": 0.0, "tick": 0.0}
	var room: Dictionary = _rooms[game]
	var color := int(_member(peer).get("color", 0))
	if game == "balls":
		Balls.join(room.state, peer, _room_name(peer), color, _room_rng)
	elif game == "race":
		Race.join(room.state, peer, _room_name(peer), color)
	elif game == "blackjack":
		Blackjack.join(room.state, peer, _room_name(peer), color)
	else:
		Stars.join(room.state, peer, _room_name(peer), color)
	_room_push(game)


func _host_room_leave(peer: int, game: String) -> void:
	if not _rooms.has(game):
		return
	var room: Dictionary = _rooms[game]
	if game == "balls":
		Balls.leave(room.state, peer)
	elif game == "race":
		Race.leave(room.state, peer)
	elif game == "blackjack":
		Blackjack.leave(room.state, peer)
	else:
		Stars.leave(room.state, peer)
	if _room_peers(game).is_empty():
		_rooms.erase(game)  # комната опустела — очки и звёзды забываются
		return
	_room_push(game)


func _room_peers(game: String) -> Array:
	if not _rooms.has(game):
		return []
	var state: Dictionary = _rooms[game].state
	return (state.balls if game == "balls" else state.players).keys()


func _room_snapshot(game: String) -> Dictionary:
	var state: Dictionary = _rooms[game].state
	if game == "blackjack":
		return Blackjack.snapshot(state)
	if game == "race":
		return Race.snapshot(state)
	return Balls.snapshot(state) if game == "balls" else Stars.snapshot(state)


## Хост: надёжно разослать снимок комнаты всем участникам.
func _room_push(game: String) -> void:
	if not _rooms.has(game):
		return
	var snap := _room_snapshot(game)
	for peer: Variant in _room_peers(game):
		_send(int(peer), "_rpc_room", [game, snap])


@rpc("authority", "reliable")
func _rpc_room(game: String, snap: Dictionary) -> void:
	_take_room(game, snap)


@rpc("authority", "unreliable_ordered")
func _rpc_room_tick(game: String, snap: Dictionary) -> void:
	_take_room(game, snap)


func _take_room(game: String, snap: Dictionary) -> void:
	var id := room_id(game)
	if not sessions.has(id):
		return
	var session: Dictionary = sessions[id]
	var old_seq := int((session.state as Dictionary).get("seq", -1))
	if game == "race":
		if bool(session.get("orphan", false)):
			session.erase("race_record_id")  # новая комната после смены хоста начинает номера кругов заново
		for row: Dictionary in snap.get("list", []):
			if int(row.peer) == my_peer() and float(row.record) > 0.0:
				var record_id := "%s:%s:%s" % [snap.track, snap.round, row.record_seq]
				if str(session.get("race_record_id", "")) == record_id:
					continue
				session.race_record_id = record_id
				var key := "race_%d" % int(snap.track)
				var previous := best_time(key)
				if previous <= 0.0 or float(row.record) < previous:
					_save_best_time(key, float(row.record))
	session.state = snap
	session.orphan = false
	if game == "stars":
		_sync_overlay()
	if int(snap.get("seq", 0)) != old_seq:
		changed.emit()  # состав, очки, звезда — перерисовать окно; простой сдвиг шариков рисует само поле


## Ввод в комнате: шарики — {"aim": Vector2, "on": bool} (часто, без гарантии доставки), {"dash": true};
## звёздочки — {"catch": id звезды}.
func room_act(game: String, action: Dictionary) -> void:
	if not in_room(game):
		return
	if _room_host():
		_host_room_act(my_peer(), game, action)
	elif action.has("aim"):
		_rpc_room_aim_up.rpc_id(1, action.aim, bool(action.get("on", false)), game)
	else:
		_rpc_room_act_up.rpc_id(1, game, action)


@rpc("any_peer", "unreliable_ordered")
func _rpc_room_aim_up(aim: Vector2, on: bool, game: String = "balls") -> void:
	if _net().is_host():
		_host_room_act(multiplayer.get_remote_sender_id(), game, {"aim": aim, "on": on})


@rpc("any_peer", "reliable")
func _rpc_room_act_up(game: String, action: Dictionary) -> void:
	if _net().is_host():
		_host_room_act(multiplayer.get_remote_sender_id(), game, action)


func _host_room_act(peer: int, game: String, action: Dictionary) -> void:
	if not _rooms.has(game):
		return
	var room: Dictionary = _rooms[game]
	if _net().minigames_locked_now(peer):
		if game == "balls":
			Balls.force_ghost(room.state, peer)
		elif game == "race":
			Race.force_ghost(room.state, peer)
		else:
			_tell(peer, "Мини-игры приостановлены до конца вашего хода")
		return
	if game == "balls":
		if action.has("aim") and action.aim is Vector2:
			Balls.steer(room.state, peer, action.aim, bool(action.get("on", false)))
		elif bool(action.get("dash", false)):
			Balls.dash(room.state, peer)
	elif game == "race":
		if bool(action.get("change_track", false)):
			if Race.change_track(room.state, peer, _room_rng):
				_room_push(game)
		elif action.has("aim") and action.aim is Vector2:
			Race.steer(room.state, peer, action.aim, bool(action.get("on", false)))
		elif bool(action.get("dash", false)):
			Race.dash(room.state, peer)
	elif game == "stars" and action.has("catch"):
		if Stars.catch_star(room.state, peer, int(action.catch), _room_rng):
			_send(peer, "_rpc_star_caught", [1])
			_room_push(game)
	elif game == "blackjack":
		var error: String = Blackjack.act(room.state, peer, action, _room_rng)
		if error != "":
			_tell(peer, error)
			return
		_room_push(game)


@rpc("authority", "reliable")
func _rpc_star_caught(_points: int) -> void:
	Sfx.play("hufflesoft", -6.0)


## Мини-игры у меня сейчас заблокированы: идёт мой ход в основной игре, и хост не разрешил.
var probe_blocked := false  # только для служебных проб (tools/_mg_probe): изобразить «мой ход»


func blocked_now() -> bool:
	if probe_blocked:
		return true
	if not _net().in_session():
		return false
	if _net().is_host():
		return bool(_net().minigames_locked_now(my_peer()))
	return bool((_net().view as Dictionary).get("minigames_blocked", false))


var _lock_clock := 0.0


## Хост: у кого начался ход — шарик сразу призрак (проверка 10 раз в секунду: вид места считать недёшево).
func _host_turn_locks(delta: float) -> void:
	_lock_clock += delta
	if _lock_clock < 0.1 or not _net().is_host():
		return
	_lock_clock = 0.0
	for game: String in ["balls", "race"]:
		if not _rooms.has(game):
			continue
		var state: Dictionary = _rooms[game].state
		for peer: int in _room_peers(game):
			if _net().minigames_locked_now(peer):
				if game == "race":
					Race.force_ghost(state, peer)
				else:
					Balls.force_ghost(state, peer)


## Каждый кадр: хост двигает комнаты и рассылает положение шариков.
func _rooms_process(delta: float) -> void:
	_host_turn_locks(delta)
	if not _online():
		# без пати комнаты живут, только пока открыта их вкладка
		for game: String in _rooms.keys():
			if not _offline_room(room_id(game)):
				_rooms.erase(game)
	elif not _net().is_host():
		_rooms.clear()
	for game: String in _rooms.keys():
		var room: Dictionary = _rooms[game]
		room.acc = minf(float(room.acc) + delta, 0.25)
		var dirty := false
		while float(room.acc) >= ROOM_STEP:
			room.acc = float(room.acc) - ROOM_STEP
			if game == "balls":
				dirty = not Balls.step(room.state, ROOM_STEP, _room_rng).is_empty() or dirty
			elif game == "race":
				dirty = Race.step(room.state, ROOM_STEP, _room_rng) or dirty
			elif game == "blackjack":
				dirty = Blackjack.step(room.state, ROOM_STEP, _room_rng) or dirty  # дилер добирает по карте
			else:
				dirty = Stars.step(room.state, ROOM_STEP, _room_rng) or dirty
		if dirty:
			_room_push(game)
		elif game in ["balls", "race"]:
			room.tick = float(room.tick) + delta
			if float(room.tick) >= ROOM_TICK:
				room.tick = 0.0
				var snap := _room_snapshot(game)
				for peer: Variant in _room_peers(game):
					if int(peer) == my_peer():
						_take_room(game, snap)
					elif not _member(int(peer)).is_empty():
						_rpc_room_tick.rpc_id(int(peer), game, snap)


## Звёздочка поверх всего интерфейса — только у тех, кто в комнате «Лови звёздочку».
func _sync_overlay() -> void:
	var session: Dictionary = sessions.get(room_id("stars"), {})
	var state: Dictionary = session.get("state", {})
	var star: Dictionary = state.get("star", {})
	if star.is_empty() and not is_instance_valid(_overlay):
		return
	if not is_instance_valid(_overlay):
		_overlay = StarOverlay.new()
		_overlay.blocked = blocked_now  # в свой ход звезда не видна и не ловится
		_overlay.caught.connect(func(id: int): room_act("stars", {"catch": id}))
		get_tree().root.add_child.call_deferred(_overlay)
	_overlay.call("show_star", star)


## Лучший результат соло-игры на этом компьютере.
static func best(key: String) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(BEST_PATH) != OK:
		return 0
	return int(cfg.get_value("best", key, 0))


static func _save_best(key: String, value: int) -> void:
	if value <= best(key):
		return
	var cfg := ConfigFile.new()
	cfg.load(BEST_PATH)
	cfg.set_value("best", key, value)
	cfg.save(BEST_PATH)


const BEST_TIME_KEY := "mines_classic_time"


## Секундомер обычного сапёра: идёт и на других вкладках, в мой ход в основной игре — пауза;
## после хода ждёт «Продолжить?» (resume_mines), а не продолжает сам.
func _mines_clock(delta: float) -> void:
	var blocked := false
	var checked := false
	for id: String in sessions:
		var session: Dictionary = sessions[id]
		if str(session.game) != "mines" or not bool(session.local):
			continue
		var state: Dictionary = session.state
		if not RULES.mines.clock_running(state):
			continue
		if not checked:
			blocked = blocked_now()
			checked = true
		if blocked:
			state.paused = true
		elif not bool(state.paused):
			state.elapsed = float(state.elapsed) + delta


## Сапёр стоит на паузе после моего хода и ждёт «Продолжить?».
func mines_waiting(id: String) -> bool:
	if not sessions.has(id) or str(sessions[id].game) != "mines":
		return false
	var state: Dictionary = sessions[id].state
	return bool(state.get("paused", false)) and RULES.mines.clock_running(state)


func resume_mines(id: String) -> void:
	if mines_waiting(id) and not blocked_now():
		sessions[id].state.paused = false
		changed.emit()


## Лучшее время (секунды, 0 — ещё нет) на этом компьютере; меньше — лучше.
static func best_time(key: String) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(BEST_PATH) != OK:
		return 0.0
	return float(cfg.get_value("best_time", key, 0.0))


static func _save_best_time(key: String, seconds: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(BEST_PATH)
	cfg.set_value("best_time", key, seconds)
	cfg.save(BEST_PATH)


## Соло: начать заново в той же вкладке.
func restart_local(id: String) -> void:
	if not sessions.has(id) or not bool(sessions[id].local):
		return
	var session: Dictionary = sessions[id]
	session.state = RULES[str(session.game)].new_state(session.opts)
	changed.emit()
