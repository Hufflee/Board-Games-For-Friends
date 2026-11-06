extends RefCounted
## Особые карты группы22. Монеты и постоянная защита514 используют общие правила.
const IDS := [500, 502, 534, 564]
static func plan(id: int, _context: String) -> Array:
	match id:
		500: return [{"op": "edit_number22", "targets": "number_targets22"}]
		502: return [{"op": "gold_token22", "targets": "gold_items22"}]
		534: return [{"op": "auto_roll"}, {"op": "rainbow_roll22"}]
		564: return [{"op": "copy_ability14", "targets": "tap_items14"}]
	return []
