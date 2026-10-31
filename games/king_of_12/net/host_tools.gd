class_name HostTools
extends RefCounted
## Панель хоста (логика): отмена/повтор действий через снимки состояния правил, таймер хода,
## правка игроков (очки/фишки, карты), смена загаданной темы, кик и «сделать зрителем».
## Живёт в Net (только на хосте). Снимок — все переменные скрипта объекта правил, вложенные
## RefCounted-объекты восстанавливаются в те же экземпляры, ГСЧ — по state.
## Игровые правки — через необязательные методы правил: host_stats / host_set_stat /
## host_give_card / host_take_card / host_hand / host_new_theme (нет метода — нет кнопки).

const LIMIT := 40  # сколько действий можно отменить
const MAX_DEPTH := 12
const RECENT := 8  # «этот/прошлый ход» для «Убрать карту»: столько последних действий назад

var net: Node
var _undo: Array = []  # [{snap, hands}]
var _redo: Array = []
var _pending: Variant = null  # снимок до действия игрока; в историю — только если состояние разослали
var _hands_log: Array = []  # руки мест на каждом шаге истории (для «Убрать карту»)
var restoring := false


func _init(owner: Node) -> void:
	net = owner


func reset() -> void:
	_undo.clear()
	_redo.clear()
	_pending = null
	_hands_log.clear()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


# --- история ---------------------------------------------------------------

## Перед действием игрока (Net._handle_action).
func before_action(kind: String) -> void:
	if restoring or kind in ["view_seat"]:
		return
	var g: Object = net._game_obj()
	if g == null:
		return
	_pending = {"snap": snapshot(g), "hands": _hands(g)}


## Состояние разослано (Net._push_state): действие что-то поменяло — кладём снимок «до» в историю.
func committed() -> void:
	if restoring or _pending == null:
		return
	_undo.append(_pending)
	_pending = null
	_redo.clear()
	while _undo.size() > LIMIT:
		_undo.pop_front()


func undo() -> bool:
	return _step(_undo, _redo)


func redo() -> bool:
	return _step(_redo, _undo)


func _step(from: Array, to: Array) -> bool:
	var g: Object = net._game_obj()
	if g == null or from.is_empty():
		return false
	if (from.back() as Dictionary).snap.get("__obj") != g:
		reset()  # история прошлой партии: объект правил уже другой
		return false
	to.append({"snap": snapshot(g), "hands": _hands(g)})
	var entry: Dictionary = from.pop_back()
	restoring = true
	restore(entry.snap)
	_pending = null
	net._phase_time = 0.0
	net._stamp_turn = true
	net._push_state()
	restoring = false
	return true


# --- снимки ----------------------------------------------------------------

## Глубокая копия состояния объекта правил.
static func snapshot(obj: Object) -> Dictionary:
	return _snap(obj, 0)


static func restore(snap: Variant) -> Variant:
	return _unsnap(snap)


static func _snap(v: Variant, depth: int) -> Variant:
	if depth > MAX_DEPTH:
		return v
	match typeof(v):
		TYPE_ARRAY:
			var arr: Array = v
			if not _has_obj(arr, depth):
				return arr.duplicate(true)
			var items := []
			for x: Variant in arr:
				items.append(_snap(x, depth + 1))
			var proto := arr.duplicate()
			proto.clear()
			return {"__arr": items, "proto": proto}
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if not _has_obj(d, depth):
				return d.duplicate(true)
			var vals := {}
			for k: Variant in d:
				vals[k] = _snap(d[k], depth + 1)
			return {"__dict": vals}
		TYPE_OBJECT:
			var o: Object = v
			if o == null or not is_instance_valid(o):
				return v
			if o is RandomNumberGenerator:
				return {"__rng": o, "state": (o as RandomNumberGenerator).state}
			if o is Node or o is Resource or o.get_script() == null:
				return v  # узлы, ресурсы и встроенные объекты — по ссылке
			var vars := {}
			for p: Dictionary in o.get_property_list():
				if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
					vars[p.name] = _snap(o.get(p.name), depth + 1)
			return {"__obj": o, "vars": vars}
	return v


static func _unsnap(s: Variant) -> Variant:
	if typeof(s) == TYPE_ARRAY:
		return (s as Array).duplicate(true)
	if typeof(s) != TYPE_DICTIONARY:
		return s
	var d: Dictionary = s
	if d.has("__obj"):
		var o: Object = d["__obj"]
		var vars: Dictionary = d["vars"]
		for name: String in vars:
			o.set(name, _unsnap(vars[name]))
		return o
	if d.has("__rng"):
		var rng: RandomNumberGenerator = d["__rng"]
		rng.state = int(d["state"])
		return rng
	if d.has("__arr"):
		var out: Array = (d["proto"] as Array).duplicate()
		for x: Variant in d["__arr"]:
			out.append(_unsnap(x))
		return out
	if d.has("__dict"):
		var vals: Dictionary = d["__dict"]
		var res := {}
		for k: Variant in vals:
			res[k] = _unsnap(vals[k])
		return res
	return d.duplicate(true)


