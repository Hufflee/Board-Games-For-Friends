extends RefCounted
## Вершина сброса выдаётся первой. Состав колоды выдаётся по номерам изображений.

const Piles := preload("res://hub/card_piles.gd")


static func public_view(decks: Array, discards: Array, heroes: PackedStringArray, hands: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for seat in heroes.size():
		var pile: Array = discards[seat]
		var cards: Array[Dictionary] = []
		for card: Dictionary in Piles.peek(pile, pile.size()):
			cards.append({"key": card.key, "hero": card.hero, "face": card.face})
		var remaining: Array[Dictionary] = []
		var pool: Array = decks[seat].duplicate()
		if seat < hands.size():
			pool.append_array(hands[seat])
		for card: Dictionary in pool:
			remaining.append({"hero": card.hero, "face": card.face})
		remaining.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.face) < str(b.face))
		result.append({"hero": heroes[seat], "deck_count": decks[seat].size(), "deck": remaining, "discard": cards})
	return result
