extends SceneTree
## Things in Rings: выбор ведущего из желающих, таймаут хода и режим Blind Mind (логика и приватность view).
## Запуск: Godot --headless --audio-driver Dummy --path . --script res://tests/test_tir_blind.gd
const Rules := preload("res://games/things_in_rings/logic/tr_rules.gd")
const POOLS := {"Attribute": [100, 101, 102, 103], "Word": [200, 201, 202, 203], "Context": [300, 301, 302, 303]}
var checks := 0
var errors := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)


func send(game: Rules, seat: int, kind: String, payload: Dictionary = {}) -> bool:
	payload.revision = game.revision
	return game.action(seat, kind, payload)


## Новая партия до первого хода искателей: правила выбраны, подсказки выложены.
func ready_game(count: int, options: Dictionary, seed_value: int) -> Rules:
	var game := Rules.new()
	var opts := {"rings": ["Attribute", "Word"]}
	opts.merge(options, true)
	var people := []
	for i: int in count:
		people.append({"name": "P%d" % i})
	check(game.new_game(people, range(300), POOLS, opts, seed_value) == "", "Партия создана")
	for category: String in game.rings:
		check(send(game, game.knower, "choose_rule", {"category": category, "card": game.rule_choices[category][0]}), "Правило выбрано")
	check(send(game, game.knower, "begin_clues"), "Правила подтверждены")
	while game.phase == "setup_clues":
		check(send(game, game.knower, "clue", {"card": game.hands[game.knower][0], "mask": 0}), "Подсказка")
	return game


