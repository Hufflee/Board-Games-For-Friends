extends RefCounted
## Пакет 28: прежние ручные карты вне стартовых предметов — Магнетит 65,
## Проклятие потери 706 (выбор души), «Нам надо углубиться!» 711, передача Проклятия бездушия 744.
## 07.11: проклятия без своей автоматизации — при выходе из колоды активный игрок выбирает, кому их отдать
## (раньше ждали ручной операции, доступной только в панели хоста: партия застревала, напр. 729).
const CURSES := [705, 706, 709, 723, 724, 729, 736, 737, 744]
const IDS := [65, 706, 711, 744, 705, 709, 723, 724, 729, 736, 737]
const EVENTS := [711, 705, 706, 709, 723, 724, 729, 736, 737, 744]

static func plan(id: int, context: String) -> Array:
	if id in CURSES and context == "":
		return [{"op": "attach_curse28", "targets": "players", "required": true}]
	match id:
		65: return [{"op": "temporary_monster_dc", "targets": "monsters", "amount": -1}]
		706: return [{"op": "loss_soul28", "targets": "loss_souls28", "required": true}]
		744: return [{"op": "curse_pass28", "targets": "curse_pass28", "required": true}]
		711: return [{"op": "deeper_attack28"}, {"op": "deeper28", "targets": "deeper_cards28", "optional": true}]
	return []
