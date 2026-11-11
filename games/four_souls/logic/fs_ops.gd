extends RefCounted
## Four Souls: операции панели ручного эффекта — одно описание для сервера (fs_effects.gd) и UI (fs_table.gd).
## Строка: [op, подпись, поля]. Поля: "target" — игрок, "amount" — число, "item" — номер (подпись — чего),
## "other" — номер у выбранного игрока (обмен). Тест tests/fs/core/core_ops.gd сверяет список с match в _effect.

const MAIN := [
	["monster_counter", "Жетоны на монстре ±", {"item": "монстра", "amount": true}],
	["coins", "Монеты ±", {"target": true, "amount": true}],
	["loot", "Взять лут", {"target": true, "amount": true}],
	["treasure", "Получить сокровища", {"target": true, "amount": true}],
	["damage", "Нанести урон игроку", {"target": true, "amount": true}],
	["heal", "Восстановить здоровье", {"target": true, "amount": true}],
	["souls", "Забрать карту награды в души", {"target": true, "amount": true}],
	["steal_soul", "Украсть карту души", {"target": true, "item": "души"}],
	["attach_curse", "Передать проклятие", {"target": true}],
	["attack", "Сила атаки ±", {"target": true, "amount": true}],
	["temporary_attack", "Атака до конца хода ±", {"target": true, "amount": true}],
	["extra_attack", "Дополнительные атаки", {"amount": true}],
	["extra_buy", "Дополнительные покупки", {"amount": true}],
	["extra_loot", "Дополнительный розыгрыш лута", {"amount": true}],
	["max_hp", "Максимум здоровья ±", {"target": true, "amount": true}],
	["roll", "Изменить бросок ±", {"amount": true}],
	["reroll", "Перебросить кубик", {}],
	["cancel", "Отменить карту в стеке", {}],
	["cancel_attack", "Отменить атаку", {}],
	["prevent_death", "Предотвратить смерть", {"target": true}],
	["destroy", "Уничтожить предмет", {"target": true, "item": "предмета"}],
	["steal", "Украсть предмет", {"target": true, "item": "предмета"}],
	["recharge", "Перезарядить предмет", {"target": true, "item": "предмета"}],
	["ready_character", "Перезарядить персонажа", {"target": true}],
	["counter", "Счётчики предмета ±", {"target": true, "item": "предмета", "amount": true}],
	["monster_damage", "Урон монстру", {"item": "монстра", "amount": true}],
	["monster_hp", "Здоровье монстра ±", {"item": "монстра", "amount": true}],
	["peek_loot", "Посмотреть верх лута", {"amount": true}],
	["peek_treasure", "Посмотреть верх сокровищ", {"amount": true}],
	["peek_monster", "Посмотреть верх монстров", {"amount": true}],
]

const EXTRA := [
	["expand_monsters", "Расширить ячейки монстров", {"amount": true}],
	["add_soul", "Добавить игроку душу", {"target": true}],
	["destroy_soul", "Уничтожить карту души по индексу", {"target": true, "item": "души"}],
	["pay_coins", "Заплатить монеты за способность (с учётом скидки)", {"amount": true}],
	["deactivate", "Деактивировать предмет", {"target": true, "item": "предмета"}],
	["item_to_soul", "Превратить невечный предмет в душу", {"target": true, "item": "предмета"}],
	["give_loot", "Передать свою карту лута выбранному игроку", {"target": true, "item": "карты руки"}],
	["discard_loot", "Сбросить свою карту лута", {"item": "карты руки"}],
	["expand_shop", "Расширить магазин", {"amount": true}],
	["temporary_monster_dc", "Защита монстра до конца хода ±", {"item": "монстра", "amount": true}],
	["set_roll", "Установить результат ожидающего броска", {"amount": true}],
	["reveal_hand", "Посмотреть руку выбранного игрока", {"target": true}],
	["swap_items", "Обменяться невечными предметами", {"target": true, "item": "своего предмета", "other": true}],
	["discard_monster", "Сбросить неатакуемого сейчас монстра", {"item": "монстра"}],
	["discard_shop", "Сбросить и заменить предмет магазина", {"item": "в магазине"}],
	["take_shop", "Забрать предмет магазина без покупки", {"target": true, "item": "в магазине"}],
	["extra_turn", "Дополнительный ход выбранному игроку", {"target": true, "amount": true}],
	["skip_turn", "Пропустить следующий ход выбранного игрока", {"target": true, "amount": true}],
	["self_underdeck", "Эту карту лута — под низ колоды", {}],
	["self_give", "Передать разыгранную карту лута выбранному игроку", {"target": true}],
	["give_item", "Передать свой предмет выбранному игроку", {"target": true, "item": "своего предмета"}],
	["peek_hand", "Посмотреть руку выбранного игрока", {"target": true}],
	["peek_hands", "Посмотреть руки всех игроков", {}],
	["prevent_damage", "Предотвратить следующий урон в этом ходу", {"target": true, "amount": true}],
]

static func fields(op: String) -> Dictionary:
	for entry: Array in MAIN + EXTRA:
		if entry[0] == op:
			return entry[2]
	return {}