func _init() -> void:
	_volunteers()
	_timeout_classic()
	_blind_round()
	_blind_win_and_coop()
	print("TIR BLIND/VOLUNTEERS: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)


func _volunteers() -> void:
	var seen := {}
	for seed_value: int in range(1, 41):
		var game := Rules.new()
		check(game.new_game([{}, {}, {}, {}], range(300), POOLS, {"rings": ["Word"], "knower": 0, "volunteers": [1, 3]}, seed_value) == "", "Партия с желающими")
		check(game.knower in [1, 3], "Ведущий — только из желающих")
		seen[game.knower] = true
	check(seen.size() == 2, "Среди нескольких желающих выбор случайный (выпадали оба)")
	var single := Rules.new()
	single.new_game([{}, {}, {}], range(300), POOLS, {"rings": ["Word"], "knower": 0, "volunteers": [2]}, 7)
	check(single.knower == 2, "Один желающий — он и ведущий")
	var nobody := Rules.new()
	nobody.new_game([{}, {}, {}], range(300), POOLS, {"rings": ["Word"], "knower": 1, "volunteers": []}, 7)
	check(nobody.knower == 1, "Никто не вызвался — ведущий из настройки хоста")
	var junk := Rules.new()
	junk.new_game([{}, {}, {}], range(300), POOLS, {"rings": ["Word"], "knower": 1, "volunteers": [9, -1, "2"]}, 7)
	check(junk.knower == 1, "Неверные места желающих игнорируются")
	check(Rules.new().new_game([{}, {}], range(300), POOLS, {"rings": ["Word"], "mode": "chaos"}) != "", "Неизвестный режим отклоняется")


func _timeout_classic() -> void:
	var game := ready_game(3, {}, 11)
	check(game.phase == "place" and game.current == 1, "Обычный режим: ход первого искателя")
	var before: int = game.hands[1].size()
	check(game.timeout(), "Таймаут принят")
	check(game.current == 2 and game.hands[1].size() == before, "Таймаут: ход переходит без штрафной карты")
	check(game.timeout() and game.phase == "place" and game.current == 1 and game.round_no == 2, "Круг замыкается")
	check(send(game, 1, "place", {"card": game.hands[1][0], "mask": 1}) and not game.timeout(), "Проверку знающего таймаут не трогает")


func _blind_round() -> void:
	var game := ready_game(4, {"mode": "blind", "knower": 0}, 21)
	check(game.phase == "blind" and game.actor() == -1, "Blind Mind: ход всех искателей сразу")
	check(game.blind_waiting() == [1, 2, 3], "Ждём всех трёх искателей")
	var stale: int = game.revision
	var c1: int = game.hands[1][0]
	var c2: int = game.hands[2][0]
	var c3: int = game.hands[3][0]
	check(not send(game, 0, "blind_place", {"card": game.hands[0][0] if not game.hands[0].is_empty() else 0, "mask": 0}), "Знающий не ставит карточку")
	check(send(game, 1, "blind_place", {"card": c1, "mask": 1}), "Искатель 1 поставил")
	check(game.action(2, "blind_place", {"revision": stale, "card": c2, "mask": 2}), "Одновременный ход со старой ревизией принят")
	check(not send(game, 1, "blind_place", {"card": game.hands[1][0], "mask": 0}), "Вторая карточка за ход запрещена")
	check(not game.action(3, "begin_clues", {"revision": stale}), "Прочие действия со старой ревизией отклоняются")
	# Приватность: чужих карточек не видно, знающий видит все.
	var v1: Dictionary = game.get_view(1)
	var v3: Dictionary = game.get_view(3)
	var vk: Dictionary = game.get_view(0)
	var vs: Dictionary = game.get_view(-1)
	check(v1.blind.keys() == [1] and int(v1.blind[1].card) == c1, "Искатель видит только свою карточку")
	check(v3.blind.is_empty() and vs.blind.is_empty(), "Не поставивший и зритель не видят карточек")
	check(vk.blind.size() == 2 and int(vk.blind[2].card) == c2, "Знающий видит все поставленные")
	check(v3.blind_placed == [1, 2] and v3.blind_waiting == [3], "Публично — только кто поставил")
	for v: Dictionary in [v1, v3, vs]:
		check(not v.blind.has(2) and v.pending.is_empty() and v.last_reveal.is_empty(), "Карточка искателя 2 не утекает в чужой view")
	check(send(game, 0, "blind_move", {"owner": 1, "mask": 3}), "Знающий сразу переносит карточку")
	check(not send(game, 1, "blind_move", {"owner": 1, "mask": 0}), "Искатель не переносит")
	check(int(game.get_view(1).blind[1].actual) == 1, "Искатель не видит перенос до конца хода")
	check(int(game.get_view(0).blind[1].actual) == 3, "Знающий видит перенос")
	check(not send(game, 0, "blind_done"), "Завершить нельзя, пока не все поставили")
	check(send(game, 3, "blind_place", {"card": c3, "mask": 0}), "Последний искатель поставил")
	check(game.phase == "blind_check" and game.actor() == 0, "Все поставили — очередь знающего")
	check(send(game, 0, "blind_move", {"owner": 3, "mask": 0}), "Перенос и на проверке")
	var deck_before: int = game.deck.size()
	check(send(game, 0, "blind_done"), "Знающий завершил проверку")
	var reveal: Dictionary = game.get_view(3).last_reveal
	check(reveal.items.size() == 3 and int(reveal.items[0].seat) == 1, "Открытие: все три карточки по порядку мест")
	check(int(reveal.items[0].actual) == 3 and not reveal.items[0].correct and reveal.items[1].correct, "Открытие показывает перенос и верность")
	check(game.hands[1].size() == 5 and game.hands[2].size() == 4 and deck_before - game.deck.size() == 1, "Ошибка — штрафная карта, верно — минус карта")
	check(game.board.size() == 6 and int(game.board[3].from) == 1 and int(game.board[3].mask) == 3, "На поле итоговая область и откуда перенесли")
	check(game.phase == "blind" and game.round_no == 2 and game.get_view(1).blind.is_empty(), "Новый слепой ход")
	# Таймаут: никто не поставил — ход пропускается; часть поставила — к проверке.
	check(game.timeout() and game.phase == "blind" and game.round_no == 3, "Таймаут без карточек — следующий ход")
	check(send(game, 2, "blind_place", {"card": game.hands[2][0], "mask": 2}), "Один успел")
	check(game.timeout() and game.phase == "blind_check" and game.get_view(0).blind.size() == 1, "Таймаут закрывает приём, знающий проверяет поставленное")
	check(send(game, 0, "blind_done") and game.last_reveal.items.size() == 1, "Открывается только поставленная")


func _blind_win_and_coop() -> void:
	var game := ready_game(3, {"mode": "blind", "knower": 0}, 31)
	for seat: int in [1, 2]:
		game.hands[seat] = [game.hands[seat][0]]
	check(send(game, 1, "blind_place", {"card": game.hands[1][0], "mask": 0}) and send(game, 2, "blind_place", {"card": game.hands[2][0], "mask": 1}), "Оба поставили последнюю карту")
	check(send(game, 0, "blind_done"), "Проверка завершена")
	check(game.phase == "postgame" and game.winners == [1, 2] and game.reason == "first_found", "Одновременно опустевшие руки делят победу")
	var solo := ready_game(3, {"mode": "blind", "knower": 0}, 32)
	solo.hands[1] = [solo.hands[1][0]]
	send(solo, 1, "blind_place", {"card": solo.hands[1][0], "mask": 0})
	send(solo, 2, "blind_place", {"card": solo.hands[2][0], "mask": 0})
	send(solo, 0, "blind_move", {"owner": 2, "mask": 1})
	send(solo, 0, "blind_done")
	check(solo.winners == [1], "Победа только у верного с пустой рукой")
	var coop := ready_game(3, {"mode": "blind", "knower": 0, "coop": true}, 33)
	check(coop.phase == "blind", "Кооператив Blind Mind начинается слепым ходом")
	send(coop, 1, "blind_place", {"card": coop.hands[1][0], "mask": 0})
	send(coop, 2, "blind_place", {"card": coop.hands[2][0], "mask": 0})
	send(coop, 0, "blind_done")
	check(coop.phase == "knower_clue", "Кооператив: после хода — подсказка знающего")
	check(send(coop, 0, "clue", {"card": coop.hands[0][0], "mask": 0}) and coop.phase == "blind", "После подсказки — снова слепой ход")
