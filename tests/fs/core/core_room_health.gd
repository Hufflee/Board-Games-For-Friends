extends RefCounted
## Уход комнаты с+1HP не оставляет здоровье выше нового предела у игрока без предметов.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func _without_items(game: FSRules) -> void:
	while not game.items[0].is_empty():
		game._remove_item(0, 0)
	game.hp[0] = game.max_hp[0]

func run(t: Check) -> void:
	var s := Scenario.new(t).players(2).dlc().current(0).character(0, 908) \
		.room(769).deck_top("room", [770]).setup(_without_items).build()
	t.equal(s.g.max_hp[0], 4, "Комната временно добавляет четвёртое здоровье")
	t.equal(s.g.hp[0], 4, "Игрок без предметов подготовлен с полным здоровьем")
	s.ok(0, "room", null)
	t.equal(s.g.room, 770, "Выбрана комната без бонуса здоровья")
	t.equal(s.g.max_hp[0], 3, "После смены предел снова равен трём")
	t.equal(s.g.hp[0], 3, "Текущее здоровье ограничено итоговым пределом даже без предметов")
	s.g._refresh_passive_stats()
	t.equal(s.g.hp[0], 3, "Повторный пересчёт не изменяет здоровье")
	s.inv("Комната без предметов")
