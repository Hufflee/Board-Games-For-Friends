extends RefCounted
## card_support.json покрывает все карты манифеста, статусы известны, у каждой карты есть подсказка.
const FSCheck = preload("res://tests/fs/fs_check.gd")
const Support = preload("res://games/four_souls/logic/fs_support.gd")

func run(t: FSCheck) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/four_souls/art/card_support.json"))
	var missing := 0
	var bad := 0
	for card: Dictionary in FSData.data().cards:
		var id := int(card.id)
		var e: Dictionary = Support.entry(id)
		if not data.cards.has(str(id)):
			missing += 1
		if not str(e.get("status", "")) in ["auto", "partial", "manual"] or str(e.get("hint", "")).is_empty():
			bad += 1
	t.equal(missing, 0, "Карт без записи в card_support.json")
	t.equal(bad, 0, "Карт с неизвестным статусом или без подсказки")
	t.equal(Support.status(709), "auto", "Проклятие алчности автоматизировано")
	t.equal(Support.status(127), "partial", "Волшебник — частично")
