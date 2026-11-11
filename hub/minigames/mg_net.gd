extends Node
## Мини-игры один на один внутри пати (узел /root/Net/MiniGames, создаёт Net): шахматы, шашки, го.
##
## Приглашение → согласие → партия. Партии живут на хосте пати: он проверяет ходы правилами
## (hub/minigames/logic) и рассылает обоим игрокам снимок. Времени на ход нет. Партий может быть несколько;
## они не зависят от основной игры и переживают смену экрана. Окно — общее «Общение» (hub/comms_panel.gd),
## поле — hub/minigames/mg_board.gd. Без пати доступна только партия «за обоих» на этом компьютере.
## После смены хоста игроки сами возвращают свои партии новому хосту (по никам).

signal changed  # партии, приглашения, выбранная вкладка
signal notice(text: String)

const GAMES := ["chess", "checkers", "go"]
const TITLES := {"chess": "Шахматы", "checkers": "Шашки", "go": "Го"}
const RULES := {
	"chess": preload("res://hub/minigames/logic/mg_chess.gd"),
	"checkers": preload("res://hub/minigames/logic/mg_checkers.gd"),
	"go": preload("res://hub/minigames/logic/mg_go.gd"),
}
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
	if game not in GAMES or sessions.size() >= MAX_SESSIONS:
		return
	var id := "local%d" % _local_next
	_local_next += 1
	var clean := _clean_opts(game, opts)
	sessions[id] = {"id": id, "game": game, "opts": clean, "peers": [0, 0], "names": ["Вы", "Вы"],
		"state": RULES[game].new_state(clean), "seat": 0, "dot": false, "gone": false, "local": true, "orphan": false}
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


## Ход в партии: словарь хода правил игры или {"resign": true}.
func move(id: String, action: Dictionary) -> void:
	if not sessions.has(id):
		return
	var session: Dictionary = sessions[id]
	if bool(session.local):
		var state: Dictionary = session.state
		var error := _apply(str(session.game), state, int(state.turn), action)
		if error != "":
			notice.emit(error)
		else:
			Sfx.play("chip", -8.0)
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


# --- Смена хоста и выход из пати -----------------------------------------------------------

## Хост сменился: приглашения сгорают, партии ждут возвращения новому хосту.
func reset_party() -> void:
	_host_sessions.clear()
	_host_invites.clear()
	_restored.clear()
	invites_in.clear()
	invites_out.clear()
	for id: String in sessions:
		if not bool(sessions[id].local):
			sessions[id].orphan = true
	changed.emit()


func _process(delta: float) -> void:
	_clock += delta
	if _clock < 1.0:
		return
	_clock = 0.0
	if not _online():
		# вышли из пати: сетевые партии закрыть, локальные оставить
		var dropped := false
		for id: String in sessions.keys():
			if not bool(sessions[id].local):
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
	for id: String in sessions:
		var session: Dictionary = sessions[id]
		if not bool(session.orphan):
			continue
		var data := {"game": session.game, "opts": session.opts, "names": session.names, "state": session.state}
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
