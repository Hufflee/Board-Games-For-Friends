extends SceneTree
## Разовая проверка (07.11): «Проклятие маленьких рук» 729 — выход из колоды, привязка, конец хода со сбросом.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")
const Inv := preload("res://games/four_souls/logic/fs_invariants.gd")
func _init() -> void:
	var t := Check.new()
	var s := Scenario.new(t).players(3).dlc().current(0).build()
	var g = s.g
	s._take(729)
	g._push({"kind": "event", "card": 729, "owner": 0}, "turn")
	s.close()
	print("после события: фаза ", g.phase, " выбор ", g.get_view(0).card_choices, " resolving ", g.resolving.get("card", -1))
	var view: Dictionary = g.get_view(0)
	for i in view.card_choices.size():
		if str(view.card_choices[i]).contains("Второй") or i == 0:
			pass
	if g.phase == "effect":
		var ok = g.action(0, "card_choice", {"index": 0, "revision": g.revision})
		print("выбор цели принят ", ok, " фаза ", g.phase)
		s.close()
	print("проклятия ", g.curses, " фаза ", g.phase, " проблемы ", Inv.check(g, true))
	var cursed := -1
	for seat in 3:
		if 729 in g.curses[seat]: cursed = seat
	g.current = cursed
	g.phase = "turn"
	g.hands[cursed].append_array([480, 481, 482])
	print("рука ", g.hands[cursed].size())
	var ended = g.action(cursed, "end")
	print("end принят ", ended, " фаза ", g.phase, " лимит ", g._discard_limit)
	var guard := 0
	while g.phase == "discard" and guard < 10:
		guard += 1
		print("  сброс ", g.action(cursed, "discard", {"card": int(g.hands[cursed][0])}), " фаза ", g.phase, " рука ", g.hands[cursed].size())
	s.close()
	print("итог фаза ", g.phase, " ходит ", g.current, " рука ", g.hands[cursed].size(), " проблемы ", Inv.check(g, true))
	print("ошибки проверки ", t.errors)
	quit()