static func _has_obj(v: Variant, depth: int) -> bool:
	if depth > MAX_DEPTH:
		return false
	match typeof(v):
		TYPE_OBJECT:
			return v != null
		TYPE_ARRAY:
			var arr: Array = v
			if arr.is_typed() and arr.get_typed_builtin() != TYPE_OBJECT:
				return false
			for x: Variant in arr:
				if _has_obj(x, depth + 1):
					return true
		TYPE_DICTIONARY:
			for x: Variant in (v as Dictionary).values():
				if _has_obj(x, depth + 1):
					return true
	return false


func _hands(g: Object) -> Dictionary:
	var out := {}
	if not g.has_method("host_hand"):
		return out
	for seat: int in net._gp().size():
		out[seat] = (g.call("host_hand", seat) as Array).duplicate()
	return out


# --- что умеет панель для текущей игры --------------------------------------

## Описание для UI панели: игра, игроки и их параметры.
func info() -> Dictionary:
	var g: Object = net._game_obj()
	var players: Array = []
	var gp: Array = net._gp() if g != null else []
	for seat: int in gp.size():
		var peer: int = net.seat_peers[seat] if seat < net.seat_peers.size() else 0
		players.append({
			"seat": seat,
			"name": str(gp[seat].get("name", "Игрок %d" % (seat + 1))),
			"peer": peer,
			"remote": peer > 1,
			"bot": bool(gp[seat].get("bot", false)),
			"stats": g.call("host_stats", seat) if g != null and g.has_method("host_stats") else [],
			"cards": g != null and g.has_method("host_give_card"),
		})
	var limit := int(net.settings.get(_timer_key(), 60))
	return {
		"undo": can_undo(),
		"redo": can_redo(),
		"timer_on": limit > 0,
		"timer": limit if limit > 0 else int(net.settings.get("host_last_turn_time", 60)),
		"theme": g != null and g.has_method("host_new_theme"),
		"players": players,
		"spectate": net.mode != "offline",
	}


func set_timer(on: bool, seconds: int) -> void:
	seconds = clampi(seconds, 5, 900)
	net.settings["host_last_turn_time"] = seconds
	net.settings[_timer_key()] = seconds if on else 0
	var g: Object = net._game_obj()
	if g != null and "turn_time" in g:
		g.set("turn_time", float(seconds) if on else 0.0)  # покер считает время хода сам
		if "time_left" in g and str(g.get("phase")) == "hand":
			g.set("time_left", float(seconds))  # текущий ход — заново с новым временем
	net._system_chat("Хост изменил время на ход: %s." % ("%d с" % seconds if on else "без ограничения"))
	net._phase_time = 0.0
	net._stamp_turn = true
	net._push_state()


## Things in Rings хранит время хода отдельно (tr_timer), остальные — общий turn_time.
func _timer_key() -> String:
	return "tr_timer" if net.tir != null else "turn_time"


func new_theme() -> bool:
	var g: Object = net._game_obj()
	if g == null or not g.has_method("host_new_theme"):
		return false
	before_action("host")
	if not bool(g.call("host_new_theme")):
		_pending = null
		return false
	net._system_chat("Хост сменил загаданное.")
	net._push_state()
	return true


func set_stat(seat: int, key: String, value: int) -> bool:
	var g: Object = net._game_obj()
	if g == null or not g.has_method("host_set_stat"):
		return false
	before_action("host")
	if not bool(g.call("host_set_stat", seat, key, value)):
		_pending = null
		return false
	net._push_state()
	return true


func give_card(seat: int) -> bool:
	var g: Object = net._game_obj()
	if g == null or not g.has_method("host_give_card"):
		return false
	before_action("host")
	if g.call("host_give_card", seat) == null:
		_pending = null
		return false
	net._system_chat("Хост выдал карту: %s." % _name(seat))
	net._push_state()
	return true


## Забрать карту: полученную в этом/прошлом ходу (по истории рук), иначе случайную.
func take_card(seat: int) -> bool:
	var g: Object = net._game_obj()
	if g == null or not g.has_method("host_take_card"):
		return false
	var prefer: Array = []
	if g.has_method("host_hand"):
		var now: Array = g.call("host_hand", seat)
		var back := mini(RECENT, _undo.size())
		if back > 0:
			var old: Array = (_undo[_undo.size() - back] as Dictionary).hands.get(seat, [])
			for card: Variant in now:
				if not old.has(card):
					prefer.append(card)
	before_action("host")
	if g.call("host_take_card", seat, prefer) == null:
		_pending = null
		return false
	net._system_chat("Хост забрал карту: %s." % _name(seat))
	net._push_state()
	return true


func kick(seat: int) -> void:
	var peer: int = net.seat_peers[seat] if seat < net.seat_peers.size() else 0
	if peer <= 1:
		return
	net._system_chat("Хост исключил игрока %s." % _name(seat))
	net._rpc_kicked.rpc_id(peer, "хост исключил вас из партии.")


func make_spectator(seat: int) -> void:
	var peer: int = net.seat_peers[seat] if seat < net.seat_peers.size() else 0
	if peer <= 1:
		return
	net._make_spectator(peer)


func _name(seat: int) -> String:
	var gp: Array = net._gp()
	return str(gp[seat].get("name", "")) if seat < gp.size() else ""
