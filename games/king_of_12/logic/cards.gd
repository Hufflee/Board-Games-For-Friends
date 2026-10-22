class_name K12Cards
extends RefCounted
## Описания карт «Дюжины короля».

const KNIGHT := "knight"
const SORCERER := "sorcerer"
const ORACLE := "oracle"
const ALCHEMIST := "alchemist"
const ROBOT := "robot"
const PARASITE := "parasite"
const GOLEM := "golem"
const CHEATER := "cheater"
const LADY := "lady"
const MERCHANTS := "merchants"
const WEREWOLF := "werewolf"
const TROUBLEMAKERS := "troublemakers"
const COLLECTOR := "collector"
const FAUN := "faun"

const BASE: Array[String] = [
	KNIGHT, SORCERER, ORACLE, ALCHEMIST, ROBOT, PARASITE,
	GOLEM, CHEATER, LADY, MERCHANTS, WEREWOLF, TROUBLEMAKERS,
]
const PROMO: Array[String] = [COLLECTOR, FAUN]
const FIRST_GAME: Array[String] = [KNIGHT, SORCERER, ORACLE, ALCHEMIST, ROBOT, PARASITE, GOLEM]
## Карты с символом кубика: физически меняют грань или переставляют кубики.
const PHYSICAL: Array[String] = [ORACLE, SORCERER, WEREWOLF, TROUBLEMAKERS, MERCHANTS]
const DECK_SIZE := 7

const INFO := {
	KNIGHT: {
		"name": "Рыцарь",
		"text": "В этом розыгрыше побеждает игрок с наименьшим значением кубика, второе место — следующий по величине.",
	},
	SORCERER: {
		"name": "Чародей",
		"text": "Поверните свой кубик на одну из пяти граней, соседних с верхней.",
	},
	ORACLE: {
		"name": "Оракул",
		"text": "Перебросьте свой кубик. Срабатывает последним в розыгрыше.",
	},
	ALCHEMIST: {
		"name": "Алхимик",
		"text": "Удвойте значение своего кубика. Грань не меняется.",
	},
	ROBOT: {
		"name": "Робот",
		"text": "Добавьте 7 к значению своего кубика. Грань не меняется.",
	},
	PARASITE: {
		"name": "Паразит",
		"text": "Уменьшите значение своего кубика на 7. Грань не меняется.",
	},
	GOLEM: {
		"name": "Голем",
		"text": "Значение вашего кубика — 12. Если после всех эффектов грань тоже 12, значение становится 1.",
	},
	CHEATER: {
		"name": "Шулер",
		"text": "Победитель розыгрыша получает 1 ПО, а второе место — 2 ПО (с Рыцарем — для наименьших значений).",
	},
	LADY: {
		"name": "Леди",
		"text": "Отменяет эффекты всех остальных карт. Если Леди отменена дублем: владелец Леди с наименьшим значением забирает жетон у владельца Леди с наибольшим.",
	},
	MERCHANTS: {
		"name": "Торговцы",
		"text": "Каждый игрок передаёт свой кубик игроку слева. Применяется первым.",
	},
	WEREWOLF: {
		"name": "Оборотень",
		"text": "Переверните свой кубик на противоположную грань (сумма противоположных граней — 13).",
	},
	TROUBLEMAKERS: {
		"name": "Смутьяны",
		"text": "Все игроки переворачивают свои кубики на противоположную грань.",
	},
	COLLECTOR: {
		"name": "Коллекционер",
		"text": "Если ваш кубик отменён, вы становитесь победителем, а тот, кто должен был победить, занимает второе место.",
	},
	FAUN: {
		"name": "Фавн",
		"text": "Если ваш кубик должен быть отменён, поверните его на наибольшую грань, которой нет на кубиках других игроков, и сравните снова.",
	},
}


static func card_name(id: String) -> String:
	return INFO[id]["name"]


static func card_text(id: String) -> String:
	return INFO[id]["text"]


static func is_physical(id: String) -> bool:
	return PHYSICAL.has(id)


## Случайный набор по правилам: Рыцарь + 6 из оставшихся, минимум 2 карты с символом кубика.
static func random_deck(rng: RandomNumberGenerator) -> Array[String]:
	var rest: Array[String] = BASE.filter(func(c): return c != KNIGHT)
	while true:
		_shuffle(rest, rng)
		var deck: Array[String] = [KNIGHT]
		deck.append_array(rest.slice(0, DECK_SIZE - 1))
		if deck.filter(is_physical).size() >= 2:
			return deck
	return []


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
