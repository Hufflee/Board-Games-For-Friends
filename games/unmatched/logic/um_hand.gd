extends RefCounted
## Хостовая проекция рук и проверка выбора. См. tests/test_unmatched_hand.gd.

const Reveal := preload("res://hub/card_reveal.gd")
const Choice := preload("res://hub/player_choice.gd")


## Один контроллер может владеть несколькими руками. hand — место героя, viewer — участник.
static func view_for(hands: Array, controllers: PackedInt32Array, viewer: int, hand: int, pending: Dictionary, reveals: Dictionary = {}, heroes: PackedStringArray = []) -> Dictionary:
	var view := {"hand": -1, "cards": [], "counts": [], "owned": [], "shown": [], "choice": {}, "heroes": heroes.duplicate()}
	for seat in hands.size():
		var cards: Array = hands[seat]
		view.counts.append(cards.size())
		if _controls(controllers, viewer, seat):
			view.owned.append(seat)
			if seat == hand:
				view.hand = seat
				view.cards = cards.duplicate(true)
		for card: Dictionary in cards:
			if Reveal.visible_to(reveals.get(card.key, {}), viewer):
				view.shown.append(card.duplicate(true))
	if view.hand >= 0 and int(pending.get("hand", -1)) == hand:
		view.choice = {"id": pending.id, "allowed": pending.get("allowed", []).duplicate(),
			"min": pending.get("min", 1), "max": pending.get("max", 1),
			"prompt": pending.get("prompt", "Выберите карту"), "pass_label": pending.get("pass_label", "Пропустить")}
	return view


## Возвращает только действительные экземпляры из заданной руки. Пустой список допустим при min == 0.
static func accepts(hands: Array, controllers: PackedInt32Array, viewer: int, pending: Dictionary, answer: Dictionary) -> bool:
	var hand := int(pending.get("hand", -1))
	var keys: Variant = answer.get("cards")
	if pending.is_empty() or not _controls(controllers, viewer, hand) or hand >= hands.size():
		return false
	if answer.get("request") != pending.get("id") or answer.get("hand") != hand or not keys is Array:
		return false
	if keys.size() < int(pending.get("min", 1)) or keys.size() > int(pending.get("max", 1)):
		return false
	var in_hand: Dictionary = {}
	for card: Dictionary in hands[hand]:
		in_hand[card.key] = true
	var choice := Choice.request(viewer, pending.get("allowed", []))
	var seen: Dictionary = {}
	for key: Variant in keys:
		if not key is String or seen.has(key) or not in_hand.has(key) or not Choice.accepts(choice, viewer, key):
			return false
		seen[key] = true
	return true


static func _controls(controllers: PackedInt32Array, viewer: int, hand: int) -> bool:
	return viewer >= 0 and hand >= 0 and hand < controllers.size() and controllers[hand] == viewer
