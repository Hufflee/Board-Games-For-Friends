class_name TGRules
extends RefCounted
## Базовая The Gang: четыре одновременных ранжирования, вскрытие и гонка до трёх сейфов/тревог.
## Только хост хранит hands/deck и вызывает action/timeout; get_view не раскрывает чужие карты до вскрытия.

const Poker := preload("res://games/the_gang/logic/tg_poker.gd")
const MIN_PLAYERS: int = 3
const MAX_PLAYERS: int = 10
const PUBLIC_PLAYER_FIELDS: Array[String] = [
	"name", "peer", "steam_id", "bot", "connected", "avatar", "avatar_url", "color"
]

var players: Array = []
var phase: String = "setup"
var heist_no: int = 0
var round_no: int = 1
var turn_no: int = 0
var vaults: int = 0
var alarms: int = 0
var revision: int = 0
var won: bool = false
var community: Array[int] = []
var history: Array = []
var chips: Array[int] = []
var result: Dictionary = {}
var log: Array[String] = []
var hands: Array = []
var deck: Array[int] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Неверная раздача очищает прежнюю партию и безопасно оставляет setup.
## Счётчики revision/turn_no не откатываются даже при повторном new_game того же экземпляра.
func new_game(members: Array, seed_value: int = 0) -> void:
	var incoming: Array = members.duplicate(true)
	players.clear()
	hands.clear()
	deck.clear()
	community.clear()
	history.clear()
	chips.clear()
	result = {}
	log.clear()
	phase = "setup"
	heist_no = 0
	round_no = 1
	vaults = 0
	alarms = 0
	won = false
	revision += 1
	var valid: bool = incoming.size() >= MIN_PLAYERS and incoming.size() <= MAX_PLAYERS
	for member: Variant in incoming:
		valid = valid and member is Dictionary
	if not valid:
		turn_no += 1
		log.append("Для игры нужны от 3 до 10 участников с данными игроков.")
		return
	for member: Dictionary in incoming:
		var metadata: Dictionary = {}
		for field: String in PUBLIC_PLAYER_FIELDS:
			if member.has(field):
				metadata[field] = member[field]
		metadata = metadata.duplicate(true)
		if not metadata.has("name"):
			metadata["name"] = "Игрок %d" % (players.size() + 1)
		players.append(metadata)
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	log.append("Новая партия · игроков: %d" % players.size())
	_start_heist()

## seat — проверенный сетью отправитель; назначать фишку через аргумент другому месту нельзя.
func action(seat: int, kind: String, arg: Dictionary = {}) -> bool:
	if seat < 0 or seat >= players.size():
		return false
	if arg.has("revision") and (not arg.revision is int or int(arg.revision) != revision):
		return false
	for field: Variant in arg:
		if field != "revision" and not (kind == "take" and field == "value"):
			return false
	if kind == "next":
		if phase != "showdown":
			return false
		revision += 1
		_start_heist()
		return true
	if phase != "rank":
		return false
	match kind:
		"take":
			if not arg.get("value") is int:
				return false
			var value: int = int(arg.value)
			if value < 1 or value > players.size() or chips[seat] == value:
				return false
			for holder: int in chips.size():
				if chips[holder] == value:
					chips[holder] = 0
			chips[seat] = value
			log.append("%s берёт фишку %d." % [str(players[seat].name), value])
		"return":
			if chips[seat] == 0:
				return false
			chips[seat] = 0
			log.append("%s возвращает фишку в центр." % str(players[seat].name))
		_:
			return false
	revision += 1
	_finish_assignment()
	return true

## Только отсутствующие фишки: назначенные значения не отбираются и не переоцениваются по картам.
func timeout() -> bool:
	if phase != "rank" or not chips.has(0):
		return false
	var free: Array[int] = []
	for value: int in range(1, players.size() + 1):
		if not chips.has(value):
			free.append(value)
	_shuffle(free)
	for seat: int in chips.size():
		if chips[seat] == 0:
			chips[seat] = free.pop_back()
	log.append("Время истекло: свободные фишки распределены случайно.")
	revision += 1
	_finish_assignment()
	return true

## show_all намеренно игнорируется: даже офлайн/отладочный view не открывает руки в rank.
func get_view(seat: int, _show_all: bool = false) -> Dictionary:
	var own: Array = hands[seat].duplicate() if seat >= 0 and seat < hands.size() else []
	return {
		"players": players.duplicate(true), "phase": phase, "heist_no": heist_no,
		"round_no": round_no, "turn_no": turn_no, "vaults": vaults, "alarms": alarms,
		"won": won, "community": community.duplicate(), "hand": own,
		"history": history.duplicate(true), "chips": chips.duplicate(),
		"result": result.duplicate(true), "log": log.duplicate(), "revision": revision, "seat": seat
	}

func _start_heist() -> void:
	heist_no += 1
	round_no = 1
	phase = "rank"
	turn_no += 1
	community.clear()
	result = {}
	hands = []
	history = []
	chips = []
	chips.resize(players.size())
	chips.fill(0)
	for round_index: int in 4:
		history.append(chips.duplicate())
	deck.clear()
	for card: int in 52:
		deck.append(card)
	_shuffle(deck)
	for seat: int in players.size():
		hands.append([])
	for deal: int in 2:
		for seat: int in players.size():
			hands[seat].append(deck.pop_back())
	log.append("Ограбление %d · раунд 1: две закрытые карты." % heist_no)

func _shuffle(values: Array[int]) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var other: int = _rng.randi_range(0, index)
		var value: int = values[index]
		values[index] = values[other]
		values[other] = value

func _finish_assignment() -> void:
	history[round_no - 1] = chips.duplicate()
	if chips.has(0):
		return
	turn_no += 1
	if round_no == 4:
		_showdown()
		return
	round_no += 1
	var count: int = 3 if round_no == 2 else 1
	for index: int in count:
		community.append(deck.pop_back())
	chips.fill(0)
	log.append("Раунд %d · общих карт: %d." % [round_no, community.size()])

func _showdown() -> void:
	var order: Array[int] = []
	var ranks: Array = []
	order.resize(players.size())
	for seat: int in players.size():
		order[chips[seat] - 1] = seat
		var available: Array = hands[seat].duplicate()
		available.append_array(community)
		ranks.append(Poker.evaluate(available))
	var success: bool = true
	for index: int in range(1, order.size()):
		if Poker.compare(ranks[order[index - 1]], ranks[order[index]]) > 0:
			success = false
	result = {"order": order, "ranks": ranks, "hands": hands.duplicate(true), "success": success}
	if success:
		vaults += 1
		log.append("Ограбление успешно · вскрыто сейфов: %d." % vaults)
	else:
		alarms += 1
		log.append("Ошибка в порядке фишек · тревог: %d." % alarms)
	phase = "showdown"
	if vaults >= 3 or alarms >= 3:
		phase = "game_over"
		won = vaults >= 3
		log.append("Банда победила!" if won else "Три тревоги. Ограбления закончены.")
