extends RefCounted
## Мини-игра «Блэкджек» (общая комната, мест сколько угодно): правила без UI. Считает только хост.
## Все игроки против дилера. На старте у каждого 1 фишка. Ставка → раздача по 2 карты (у дилера одна закрыта)
## → каждый сам решает «Ещё» / «Хватит» / «Удвоить» → дилер открывается и добирает до 17 → расчёт.
## Блэкджек (туз + десятка с раздачи) платит 3:2 (не меньше одной фишки), обычная победа — 1:1, ничья — ставка
## возвращается. Кончились фишки — «Начать заново» с одной фишкой. Вошедший посреди раздачи ждёт следующую.
## После расчёта через NEXT_PAUSE секунд новая раздача начинается сама (кнопка «Новая раздача» — не ждать).
## Состояние: {"players": {peer: {...}}, "dealer": [карты], "deck": [карты], "phase", "clock", "last", "seq"}.
## Карта — число 0..51: масть = c / 13, номинал = c % 13 (0 — туз, 9..12 — 10, валет, дама, король).
## Тесты: godot --headless --path . --script res://tests/test_minigames.gd

const DEALER_STEP := 0.8  # пауза между картами дилера — видно, как он добирает
const NEXT_PAUSE := 3.0  # столько секунд виден расчёт, потом новая раздача сама
const SUITS := ["♠", "♥", "♦", "♣"]
const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]


static func new_state() -> Dictionary:
	return {"game": "blackjack", "players": {}, "dealer": [], "deck": [], "phase": "bet", "clock": 0.0, "last": "Делайте ставки", "seq": 0}


static func join(state: Dictionary, peer: int, nick: String, color: int) -> void:
	if state.players.has(peer):
		return
	var waiting: bool = state.phase != "bet"
	state.players[peer] = {"name": nick, "color": color, "chips": 1, "bet": 0, "hand": [],
		"status": "wait" if waiting else "bet", "result": "", "delta": 0}
	_touch(state)


static func leave(state: Dictionary, peer: int) -> void:
	if state.players.erase(peer):
		_touch(state)
		if state.phase == "bet":
			_maybe_deal(state, null)
		elif state.phase == "play":
			_maybe_dealer(state)


static func _touch(state: Dictionary) -> void:
	state.seq = int(state.seq) + 1


## Очки руки: тузы считаются за 11, пока нет перебора.
static func value(hand: Array) -> int:
	var total := 0
	var aces := 0
	for card: int in hand:
		var rank := card % 13
		if rank == 0:
			aces += 1
			total += 11
		else:
			total += mini(rank + 1, 10)
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return total


static func is_blackjack(hand: Array) -> bool:
	return hand.size() == 2 and value(hand) == 21


static func card_text(card: int) -> String:
	return RANKS[card % 13] + SUITS[card / 13]


static func _draw(state: Dictionary, rng: RandomNumberGenerator) -> int:
	if (state.deck as Array).size() < 10:
		var deck: Array = range(52)
		for i in range(deck.size() - 1, 0, -1):
			var j := rng.randi_range(0, i) if rng != null else randi_range(0, i)
			var t: int = deck[i]
			deck[i] = deck[j]
			deck[j] = t
		state.deck = deck
	return int((state.deck as Array).pop_back())


## Действие игрока. Возвращает текст ошибки ("" — принято).
## {"bet": n} — поставить n фишек; {"hit"}, {"stand"}, {"double"} — в раздаче; {"next"} — новая раздача после
## расчёта; {"restart"} — фишки кончились, начать с одной.
static func act(state: Dictionary, peer: int, action: Dictionary, rng: RandomNumberGenerator) -> String:
	if not state.players.has(peer):
		return "Вы не за столом"
	var p: Dictionary = state.players[peer]
	if action.has("restart"):
		if int(p.chips) > 0:
			return "Фишки ещё есть"
		p.chips = 1
		p.result = ""
		p.delta = 0
		p.status = "bet" if state.phase == "bet" else "wait"
		_touch(state)
		return ""
	if action.has("next"):
		if state.phase != "done":
			return "Раздача ещё идёт"
		_new_round(state)
		return ""
	if action.has("bet"):
		if state.phase != "bet" or p.status != "bet":
			return "Сейчас не время ставок"
		var amount := int(action.bet)
		if amount < 1 or amount > int(p.chips):
			return "Ставка — от 1 до %d" % int(p.chips)
		p.bet = amount
		p.status = "ready"
		_touch(state)
		_maybe_deal(state, rng)
		return ""
	if state.phase != "play" or p.status != "play":
		return "Сейчас не ваш ход"
	if action.has("hit"):
		p.hand.append(_draw(state, rng))
		if value(p.hand) > 21:
			p.status = "bust"
		elif value(p.hand) == 21:
			p.status = "stand"
	elif action.has("stand"):
		p.status = "stand"
	elif action.has("double"):
		if (p.hand as Array).size() != 2 or int(p.chips) < int(p.bet) * 2:
			return "Удвоить можно только первым ходом и если хватает фишек"
		p.bet = int(p.bet) * 2
		p.hand.append(_draw(state, rng))
		p.status = "bust" if value(p.hand) > 21 else "stand"
	else:
		return "Неизвестное действие"
	_touch(state)
	_maybe_dealer(state)
	return ""


