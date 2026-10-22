class_name RSBData
extends RefCounted
## Данные «На старт, ставки!»: лошади, поле ставок (сняты с поля в правилах), пари, экзотические финиши, VIP-карты.

const FINISH := 15
const RED_LINE := 9  # линия — после 9-й клетки: пересекла, когда стоит на 10-й и дальше
const RACES := 4

const HORSES := ["2/3", "4", "5", "6", "7", "8", "9", "10", "11/12"]
const HORSE_COLOR := ["blue", "blue", "orange", "red", "black", "red", "orange", "blue", "blue"]
const BONUS := [3, 3, 2, 1, 0, 1, 2, 3, 3]
const COLOR_NAMES := {"blue": "синие", "orange": "оранжевые", "red": "красные", "black": "чёрная"}

## Ячейки ставок на лошадь: [коэффициент, штраф] — Show ×2, Place ×2, Win ×3.
const SHOW := [
	[[4, 4], [4, 3]], [[3, 1], [3, 0]], [[2, 3], [2, 0]], [[1, 2], [1, 0]], [[1, 3], [1, 1]],
	[[1, 2], [1, 0]], [[2, 3], [2, 0]], [[3, 1], [3, 0]], [[4, 4], [4, 3]],
]
const PLACE := [
	[[5, 4], [5, 3]], [[4, 1], [4, 0]], [[2, 2], [3, 2]], [[2, 5], [2, 4]], [[2, 6], [2, 5]],
	[[2, 5], [2, 4]], [[2, 2], [3, 2]], [[4, 1], [4, 0]], [[5, 4], [5, 3]],
]
const WIN := [
	[[7, 2], [8, 2], [9, 2]], [[5, 1], [6, 0], [7, 0]], [[4, 2], [4, 0], [5, 0]], [[3, 2], [3, 1], [3, 0]],
	[[3, 4], [3, 3], [3, 2]], [[3, 2], [3, 1], [3, 0]], [[4, 2], [4, 0], [5, 0]], [[5, 1], [6, 0], [7, 0]],
	[[7, 2], [8, 2], [9, 2]],
]
## Ставки на цвет победителя и «7 — пятой или хуже».
const COLOR_BETS := {
	"color_blue": {"name": "Синие победят", "mult": 5, "loss": 1},
	"color_orange": {"name": "Оранжевые победят", "mult": 3, "loss": 1},
	"color_red": {"name": "Красные победят", "mult": 2, "loss": 1},
	"seven_5th": {"name": "7 — пятой или хуже", "mult": 4, "loss": 0},
}

## Пари: лошадь a обгонит лошадь b (или всех лошадей цвета group). Коэффициенты — по симуляции 100 000 забегов.
const PROPS := [
	{"a": 0, "b": 5, "mult": 4, "loss": 3}, {"a": 8, "b": 3, "mult": 4, "loss": 3},
	{"a": 0, "b": 3, "mult": 4, "loss": 3}, {"a": 8, "b": 5, "mult": 4, "loss": 3},
	{"a": 1, "b": 4, "mult": 5, "loss": 3}, {"a": 7, "b": 4, "mult": 5, "loss": 3},
	{"a": 1, "b": 2, "mult": 3, "loss": 3}, {"a": 7, "b": 6, "mult": 3, "loss": 3},
	{"a": 0, "b": 2, "mult": 3, "loss": 3}, {"a": 8, "b": 6, "mult": 3, "loss": 3},
	{"a": 2, "b": 3, "mult": 3, "loss": 3}, {"a": 6, "b": 5, "mult": 3, "loss": 3},
	{"a": 3, "b": 6, "mult": 2, "loss": 2}, {"a": 5, "b": 2, "mult": 2, "loss": 2},
	{"a": 2, "b": 6, "mult": 2, "loss": 2}, {"a": 3, "b": 5, "mult": 2, "loss": 2},
	{"a": 2, "b": 4, "mult": 3, "loss": 3}, {"a": 6, "b": 4, "mult": 3, "loss": 3},
	{"a": 3, "b": 4, "mult": 2, "loss": 2}, {"a": 5, "b": 4, "mult": 2, "loss": 2},
	{"a": 4, "group": "blue", "mult": 2, "loss": 2}, {"a": 4, "group": "orange", "mult": 2, "loss": 2},
	{"a": 4, "group": "red", "mult": 2, "loss": 3}, {"a": 3, "group": "orange", "mult": 2, "loss": 2},
	{"a": 5, "group": "orange", "mult": 2, "loss": 2}, {"a": 2, "group": "red", "mult": 4, "loss": 3},
	{"a": 6, "group": "red", "mult": 4, "loss": 3}, {"a": 1, "group": "orange", "mult": 5, "loss": 3},
]

