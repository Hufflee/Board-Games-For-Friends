extends "res://games/four_souls/logic/fs_rules.gd"
## Только стенд старых записанных трасс: все награды считаются неизвестными каталогу.
## Проверяет сохраняемый ручной fallback и прежние инварианты; не покрывает новую автоматику.
## Новые core/UI/fuzz используют обычный FSRules без этого шва.
func _printed_monster_reward(_id: int) -> Dictionary:
	return {}

## Старые трассы сохраняют ручной протокол, не проверяют автоматизацию04.11.
func _card_automation_active() -> bool:
	return false

func _card_automation_enabled() -> bool:
	return false

func _advance_card_automation() -> void:
	pass

## Записанные грани предшествуют автоматическому Раку552; новый первый бросок — в batch07.
func _card_die(seat: int, _attack_roll: bool = false) -> int:
	return clampi(_roll_die() + int(_turn_roll_bonus[seat]), 1, 6)

## Историческая трасса содержит старый постоянный бонус652; обычный FSRules проверяет batch08.
func _refresh_passive_stats() -> void:
	super._refresh_passive_stats()
	for seat in players.size():
		for item: Dictionary in items[seat]:
			if int(item.id) == 652:
				attack[seat] = int(attack[seat]) + 1
				item["_attack_bonus"] = int(item.get("_attack_bonus", 0)) + 1

## Старые трассы предшествуют пассивной защите297.
func _monster_evasion(monster: Dictionary) -> int:
	return super._monster_evasion(monster) + (1 if int(monster.id) == 297 and int(monster.hp) <= 2 else 0)

## Старый ручной штраф385 уже отражён в записанных трассах.
func _monster_attack(monster: Dictionary) -> int:
	return super._monster_attack(monster) - (1 if int(monster.id) == 385 and int(monster.hp) == 1 else 0)
