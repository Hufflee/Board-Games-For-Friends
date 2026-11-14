class_name CERules
extends RefCounted
## Правила «Кольт Экспресс». Тест: res://tests/test_colt_express.gd.

const NAMES := ["Туко", "Док", "Шейенна", "Джанго", "Призрак", "Белла"]
const ACTIONS := {"move":"Перемещение", "level":"Смена уровня", "shoot":"Выстрел", "punch":"Удар", "loot":"Добыча", "marshal":"Маршал", "bullet":"Пуля", "ride":"Верхом", "idea":"Блестящая идея", "capture":"Арест", "move_plus":"Перемещение +", "level_plus":"Смена уровня +"}
const EVENTS := {"none":"Конец раунда", "tail":"Поворотная рука", "brake":"Торможение", "passengers":"Восстание пассажиров", "angry":"Маршал зол", "case":"Забирайте всё!", "revenge":"Возмездие маршала", "ransom":"Кондуктор взят в заложники", "pockets":"Карманные кражи","speed":"Ускорение поезда","tired":"Уставшие лошади","rage":"Ярость охранника","whiskey":"Виски для маршала","reflex":"Рефлекторное действие","rumors":"Слухи","safekeeping":"На крышу","sharing":"Раздел добычи","escape":"Побег","mortal":"Смертельная пуля","crime":"Преступление не окупается","fall":"Смертельное падение","guilty":"Угрызения совести"}
# О — открытый, Т — тоннель, Д — двойной, Н — обратный порядок.
const ROUND_STEPS := ["отото", "отоо", "одо", "оооо", "оотоо", "оотн", "отдо", "оон", "одн", "отот", "ото", "од", "отоо", "отон", "оото", "оото", "оото"]
const ROUND_EVENTS := ["none","tail","none","brake","passengers","angry","case","angry","case","none","tail","none","brake","passengers","revenge","ransom","pockets"]
const CAR_LOOT := [[1,0],[0,3],[1,1],[3,1],[3,0],[4,1]]

const EXTRA_STEPS := ["ото","водо","отво","оотто","втоо","ооок","ооок","ооото","ото","окк","вто","отто","вод","оото","отво","окко","ото","оото","оок","оок","оото","оотоо","оото","оото","оото","оото"]
const EXTRA_EVENTS := ["speed","tired","rage","whiskey","none","reflex","rumors","safekeeping","reflex","none","none","whiskey","tired","speed","rage","none","reflex","safekeeping","rumors","reflex","sharing","escape","mortal","crime","fall","guilty"]
const RESERVE := {17:1,19:1,20:1,21:2,23:1,24:1,26:1,27:2,28:1,30:1,31:1,32:1,34:1}
var reserve_limit := 0
var reserve_count := 0
var reflex_count := 0
var reflex_done := false
var angry_step := 0
var simultaneous: Array[Dictionary] = []
var round_received: Array = []
var escaped: Array[int] = []
var revealed_goals: Array = []
var players: Array = []
var bandits: Array[Dictionary] = []
var cars := 0
var car_types: Array = []
var phase := "select"
var turn_no := 0
var turn := 0
var starter := 0
var teams := false
var team_hits: Array[int] = []
var step_starter := 0
var steps := ""
var step := 0
var subturn := 0
var rounds: Array = []
var queue: Array[Dictionary] = []
var cursor := 0
var serial := 0
var marshal_car := 0
var neutral := 13
var loot: Array[Dictionary] = []
var history: Array[Dictionary] = []
var clip: Dictionary = {}
var replay_index := 0
var match_history: Array[Array] = []
var replay_round := 0
var elapsed := 0.0
## Пауза после переворота верхней карты стопки, прежде чем действие разыграется на поезде (владелец, 14.11).
## Только при запуске кнопкой «Следующее действие» без выбора; в повторах паузы нет.
const FLIP_LEAD := 2.0
## Скорость показа действий и повторов (хост: 1, 2 или 4) — владелец, 15.11.
var speed := 1.0
var options: Array[Dictionary] = []
var reactions: Array[Dictionary] = []
var staged_clip: Dictionary = {}
var pending: Dictionary = {}
var sprites := false
var marshal_player := false
var marshal_goals: Array = []
const BULLET_EFFECTS := ["shoot","level","punch","prisoner","mailbag","gold"]
const BULLET_LABELS := ["Разоружение","Ранение в колено","Ранение в плечо","Отобрать сообщника","Отобрать почту","Золотая пуля"]
var cylinders := [0,0]
var seized_prisoners := 0
var seized_mailbags := 0
var hits_on_marshal := {}
var arrested: Array[int] = []
var brawls := [800,500,300]
var cursed := false
var prison := false
var prisoners: Array = []
var copied_kind := ""
var last_kind := ""
var coach_enabled := false
var coach_car := 0
var guard_on_train := false
var coach_hostages: Array = []
const HOSTAGES := ["Пудель","Банкир","Министр","Учитель","Фанатик","Старушка","Игрок в покер","Фотограф"]
var time_car := false
var travel_bandit := -1
var travel_destination := -1
var horses_enabled := false
var whiskey_enabled := false
var horses: Array[int] = []
var mount_car := 0
var mount_votes: Dictionary = {}
var flask_plays := 0
var duel := false
var results: Array[Dictionary] = []

