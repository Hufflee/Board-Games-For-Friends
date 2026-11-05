extends RefCounted
## Первая часть пакета20: последние15монстров452–466, проверки после всех40карт.
const IDS := [452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464, 465, 466]
static func plan(id: int, _context: String) -> Array:
	match id:
		453:
			return [{"op": "discard_victim16"}]
		454:
			return [{"op": "kill_player16", "targets": "living_players16"}]
		455:
			return [{"op": "discard_target18", "targets": "players"}]
		460:
			return [{"op": "nonactive_damage17"}]
		463:
			return [{"op": "slayer_damage20"}]
		464:
			return [{"op": "left_damage20"}]
		465:
			return [{"op": "split_prepare20"}]
		466:
			return [{"op": "left_mirror20"}]
	return []
