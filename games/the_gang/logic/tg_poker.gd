class_name TGPoker
extends RefCounted
## Чистая оценка лучшей пятёрки из 5–7 уникальных карт. ID: масть=id/13, значение=id%13+2.
## Проверка: --headless --audio-driver Dummy --script res://tests/test_the_gang.gd.

const NAMES: Array[String] = [
	"Старшая карта", "Пара", "Две пары", "Тройка", "Стрит",
	"Флеш", "Фулл-хаус", "Каре", "Стрит-флеш"
]

## Младшие наборы и некорректные входы не оцениваются; чужое состояние не изменяется.
static func evaluate(cards: Array) -> Dictionary:
	if cards.size() < 5 or cards.size() > 7:
		return {}
	var seen: Dictionary = {}
	for card: Variant in cards:
		if not card is int or int(card) < 0 or int(card) >= 52 or seen.has(card):
			return {}
		seen[card] = true
	var best: Dictionary = {}
	for a: int in range(cards.size() - 4):
		for b: int in range(a + 1, cards.size() - 3):
			for c: int in range(b + 1, cards.size() - 2):
				for d: int in range(c + 1, cards.size() - 1):
					for e: int in range(d + 1, cards.size()):
						var five: Array[int] = [cards[a], cards[b], cards[c], cards[d], cards[e]]
						var candidate: Dictionary = _five(five)
						if best.is_empty() or compare(candidate, best) > 0:
							best = candidate
	return best

## Полный лексикографический ключ включает категорию, все значимые ранги и кикеры; мастей нет.
static func compare(a: Dictionary, b: Dictionary) -> int:
	var left: Array = a.get("key", [])
	var right: Array = b.get("key", [])
	for index: int in mini(left.size(), right.size()):
		if int(left[index]) != int(right[index]):
			return 1 if int(left[index]) > int(right[index]) else -1
	return signi(left.size() - right.size())

static func _five(cards: Array[int]) -> Dictionary:
	var counts: Array[int] = []
	counts.resize(15)
	counts.fill(0)
	var ranks: Array[int] = []
	var flush: bool = true
	var suit: int = int(cards[0] / 13)
	for card: int in cards:
		var rank: int = card % 13 + 2
		ranks.append(rank)
		counts[rank] += 1
		flush = flush and int(card / 13) == suit
	ranks.sort()
	ranks.reverse()
	var singles: Array[int] = []
	var pairs: Array[int] = []
	var triples: Array[int] = []
	var fours: Array[int] = []
	for rank: int in range(14, 1, -1):
		match counts[rank]:
			1: singles.append(rank)
			2: pairs.append(rank)
			3: triples.append(rank)
			4: fours.append(rank)
	var straight: int = 0
	if singles.size() == 5:
		if ranks[0] - ranks[4] == 4:
			straight = ranks[0]
		elif ranks == [14, 5, 4, 3, 2]:
			straight = 5
	var key: Array[int] = []
	if flush and straight > 0:
		key = [8, straight]
	elif not fours.is_empty():
		key = [7, fours[0], singles[0]]
	elif not triples.is_empty() and not pairs.is_empty():
		key = [6, triples[0], pairs[0]]
	elif flush:
		key = [5]
		key.append_array(ranks)
	elif straight > 0:
		key = [4, straight]
	elif not triples.is_empty():
		key = [3, triples[0]]
		key.append_array(singles)
	elif pairs.size() == 2:
		key = [2, pairs[0], pairs[1], singles[0]]
	elif pairs.size() == 1:
		key = [1, pairs[0]]
		key.append_array(singles)
	else:
		key = [0]
		key.append_array(ranks)
	var category: int = key[0]
	var title: String = "Роял-флеш" if category == 8 and straight == 14 else NAMES[category]
	return {"category": category, "key": key, "name": title, "best": cards.duplicate()}