func new_game(seats: Array, config: Dictionary) -> void:
	players = seats.duplicate(true)
	duel = players.size() == 2
	sprites = bool(config.get("sprites", false))
	marshal_player = not duel and bool(config.get("marshal_player",false))
	teams = not marshal_player and players.size() in [4,6] and bool(config.get("teams",false))
	if teams:
		team_hits.resize(players.size()/2)
		team_hits.fill(0)
	cursed = bool(config.get("cursed",false))
	prison = marshal_player or bool(config.get("prison",false))
	if prison:
		prisoners = [0,1,2,3,4,5,7]
		prisoners.shuffle()
		prisoners.resize(3)
	coach_enabled = bool(config.get("coach",false))
	time_car = bool(config.get("time_car",false))
	horses_enabled = bool(config.get("horses",false))
	whiskey_enabled = bool(config.get("whiskey",false))
	if coach_enabled:
		neutral += 3
		coach_hostages = range(HOSTAGES.size())
		coach_hostages.shuffle()
		coach_hostages.resize(players.size()-1)
	cars = (5 if players.size() <= 5 else 6) if marshal_player else (4 if duel else players.size())
	starter = 0 if marshal_player else randi_range(0, players.size() - 1)
	if teams:
		starter = starter & ~1
	turn = starter
	car_types = range(6)
	car_types.shuffle()
	car_types.resize(cars)
	var purses := [250,250,250,250,250,250,300,300,300,300,350,350,350,400,400,450,450,500]
	if cursed:
		purses.append_array([1,1,2,2])
	purses.shuffle()
	if marshal_player:
		_add_loot("mailbag",200,0)
		_add_loot("mailbag",1200,0)
	else:
		_add_loot("case", 10 if cursed and randi_range(0,2) == 0 else 1000, 0)
	if coach_enabled:
		_add_loot("case",1000,-2)
		loot.back()["roof"] = true
	for i in cars:
		if prison and i == cars-1:
			continue
		var counts: Array = CAR_LOOT[car_types[i]]
		for j in counts[0]:
			_add_loot("purse", purses.pop_back(), i + 1)
		for j in counts[1]:
			_add_loot("gem", 5 if cursed and randi_range(0,3) == 0 else 500, i + 1)
	if whiskey_enabled:
		var old := randi_range(1,6)
		for car in range(1,cars+1):
			_add_loot("old_whiskey" if car == old else "whiskey",0,car)
			loot.back()["uses"] = 2
	var small := players.size()-int(marshal_player) <= 4
	rounds = range(0,7) if small else range(7,14)
	var stations := range(14,17)
	if coach_enabled:
		rounds.append_array([17,19] if small else [30,31])
		stations.append_array([37,38,39])
	if horses_enabled:
		rounds.append(18 if small else 29)
	if whiskey_enabled:
		rounds.append(20 if small else 28)
	if horses_enabled or whiskey_enabled:
		rounds.append(21 if small else 27)
	if marshal_player:
		rounds.append_array(range(22,27) if small else range(32,37))
		stations.append_array([40,41,42])
	rounds.shuffle()
	rounds.resize(4)
	rounds.append(stations.pick_random())
	for player: Dictionary in players:
		player["deck"] = []
		player["hand"] = []
		player["discard"] = []
		player["received"] = 0
		player["ransom"] = 0
	if marshal_player:
		bandits.append({"id":6,"seat":0,"car":0,"roof":false,"ammo":12})
		for kind in ["move","move","move_plus","level","level_plus","shoot","shoot","shoot","capture","capture"]:
			players[0].deck.append({"id":6,"kind":kind})
		turn = 1

func _add_loot(kind: String, value: int, car: int, bandit: int = -1) -> void:
	loot.append({"kind":kind, "value":value, "car":car, "roof":false, "owner":bandit})

func _select(seat: int, id: int) -> bool:
	if id < 0 or (id >= NAMES.size() and not (prison and id == 7)) or _bandit(id) != {}:
		return false
	var count := 0
	for b in bandits:
		if b.seat == seat:
			count += 1
	var rank := posmod(seat - starter, players.size())
	var car := cars - (count if duel else (seat % 2 if teams else rank % 2)) - int(prison)
	bandits.append({"id":id,"seat":seat,"car":car,"roof":false,"ammo":6})
	_add_loot("purse",250,-1,id)
	var deck: Array = players[seat].deck
	for kind: String in ACTIONS:
		if kind in ["bullet","capture","move_plus","level_plus"] or (marshal_player and kind == "marshal") or (kind == "ride" and not horses_enabled) or (kind == "idea" and not prison) or (duel and kind == "marshal" and count == 1):
			continue
		deck.append({"id":id,"kind":kind})
		if not duel and kind not in ["punch","marshal","ride","idea"]:
			deck.append({"id":id,"kind":kind})
	if not duel or count == 1:
		turn = (turn + 1) % players.size()
	if bandits.size() == (4 if duel else players.size()):
		if marshal_player:
			var warrants := bandits.filter(func(b: Dictionary) -> bool: return b.id != 6).map(func(b: Dictionary) -> int: return b.id)
			warrants.shuffle()
			marshal_goals = warrants.slice(0,2)
			var special := ["brawler","mail","keys","cylinder","dodge"]
			if warrants.size() >= 4:
				special.append_array(["all_hit","four_hits"])
			special.shuffle()
			marshal_goals.append_array(special.slice(0,3))
			marshal_goals.shuffle()
		if horses_enabled:
			phase = "mount"
			mount_car = cars-int(prison)
			if marshal_player:
				horses.append(0)
				_bandit(6)["mounted"] = true
			_advance_mount()
		else:
			_start_round()
	return true

func _bandit(id: int) -> Dictionary:
	for b in bandits:
		if b.id == id:
			return b
	return {}

## Сколько жетонов добычи у бандита (для строки бандитов на столе; номиналы остаются тайными).
func _bag_count(id: int) -> int:
	var count := 0
	for item: Dictionary in loot:
		if int(item.owner) == id:
			count += 1
	return count

func _board(seat: int = -2) -> Dictionary:
	var positions: Array[Dictionary] = []
	for b in bandits:
		if b.id in escaped:
			continue
		if travel_bandit == b.id and phase in ["plan","discard","reserve"] and seat != b.seat:
			continue
		positions.append({"id":b.id,"seat":b.seat,"car":-4 if phase == "mount" and not b.has("mounted") else b.car,"roof":b.roof,"ammo":b.ammo,"hostage":b.get("hostage",-1),"cell":b.get("cell",false),"bags":_bag_count(b.id)})
	var ground: Array[Dictionary] = []
	for i in loot.size():
		var item: Dictionary = loot[i]
		if item.owner == -1 and (item.car >= 0 or item.car == -2 or item.get("in_time",false)):
			ground.append({"index":i,"car":item.car,"roof":item.roof,"kind":"whiskey" if item.kind == "old_whiskey" else item.kind})
	return {"bandits":positions,"loot":ground,"marshal":-1 if marshal_player else marshal_car,"horses":horses.duplicate(),"time_car":time_car,"prison":prison,"coach":coach_car if coach_enabled else -1,"guard":guard_on_train}

func _draw(seat: int, amount: int) -> void:
	var p: Dictionary = players[seat]
	for i in maxi(0,amount):
		if p.deck.is_empty() and duel and not p.discard.is_empty():
			p.discard.shuffle()
			p.deck = p.discard
			p.discard = []
		if p.deck.is_empty():
			break
		p.hand.append(p.deck.pop_back())

