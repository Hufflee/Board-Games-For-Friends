extends SceneTree
## Независимые границы WS29: каталог не подменяет режим/колоду; лимиты sparse-рядов атомарны.
var checks := 0
func check(ok: bool) -> void:
	checks += 1
	if not ok:
		push_error("WS29 REVIEW: проверка %d" % checks)
		quit(1)
func _initialize() -> void:
	var players := [{"name":"А","team":0},{"name":"Б","team":0},{"name":"В","team":1},{"name":"Г","team":1}]
	for solo in [false, true]:
		for intro in [false, true]:
			var basic := WSRules.new()
			var simple := WSRules.new()
			basic.new_game(players, solo, 10 if intro else 21, intro, true, 928, "basic")
			simple.new_game(players, solo, 10 if intro else 21, intro, true, 928, "simplified")
			check(basic.mode == ("solo" if solo else "teams") and basic.mode == simple.mode)
			check(basic.deck == simple.deck and basic.card == simple.card and basic.word == simple.word)
			check(basic.names_on == not intro and simple.names_on == not intro)
			var old := basic.catalog_order.duplicate(true)
			for seat in basic.storytellers:
				basic.set_ready(seat)
			for seat in simple.storytellers:
				simple.set_ready(seat)
			check(basic.phase == "play" and simple.phase == "play" and basic.catalog_order != old and simple.catalog_order == old)
			var sparse := []
			sparse.resize(12)
			sparse.fill("")
			sparse[11] = "noun:0"
			var seat: int = basic.storytellers[0]
			check(basic.set_holders(seat, [sparse, []]) and basic.holders[0][0] == sparse)
			var before := basic.holders.duplicate(true)
			sparse.append("noun:1")
			check(not basic.set_holders(seat, [sparse, []]) and basic.holders == before)
	print("WS29 REVIEW BOUNDARIES: %d проверок, 0 ошибок" % checks)
	quit(0)
