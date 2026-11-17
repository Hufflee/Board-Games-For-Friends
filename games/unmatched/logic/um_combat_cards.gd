extends RefCounted
## Закрытые заявки атаки и защиты. Условия пригодности карт задают правила боя.

const Hand := preload("res://games/unmatched/logic/um_hand.gd")

var _requests: Array[Dictionary] = []
var _sealed: Array = []


func _init(first_request_id: int, attacker: int, defender: int, attack_cards: Array, defense_cards: Array, fixed_attack: Dictionary = {}) -> void:
	_requests = [
		{"id": first_request_id, "hand": attacker, "allowed": attack_cards.duplicate(),
			"min": 1, "max": 1, "prompt": "Выберите карту атаки"},
		{"id": first_request_id + 1, "hand": defender, "allowed": defense_cards.duplicate(),
			"min": 0, "max": 1, "prompt": "Выберите карту защиты", "pass_label": "Без защиты"},
	]
	if not fixed_attack.is_empty():
		_sealed.append(fixed_attack.duplicate(true))


func pending() -> Dictionary:
	if _sealed.size() >= _requests.size():
		return {}
	return _requests[_sealed.size()].duplicate(true)


func choose(hands: Array, controllers: PackedInt32Array, viewer: int, answer: Dictionary) -> bool:
	var request := pending()
	if not Hand.accepts(hands, controllers, viewer, request, answer):
		return false
	if answer.cards.is_empty():
		_sealed.append({})
		return true
	var key: String = answer.cards[0]
	for card: Dictionary in hands[int(request.hand)]:
		if card.key == key:
			_sealed.append(card.duplicate(true))
			return true
	return false


func revealed() -> Dictionary:
	if _sealed.size() < _requests.size():
		return {}
	return {"attack": _sealed[0].duplicate(true), "defense": _sealed[1].duplicate(true)}


func selected_attack_key() -> String:
	return _sealed[0].key if not _sealed.is_empty() else ""