func _start_round() -> void:
	turn_no += 1
	phase = "plan"
	step_starter = starter
	turn = starter
	step = 0
	subturn = 0
	flask_plays = 0
	for b in bandits:
		b.erase("penalties")
	last_kind = ""
	cursor = 0
	queue.clear()
	history.clear()
	clip = {}
	var card: int = rounds[turn_no-1]
	steps = ROUND_STEPS[card] if card < 17 else EXTRA_STEPS[card-17]
	reserve_limit = int(RESERVE.get(card,0))
	reserve_count = 0
	reflex_done = false
	angry_step = 0
	reflex_count = 0
	round_received = players.map(func(player: Dictionary) -> int: return player.received)
	for player: Dictionary in players:
		if not duel or turn_no == 1:
			player.deck.shuffle()
	if teams:
		for s in players.size():
			var partner_deck: Array = players[s ^ 1].deck
			if not partner_deck.is_empty():
				players[s].hand.append(partner_deck.pop_back())
	for s in players.size():
		var p: Dictionary = players[s]
		var count := 6
		for b in bandits:
			if b.seat == s:
				if _power(b,1):
					count += 1
				if b.get("hostage",-1) == 2:
					count -= 1
				if b.get("hostage",-1) == 0:
					_wound(b)
		_draw(s, count - p.hand.size())
		if duel:
			for i in range(p.hand.size() - 1, -1, -1):
				if p.hand[i].kind == "bullet":
					p.discard.append(p.hand.pop_at(i))

func _advance_plan() -> void:
	if steps[step] == "д" and subturn == 0:
		subturn = 1
		return
	subturn = 0
	turn = posmod(turn + (-1 if steps[step] == "н" else 1), players.size())
	if turn != step_starter:
		return
	queue.append_array(simultaneous)
	simultaneous.clear()
	step += 1
	if step < steps.length():
		step_starter = starter + int(teams and steps[step] == "н")
		turn = step_starter
		return
	if not duel and reserve_limit > 0:
		phase = "reserve"
		turn = starter
	elif duel:
		phase = "discard"
		turn = starter
	else:
		if _round_event() != "reflex":
			_return_hands()
		_open()

func _return_hands() -> void:
	for player: Dictionary in players:
		player.deck.append_array(player.hand)
		player.hand.clear()
		player.hand.append_array(player.get("reserved",[]))
		player.erase("reserved")

func _advance_reflex() -> void:
	reflex_count += 1
	serial += 1
	if reflex_count >= players.size():
		reflex_done = true
		if not duel:
			_return_hands()
		_open()
	else:
		turn = posmod(starter+reflex_count,players.size())
		phase = "reflex"

func _round_event() -> String:
	var id: int = rounds[turn_no-1]
	return ROUND_EVENTS[id] if id < 17 else EXTRA_EVENTS[id-17]

func _open() -> void:
	if travel_bandit >= 0 and travel_destination >= 0:
		var b := _bandit(travel_bandit)
		b.car = travel_destination
		b.roof = false
		travel_bandit = -1
		travel_destination = -1
		_meet_marshal()
	serial += 1
	phase = "reveal"
	if cursor == queue.size() and _round_event() == "reflex" and not reflex_done:
		phase = "reflex"
		turn = starter
		return
	if cursor == queue.size() and marshal_player and _round_event() == "angry" and angry_step < 2:
		pending = {"kind":"shoot" if angry_step == 0 else "move","id":6,"event_action":true}
		turn = 0
		options.clear()
		return
	pending = queue[cursor] if cursor < queue.size() else {"kind":"event","id":-1,"event":_round_event()}
	turn = int(_bandit(pending.id).get("seat",-1))
	options.clear()

func action(seat: int, kind: String, arg: Dictionary, host: bool) -> bool:
	if seat < 0 or seat >= players.size():
		return false
	# ускорение и пропуск анимаций — только хост, правил не меняют
	if host and kind == "anim_speed":
		speed = clampf(float(arg.get("value", 1.0)), 1.0, 4.0)
		return true
	if host and kind == "skip_anim" and phase in ["animate", "replay", "match_replay"]:
		_skip_animation()
		return true
	if phase == "select" and seat == turn and kind == "select":
		return _select(seat,int(arg.get("id",-1)))
	if phase == "travel" and seat == turn and kind == "travel" and int(arg.get("serial",-1)) == serial:
		var car := int(arg.get("car",-2))
		if car < 0 or car > cars:
			return false
		travel_destination = car
		_next_round()
		return true
	if phase == "mount" and kind == "mount" and int(arg.get("serial",-1)) == serial:
		for bandit in bandits:
			if bandit.seat == seat and not bandit.has("mounted") and not mount_votes.has(bandit.id):
				mount_votes[bandit.id] = bool(arg.get("land",false)) or mount_car == 1
				_advance_mount()
				return true
		return false
	if phase == "plan" and seat == turn:
		if int(arg.get("serial",-1)) != serial:
			return false
		if kind == "flask":
			return _drink(seat,int(arg.get("index",-1)))
		if kind == "draw" and flask_plays == 0:
			_draw(seat,3)
		elif kind == "draw_idea" and prison and flask_plays == 0:
			var pile: Array = players[seat].deck
			var i := pile.find_custom(func(card: Dictionary) -> bool: return card.kind == "idea")
			if i < 0:
				return false
			players[seat].hand.append(pile.pop_at(i))
			pile.shuffle()
		elif kind == "play":
			var hand: Array = players[seat].hand
			var i := int(arg.get("index",-1))
			if i < 0 or i >= hand.size() or hand[i].kind == "bullet" or (steps[step] == "к" and hand[i].kind in ["shoot","punch"]):
				return false
			var c: Dictionary = hand.pop_at(i)
			var planner := _bandit(c.id)
			c["hidden"] = planner.get("hostage",-1) != 7 and (steps[step] == "т" or (_power(planner,4) and step == 0 and subturn == 0 and bool(arg.get("hidden",false))))
			if steps[step] == "в":
				simultaneous.append(c)
			else:
				queue.append(c)
			if c.kind.ends_with("_plus") and flask_plays == 0 and steps[step] == "о" and hand.any(func(other: Dictionary) -> bool: return other.kind != "bullet"):
				flask_plays = maxi(2,flask_plays+1)
		else:
			return false
		serial += 1
		if flask_plays > 0:
			flask_plays -= 1
		if flask_plays == 0:
			_advance_plan()
		return true
	if phase == "reserve" and seat == turn and int(arg.get("serial",-1)) == serial:
		var hand: Array = players[seat].hand
		if kind == "reserve":
			var i := int(arg.get("index",-1))
			if i < 0 or i >= hand.size() or reserve_count >= reserve_limit:
				return false
			var saved: Array = players[seat].get("reserved",[])
			saved.append(hand.pop_at(i))
			players[seat]["reserved"] = saved
			reserve_count += 1
		elif kind == "keep":
			turn = posmod(turn+1,players.size())
			reserve_count = 0
			if turn == starter:
				_return_hands()
				_open()
		else:
			return false
		serial += 1
		return true
	if phase == "reflex" and seat == turn and int(arg.get("serial",-1)) == serial:
		if kind == "keep":
			_advance_reflex()
			return true
		var hand: Array = players[seat].hand
		var i := int(arg.get("index",-1))
		if kind != "reflex" or i < 0 or i >= hand.size() or hand[i].kind == "bullet":
			return false
		pending = hand.pop_at(i)
		pending["extra"] = true
		serial += 1
		phase = "reveal"
		return true
	if phase == "discard" and seat == turn and int(arg.get("serial",-1)) == serial:
		if kind == "discard":
			var hand: Array = players[seat].hand
			var i := int(arg.get("index",-1))
			if i < 0 or i >= hand.size():
				return false
			players[seat].discard.append(hand.pop_at(i))
		elif kind == "keep":
			turn = (turn + 1) % players.size()
			if turn == starter:
				_open()
		else:
			return false
		serial += 1
		return true
	if int(arg.get("serial",-1)) != serial:
		return false
	if phase == "reaction" and seat == turn and kind == "choose":
		var i := int(arg.get("index",-1))
		if i < 0 or i >= options.size():
			return false
		_resolve_reaction(options[i])
		return true
	if phase == "reveal" and host and kind == "next":
		copied_kind = last_kind if pending.kind == "idea" and _bandit(pending.id).car != cars else ""
		options = _choices()
		if pending.get("event_action",false) and not options.is_empty():
			options.append({"skip":true,"label":"Пропустить"})
		if options.size() > 1:
			phase = "choose"
		else:
			_execute(options[0] if options.size() == 1 else {})
			if phase == "animate":
				clip["lead"] = FLIP_LEAD
		return true
	if phase == "choose" and kind == "choose" and seat == turn:
		var i := int(arg.get("index",-1))
		if i >= 0 and i < options.size():
			_execute(options[i])
			return true
	return false

