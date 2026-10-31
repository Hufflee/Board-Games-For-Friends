extends SceneTree
## Тесты необязательных методов «Панели хоста» в правилах игр:
## host_stats / host_set_stat / host_give_card / host_hand / host_take_card / host_new_theme.
## Запуск: godot --headless --audio-driver Dummy --path . --script res://tests/test_host_hooks.gd

var failures := 0
var checks := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _init() -> void:
	_poker()
	_hues()
	_wavelength()
	_word_slam()
	_dangerous_words()
	_brodilka()
	_gloom()
	_king_of_12()
	_not_a_hat()
	_tip_top()
	_khorom()
	_stillion()
	_ready_set_bet()
	_the_gang()
	_things_in_rings()
	_perudo()
	print("Проверок: %d, ошибок: %d" % [checks, failures])
	quit(1 if failures > 0 or checks == 0 else 0)


func _names(n: int) -> Array:
	var out := []
	for i in n:
		out.append({"name": "И%d" % i})
	return out


func _teams(n: int) -> Array:
	var out := []
	for i in n:
		out.append({"name": "И%d" % i, "team": i % 2})
	return out


func _stat(rules: Object, seat: int, key: String) -> Dictionary:
	for s: Dictionary in rules.host_stats(seat):
		if str(s.key) == key:
			return s
	return {}


func _poker() -> void:
	var r: Object = load("res://games/poker/logic/pk_rules.gd").new()
	r.new_game(_names(3), {"mode": "sport", "seed": 7})
	check(not _stat(r, 1, "stacks").is_empty() and not _stat(r, 1, "scores").is_empty(), "покер: фишки и очки (спорт)")
	check(r.host_set_stat(1, "stacks", 555) and int(r.stacks[1]) == 555, "покер: фишки меняются")
	check(r.host_set_stat(1, "scores", 4) and int(r.scores[1]) == 4, "покер: очки меняются")
	check(not r.host_set_stat(1, "nope", 1), "покер: неизвестный ключ — false")


func _hues() -> void:
	var r: Object = load("res://games/hues_and_cues/logic/hc_rules.gd").new()
	r.new_game(_names(3), 1, false, 7)
	check(r.host_set_stat(2, "scores", 9) and int(r.scores[2]) == 9, "hues: очки меняются")
	var g: int = r.giver
	r.pick_color(g, int(r.card[0]))
	check(r.phase == "cue1" and r.host_new_theme() and r.phase == "pick" and r.target == -1, "hues: новая цель до подсказки")
	r.pick_color(g, int(r.card[0]))
	r.give_cue(g, "закат")
	check(not r.host_new_theme(), "hues: после подсказки цель не меняется")


func _wavelength() -> void:
	var r: Object = load("res://games/wavelength/logic/wl_rules.gd").new()
	r.new_game(_teams(4), false, 11)
	check(r.host_set_stat(1, "score", 6) and int(r.scores[1]) == 6 and int(r.scores[0]) == 0, "wavelength: очки команды игрока")
	check(r.host_new_theme() and r.phase == "card", "wavelength: новая карточка до подсказки")
	r.choose_side(r.psychic, 0)
	r.give_clue(r.psychic, "тест")
	check(not r.host_new_theme(), "wavelength: после подсказки нельзя")


func _word_slam() -> void:
	var r: Object = load("res://games/word_slam/logic/ws_rules.gd").new()
	r.new_game(_teams(4), false, 5, false, true, 9)
	var left: int = r.deck.size()
	check(r.host_set_stat(0, "scores", 3) and int(r.scores[0]) == 3, "word slam: очки команды")
	check(r.host_new_theme() and r.phase == "word" and r.deck.size() == left, "word slam: новая карта, колода той же длины")


func _dangerous_words() -> void:
	var r: Object = load("res://games/dangerous_words/logic/dw_rules.gd").new()
	r.new_game(_teams(4), [3, 4, 5, 6, 7], "troll", false, 5, false)
	check(r.phase == "traps" and r.host_new_theme() and str(r.secret[0]) != "", "опасные слова: новые слова на фазе ловушек")
	r.ready[0] = true
	check(not r.host_new_theme(), "опасные слова: после «Готово» нельзя")


func _brodilka() -> void:
	var r: Object = load("res://games/brodilka/logic/br_rules.gd").new()
	r.new_game(_names(3), 7)
	check(r.host_set_stat(1, "coins", 42) and int(r.coins[1]) == 42, "бродилка: монеты")
	var got: Variant = r.host_give_card(1)
	check(got != null and r.host_hand(1).has(got), "бродилка: карта Лавки выдана")
	var back: Variant = r.host_take_card(1, [got])
	check(back == got and r.host_hand(1).is_empty() and int(r.deck_shop[0]) == int(got), "бродилка: карта ушла под низ колоды")


func _gloom() -> void:
	var r: Object = load("res://games/gloom/logic/gl_rules.gd").new()
	r.new_game(_names(3), 7, ["base"])
	var before: int = r.host_hand(0).size()
	var got: Variant = r.host_give_card(0)
	check(got != null and r.host_hand(0).size() == before + 1, "gloom: карта из колоды в руку")
	var back: Variant = r.host_take_card(0, [got])
	check(back == got and r.host_hand(0).size() == before and r.deck[0] == got, "gloom: забрана нужная карта (из prefer)")


