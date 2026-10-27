extends SceneTree
## Открытые ответы без таймера: любой игрок до следующего действия активного.
var checks := 0
var errors := 0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: errors+=1; push_error(message)
func make() -> FSRules:
	var game:=FSRules.new()
	game.new_game([{"name":"Первый"},{"name":"Второй"},{"name":"Третий"},{"name":"Четвёртый"}],false,77)
	preload("res://tests/fs_test_setup.gd").finish(game)
	game.current=0;game.phase="turn";game.stack=[];game.next_action={}
	for i in 4: game.character_ready[i]=true;game.dead[i]=false
	return game
func _initialize() -> void:
	var g:=make()
	var coins:=FSData.pool("loot",false).filter(func(id):return FSData.card(int(id)).lua.get("type","")=="1c")
	for i in 4:g.hands[i]=[coins[i]]
	check(g.action(2,"loot",{"card":coins[2]}),"Неактивный игрок может начать ответ")
	check(g.action(1,"loot",{"card":coins[1]}),"Любой другой игрок может ответить без последовательного паса")
	check(g.phase=="priority" and g.stack.size()==2,"Окно остаётся открытым без таймера")
	check(not g.action(3,"end"),"Только активный игрок завершает ожидание следующим действием")
	check(not g.action(g.priority,"pass"),"Ручного подтверждения стека нет и в сетевых действиях")
	var money1:int=g.coins[1];var money2:int=g.coins[2]
	check(g.action(0,"end"),"Следующее действие активного закрывает окно")
	check(g.current==1 and g.phase=="turn" and g.stack.is_empty(),"Предыдущие эффекты завершены до перехода хода")
	check(g.coins[1]==money1+1 and g.coins[2]==money2+1,"Ответы обоих игроков выполнены")
	g=make();g.items[2]=[{"id":822,"tapped":false,"eternal":true,"counters":0}]
	check(g.action(2,"activate",{"item":0}),"Вечный предмет разыгрывается в чужой ход")
	check(g.action(0,"end") and g.phase=="effect" and g.current==0,"Ручной эффект не пропускается следующим действием")
	check(g.action(2,"effect_done") and g.current==1,"После ручного эффекта выполняется отложенное действие")
	g=make();g.monsters[0].hp=99
	check(g.action(0,"attack",{"slot":0}),"Объявлена атака")
	check(g.action(0,"roll") and g.stack.back().kind=="roll","Первый ручной бросок завершает объявление атаки")
	check(g.action(0,"roll") and g.stack.back().kind=="roll","Следующий бросок завершает предыдущий бросок и боевой урон")
	check(g.roll_no==2,"На две попытки игрока приходится два броска")
	g=make();g.hands[1]=[636]
	check(not g.action(1,"loot",{"card":636}),"Солнце требует своего хода")
	check(FSData.response_kind(822)=="tap" and FSData.response_kind(838)=="passive","Вечные предметы различаются по тексту карты")
	check(FSData.response_kind(843)=="hybrid" and FSData.response_kind(853)=="paid","Смешанные и платные способности")
	check(FSData.response_kind(94)=="paid" and FSData.response_kind(257)=="tap","Особые сокровища с активной способностью")
	print("FS RESPONSES: %d проверок, %d ошибок"%[checks,errors]);quit(1 if errors else 0)
