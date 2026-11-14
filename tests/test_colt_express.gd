extends SceneTree
## Полные партии 2–6 мест, разрешения, приватность и повтор.
const Rules := preload("res://games/colt_express/logic/ce_rules.gd")
var failed := 0

func _initialize() -> void:
	_expansions()
	for seats in range(2,7):
		for trial in 12:
			_play(seats,trial)
	print("Кольт Экспресс: 60 партий, ошибок ",failed)
	quit(1 if failed else 0)

func _check(ok: bool,message: String) -> void:
	if not ok:
		failed += 1
		printerr(message)

func _play(count: int, trial: int) -> void:
	seed(count*100+trial)
	var r := Rules.new()
	var seats: Array = []
	for i in count:
		seats.append({"name":"Игрок %d" % i})
	r.new_game(seats,{"teams":count in [4,6] and trial % 3 == 2,"sprites":trial % 2 == 1,"time_car":trial % 2 == 0,"marshal_player":count >= 3 and trial % 6 == 5,"cursed":trial % 2 == 0,"prison":trial % 5 == 0,"coach":trial % 4 == 0,"horses":trial % 3 == 1 or trial % 4 == 0,"whiskey":trial % 3 != 0})
	_check(r.get_view(-1).hand.is_empty(),"Зритель видит руку")
	var expected: Array = []
	var played: Array = []
	for i in 2000:
		var seat := r.turn
		var token := {"serial":r.serial}
		match r.phase:
			"select":
				_check(r.action(seat,"select",{"id":r.bandits.size()-int(r.marshal_player)},false),"Выбор персонажа")
			"travel":
				token.car = 1
				_check(r.action(seat,"travel",token,false),"Тайный выбор вагона")
			"mount":
				_check(r.action(seat,"mount",{"land":true,"serial":r.serial},false),"Выбор стартового вагона")
			"plan":
				var hand: Array = r.get_view(seat).hand
				var index := -1
				for j in hand.size():
					if hand[j].kind != "bullet" and not (r.steps[r.step] == "к" and hand[j].kind in ["shoot","punch"]):
						index = j
						break
				token.index = index
				token.hidden = true
				_check(r.action(seat,"draw" if index == -1 or (i%6 == 1 and r.flask_plays == 0) else "play",token,false),"Планирование")
				for card: Dictionary in r.get_view(-1).queue:
					_check(card.kind != "hidden" or card.id == -1,"Тоннель раскрывает персонажа")
			"discard","reserve","reflex":
				_check(r.action(seat,"keep",token,false),"Сохранение руки")
			"reveal":
				var board: Dictionary = r.get_view(-1).board
				_check(not r.tick(10),"Действие началось само")
				_check(not r.action(0,"next",token,false),"Клиент запустил действие")
				_check(board == r.get_view(-1).board,"Поезд изменился при раскрытии")
				_check(r.action(0,"next",token,true),"Хост не смог запустить действие")
				_check(not r.action(0,"next",token,true),"Карта исполнилась повторно")
			"choose","reaction":
				_check(r.get_view(-1).options.is_empty(),"Зритель видит варианты чужого хода")
				token.index = trial % r.options.size()
				_check(r.action(seat,"choose",token,false),"Выбор варианта")
			"animate":
				_check(r.tick(2 + r.FLIP_LEAD),"Действие не завершилось")  # пауза переворота карты (14.11)
			"replay":
				var board: Dictionary = r.get_view(-1).board
				_check(r.tick(2),"Повтор не идёт автоматически")
				_check(board == r.get_view(-1).board,"Повтор изменил поезд")
			"match_replay":
				if expected.is_empty():
					for round_index in r.match_history.size():
						for event: Dictionary in r.match_history[round_index]:
							expected.append([round_index + 1, event.serial])
				var view := r.get_view(-1)
				played.append([view.replay_round, view.clip.serial])
				_check(view.results.is_empty(), "Итоги показаны до окончания повтора")
				_check(r.tick(2), "Повтор партии не продолжился")
				_check(view.board == r.get_view(-1).board, "Повтор партии изменил поезд")
			"end":
				_check(r.match_history.size() == 5 and not played.is_empty() and played == expected,
					"Повтор партии пропустил или переставил события")
				_check(r.turn_no == 5 and r.results.size() == count,"Некорректные итоги")
				return
	_check(false,"Партия зависла: "+r.phase)

func _expansions() -> void:
	var r := Rules.new()
	r.new_game([{}, {}, {}],{"marshal_player":true,"coach":true,"horses":true})
	r.action(1,"select",{"id":0},false)
	r.action(2,"select",{"id":5},false)
	r.action(1,"mount",{"land":true,"serial":r.serial},false)
	r.action(2,"mount",{"land":true,"serial":r.serial},false)
	r._bandit(0).car = 1
	r._bandit(5).car = 1
	r.pending = {"kind":"shoot","id":6}
	var shots := r._choices()
	var pair := shots.filter(func(o: Dictionary) -> bool: return o.has("second_target"))
	_check(pair.size() == 2,"Две цели маршала, включая Беллу")
	r._execute(pair[0])
	_check(r.cylinders == [1,1],"Двойной выстрел тратит по пуле из двух барабанов")
	_check(r.players[1].received == 1 and r.players[2].received == 1,"Двойной выстрел ранит двух разных игроков")
	_check(r.clip.has("second_target"),"Повтор должен хранить обе цели выстрела")
	r.pending = {"kind":"shoot","id":0}
	_check(r._blocked(r._bandit(0)),"Разоружение блокирует стрельбу")
	r.pending = {"kind":"idea","id":0}
	_check(not r._blocked(r._bandit(0)),"Разоружение разрешает скопировать стрельбу")
	r._bandit(0).car = -2
	r.coach_hostages = [1,2]
	r._coach_entry(r._bandit(0))
	r._next_reaction()
	_check(r.phase == "reaction" and r.get_view(1).options.size() == 2 and r.get_view(2).options.is_empty(),"Выбор заложника доступен только владельцу")
	_check(r.action(1,"choose",{"serial":r.serial,"index":1},false),"Можно выбрать второго заложника")
	_check(r._bandit(0).hostage == 2 and r.coach_hostages == [1],"Выбранный заложник ушёл из общего списка")
	for id in range(17,43):
		_check(FileAccess.file_exists("res://games/colt_express/art/round_%d.webp" % id),"Отсутствует карта дополнения")
