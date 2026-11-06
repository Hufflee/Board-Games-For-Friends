extends RefCounted
## Пакет 28: прежние ручные карты вне стартовых предметов — Магнетит 65,
## Проклятие потери 706 (выбор души), «Нам надо углубиться!» 711, передача Проклятия бездушия 744.
const IDS := [65, 706, 711, 744]
const EVENTS := [711]

static func plan(id: int, context: String) -> Array:
	match id:
		65: return [{"op": "temporary_monster_dc", "targets": "monsters", "amount": -1}]
		706: return [{"op": "loss_soul28", "targets": "loss_souls28", "required": true}]
		744: return [{"op": "curse_pass28", "targets": "curse_pass28", "required": true}]
		711: return [{"op": "deeper_attack28"}, {"op": "deeper28", "targets": "deeper_cards28", "optional": true}]
	return []