func _king_of_12() -> void:
	var cards: Variant = load("res://games/king_of_12/logic/cards.gd")
	var deck: Array[String] = []
	deck.append_array(cards.BASE)
	var r: Object = load("res://games/king_of_12/logic/rules.gd").new()
	r.new_game(_names(3), deck, 5)
	check(r.host_set_stat(0, "points", 5) and r.points(0) == 5, "король 12: очки раунда через жетоны")
	var size: int = r.host_hand(1).size()
	var taken: Variant = r.host_take_card(1, [])
	check(taken != null and r.host_hand(1).size() == size - 1 and r.discards[1].has(taken), "король 12: карта ушла в сброс")
	check(r.host_give_card(1) == taken and r.host_hand(1).size() == size, "король 12: карта вернулась из сброса")


func _not_a_hat() -> void:
	var r: Object = load("res://games/not_a_hat/logic/nh_rules.gd").new()
	r.new_game(_names(3), 1, 7)
	check(r.host_set_stat(2, "penalties", 2) and r.penalties[2].size() == 2, "не шляпа: штрафные карты")
	check(r.host_take_card(0, []) == null, "не шляпа: последний подарок не забирается")
	var got: Variant = r.host_give_card(0)
	check(got != null and r.host_hand(0).size() == 2 and r.host_take_card(0, [got]) == got, "не шляпа: подарок выдан и забран")


func _tip_top() -> void:
	var r: Object = load("res://games/tip_top/logic/tt_rules.gd").new()
	r.new_game(_names(4), false, false, 5)
	var total: int = r.unicorns + r.poops
	check(r.host_set_stat(0, "unicorns", 2) and r.unicorns == 2 and r.unicorns + r.poops == total, "тип-топ: единороги, всего жетонов столько же")
	check(r.host_new_theme() and r.phase == "theme" and r.theme == -1, "тип-топ: новая карточка тем")


func _khorom() -> void:
	var r: Object = load("res://games/khorom/logic/kh_rules.gd").new()
	r.new_game(_names(3), {"seed": 7, "rounds": 3, "timer": 90})
	check(r.host_set_stat(1, "banked", 7) and r.score(1) == 7, "хором: очки прошлых раундов")
	r.write(0, 0, "ответ")
	check(r.host_new_theme() and str(r.answers[0][0]) == "", "хором: новая тема стирает ответы")


func _stillion() -> void:
	var r: Object = load("res://games/stillion/logic/st_rules.gd").new()
	r.new_game(_names(3), false, 7)
	var q: int = r.q_no
	check(r.host_set_stat(0, "lives", 5) and int(r.players[0].lives) == 5, "столлион: жизни")
	check(r.host_new_theme() and r.q_no == q + 1, "столлион: новый вопрос")


func _ready_set_bet() -> void:
	var r: Object = load("res://games/ready_set_bet/logic/rsb_rules.gd").new()
	r.new_game(_names(3), 5)
	check(r.host_set_stat(1, "money", 120) and int(r.money[1]) == 120, "ready set bet: деньги")


func _the_gang() -> void:
	var r: Object = load("res://games/the_gang/logic/tg_rules.gd").new()
	r.new_game(_names(3), 91)
	check(r.host_set_stat(0, "vaults", 9) and r.vaults == 2, "банда: сейфы, граница 2")


func _things_in_rings() -> void:
	var r: Object = load("res://games/things_in_rings/logic/tr_rules.gd").new()
	var pools := {"Attribute": [300, 301, 302, 303], "Word": [200, 201, 202, 203], "Context": [400, 401, 402, 403]}
	check(r.new_game(_names(3), range(240), pools, {}, 29) == "", "кольца: партия создана")
	check(r.host_new_theme() and r.secret_rules.is_empty(), "кольца: новые варианты правил до раздачи")
	var k: int = r.knower
	for cat: String in r.rings:
		r.choose_rule(k, cat, int(r.rule_choices[cat][0]))
	r.begin_clues(k)
	var seeker := (k + 1) % 3
	var size: int = r.host_hand(seeker).size()
	var got: Variant = r.host_give_card(seeker)
	check(got != null and r.host_hand(seeker).size() == size + 1, "кольца: предмет выдан")
	check(r.host_take_card(seeker, [got]) == got and r.deck[0] == got, "кольца: предмет под низ колоды")
	check(r.host_give_card(k) == null, "кольца: знающему (не кооператив) карт не даём")
	check(r.host_new_theme() and r.secret_rules.size() == r.rings.size(), "кольца: поле пустое — правила сменились")
	r.clue(k, int(r.hands[k][0]), 0)
	check(not r.host_new_theme(), "кольца: на поле есть карта — правила не меняются")


func _perudo() -> void:
	var r: Object = load("res://games/perudo/logic/perudo_rules.gd").new()
	r.new_game(_names(3), 5, true, 42)
	r.begin()
	check(r.host_set_stat(1, "dice", 3) and r.counts[1] == 3 and r.dice[1].size() == 3, "перудо: кости в стакане")
	check(r.host_set_stat(1, "dice", 7) and r.dice[1].size() == 7, "перудо: кости добавлены")