## Все, у кого есть фишки, поставили — раздаём.
static func _maybe_deal(state: Dictionary, rng: RandomNumberGenerator) -> void:
	var betting := (state.players as Dictionary).values().filter(func(p: Dictionary) -> bool: return p.status in ["bet", "ready"])
	if betting.is_empty() or betting.any(func(p: Dictionary) -> bool: return p.status == "bet"):
		return
	state.dealer = [_draw(state, rng), _draw(state, rng)]
	for p: Dictionary in betting:
		p.hand = [_draw(state, rng), _draw(state, rng)]
		p.status = "blackjack" if is_blackjack(p.hand) else "play"
	state.phase = "play"
	state.last = "Раздача: ещё карту или хватит?"
	_touch(state)
	_maybe_dealer(state)


## Все в раздаче закончили — ход дилера (карты он добирает в step()).
static func _maybe_dealer(state: Dictionary) -> void:
	if state.phase != "play":
		return
	if (state.players as Dictionary).values().any(func(p: Dictionary) -> bool: return p.status == "play"):
		return
	state.phase = "dealer"
	state.clock = DEALER_STEP
	state.last = "Дилер открывает карту"
	_touch(state)


## Шаг времени (хост): дилер добирает по карте с паузой, потом расчёт. true — надо разослать снимок.
static func step(state: Dictionary, dt: float, rng: RandomNumberGenerator) -> bool:
	if state.phase == "done":
		state.clock = float(state.clock) - dt
		if float(state.clock) > 0.0:
			return false
		_new_round(state)  # расчёт показан — следующая раздача без нажатий
		return true
	if state.phase != "dealer":
		return false
	state.clock = float(state.clock) - dt
	if float(state.clock) > 0.0:
		return false
	state.clock = DEALER_STEP
	var anyone_left := (state.players as Dictionary).values().any(func(p: Dictionary) -> bool: return p.status in ["stand", "blackjack"])
	if anyone_left and value(state.dealer) < 17:
		state.dealer.append(_draw(state, rng))
		state.last = "Дилер берёт карту: %d" % value(state.dealer)
		_touch(state)
		return true
	_settle(state)
	return true


static func _settle(state: Dictionary) -> void:
	var dealer := value(state.dealer)
	var dealer_bj := is_blackjack(state.dealer)
	for p: Dictionary in (state.players as Dictionary).values():
		if p.status not in ["stand", "bust", "blackjack"]:
			continue
		var bet := int(p.bet)
		var mine := value(p.hand)
		var delta := 0
		if p.status == "bust":
			delta = -bet
			p.result = "Перебор"
		elif p.status == "blackjack" and not dealer_bj:
			delta = maxi(1, bet * 3 / 2)
			p.result = "Блэкджек!"
		elif dealer_bj and p.status != "blackjack":
			delta = -bet
			p.result = "У дилера блэкджек"
		elif dealer > 21 or mine > dealer:
			delta = bet
			p.result = "Победа"
		elif mine == dealer:
			p.result = "Ничья"
		else:
			delta = -bet
			p.result = "Проигрыш"
		p.chips = int(p.chips) + delta
		p.delta = delta
		p.status = "done"
	state.phase = "done"
	state.clock = NEXT_PAUSE
	state.last = "У дилера %d%s · новая раздача через %d с" % [dealer, " — перебор!" if dealer > 21 else "", int(NEXT_PAUSE)]
	_touch(state)


static func _new_round(state: Dictionary) -> void:
	state.dealer = []
	for p: Dictionary in (state.players as Dictionary).values():
		p.hand = []
		p.bet = 0
		p.result = ""
		p.delta = 0
		p.status = "bet" if int(p.chips) > 0 else "broke"
	state.phase = "bet"
	state.last = "Делайте ставки"
	_touch(state)


## Снимок для участников: всё открыто, кроме закрытой карты дилера во время раздачи (-1).
static func snapshot(state: Dictionary) -> Dictionary:
	var list: Array = []
	for peer: int in state.players:
		var p: Dictionary = state.players[peer]
		list.append({"peer": peer, "name": p.name, "color": p.color, "chips": p.chips, "bet": p.bet,
			"hand": (p.hand as Array).duplicate(), "status": p.status, "result": p.result, "delta": p.delta,
			"value": value(p.hand) if not (p.hand as Array).is_empty() else 0})
	var dealer: Array = (state.dealer as Array).duplicate()
	if state.phase == "play" and dealer.size() >= 2:
		dealer[1] = -1
	return {"game": "blackjack", "list": list, "dealer": dealer, "dealer_value": value(state.dealer) if state.phase in ["dealer", "done"] else (value([dealer[0]]) if not dealer.is_empty() else 0),
		"phase": state.phase, "last": state.last, "seq": state.seq}