func _advance_mount() -> void:
	var riding := bandits.filter(func(b: Dictionary) -> bool: return not b.has("mounted"))
	if riding.is_empty():
		var tail: int = horses.max()
		var candidates := bandits.filter(func(b: Dictionary) -> bool: return b.car == tail)
		starter = 0 if marshal_player else candidates.pick_random().seat
		if teams:
			starter = starter & ~1
		_start_round()
		return
	for bandit in riding:
		if not mount_votes.has(bandit.id):
			turn = bandit.seat
			return
	for bandit in riding:
		if mount_votes[bandit.id]:
			bandit.car = mount_car
			bandit["mounted"] = true
			horses.append(mount_car)
	mount_votes.clear()
	mount_car -= 1
	serial += 1
	_advance_mount()

func _drink(seat: int,index: int) -> bool:
	if steps[step] != "о" or flask_plays > 0 or index < 0 or index >= loot.size():
		return false
	var flask: Dictionary = loot[index]
	if flask.kind not in ["whiskey","old_whiskey"] or flask.owner < 0 or _bandit(flask.owner).seat != seat:
		return false
	var hand: Array = players[seat].hand
	var playable := hand.filter(func(c: Dictionary) -> bool: return c.kind != "bullet").size()
	if flask.kind == "old_whiskey" and playable < 2:
		return false
	if flask.kind == "whiskey":
		var pile: Array = players[seat].deck
		var count := mini(pile.size(),3)
		for i in range(pile.size()-count,pile.size()):
			if pile[i].kind != "bullet":
				playable += 1
		if playable == 0:
			return false
		_draw(seat,3)
	flask_plays = 2 if flask.kind == "old_whiskey" else 1
	flask.uses -= 1
	if flask.uses == 0:
		flask.owner = -1
		flask.car = -1
	serial += 1
	return true

func _power(b: Dictionary,id: int) -> bool:
	return (b.get("id",-1) == id or b.get("prisoner",-1) == id) and b.get("hostage",-1) != 6

func _coach_entry(b: Dictionary) -> void:
	if b.id != 6 and b.car == -2 and not b.roof and not b.has("hostage") and not coach_hostages.is_empty():
		reactions.append({"kind":"hostage","id":b.id})

func _guard_check(before: Dictionary) -> void:
	if not guard_on_train:
		return
	for b in bandits:
		if not b.roof or b.car < 0 or b.id == 6:
			continue
		var origin: int = b.car
		for old: Dictionary in before.bandits:
			if old.id == b.id and old.roof:
				origin = old.car
		if b.car == coach_car:
			_wound(b)
			reactions.append({"kind":"retreat","id":b.id})
		elif origin >= 0 and mini(origin,b.car) < coach_car and maxi(origin,b.car) > coach_car:
			_wound(b)

func _choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var b := _bandit(pending.id)
	if _blocked(b):
		return out
	match _actual_kind():
		"level":
			if _power(b,7) and b.car >= 0:
				for car in range(maxi(0,b.car-1),mini(cars,b.car+1)+1):
					out.append({"car":car,"label":_car_label(car)})
		"capture":
			for target in _targets(b,false):
				out.append({"target":target.id,"label":"Арестовать · "+NAMES[target.id]})
		"idea":
			if b.get("cell",false):
				out.assign([{"escape":false,"label":"Выйти в коридор"},{"escape":true,"label":"Выйти на крышу"}])
			elif b.car == cars and not b.has("prisoner"):
				for prisoner in prisoners:
					out.append({"prisoner":prisoner,"label":"Освободить · "+_name(prisoner)})
			if b.car == cars and not b.get("cell",false):
				for captive in bandits:
					if captive.get("cell",false):
						out.append({"free":captive.id,"label":"Освободить · "+_name(captive.id)})
		"move", "marshal":
			var police: bool = pending.kind == "marshal"
			var source: int = marshal_car if police else b.car
			var reach := 3 if not police and b.roof and b.get("hostage",-1) != 5 else 1
			if source == -2:
				if b.roof:
					out.append({"car":coach_car,"label":_car_label(coach_car)})
				return out
			if not police and coach_enabled and b.roof and absi(coach_car-source) < reach:
				out.append({"car":-2,"label":"Крыша дилижанса"})
			for car in range(maxi(-1 if time_car and not police else 0,source-reach),mini(cars,source+reach)+1):
				if car != source and (car != -1 or source == 0):
					out.append({"car":car,"label":_car_label(car)})
		"ride":
			var horse_car: int = coach_car if b.car == -2 else b.car
			if b.get("hostage",-1) != 4 and horses.has(horse_car):
				if _round_event() == "escape":
					out.append({"escape_train":true,"label":"Покинуть поезд"})
				if coach_enabled and absi(coach_car-horse_car) <= 3:
					out.append({"car":-2,"label":"Внутрь дилижанса"})
				for car in range(maxi(-1 if time_car else 0,horse_car-3),mini(cars,horse_car+3)+1):
					out.append({"car":car,"label":_car_label(car)})
		"loot":
			for i in loot.size():
				var l: Dictionary = loot[i]
				if l.owner == -1 and l.car == b.car and l.roof == b.roof and (b.id != 6 or l.kind == "mailbag") and (l.car != -2 or not l.roof or guard_on_train):
					out.append({"loot":i,"label":_loot_name(l.kind)})
		"shoot":
			if b.id == 6:
				return _marshal_shots(b)
			if b.ammo == 0:
				return out
			for victim in _targets(b,true):
				out.append({"target":victim.id,"label":_name(victim.id)})
				if _round_event() == "fall" and _power(b,3) and victim.roof and ((victim.car == 0 and b.car > 0) or (victim.car == cars and b.car < cars)):
					out.append({"target":victim.id,"fall":true,"label":"Сбросить выстрелом · "+_name(victim.id)})
		"punch":
			if b.get("hostage",-1) == 3:
				return out
			if b.car == -2 and b.roof and not guard_on_train:
				out.append({"guard":true,"label":"Ударить охранника"})
			for victim in _targets(b,false):
				var carried: Array[int] = []
				for i in loot.size():
					if loot[i].owner == victim.id and (victim.id != 6 or loot[i].kind not in ["whiskey","old_whiskey","mailbag"]):
						carried.append(i)
				if carried.is_empty():
					carried.append(-1)
				if _round_event() == "fall" and b.roof:
					for item in carried:
						out.append({"target":victim.id,"fall":true,"loot":item,"label":"Сбросить с поезда · "+_name(victim.id)})
				for direction in ([-1] if b.car == -2 else [-1,1]):
					var car: int = b.car + direction if b.car != -2 else coach_car
					if car < (-1 if time_car else 0) or car > cars:
						continue
					for item in carried:
						var label := "%s → %s" % [_name(victim.id),_car_label(car)]
						if item >= 0:
							label += " · " + _loot_name(loot[item].kind)
						out.append({"target":victim.id,"car":car,"loot":item,"label":label})
	return out

