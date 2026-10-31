extends RefCounted
## Four Souls: статус автоматизации карты (auto | partial | manual) и подсказка «что сделать руками».
## Данные — games/four_souls/art/card_support.json (генерирует tools/make_fs_card_support.py).

static var _cards: Dictionary = {}

static func entry(id: int) -> Dictionary:
	if _cards.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://games/four_souls/art/card_support.json"))
		_cards = data.cards if data is Dictionary else {"_": {}}
	return _cards.get(str(id), {"status": "manual", "hint": "Выполните текст карты через панель эффекта."})

static func status(id: int) -> String:
	return str(entry(id).status)

static func hint(id: int) -> String:
	return str(entry(id).hint)
