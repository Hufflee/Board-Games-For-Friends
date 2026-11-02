extends "res://games/four_souls/logic/fs_rules.gd"
## Только стенд старых записанных трасс: все награды считаются неизвестными каталогу.
## Проверяет сохраняемый ручной fallback и прежние инварианты; не покрывает новую автоматику.
## Новые core/UI/fuzz используют обычный FSRules без этого шва.
func _printed_monster_reward(_id: int) -> Dictionary:
	return {}
