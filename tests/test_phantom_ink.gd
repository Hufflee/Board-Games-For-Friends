extends SceneTree
## Проверка правил, секретности и случайных полных сеансов.
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func fresh(seed_value: int = 1) -> PIRules:
	var game := PIRules.new()
	game.new_game([{"name":"А"},{"name":"Б"},{"name":"В"},{"name":"Г"}], [0,1,2,3], seed_value)
	return game
func start(game: PIRules) -> void:
	check(game.action(1, "object", 2), "Солнце выбирает предмет")
	check(game.action(3, "object", 2), "Луна согласна")
func _initialize() -> void:
	check(PIData.validate([0,1,2,3],4) == "", "Роли верны")
	check(PIData.validate([0,1,2,2],4) != "", "Дух каждой команде")
	var g := fresh()
	check(g.hands[0].size()==7 and g.hands[1].size()==7, "Начальная рука")
	check(not g.action(0,"object",2), "Медиум не выбирает предмет")
	g.action(1,"object",1)
	g.action(3,"object",2)
	check(g.phase=="object", "Духи согласуют слово")
	g.action(1,"object",2)
	check(g.phase=="turn", "Начало после согласования")
	for seat in [-1,0,2]:
		check(g.get_view(seat,true).object_card == -1, "Предмет скрыт от медиумов и зрителя")
	check(g.get_view(-1).hand.is_empty(), "У зрителя нет чужой руки")
	var q: Array = g.hands[0].slice(0,2)
	check(not g.action(2,"ask",q),"Противник не ходит за Солнце")
	check(g.action(0,"ask",q),"Предложены вопросы")
	check(g.get_view(2).offered.is_empty(),"Вопросы скрыты от соперника")
	check(g.action(1,"question",q[0]),"Дух выбирает вопрос")
	check(g.discard.has(q[1]),"Отклонённый вопрос открыт")
	check(not g.action(1,"clue","42!"),"Запрещены цифры и знаки")
	check(g.action(1,"clue","Мороз"),"Дух пишет")
	check(not str(g.get_view(0)).contains('Мороз'),"Полный ответ не передаётся")
	g.tick(1.0)
	check(g.rows[0][0].text=="М","Первая буква")
	check(not g.get_view(2).rows[0][0].has("question"),"Вопрос не раскрывается сопернику")
	check(not g.get_view(0).rows[0][0].has("full"),"Полный ответ скрыт от своего медиума")
	check(g.action(0,"silence"),"Тишина прерывает письмо")
	check(g.hands[0].size()==7,"Добор двух вопросов")
	check(g.rows[0][0].text=="М" and not g.rows[0][0].complete,"Остался фрагмент")
	check(g.action(2,"guess_begin"),"Луна угадывает")
	check(g.action(2,"letter","К"),"Буква догадки")
	check(not g.action(2,"judge",true),"Медиум не судит себя")
	check(g.action(3,"judge",false),"Дух отклоняет букву")
	check(g.rows[1][0].wrong and g.team==0,"Ошибка завершает ход")
	g.phase="eye"
	check(g.action(0,"eye",[0,0]),"Око своей команды")
	check(g.rows[0][0].text=="МО","Око дописывает одну букву")
	g.phase="eye";g.team=1
	check(g.action(2,"eye",[0,0]),"Око соперника")
	check(g.rows[0][0].text=="МОР","Око соперника даёт следующую букву")
	g.phase="turn"
	check(g.action(2,"refresh"),"Разрешена замена руки")
	check(not g.action(2,"refresh"),"Замена только один раз")
	g.action(2,"guess_begin");g.action(2,"letter","К");g.action(3,"judge",true)
	g.action(2,"letter",".");g.action(3,"judge",true)
	check(g.phase=="game_over" and g.winner==1,"Угаданный предмет приносит победу")
	for seed_value in range(1,101):
		g=fresh(seed_value);start(g)
		var steps:=0
		while g.phase!="game_over" and steps<500:
			steps+=1
			var actor:=g.actor()
			match g.phase:
				"eye": g.action(actor,"eye_skip")
				"turn":
					if steps%3==0:
						g.action(actor,"guess_begin")
					else:
						g.action(actor,"ask",g.hands[g.team].slice(0,2))
				"question":g.action(actor,"question",g.offered[0])
				"clue":g.action(actor,"clue","Лёд")
				"writing":
					if steps%2==0 and not str(g.rows[g.team].back().text).is_empty():
						g.action(actor,"silence")
					else:g.tick(1.0)
				"guess":g.action(actor,"letter","Я")
				"judge":g.action(actor,"judge",false)
			for seat in [-1,0,1,2,3]:
				var v:=g.get_view(seat)
				check(not str(v.rows).contains('"full"'),"Секретная строка не попала в view")
			check(g.hands[0].size()<=7 and g.hands[1].size()<=7,"Рука не превышает 7")
		check(g.phase=="game_over" and g.winner==-1,"После 16 неудачных ходов обе команды проиграли")
		check(g.rows[0].size()==8 and g.rows[1].size()==8,"По 8 строк")
	for i in PIData.QUESTIONS:
		check(ResourceLoader.exists("res://games/phantom_ink/art/cards/q%d.webp"%i),"Карта вопроса")
		check(PIData.question(i).contains("?"),"Текст вопроса")
	for i in PIData.OBJECTS:
		check(ResourceLoader.exists("res://games/phantom_ink/art/cards/o%d.webp"%i),"Карта предметов")
	print("PHANTOM INK: %d проверок, %d ошибок" % [checks,failures])
	quit(0 if failures==0 else 1)