func _car_label(car: int) -> String:
	return "Машина времени" if car == -1 else ("Локомотив" if car == 0 else "Вагон %d" % car)

func _loot_name(kind: String) -> String:
	return {"purse":"Кошелёк","gem":"Драгоценность","case":"Чемодан","mailbag":"Почтовая сумка","whiskey":"Виски","old_whiskey":"Виски"}.get(kind,kind)

func _targets(b: Dictionary, shoot: bool, protect_belle: bool = true) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var left := -1
	var right := cars + 1
	if shoot and b.roof:
		for v in bandits:
			if v.roof and v.car >= 0 and v.id not in escaped and v.car < b.car:
				left = maxi(left,v.car)
			if v.roof and v.car >= 0 and v.id not in escaped and v.car > b.car:
				right = mini(right,v.car)
	if shoot and b.roof and guard_on_train and b.car >= 0:
		if coach_car < b.car and coach_car > left:
			left = -1
		if coach_car > b.car and coach_car < right:
			right = cars+1
	for v in bandits:
		if b.id == v.id or v.id in escaped or v.get("cell",false):
			continue
		if not shoot:
			if b.car == v.car and b.roof == v.roof:
				found.append(v)
		elif coach_enabled and (b.car == -2 or v.car == -2):
			var coach: Dictionary = b if b.car == -2 else v
			var other: Dictionary = v if b.car == -2 else b
			if coach != other and other.car != -2 and ((coach.roof and other.roof) or (not coach.roof and not other.roof and other.car == coach_car)):
				found.append(v)
		elif time_car and (b.car == -1 or v.car == -1):
			var other: Dictionary = v if b.car == -1 else b
			if other.roof or other.car == 0:
				found.append(v)
		elif _power(b,0) and b.car == v.car and b.roof != v.roof:
			found.append(v)
		elif b.roof == v.roof and ((b.roof and v.car in [left,right]) or (not b.roof and absi(v.car-b.car) == 1)):
			found.append(v)
	if protect_belle and found.size() > 1:
		found = found.filter(func(v: Dictionary) -> bool: return not _power(v,5))
	return found

func _marshal_shots(b: Dictionary) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	var targets := _targets(b,true,false)
	for barrel in 2:
		if cylinders[barrel] >= BULLET_EFFECTS.size():
			continue
		for target in targets:
			if targets.size() == 1 or not _power(target,5):
				shots.append({"target":target.id,"barrel":barrel,"label":"%s · %s" % [_name(target.id),BULLET_LABELS[cylinders[barrel]]]})
	if cylinders[0] < 6 and cylinders[1] < 6:
		for a in targets:
			for b_target in targets:
				if a.id == b_target.id or (targets.size() > 2 and (_power(a,5) or _power(b_target,5))):
					continue
				shots.append({"target":a.id,"second_target":b_target.id,"barrel":0,"label":"%s (%s) и %s (%s)" % [_name(a.id),BULLET_LABELS[cylinders[0]],_name(b_target.id),BULLET_LABELS[cylinders[1]]]})
	return shots

func _marshal_bullet(victim: Dictionary, barrel: int) -> void:
	var effect: String = BULLET_EFFECTS[cylinders[barrel]]
	cylinders[barrel] += 1
	_bandit(6).ammo -= 1
	victim["marshal_hits"] = int(victim.get("marshal_hits",0))+1
	_wound(victim,6)
	if effect in ["shoot","level","punch"]:
		var penalties: Array = victim.get("penalties",[])
		penalties.append(effect)
		victim["penalties"] = penalties
	elif effect == "prisoner" and victim.has("prisoner"):
		seized_prisoners += 1
		victim.erase("prisoner")
	elif effect == "mailbag":
		for l in loot:
			if l.owner == victim.id and l.kind == "mailbag":
				seized_mailbags += 1
				l.owner = -1
				l.car = -3
				break

func _blocked(b: Dictionary) -> bool:
	return b.get("id",-1) in escaped or (b.get("cell",false) and pending.kind != "idea") or pending.kind in b.get("penalties",[])

func _wound(b: Dictionary, source: int = -1) -> void:
	if source == -1:
		if neutral <= 0:
			return
		neutral -= 1
	players[b.seat].deck.append({"kind":"bullet","id":source})
	players[b.seat].received += 1
	if b.id == 6 and source >= 0:
		hits_on_marshal[source] = int(hits_on_marshal.get(source,0))+1
	if source >= 0 and _bandit(source).seat != b.seat:
		players[b.seat]["enemy_bullets"] = int(players[b.seat].get("enemy_bullets",0))+1

func _meet_marshal() -> void:
	if marshal_player:
		return
	for b in bandits:
		if b.car == marshal_car and not b.roof:
			b.roof = true
			_wound(b)

func _name(id: int) -> String:
	return "Маршал" if id == 6 else ("Мэй" if id == 7 else NAMES[id])

