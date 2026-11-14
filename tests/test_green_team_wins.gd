extends SceneTree
## Проверка правил Green Team Wins и наличия всех переводов.
const Rules := preload("res://games/green_team_wins/logic/gtw_rules.gd")
var errors := 0

func _initialize() -> void:
	var x := Rules.new()
	x.new_game([{}, {}, {}, {}])
	x.cards[0] = "three_00"
	var cards: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/green_team_wins/logic/translations.json"))
	check(cards.size() == 210,"Переведены не все карты")
	for key: String in cards:
		check(not str(cards[key]).is_empty() and FileAccess.file_exists("res://games/green_team_wins/art/"+key+".webp"),"Неполная карта: "+key)
	x.cards[1] = "three_01"
	x.cards[2] = "blank_02"
	answer(x,["1","1","1","2"])
	check(x.score == [1,1,1,0],"Вход в зелёную команду")
	x.action(0,"next",{"round":0},true)
	answer(x,["1","1","2","2"])
	check(x.score == [3,3,3,0],"Ничья даёт очки только зелёным")
	x.action(0,"next",{"round":1},true)
	answer(x,["Кот","Котик","Пёс","Хомяк"])
	check(not x.action(1,"merge",{"round":2,"from":1,"into":0},false),"Клиент смог объединить ответы")
	check(x.action(0,"merge",{"round":2,"from":1,"into":0},true),"Объединение не работает")
	x.action(0,"score",{"round":2},true)
	check(x.score == [5,5,3,0],"Подсчёт объединённых ответов")
	x.action(0,"next",{"round":2},true)
	for i in range(3,15):
		var blank: bool = x.cards[i].begins_with("blank")
		answer(x,["один","два","три","четыре"] if blank else ["1","1","1","1"])
		if blank:
			x.action(0,"score",{"round":i},true)
			check(not x.green.has(true),"Уникальные ответы должны сбросить команды")
		x.action(0,"next",{"round":i},true)
	check(x.phase == "end" and not x.results.is_empty(),"Нет финала после 15-го вопроса")
	print("Green Team Wins: проверены 15 вопросов и 210 переводов, ошибок ",errors)
	quit(1 if errors else 0)

func answer(x: Rules, values: Array) -> void:
	for s in values.size():
		check(x.get_view(s).answers.is_empty(),"До раскрытия видны ответы")
		check(x.action(s,"answer",{"round":x.turn_no,"answer":values[s]},false),"Ответ отклонён")

func check(pass_test: bool,message: String) -> void:
	if not pass_test:
		errors += 1
		printerr(message)
