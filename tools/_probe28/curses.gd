extends SceneTree
## Разовая проверка (07.11): какие проклятия автоматизация не обрабатывает при выходе из колоды.
const CardAutomation := preload("res://games/four_souls/logic/fs_card_automation.gd")
func _init() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://games/four_souls/art/manifest.json"))
	var out: Array = []
	for card in data.cards:
		if str(card.lua.get("type", "")) == "curse":
			out.append("%d %s handles=%s" % [int(card.id), str(card.name).split("/")[0], str(CardAutomation.handles({"kind": "event", "card": int(card.id)}))])
	print("\n".join(out))
	quit()