func _actual_kind() -> String:
	var kind := copied_kind if not copied_kind.is_empty() else str(pending.kind)
	return kind.trim_suffix("_plus")

func _execute(choice: Dictionary) -> void:
	var before := _board()
	var b := _bandit(pending.id)
	var applied := true
	var actual := _actual_kind()
	if _blocked(b) or choice.get("skip",false):
		actual = "blocked"
		applied = false
	match actual:
		"capture":
			if choice.is_empty():
				applied = false
			else:
				var target := _bandit(choice.target)
				target.car = cars
				target.roof = false
				target["cell"] = true
				if not arrested.has(target.id):
					arrested.append(target.id)
		"idea":
			if choice.is_empty():
				applied = false
			else:
				if choice.has("escape"):
					b["cell"] = false
					b.roof = choice.escape
				elif choice.has("free"):
					var captive := _bandit(choice.free)
					captive["cell"] = false
					captive.roof = b.roof
					var payment := loot.filter(func(l: Dictionary) -> bool: return l.owner == captive.id)
					if not payment.is_empty():
						reactions.append({"kind":"payment","id":captive.id,"receiver":b.id})
				else:
					b["prisoner"] = choice.prisoner
					prisoners.erase(choice.prisoner)
		"level":
			if b.car == -1:
				applied = false
			else:
				b.car = int(choice.get("car",b.car))
				b.roof = not b.roof
		"event":
			_event(pending.event)
		"move":
			if choice.is_empty():
				applied = false
			else:
				var from_time: bool = b.car == -1
				b.car = choice.car
				if b.car == -1 or from_time:
					b.roof = false
		"ride":
			if choice.is_empty():
				applied = false
			elif choice.get("escape_train",false):
				escaped.append(b.id)
			else:
				var horse_car: int = coach_car if b.car == -2 else b.car
				horses[horses.find(horse_car)] = coach_car if choice.car == -2 else maxi(0,choice.car)
				b.car = choice.car
				b.roof = false
		"marshal":
			if choice.is_empty():
				applied = false
			else:
				marshal_car = choice.car
		"loot":
			if choice.is_empty():
				applied = false
			else:
				loot[choice.loot].owner = b.id
				if b.get("prisoner",-1) == b.id:
					for l in loot:
						if l.owner == -1 and l.car == b.car and l.roof == b.roof and (l.car != -2 or not l.roof or guard_on_train):
							l.owner = b.id
							break
		"shoot":
			if choice.is_empty():
				applied = false
			else:
				var victim := _bandit(choice.target)
				if b.id == 6:
					_marshal_bullet(victim,choice.barrel)
					if choice.has("second_target"):
						_marshal_bullet(_bandit(choice.second_target),1)
				else:
					b.ammo -= 1
					_wound(victim,b.id)
					if teams and (int(b.seat) >> 1) != (int(victim.seat) >> 1):
						team_hits[int(b.seat) >> 1] += 1
				if choice.get("fall",false):
					escaped.append(victim.id)
					victim["fallen"] = true
				elif _power(b,3) and b.car >= 0 and victim.car >= 0:
					victim.car = clampi(victim.car + signi(victim.car - b.car),-1 if time_car else 0,cars)
					if victim.car == -1:
						victim.roof = false
		"punch":
			if choice.is_empty():
				applied = false
			elif choice.get("guard",false):
				guard_on_train = true
			else:
				var victim := _bandit(choice.target)
				if victim.id == 6 and not brawls.is_empty():
					players[b.seat].ransom += int(brawls.pop_front())
				if choice.loot >= 0:
					var item: Dictionary = loot[choice.loot]
					item.owner = b.id if _power(b,2) and item.kind == "purse" else -1
					item.car = b.car
					item.roof = b.roof
					item["in_time"] = b.car == -1
				if choice.get("fall",false):
					escaped.append(victim.id)
					victim["fallen"] = true
				else:
					victim.car = choice.car
				if victim.car == -1:
					victim.roof = false
	if coach_enabled:
		if pending.kind == "event":
			coach_car = mini(cars,coach_car+1)
		for actor in bandits:
			_coach_entry(actor)
		_guard_check(before)
	_meet_marshal()
	if not b.is_empty() and not pending.get("event_action",false):
		var pile: Array = players[b.seat].discard if duel else players[b.seat].deck
		pile.append({"kind":pending.kind,"id":pending.id})
	if pending.kind not in ["idea","event"] and pending.id != 6:
		last_kind = pending.kind
	var played := pending.duplicate()
	played["kind"] = pending.kind if actual == "blocked" else actual
	var duration := 1.05 if applied else 0.55
	clip = {"serial":serial,"card":played,"from":before,"to":_board(),"target":choice.get("target",-1),"second_target":choice.get("second_target",-1),"applied":applied,"duration":duration}
	staged_clip = clip
	_next_reaction()

func _next_reaction() -> void:
	if reactions.is_empty():
		clip = staged_clip
		clip["to"] = _board()
		history.append(clip)
		elapsed = 0.0
		phase = "animate"
		return
	var reaction: Dictionary = reactions[0]
	var b := _bandit(reaction.id)
	options.clear()
	if reaction.kind == "hostage":
		for id in coach_hostages:
			options.append({"id":id,"label":HOSTAGES[id]})
	elif reaction.kind == "payment":
		for i in loot.size():
			if loot[i].owner == b.id:
				options.append({"loot":i,"label":"Отдать "+_loot_name(loot[i].kind)})
	else:
		for car in [coach_car-1,coach_car+1]:
			if car >= 0 and car <= cars:
				options.append({"car":car,"label":_car_label(car)})
	if options.size() <= 1:
		_resolve_reaction(options[0] if not options.is_empty() else {})
	else:
		turn = b.seat
		serial += 1
		phase = "reaction"

func _resolve_reaction(choice: Dictionary) -> void:
	var reaction: Dictionary = reactions.pop_front()
	var b := _bandit(reaction.id)
	if not choice.is_empty():
		if reaction.kind == "hostage":
			b["hostage"] = choice.id
			coach_hostages.erase(choice.id)
		elif reaction.kind == "payment":
			loot[choice.loot].owner = reaction.receiver
		else:
			b.car = choice.car
	_next_reaction()

