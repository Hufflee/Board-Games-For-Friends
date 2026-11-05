extends RefCounted
## Особый лут467/468 — заключительные две карты сорокакарточной группы20.
const IDS := [467, 468]
static func plan(id: int, context: String) -> Array:
	if id == 467:
		return [{"op": "ambush_copy20"}] if context == "copy20" else [{"op": "ambush_place20", "targets": "ambush_slots20"}]
	return [{"op": "make_room20", "targets": "room_items20"}]
