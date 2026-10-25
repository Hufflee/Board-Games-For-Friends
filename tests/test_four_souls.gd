extends SceneTree
## Наборы карт, закрытые руки, восемь мест, стек, бой, смерть и ручные эффекты Four Souls.
var checks := 0
var errors := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
func make(count: int = 8, dlc: bool = false, seed_value: int = 1) -> FSRules:
	var players := []
	for i in count: players.append({"name":"Игрок %d" % i})
	var game := FSRules.new(); game.new_game(players,dlc,seed_value); return game
func drain(g: FSRules) -> void:
	var limit := 0
	while g.phase in ["priority","effect"] and limit < 500:
		limit += 1
		if g.phase == "priority": g._resolve_top()
		elif g.phase == "effect":
			if g.resolving.kind == "event" and str(FSData.card(int(g.resolving.card)).lua.get("type",""))=="curse": g.action(g.actor(),"effect",{"op":"attach_curse","target":g.actor()})
			check(g.action(g.actor(),"effect_done"),"Эффект разрешается")
	check(limit < 500,"Стек завершается")
func _initialize() -> void:
	check(FSData.pool("loot",false).size()==154,"Лут базы точно повторяет третий мод")
	check(FSData.pool("treasure",false).size()==158,"Сокровища базы точно повторяют третий мод")
	check(FSData.pool("monster",false).size()==123,"Монстры базы точно повторяют третий мод")
	check(FSData.pool("event",false).size()==34,"События базы точно повторяют третий мод")
	check(FSData.pool("room",false).is_empty(),"Комнаты исключены без DLC")
	check(FSData.pool("bonus",false).size()==3,"В базе три бонусные души")
	check(FSData.pool("loot",true).size()==222 and FSData.pool("treasure",true).size()==258,"Расширенные карты включены")
	check(FSData.data().unmatched_baseline.is_empty(),"Все карты базового состава сопоставлены")
	for kind in ["loot","monster","treasure","event","character","eternal"]:
		for id in FSData.pool(kind,false): check(FSData.card(id).base,"DLC не просочилось в базу")
	var g := make()
	check(g.players.size()==8 and g.chars.size()==8,"Восемь мест")
	check(g.chars.duplicate().size()==8,"Персонажи выданы всем")
	check(g.monsters.size()==2 and g.shop.size()==2,"Два монстра и два сокровища")
	check(g.bank==76,"Общий банк после раздачи восьми игрокам")
	for seat in 8:
		check(g.coins[seat]==3 and g.items[seat].size()==1 and g.items[seat][0].eternal,"Начальные ресурсы и вечный предмет")
		check(g.hands[seat].size()==(4 if seat==g.current else 3),"Начальная рука и добор активного игрока")
		check(g.get_view(seat).hand==g.hands[seat],"Игрок видит свою руку")
		check(not g.get_view(seat).has("hands"),"Чужие руки не передаются")
	check(g.get_view(-1,true).hand.is_empty(),"Зритель не видит руку")
	check(not g.action((g.current+1)%8,"end"),"Чужой ход нельзя закончить")
	check(not g.action(g.current,"roll"),"Нельзя бросать вне боя")
	check(not g.action(g.current,"effect",{"op":"souls","amount":4}),"Нельзя менять ресурсы вне эффекта")
	g.phase="effect";g.resolving={"owner":g.current,"kind":"item","card":g.items[g.current][0].id}
	check(g.action(g.current,"effect",{"op":"peek_loot","amount":3}),"Просмотр верхних карт")
	check(g.get_view(g.current).peek.cards.size()==3,"Просмотр доступен владельцу эффекта")
	check(g.get_view((g.current+1)%8).peek.is_empty(),"Секретный просмотр скрыт от соперника")
	check(not g.action((g.current+1)%8,"peek_take",{"card":g.peek.cards[0],"dest":"hand"}),"Соперник не забирает просмотренную карту")
	var top: int = int(g.peek.cards.back())
	check(g.action(g.current,"peek_take",{"card":top,"dest":"hand"}),"Карта из просмотра переходит в руку")
	check(g.hands[g.current].has(top) and not g.decks.loot.has(top),"Карта не дублируется")
	check(not g.action(g.current,"effect",{"op":"destroy","target":g.current,"item":0}),"Вечный предмет защищён")
	var resolving_card: int = int(g.resolving.card)
	check(g.action(g.current,"effect_roll"),"Бросок по карте начинается вручную")
	check(g.phase=="priority" and g.stack.back().kind=="effect_roll","На бросок по карте можно ответить")
	while g.phase=="priority": g._resolve_top()
	check(g.phase=="effect" and int(g.resolving.card)==resolving_card,"После броска продолжается исходная карта")
	check(g.last_roll>=1 and g.last_roll<=6 and g.paused_effects.is_empty(),"Результат ручного броска корректен")
	var overlay := make(2)
	var base_id: int = int(overlay.monsters[1].id)
	var top_monster: int = int(FSData.pool("monster",false)[0])
	overlay.decks.monster.erase(top_monster); overlay.decks.monster.append(top_monster)
	check(overlay.action(overlay.current,"attack",{"slot":-1,"over":1}),"Атака верха колоды")
	while overlay.phase=="priority":overlay._resolve_top()
	check(overlay.monsters.size()==2 and int(overlay.monsters[1].get("under",{}).get("id",-1))==base_id,"Новый монстр накрывает выбранного, не добавляя слот")
	overlay.monsters[1].hp=1;overlay.monsters[1].dc=1
	overlay.action(overlay.current,"roll")
	while overlay.phase=="priority":overlay._resolve_top()
	overlay.action(overlay.actor(),"effect_done")
	check(overlay.monsters.size()==2 and int(overlay.monsters[1].id)==base_id,"После убийства верхнего открывается нижний монстр")
	g = make(2)
	var who := g.current
	g.coins[who]=20
	check(g.action(who,"buy",{"slot":0}),"Покупка")
	drain(g)
	check(g.coins[who]==10 and g.items[who].size()==2,"Цена покупки 10 монет")
	check(not g.action(who,"buy",{"slot":1}),"Только одна покупка за ход")
	g.monsters[0].dc=1;g.monsters[0].hp=1
	check(g.action(who,"attack",{"slot":0}),"Объявлена атака")
	while g.phase=="priority":g._resolve_top()
	check(g.action(who,"roll"),"Бросок атаки")
	check(g.phase=="priority" and g.stack.back().kind=="roll","На бросок можно ответить")
	while g.phase=="priority": g._resolve_top()
	check(g.phase=="effect" and g.resolving.kind=="reward","Убитый монстр даёт панель награды")
	check(g.action(who,"effect",{"op":"souls","amount":1}),"Награда души по тексту карты")
	g.action(who,"effect_done")
	drain(g)
	check(g.monsters.size()>=2,"Место монстра заполнено")
	g = make(2);who=g.current;g.hp[who]=0;g._check_deaths()
	var hand_count: int = g.hands[who].size()
	while g.phase=="priority":g._resolve_top()
	check(g.phase=="death","Смерть требует штрафа")
	check(g.action(who,"death",{"loot":g.hands[who][0],"item":-1}),"При одном вечном предмете уничтожение не требуется")
	check(g.coins[who]==2 and g.hands[who].size()==hand_count-1,"Штраф за смерть")
	check(g.items[who].size()==1 and g.items[who][0].eternal,"Вечный предмет сохранён")
	var rescue := make(2)
	var dying := rescue.current
	rescue.hp[dying]=0; rescue._check_deaths()
	var helper := rescue.actor()
	check(rescue.action(helper,"activate",{"item":0,"tap":true}),"На смерть можно ответить предметом")
	while rescue.phase=="priority": rescue._resolve_top()
	check(rescue.phase=="effect","Ответ на смерть разрешается первым")
	rescue.action(helper,"effect",{"op":"heal","target":dying,"amount":1})
	rescue.action(helper,"effect_done")
	while rescue.phase=="priority":rescue._resolve_top()
	check(rescue.phase=="turn" and rescue.hp[dying]==1 and rescue.coins[dying]==3,"Спасённый не получает штраф смерти")
	var other_death := make(2)
	var victim := (other_death.current+1)%2
	other_death.hp[victim]=0;other_death._check_deaths()
	while other_death.phase=="priority":other_death._resolve_top()
	check(other_death.action(victim,"death",{"loot":other_death.hands[victim][0],"item":-1}),"Штраф погибшего вне своего хода")
	check(other_death.phase=="turn" and other_death.dead[victim],"Чужая смерть не оставляет пустого стека ответов")
	for count in [2,4,8]:
		for expanded in [false,true]:
			for seed_value in range(1,31):
				g=make(count,expanded,seed_value)
				for turn in 4:
					who=g.current
					if not g.hands[who].is_empty():
						check(g.action(who,"loot",{"card":g.hands[who][0]}),"Лут разыгрывается")
						drain(g)
					if g.phase=="turn":g.action(g.current,"end")
					while g.phase=="discard":g.action(g.current,"discard",{"card":g.hands[g.current][0]})
					check(g.phase=="turn","После эффектов и конца хода игра продолжается")
					for seat in count:check(g.coins[seat]>=0 and g.souls[seat]>=0,"Ресурсы неотрицательные")
					var total: int = g.bank
					for value in g.coins: total += int(value)
					check(total==100,"В банке и у игроков ровно 100 монет")
				g.phase="effect";g.resolving={"kind":"item","owner":0,"card":g.items[0][0].id}
				check(g.action(0,"effect",{"op":"souls","amount":4}),"Победная душа")
				check(g.phase=="game_over" and g.winner==0,"Четыре души приносят победу")
	print("FOUR SOULS: %d проверок, ошибок: %d" % [checks,errors])
	quit(1 if errors else 0)