## Экзотические финиши (по 3 ячейки на карте).
const EXOTICS := [
	{"id": "tight", "name": "Плотная гонка", "text": "Все лошади прошли 6 клеток или больше.", "mult": 6, "loss": 2, "art": "exotic_red"},
	{"id": "late", "name": "Поздний старт", "text": "Хотя бы 2 лошади прошли 3 клетки или меньше.", "mult": 4, "loss": 1, "art": "exotic_blue"},
	{"id": "photo", "name": "Фотофиниш", "text": "Третья лошадь отстала от финиша на 3 клетки или меньше.", "mult": 5, "loss": 3, "art": "exotic_green"},
	{"id": "nose", "name": "На полкорпуса", "text": "Вторая лошадь отстала ровно на 1 клетку.", "mult": 5, "loss": 3, "art": "exotic_purple"},
	{"id": "blowout", "name": "Разгром", "text": "Вторая лошадь отстала больше чем на 5 клеток.", "mult": 4, "loss": 2, "art": "exotic_navy"},
]

## Бонус-жетоны: номинал → дополнительный штраф при проигрыше (-1 у «2» — отменяет штраф ячейки).
const BONUS_TOKEN_LOSS := {2: -1, 3: 0, 4: 1, 5: 2, 6: 3, 7: 5}

## VIP-карты (32). kind: bonus / piggy / comp / snake / risky / late / insure / highroller / fan / early / comeback.
const VIP := [
	{"kind": "bonus", "color": "black", "value": 2}, {"kind": "bonus", "color": "white", "value": 2},
	{"kind": "bonus", "color": "black", "value": 3}, {"kind": "bonus", "color": "white", "value": 3},
	{"kind": "bonus", "color": "black", "value": 4}, {"kind": "bonus", "color": "white", "value": 4},
	{"kind": "bonus", "color": "black", "value": 5}, {"kind": "bonus", "color": "white", "value": 5},
	{"kind": "bonus", "color": "black", "value": 6}, {"kind": "bonus", "color": "white", "value": 6},
	{"kind": "bonus", "color": "black", "value": 7}, {"kind": "bonus", "color": "white", "value": 7},
	{"kind": "piggy", "value": 2}, {"kind": "piggy", "value": 3}, {"kind": "piggy", "value": 4}, {"kind": "piggy", "value": 5},
	{"kind": "comp"}, {"kind": "comp"},
	{"kind": "snake"}, {"kind": "snake"},
	{"kind": "risky"}, {"kind": "risky"},
	{"kind": "late"}, {"kind": "late"},
	{"kind": "insure"}, {"kind": "insure"},
	{"kind": "highroller"},
	{"kind": "fan", "color": "blue", "value": 6}, {"kind": "fan", "color": "orange", "value": 4}, {"kind": "fan", "color": "red", "value": 3},
	{"kind": "early"},
	{"kind": "comeback"},
]
const COMP_CHIPS := [4, 7, 10]  # «Фишки от заведения»: если это ваша 1-я / 2-я / 3-я VIP-карта


static func horse_for_roll(sum: int) -> int:
	return {2: 0, 3: 0, 4: 1, 5: 2, 6: 3, 7: 4, 8: 5, 9: 6, 10: 7, 11: 8, 12: 8}[sum]


static func vip_title(v: Dictionary) -> String:
	match v["kind"]:
		"bonus":
			return "Бонус-жетон: %s %d" % ["чёрный" if v["color"] == "black" else "белый", v["value"]]
		"piggy":
			return "Ставка на плечах: %d" % v["value"]
		"comp":
			return "Фишки от заведения"
		"snake":
			return "Змеиные глаза и вагоны"
		"risky":
			return "Рисковый игрок"
		"late":
			return "Опоздавший"
		"insure":
			return "Страховка"
		"highroller":
			return "Хайроллер"
		"fan":
			return "Фанат: %s" % COLOR_NAMES[v["color"]]
		"early":
			return "Ранняя пташка"
		"comeback":
			return "Утешительный приз"
	return "?"


static func vip_text(v: Dictionary) -> String:
	match v["kind"]:
		"bonus":
			var loss: int = BONUS_TOKEN_LOSS[v["value"]]
			var tail := "Отменяет штраф ячейки при проигрыше." if loss < 0 else ("При проигрыше — ещё −$%d к штрафу ячейки." % loss if loss > 0 else "Без дополнительного штрафа.")
			return "Получите дополнительный жетон ставки «%d». %s" % [v["value"], tail]
		"piggy":
			return "Раз за забег можно положить жетон «%d» на ячейку, где уже лежит ровно один жетон соперника." % v["value"]
		"comp":
			return "Сразу получите $%d, $%d или $%d — если это ваша 1-я, 2-я или 3-я VIP-карта." % COMP_CHIPS
		"snake":
			return "+$1 каждый раз, когда выпадает 2 («змеиные глаза») или 12 («товарные вагоны»)."
		"risky":
			return "За каждую выигравшую ставку +$2, за каждую проигравшую −$1."
		"late":
			return "Раз за забег можно сделать одну ставку после «Ставок больше нет!»."
		"insure":
			return "Первая проигравшая ставка в каждом забеге — без штрафа."
		"highroller":
			return "Выигрыш жетоном «5» приносит ещё +$5."
		"fan":
			return "+$%d, если в забеге победила %s лошадь." % [v["value"], {"blue": "синяя", "orange": "оранжевая", "red": "красная"}[v["color"]]]
		"early":
			return "+$2 за каждую выигравшую ставку, сделанную до того, как хоть одна лошадь пересекла красную линию."
		"comeback":
			return "Если после забега у вас меньше всех денег — +$6."
	return ""
