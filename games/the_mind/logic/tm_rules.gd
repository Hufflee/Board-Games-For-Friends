class_name TMRules
extends RefCounted
## Чистые правила Unspoken. Проверка: --headless --script res://tests/test_the_mind.gd.

var players: Array = []
var hands: Array = []
var phase := "focus"
var level := 1
var target := 12
var lives := 2
var panic := 1
var revision := 0
var turn_no := 0
var won := false
var blind := false
var ready: Array = []
var votes: Array = []
var pile: Array = []
var discarded: Array = []
var log: Array = []
var message := "Сосредоточьтесь и подтвердите готовность."
var rng := RandomNumberGenerator.new()
var pending_cutoff := 0
var events: Array = []
var discard_info: Array = []
var event_no := 0
var last_play: Dictionary = {}
var refocus_left := 0.0
const REFOCUS_DELAY := 15.0

func new_game(seats: Array, seed_value: int = -1) -> String:
	if seats.size() < 2 or seats.size() > 8:
		return "Нужно от 2 до 8 игроков."
	players = seats.duplicate(true)
	for p: Dictionary in players:
		p["bot"] = false
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	target = {2: 12, 3: 10, 4: 8, 5: 8, 6: 6, 7: 6, 8: 6}[players.size()]
	lives = mini(players.size(), 5)
	panic = 1
	level = 1
	revision = 0
	turn_no = 0
	won = false
	blind = false
	log.clear()
	event_no = 0
	refocus_left = 0.0
	_deal()
	return ""

