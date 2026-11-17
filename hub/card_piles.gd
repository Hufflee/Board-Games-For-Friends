extends RefCounted
## Операции над упорядоченными стопками. Верхняя карта хранится в конце массива.
## Проверка правил и обновление видимости остаются в вызывающей игре.

static func top_index(pile: Array) -> int:
	return pile.size() - 1


## Возвращает копию списка от вершины к низу, до count карт.
static func peek(pile: Array, count: int) -> Array:
	var cards := pile.slice(maxi(0, pile.size() - maxi(count, 0)))
	cards.reverse()
	return cards


## Возвращает перенесённые карты в порядке добора. При истощении возвращает меньше count.
static func draw_many(deck: Array, hand: Array, count: int) -> Array:
	var cards: Array = []
	if is_same(deck, hand):
		return cards
	for i in mini(maxi(count, 0), deck.size()):
		cards.append(deck.back())
		draw(deck, hand)
	return cards


## Переносит карту по позиции. Позиция назначения отсчитывается после изъятия карты.
static func transfer(source: Array, index: int, target: Array, position: int = -1) -> bool:
	if index < 0 or index >= source.size():
		return false
	var target_size := target.size() - int(is_same(source, target))
	if position < -1 or position > target_size:
		return false
	var card: Variant = source.pop_at(index)
	if position == -1:
		target.append(card)
	else:
		target.insert(position, card)
	return true


static func draw(deck: Array, hand: Array) -> bool:
	return transfer(deck, top_index(deck), hand)


static func discard(hand: Array, index: int, pile: Array) -> bool:
	return transfer(hand, index, pile)


## Индексы уникальны, даже если одинаковые карты занимают разные позиции.
static func random_indices(pile: Array, count: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var available: Array = range(pile.size())
	var picked := PackedInt32Array()
	for i in mini(maxi(count, 0), pile.size()):
		picked.append(int(available.pop_at(rng.randi_range(0, available.size() - 1))))
	return picked


static func discard_random(hand: Array, pile: Array, count: int, rng: RandomNumberGenerator) -> Array:
	var discarded: Array = []
	if is_same(hand, pile):
		return discarded
	var picked := random_indices(hand, count, rng)
	var source_order := picked.duplicate()
	source_order.sort()
	for index in picked:
		discarded.append(hand[index])
	for i in range(source_order.size() - 1, -1, -1):
		hand.remove_at(source_order[i])
	pile.append_array(discarded)
	return discarded


static func matching(pile: Array, predicate: Callable) -> Array:
	return pile.filter(predicate)


static func count_matching(pile: Array, predicate: Callable) -> int:
	var count := 0
	for card: Variant in pile:
		count += int(bool(predicate.call(card)))
	return count


static func shuffle(pile: Array, rng: RandomNumberGenerator) -> void:
	for index in range(pile.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var card: Variant = pile[index]
		pile[index] = pile[other]
		pile[other] = card