func _event(event: String) -> void:
	var marshal := _bandit(6)
	var law_car: int = marshal.get("car",marshal_car)
	match event:
		"tired":
			horses.sort()
			for i in mini(horses.size(),2 if players.size() >= 5 else 1):
				horses.pop_back()
		"speed":
			for b in bandits:
				if b.roof and b.car >= 0:
					b.car = mini(cars,b.car+1)
			for i in horses.size():
				horses[i] = mini(cars,horses[i]+1)
			coach_car = mini(cars,coach_car+1)
		"rage":
			for b in bandits:
				if b.id != 6 and b.car in [-2,coach_car]:
					_wound(b)
		"whiskey":
			for l in loot:
				if l.owner != -1 or l.car != law_car or l.kind not in ["whiskey","old_whiskey"] or l.roof != marshal.get("roof",false):
					continue
				if marshal_player:
					l.owner = 6
				else:
					l.car = -3
					var last := cars if l.kind == "old_whiskey" else mini(cars,marshal_car+1)
					while marshal_car < last:
						marshal_car += 1
						_meet_marshal()
				break
		"mortal":
			for s in players.size():
				players[s].ransom -= 150 * (players[s].received-round_received[s])
		"safekeeping":
			for l in loot:
				if l.owner == -1 and l.car == law_car:
					l.roof = true
		"rumors":
			var remaining := marshal_goals.slice(0,turn_no).filter(func(goal: Variant) -> bool: return goal not in revealed_goals)
			if not remaining.is_empty():
				revealed_goals.append(remaining.pick_random())
		"tail", "brake", "angry", "passengers", "revenge", "ransom", "pockets":
			for b in bandits:
				match event:
					"tail":
						if b.roof and b.car >= 0:
							b.car = cars
					"brake":
						if b.roof and b.car >= 0:
							b.car = maxi(-1 if time_car else 0,b.car-1)
							if b.car == -1:
								b.roof = false
					"angry":
						if not marshal_player and b.roof and b.car == marshal_car:
							_wound(b)
					"passengers":
						if not b.roof and b.id != 6 and b.car >= 0:
							_wound(b)
					"revenge":
						if (b.roof or marshal_player) and b.id != 6 and b.car == law_car:
							_lose_purse(b)
					"ransom":
						if b.car == 0 and b.id != 6:
							players[b.seat].ransom += 250
					"pockets":
						if b.id != 6:
							_pick_pocket(b)
			if event == "angry" and not marshal_player:
				marshal_car = mini(cars,marshal_car+1)
		"case":
			_add_loot("case",1000,marshal_car)

func _lose_purse(b: Dictionary) -> void:
	var cheapest: Dictionary = {}
	for l in loot:
		if l.owner == b.id and l.kind == "purse" and (cheapest.is_empty() or l.value < cheapest.value):
			cheapest = l
	if not cheapest.is_empty():
		cheapest.owner = -1
		cheapest.car = -1

func _pick_pocket(b: Dictionary) -> void:
	for v in bandits:
		if v.id != b.id and v.car == b.car and v.roof == b.roof:
			return
	for l in loot:
		if l.owner == -1 and l.kind == "purse" and l.car == b.car and l.roof == b.roof:
			l.owner = b.id
			return

## Пропуск: текущее действие заканчивается сразу; повтор раунда — к последнему клипу; повтор партии — к итогам.
func _skip_animation() -> void:
	if phase == "match_replay":
		_finish()
		return
	if phase == "replay" and not history.is_empty():
		replay_index = history.size() - 1
		clip = history[replay_index]
	elapsed = float(clip.get("duration", 0.0)) + float(clip.get("lead", 0.0))


## Фазы, в которых идут часы хода (настройка комнаты «Время на ход»).
const TIMED := ["select", "travel", "mount", "plan", "discard", "reserve", "reflex", "choose", "reaction"]


## Время хода вышло — хост ходит за игрока самым безопасным вариантом (владелец, 15.11):
## бандит — первый свободный, планирование — взять 3 карты (или сыграть первую подходящую),
## сохранение руки и рефлекс — «Готово», выбор — первый вариант, верхом — войти в вагон.
func timeout() -> bool:
	if phase not in TIMED:
		return false
	var token := {"serial": serial}
	match phase:
		"select":
			for id in range(NAMES.size()):
				if _bandit(id) == {}:
					return _select(turn, id)
			return prison and _select(turn, 7)
		"travel":
			token["car"] = 1
			return action(turn, "travel", token, false)
		"mount":
			var acted := false
			for b in bandits.duplicate():
				if not b.has("mounted") and not mount_votes.has(b.id) and phase == "mount":
					acted = action(b.seat, "mount", {"serial": serial, "land": true}, false) or acted
			return acted
		"plan":
			if flask_plays == 0 and action(turn, "draw", token, false):
				return true
			var hand: Array = players[turn].hand
			for i in hand.size():
				if hand[i].kind != "bullet" and not (steps[step] == "к" and hand[i].kind in ["shoot", "punch"]):
					return action(turn, "play", {"serial": serial, "index": i, "hidden": false}, false)
			return action(turn, "draw", token, false)
		"discard", "reserve", "reflex":
			return action(turn, "keep", token, false)
		"choose", "reaction":
			token["index"] = 0
			return action(turn, "choose", token, false)
	return false


func tick(delta: float) -> bool:
	if phase not in ["animate", "replay", "match_replay"]:
		return false
	elapsed += delta * speed
	if elapsed < float(clip.duration) + (float(clip.get("lead", 0.0)) if phase == "animate" else 0.0):
		return false
	elapsed = 0.0
	if phase == "match_replay":
		replay_index += 1
		if replay_index == match_history[replay_round].size():
			replay_round += 1
			replay_index = 0
		if replay_round == match_history.size():
			_finish()
		else:
			clip = match_history[replay_round][replay_index]
		return true
	if phase == "animate":
		if pending.get("event_action",false):
			angry_step += 1
			_open()
		elif pending.get("extra",false):
			_advance_reflex()
		elif cursor < queue.size():
			cursor += 1
			_open()
		else:
			match_history.append(history.duplicate())
			replay_index = 0
			phase = "replay"
			clip = history[0]
	else:
		replay_index += 1
		if replay_index < history.size():
			clip = history[replay_index]
		elif turn_no == 5:
			phase = "match_replay"
			replay_round = 0
			replay_index = 0
			turn = -1
			clip = match_history[0][0]
		else:
			var visitors := bandits.filter(func(b: Dictionary) -> bool: return b.car == -1)
			if time_car and visitors.size() == 1:
				travel_bandit = visitors[0].id
				phase = "travel"
				turn = visitors[0].seat
				clip = {}
				serial += 1
			else:
				_next_round()
	return true

func _next_round() -> void:
	starter = (starter + (2 if teams else 1)) % players.size()
	_start_round()