func _deal() -> void:
	var deck: Array = range(1, 101)
	for i in range(99, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	hands.clear()
	for s in players.size():
		var hand: Array = []
		for k in level:
			hand.append(deck.pop_back())
		hand.sort()
		hands.append(hand)
	pile.clear()
	discarded.clear()
	discard_info.clear()
	events.clear()
	last_play.clear()
	pending_cutoff = 0
	_focus("Уровень %d. Сосредоточьтесь." % level)

func _focus(text: String) -> void:
	phase = "focus"
	ready = []
	ready.resize(players.size())
	ready.fill(false)
	for seat in hands.size():
		ready[seat] = hands[seat].is_empty()
	votes.clear()
	message = text
	_note(text)

func _note(text: String) -> void:
	log.append(text)
	if log.size() > 120:
		log.pop_front()

func action(seat: int, kind: String, data: Variant = {}) -> bool:
	if seat < 0 or seat >= players.size() or not data is Dictionary:
		return false
	if not data.get("revision") is int or data.revision != revision:
		return false
	var accepted := false
	match kind:
		"ready":
			if phase == "focus" and not ready[seat]:
				ready[seat] = true
				for i in hands.size():
					if hands[i].is_empty():
						ready[i] = true
				if not ready.has(false):
					phase = "play"
					message = "Почувствуйте момент. Разыгрывайте карты по возрастанию."
				accepted = true
		"refocus":
			if phase == "play" and pending_cutoff == 0 and refocus_left <= 0.0:
				refocus_left = REFOCUS_DELAY
				_focus("Стоп. Снова настройтесь друг на друга.")
				accepted = true
		"stop":
			if can_stop(seat):
				_resolve_stop(seat)
				accepted = true
		"play":
			if phase == "play" and pending_cutoff == 0 and data.get("card") is int and not hands[seat].is_empty():
				var value: int = data.card
				if value == int(hands[seat][0]):
					_play(seat, value)
					accepted = true
		"panic":
			if phase == "play" and pending_cutoff == 0 and panic > 0:
				phase = "vote"
				votes = []
				votes.resize(players.size())
				votes.fill(false)
				votes[seat] = true
				message = "Паника? Нужно согласие всей команды."
				accepted = true
		"yes", "no":
			if phase == "vote":
				if kind == "no":
					phase = "play"
					votes.clear()
					message = "Панику отменили. Продолжаем."
					accepted = true
				elif not votes[seat]:
					votes[seat] = true
					if not votes.has(false):
						_use_panic()
					accepted = true
		"next":
			if phase == "level_done":
				level += 1
				_deal()
				accepted = true
		"blind":
			if phase == "game_over" and won and not blind:
				blind = true
				won = false
				level = 1
				_deal()
				accepted = true
	if accepted:
		revision += 1
		turn_no += 1
	return accepted

func _play(seat: int, value: int) -> void:
	hands[seat].pop_front()
	pile.append(value)
	last_play = _event("play", seat, value)
	if blind:
		_note("%s выложил карту рубашкой вверх." % players[seat].get("name", "Игрок"))
	else:
		_note("%s: %d" % [players[seat].get("name", "Игрок"), value])
		for hand: Array in hands:
			if not hand.is_empty() and int(hand[0]) < value:
				pending_cutoff = value
				return  # Штраф и раскрытие — только после СТОП владельца меньшей карты.
	_check_level()

func _event(kind: String, seat: int, value: int) -> Dictionary:
	event_no += 1
	var entry := {"id": event_no, "kind": kind, "seat": seat, "card": value}
	events.append(entry)
	if events.size() > 100:
		events.pop_front()
	return entry.duplicate()

func can_stop(seat: int) -> bool:
	return not blind and phase == "play" and pending_cutoff > 0 and seat >= 0 and seat < hands.size() \
		and not hands[seat].is_empty() and int(hands[seat][0]) < pending_cutoff

func _discard(seat: int) -> int:
	var value: int = hands[seat].pop_front()
	discarded.append(value)
	discard_info.append(_event("discard", seat, value))
	_note("%s сбрасывает %d." % [players[seat].get("name", "Игрок"), value])
	return value

func _resolve_stop(seat: int) -> void:
	var cutoff := pending_cutoff
	pending_cutoff = 0
	_note("%s: СТОП!" % players[seat].get("name", "Игрок"))
	for s in hands.size():
		while not hands[s].is_empty() and int(hands[s][0]) < cutoff:
			_discard(s)
	lives -= 1
	if lives <= 0:
		_finish(false)
		return
	_focus("СТОП: сброшены меньшие карты. Потеряна одна жизнь.")
	_check_level()

func _use_panic() -> void:
	panic -= 1
	var removed: Array = []
	for s in hands.size():
		if not hands[s].is_empty():
			removed.append(_discard(s))
	_focus("Паника: сброшены %s." % str(removed))
	_check_level()

func _check_level() -> void:
	for hand: Array in hands:
		if not hand.is_empty():
			return
	if blind:
		var high := 0
		var errors := 0
		for value: int in pile:
			if value < high:
				errors += 1
			high = maxi(high, value)
		lives = maxi(0, lives - errors)
		_note("Вскрытие: %s. Ошибок: %d." % [str(pile), errors])
		if lives == 0:
			_finish(false)
			return
	if level in [2, 5, 8]:
		panic = mini(3, panic + 1)
		_note("Награда: одна Паника (не больше трёх).")
	if level in [3, 6, 9]:
		lives = mini(5, lives + 1)
		_note("Награда: одна жизнь (не больше пяти).")
	if level == target:
		_finish(true)
	else:
		phase = "level_done"
		message = "Уровень %d пройден!" % level
		_note(message)

func _finish(success: bool) -> void:
	won = success
	phase = "game_over"
	message = "Вы на одной волне!" if success else "Жизни закончились. Попробуем ещё раз!"
	_note(message)

## Отсчёт только на хосте; сеть обновляется при окончании блокировки.
func tick(delta: float) -> bool:
	var before := refocus_left
	refocus_left = maxf(0.0, refocus_left - maxf(0.0, delta))
	return before > 0.0 and refocus_left == 0.0

func level_reward() -> String:
	if level in [2, 5, 8]:
		return "+1 Паника (до 3)"
	if level in [3, 6, 9]:
		return "+1 жизнь (до 5)"
	return "без бонуса"

func get_view(seat: int) -> Dictionary:
	var public_players: Array = []
	for i in players.size():
		var p: Dictionary = players[i].duplicate(true)
		p["count"] = hands[i].size()
		public_players.append(p)
	var shown_events: Array = events.duplicate(true)
	var shown_last := last_play.duplicate(true)
	if blind and phase in ["play", "focus", "vote"]:
		for entry: Dictionary in shown_events:
			if entry.kind == "play":
				entry.card = 0
		if not shown_last.is_empty():
			shown_last.card = 0
	return {"players": public_players, "seat": seat, "hand": hands[seat].duplicate() if seat >= 0 and seat < hands.size() else [],
		"events": shown_events, "last_play": shown_last, "discard_info": discard_info.duplicate(true),
		"can_stop": can_stop(seat), "can_play": phase == "play" and pending_cutoff == 0,
		"refocus_left": refocus_left, "level_reward": level_reward(),
		"phase": phase, "level": level, "target": target, "lives": lives, "panic": panic, "ready": ready.duplicate(),
		"votes": votes.duplicate(), "pile": [] if blind and phase in ["play", "focus", "vote"] else pile.duplicate(),
		"pile_count": pile.size(), "discarded": discarded.duplicate(), "revision": revision, "turn_no": turn_no,
		"message": message, "log": log.duplicate(), "won": won, "blind": blind, "coop": true, "clock": false}

func can_spectate() -> bool:
	return false
