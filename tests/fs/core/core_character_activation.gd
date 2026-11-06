extends RefCounted
## Карта персонажа: отдельная активация в стеке и прежний дополнительный розыгрыш.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")
func _game(t: Check) -> RefCounted:
	var s := Scenario.new(t).players(2).dlc().current(0).character(0, 821).character(1, 821).no_items(0).no_items(1).hand(0, [549, 550]).hand(1, [548]).monster(0, 348).monster(1, 352).room(-1).build()
	s.g.bonuses.clear()
	return s
func run(t: Check) -> void:
	var own = _game(t)
	own.ok(0, "character")
	t.check(not own.g.character_ready[0], "Персонаж повёрнут при объявлении способности")
	t.equal(own.g._bonus_loot_plays[0], 0, "Дополнительный розыгрыш ждёт разрешения способности")
	own.no(0, "character")
	own.close()
	t.equal(own.g._bonus_loot_plays[0], 1, "Разрешение персонажа добавляет один розыгрыш")
	own.ok(0, "loot", {"card": 549})
	own.close()
	t.equal(own.g.free_loot, 0, "Первый лут использует обычный розыгрыш")
	own.ok(0, "loot", {"card": 550})
	own.close()
	t.equal(own.g._bonus_loot_plays[0], 0, "Второй лут использует дополнительный розыгрыш персонажа")
	var other = _game(t)
	other.ok(1, "character")
	other.close()
	t.equal(other.g._bonus_loot_plays[1], 1, "В чужой ход способность принадлежит своему владельцу")
	other.ok(1, "loot", {"card": 548})
	other.close()
	t.equal(other.g.free_loot, 1, "Чужая активация не отнимает основной лут ходящего")
	var late = _game(t)
	late.g.turn_elapsed = 11
	late.g._turn_seen = late.g.turn_serial
	late.ok(1, "character", null, "06.11: окна 10 с нет — персонажа можно повернуть и на 11-й секунде чужого хода")
	var room = _game(t)
	room._take(814)
	room.g.room = 814
	room.g._room_activations[0] = 1
	room.no(0, "character", null, "Планетарий ограничивает и активацию персонажа")
	var jail = _game(t)
	jail.g._jail_owner = 0
	jail.no(1, "character", null, "Тюрьма блокирует чужую активацию персонажа")
	var auto = _game(t)
	auto.g.free_loot = 0
	auto.ok(0, "loot", {"card": 549})
	t.check(not auto.g.character_ready[0], "Прежний прямой розыгрыш лута тоже поворачивает персонажа")
	auto.close()
	t.equal(auto.g._bonus_loot_plays[0], 0, "Прямой розыгрыш не выдаёт второй бесплатный бонус")