func _finish() -> void:
	phase = "end"
	clip = {}
	var least := 6
	for b in bandits:
		if b.id != 6:
			least = mini(least,b.ammo)
	for s in players.size():
		var score: int = players[s].ransom
		var shooter := false  # бонус лучшего стрелка — для разбивки итога на столе
		for b in bandits:
			if b.seat != s:
				continue
			if time_car and b.car == -1:
				score += 500
				for l in loot:
					if l.car == -1 and l.owner == -1 and l.get("in_time",false):
						score += l.value
			if b.id == 6:
				continue
			if marshal_player and not arrested.has(b.id):
				score += 500
			score += _ransom(b)
			if b.has("prisoner"):
				score += 200
			if not duel and not teams and b.ammo == least:
				score += 1000
				shooter = true
			for l in loot:
				if l.owner == b.id and not (_round_event() == "sharing" and l.kind == "case"):
					score += l.value
			if _round_event() == "sharing":
				var colocated := bandits.filter(func(other: Dictionary) -> bool: return other.id != 6 and other.car == b.car and other.roof == b.roof and other.get("cell",false) == b.get("cell",false))
				for l in loot:
					if l.kind == "case" and colocated.any(func(other: Dictionary) -> bool: return other.id == l.owner):
						score += floori(float(l.value)/colocated.size())
		var eligible := bandits.any(func(b: Dictionary) -> bool:
			return b.seat == s and not b.get("fallen",false) and (_round_event() != "crime" or not b.get("cell",false)) and (_round_event() != "escape" or b.id == 6 or b.id in escaped or b.car == -2))
		results.append({"seat":s,"score":score,"received":players[s].received,"eligible":eligible,"shooter":shooter})
	if teams:
		for s in range(0,players.size(),2):
			var total: int = results[s].score + results[s+1].score
			if team_hits[s >> 1] == team_hits.max():
				total += 1000
			for member in [s,s+1]:
				results[member]["team"] = (s >> 1) + 1
				results[member]["score"] = total
	if marshal_player:
		var won := _marshal_goal_count()
		results[0]["marshal_goals"] = won
		results[0]["score"] = -1
		results[0]["marshal_won"] = won >= 4 and not _bandit(6).get("fallen",false)
		results[0]["eligible"] = results[0].marshal_won
		if results[0].marshal_won and _round_event() == "guilty":
			var lowest := INF
			var poorest: Array[Dictionary] = []
			for result in results.slice(1):
				if result.score < lowest:
					lowest = result.score
					poorest.assign([result])
				elif result.score == lowest:
					poorest.append(result)
			if poorest.size() == 1:
				poorest[0]["co_winner"] = true
	results.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if a.get("marshal_won",false) != b.get("marshal_won",false):
			return a.get("marshal_won",false)
		if a.eligible != b.eligible:
			return a.eligible
		return a.score > b.score or (a.score == b.score and a.received < b.received))

func _marshal_goal_count() -> int:
	var total := 0
	for goal: Variant in marshal_goals:
		if goal is int:
			if goal in arrested:
				total += 1
			continue
		if goal == "brawler" and not brawls.is_empty():
			total += 1
		elif goal == "cylinder" and 6 in cylinders:
			total += 1
		elif goal == "keys" and prisoners.size() + seized_prisoners >= 2:
			total += 1
		elif goal == "mail" and (seized_mailbags > 0 or loot.any(func(l: Dictionary) -> bool: return l.kind == "mailbag" and l.owner in [-1,6] and l.car != -3)):
			total += 1
		elif goal == "dodge" and not hits_on_marshal.values().any(func(count: int) -> bool: return count > 2):
			total += 1
		elif goal == "all_hit" and bandits.all(func(b: Dictionary) -> bool: return b.id == 6 or b.get("marshal_hits",0) > 0):
			total += 1
		elif goal == "four_hits" and bandits.any(func(b: Dictionary) -> bool: return b.get("marshal_hits",0) >= 4):
			total += 1
	return total

func _ransom(b: Dictionary) -> int:
	var items := loot.filter(func(l: Dictionary) -> bool: return l.owner == b.id)
	match int(b.get("hostage",-1)):
		0: return 1000
		1: return 1000 if items.any(func(l: Dictionary) -> bool: return l.kind == "case") else 0
		2: return 900
		3: return 800
		4: return 700
		5: return 500 * items.filter(func(l: Dictionary) -> bool: return l.kind == "gem").size()
		6: return 250 * items.filter(func(l: Dictionary) -> bool: return l.kind == "purse").size()
		7: return 200 * int(players[b.seat].get("enemy_bullets",0))
	return 0

func get_view(seat: int) -> Dictionary:
	var hand: Array = []
	var bag: Array = []
	var flasks: Array = []
	if seat >= 0 and seat < players.size():
		hand = players[seat].hand.duplicate(true)
		for i in loot.size():
			var l: Dictionary = loot[i]
			if l.owner >= 0 and _bandit(l.owner).seat == seat:
				bag.append({"kind":l.kind,"value":l.value})
				if phase == "plan" and steps[step] == "о" and l.has("uses") and flask_plays == 0:
					flasks.append({"index":i,"old":l.kind == "old_whiskey","uses":l.uses})
	var visible: Array[Dictionary] = []
	for i in queue.size():
		var c := queue[i]
		visible.append({"kind":"hidden","id":-1} if c.hidden and (phase in ["plan", "discard", "reserve"] or i > cursor) else {"kind":c.kind,"id":c.id})
	return {"seat_names":players.map(func(player: Dictionary) -> String: return str(player.get("name","Игрок"))),"phase":phase,"round":turn_no,"replay_round":replay_round + 1 if phase == "match_replay" else turn_no,"round_card":rounds[replay_round] if phase == "match_replay" else (rounds[turn_no-1] if turn_no > 0 else -1),
		"steps":steps,"reserve_left":reserve_limit-reserve_count,"mount_car":mount_car,"can_mount":phase == "mount" and bandits.any(func(b: Dictionary) -> bool: return b.seat == seat and not b.has("mounted") and not mount_votes.has(b.id)),"step":step,"turn":turn,"seat":seat,"serial":serial,"cars":cars,"board":_board(seat),
		"hand":hand,"bag":bag,"flasks":flasks,"flask_plays":flask_plays,"can_draw_idea":prison and seat >= 0 and phase == "plan" and players[seat].deck.any(func(c: Dictionary) -> bool: return c.kind == "idea"),"queue":visible,"cursor":cursor,"sprites":sprites,"duel":duel,"teams":teams,"marshal_goals":marshal_goals.slice(0,turn_no) if marshal_player and seat == 0 else revealed_goals.duplicate(),
		"card":pending.duplicate() if phase in ["reveal","choose","reaction"] else clip.get("card",{}),
		"options":options.duplicate(true) if phase in ["choose","reaction"] and seat == turn else [],
		"clip":clip.duplicate(true) if phase in ["animate", "replay", "match_replay"] else {},
		"progress":elapsed,"results":results.duplicate(true),"speed":speed}
