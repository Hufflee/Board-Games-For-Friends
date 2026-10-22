class_name GLRules
extends RefCounted
## Движок Gloom (2-е издание) с дополнениями «Незваные гости» и «Неспокойные мертвецы».
## У каждого — семья из 5 персонажей; на них кладут прозрачные карты: свои — с несчастьями (минусы),
## чужим — с радостями (плюсы). Персонажа с отрицательным счётом можно убить картой безвременной
## смерти. Игра кончается, когда вымерла чья-то семья; побеждает самая низкая сумма очков мёртвых.
##
## Видны только верхние элементы: ячейка очков / иконки — от верхней карты, где она заполнена;
## постоянный эффект (текст) действует, пока карта лежит сверху; эффект со значком persist (нежить,
## гость) — пока виден этот значок в правом верхнем углу (его закрывает, например, смерть).
##
## Gloomier (набор gm): все 20 персонажей — из Хемлок-Холла, каждый по очереди выбирает себе 4 (фаза draft).
##
## Дополнения: гости (без хозяина в центре, «следуют» за картами из семьи в семью), истории
## (забираются действием, дают бонусы), нежить (модификатор оживляет мёртвого: персонаж и жив,
## и приносит очки).
##
## Фазы: trim (4–5 игроков: каждый откладывает персонажа) → play (2 действия) ⇄ prompt (кто-то
## выбирает) / react (можно ответить картой) → … → game_over.
## «Вы» на карте — тот, кто управляет персонажем, на которого её сыграли.

const HAND := 5
const MISFIT := 4  # пятый игрок — сборная семья из отложенных персонажей
## События без цели (кнопка «Сыграть»).
const FX_NO_TARGET := ["stormy", "root_of_evil", "extra_plays", "unlimited_plays_discard_each", "draw2_per_guest_play_any", "mod_on_dead", "everyone_removes_own_char", "midnight", "plot_twist", "whodunnit", "others_discard_family_icons", "dramatic"]
## События «цель + второй персонаж».
const FX_TWO := ["swap_top_mods", "swap_all_mods_with_guest", "move_guest_between", "swap_living_chars_with_opponent"]
const DRAFT_EACH := 4  # Gloomier: персонажей у каждого

var players: Array = []
var sets: Array = ["base"]
var fam: Array = []  # семья игрока: 0…3 или MISFIT
var chars: Array = []  # [{id, kind: char|guest, owner (-1 — без хозяина), stack: [карты], dead, removed}]
var stories: Array = []  # [{id, owner}]
var hands: Array = []
var deck: Array = []
var discard: Array = []  # верхняя — последняя
var removed: Array = []  # карты, удалённые из игры
var phase := "setup"
var current := 0
var plays_left := 2
var plays_used := 0
var ud_any := false  # «Старикам закон не писан»: смерть — любым действием
var ud_next := false  # «Сожжён на костре»: смерть можно сыграть вторым действием
var mod_dead := false  # «Вечеринка мертвеца»: один модификатор можно сыграть на мёртвого
var disc_each := false  # «В два раза ярче»: за каждую сыгранную карту — сбросить карту
var free := {}  # бесплатное действие: {cards: [], ud_only, guest_only, target, left, after}
var skip_draw: Array = []
var prompts: Array = []  # очередь выборов: {seat, kind: discard|give|refresh|pick_char|pick_discard, …}
var react := {}  # {play, kind: ud|event|card, eligible: [], passed: []}
var trim_left: Array = []
var draft_order: Array = []  # Gloomier: очередь выбора персонажей
var ending := false  # игрок закончил ход — после выборов добор и переход хода
var turn_no := 0
var log: Array = []
var finals: Array = []
var winners: Array = []
var rng := RandomNumberGenerator.new()


## card_sets: ["base"] — классика; ["base", "ug", "ud"] — с дополнениями (гости и истории);
## ["gm"] — Gloomier (выбор 4 персонажей); ["base", "ug", "ud", "gm"] — всё вместе.
func new_game(player_list: Array, seed_value: int = 0, card_sets: Array = ["base"]) -> void:
	players = player_list.duplicate(true)
	sets = card_sets.duplicate()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var n := players.size()
	var fams := [0, 1, 2, 3]
	_shuffle(fams)
	fam = []
	chars = []
	hands = []
	skip_draw = []
	var draft := not "base" in sets
	for s in n:
		fam.append(GLData.GLOOMIER if draft else (fams[s] if s < 4 else MISFIT))
		hands.append([])
		skip_draw.append(false)
		if s < 4 and not draft:
			for i in GLData.CHARS.size():
				if int(GLData.CHARS[i]["family"]) == fams[s]:
					chars.append(_new_char(i, "char", s))
	stories = []
	if expansions():
		var gs := range(GLData.GUESTS.size()).filter(func(i): return GLData.GUESTS[i]["set"] in sets)
		var ss := range(GLData.STORIES.size()).filter(func(i): return GLData.STORIES[i]["set"] in sets)
		_shuffle(gs)
		_shuffle(ss)
		if draft:
			# Gloomier: всего 2 карты — гости и/или истории вперемешку
			var pool := gs.map(func(g): return ["g", g]) + ss.map(func(x): return ["s", x])
			_shuffle(pool)
			for it in pool.slice(0, 2):
				if it[0] == "g":
					chars.append(_new_char(it[1], "guest", -1))
				else:
					stories.append({"id": it[1], "owner": -1})
		else:
			for g in gs.slice(0, 2):
				chars.append(_new_char(g, "guest", -1))
			for x in ss.slice(0, 2):
				stories.append({"id": x, "owner": -1})
	deck = []
	for i in GLData.CARDS.size():
		if GLData.CARDS[i]["set"] in sets:
			deck.append(i)
	_shuffle(deck)
	discard = []
	removed = []
	for s in n:
		_draw(s, HAND)
	current = rng.randi_range(0, n - 1)
	log = []
	finals = []
	winners = []
	prompts = []
	react = {}
	turn_no = 0
	trim_left = []
	draft_order = []
	if draft:
		for r in DRAFT_EACH:
			for k in n:
				draft_order.append((current + k) % n)
		phase = "draft"
	elif n >= 4:
		trim_left = [0, 1, 2, 3]
		phase = "trim"
	else:
		_start_play()


func expansions() -> bool:
	return "ug" in sets or "ud" in sets or "gm" in sets


## Gloomier: персонажи, которых ещё никто не взял.
func draft_left() -> Array:
	var taken := chars.filter(func(ch): return ch["kind"] == "char").map(func(ch): return int(ch["id"]))
	return range(GLData.CHARS.size()).filter(func(i): return int(GLData.CHARS[i]["family"]) == GLData.GLOOMIER and not i in taken)


func draft(seat: int, id: int) -> bool:
	if phase != "draft" or draft_order.is_empty() or seat != int(draft_order[0]) or not id in draft_left():
		return false
	chars.append(_new_char(id, "char", seat))
	draft_order.pop_front()
	if draft_order.is_empty():
		_start_play()
	return true


func auto_draft() -> void:
	if phase == "draft" and not draft_order.is_empty():
		var left := draft_left()
		draft(int(draft_order[0]), left[rng.randi_range(0, left.size() - 1)])


func _new_char(id: int, kind: String, own: int) -> Dictionary:
	return {"id": id, "kind": kind, "owner": own, "stack": [], "dead": false, "removed": false}


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func _start_play() -> void:
	_begin_turn(current)
	turn_no = 1


func _begin_turn(s: int) -> void:
	current = s
	plays_left = 2
	plays_used = 0
	ud_any = false
	ud_next = false
	mod_dead = false
	disc_each = false
	free = {}
	ending = false
	turn_no += 1
	phase = "play"
	var ic := _start_free_icon(s)
	if ic != "":
		free = {"cards": [], "mod_icon": ic, "target": -1, "left": 1}


## «Злодей-камердинер», «Последнее дело»: в начале хода — бесплатный модификатор с иконкой.
func _start_free_icon(s: int) -> String:
	for g in _guests_of(s):
		var a := GLData.fx_arg_in(GLData.GUESTS[int(chars[g]["id"])]["fx"], "free_mod_start")
		if a != "" and _guest_active(g):
			return a
	for st in stories:
		if int(st["owner"]) == s:
			var a := GLData.fx_arg_in(GLData.STORIES[int(st["id"])]["fx"], "free_mod_start")
			if a != "":
				return a
	return ""


# --- Персонажи ------------------------------------------------------------------------

func valid(c: int) -> bool:
	return c >= 0 and c < chars.size() and not chars[c]["removed"]


func alive(c: int) -> bool:
	return valid(c) and not chars[c]["dead"]


func owner(c: int) -> int:
	return int(chars[c]["owner"])


## Нижняя карта персонажа: у героя ячейки пусты, у гостя — свои очки и иконки.
func _base(c: int) -> Dictionary:
	if chars[c]["kind"] == "guest":
		return GLData.GUESTS[int(chars[c]["id"])]
	return {"pts": [null, null, null], "icons": ["", "", ""], "fx": []}


## Видимое значение ячейки очков k (0 — верх, 1 — середина, 2 — низ).
func slot(c: int, k: int) -> int:
	var st: Array = chars[c]["stack"]
	for i in range(st.size() - 1, -1, -1):
		var p = GLData.CARDS[st[i]]["pts"][k]
		if p != null:
			return int(p)
	var b = _base(c)["pts"][k]
	return int(b) if b != null else 0


func worth(c: int) -> int:
	return slot(c, 0) + slot(c, 1) + slot(c, 2)


## Видимая иконка в ячейке k: [иконка, откуда] (откуда — индекс в стопке, -1 — сам гость).
func icon_at(c: int, k: int) -> Array:
	var st: Array = chars[c]["stack"]
	for i in range(st.size() - 1, -1, -1):
		var ic: String = GLData.CARDS[st[i]]["icons"][k]
		if ic != "":
			return [ic, i]
	return [_base(c)["icons"][k], -1]


## Действующие эффекты персонажа: текст верхней карты + постоянный эффект (видимый значок persist).
func active_fx(c: int) -> Array:
	var out := []
	var st: Array = chars[c]["stack"]
	if not st.is_empty():
		out.append_array(GLData.CARDS[st[-1]]["fx"])
	var v := icon_at(c, 0)
	if v[0] == "persist":
		var src: Array = _base(c)["fx"] if v[1] < 0 else GLData.CARDS[st[v[1]]]["fx"]
		for f in src:
			if not f in out:
				out.append(f)
	return out


func is_undead(c: int) -> bool:
	if not valid(c):
		return false
	var v := icon_at(c, 0)
	return v[0] == "persist" and v[1] >= 0 and "undead" in GLData.CARDS[chars[c]["stack"][v[1]]]["fx"]


## Гость: карта гостя или персонаж с «Пока виден этот текст, этот персонаж считается гостем».
func is_guest(c: int) -> bool:
	return valid(c) and (chars[c]["kind"] == "guest" or "becomes_guest" in active_fx(c))


## Живой гость со своим постоянным эффектом (значок не закрыт).
func _guest_active(c: int) -> bool:
	return alive(c) and chars[c]["kind"] == "guest" and icon_at(c, 0) == ["persist", -1]


func icons(c: int) -> Array:
	var out := []
	for k in 3:
		var ic: String = icon_at(c, k)[0]
		if not ic in ["", "blank", "persist"]:
			out.append(ic)
	var always := GLData.fx_arg_in(active_fx(c), "always_icons")
	if always != "":
		for ic in always.split(","):
			out.append(ic)
	return out


func has_icon(c: int, ic: String) -> bool:
	return ic in icons(c)


## Сколько персонажей семьи (живых и мёртвых) показывают иконку.
func count_family_icon(s: int, ic: String) -> int:
	var k := 0
	for c in chars.size():
		if valid(c) and owner(c) == s and has_icon(c, ic):
			k += 1
	return k


func count_icon_in_play(ic: String) -> int:
	var k := 0
	for c in chars.size():
		if valid(c) and has_icon(c, ic):
			k += 1
	return k


func top(c: int) -> int:
	var st: Array = chars[c]["stack"]
	return int(st[-1]) if not st.is_empty() else -1


func top_mod(c: int) -> int:
	var t := top(c)
	return t if t >= 0 and GLData.CARDS[t]["t"] == "M" else -1


## Приносит ли персонаж очки в конце (мёртвый или нежить).
func scores(c: int) -> bool:
	return valid(c) and (chars[c]["dead"] or is_undead(c))


## Итог персонажа: очки + «приносит дополнительные −N», если подошла иконка.
func final_worth(c: int) -> int:
	var w := worth(c)
	var t := top(c)
	if chars[c]["dead"] and t >= 0:
		for key in ["extra10", "extra20"]:
			var need := GLData.fx_arg(t, key)
			if need != "":
				for ic in need.split(","):
					if has_icon(c, ic):
						w -= 10 if key == "extra10" else 20
						break
		if "extra10_if_guest" in GLData.CARDS[t]["fx"] and is_guest(c):
			w -= 10
	return w


## Сколько живых персонажей семьи s держат действующий эффект f.
func _top_fx_count(s: int, f: String) -> int:
	var k := 0
	for c in chars.size():
		if alive(c) and owner(c) == s and f in active_fx(c):
			k += 1
	return k


func owns_story(s: int, fx: String) -> bool:
	for st in stories:
		if int(st["owner"]) == s and fx in GLData.STORIES[int(st["id"])]["fx"]:
			return true
	return false


func hand_limit(s: int) -> int:
	var lim := HAND
	for c in chars.size():
		if not valid(c):
			continue
		var o := owner(c)
		var fx := active_fx(c)
		if alive(c):
			if o == s:
				lim += fx.count("limit+1") - fx.count("limit-1")
				var per := GLData.fx_arg_in(fx, "limit+per_family_icon")
				if per != "":
					lim += count_family_icon(s, per)
			if o == right_of(s) and "left_limit+1" in fx:
				lim += 1
			if o >= 0 and o != s and "opponents_limit+1" in fx:
				lim += 1
		elif top(c) >= 0:
			var tf: Array = GLData.CARDS[top(c)]["fx"]
			if o == s and "limit+1_if:coin" in tf and has_icon(c, "coin"):
				lim += 1
			if o == right_of(s) and "left_limit+1_if_coin" in tf and has_icon(c, "coin"):
				lim += 1
	for st in stories:
		if int(st["owner"]) == s:
			var fx: Array = GLData.STORIES[int(st["id"])]["fx"]
			for key in ["limit+per_family_icon", "limit+per_family_char"]:
				var a := GLData.fx_arg_in(fx, key)
				if a != "":
					lim += count_family_icon(s, a)
	return maxi(0, lim)


func _story_fx_arg(s: int, key: String) -> String:
	for st in stories:
		if int(st["owner"]) == s:
			var a := GLData.fx_arg_in(GLData.STORIES[int(st["id"])]["fx"], key)
			if a != "":
				return a
	return ""


func events_blocked(s: int) -> bool:
	return _top_fx_count(s, "no_events") > 0


func _controls_icon(s: int, ic: String) -> bool:
	for c in chars.size():
		if alive(c) and owner(c) == s and has_icon(c, ic):
			return true
	return false


func living_of(s: int) -> int:
	var k := 0
	for c in chars.size():
		if owner(c) == s and alive(c):
			k += 1
	return k


func _guests_of(s: int, living: bool = true) -> Array:
	var out := []
	for c in chars.size():
		if valid(c) and owner(c) == s and chars[c]["kind"] == "guest" and (alive(c) or not living):
			out.append(c)
	return out


## Рука под защитой («Не отдал душу»): никто не берёт и не сбрасывает её карты.
func _protected(s: int) -> bool:
	return _top_fx_count(s, "hand_protected") > 0


func right_of(s: int) -> int:
	return posmod(s - 1, players.size())


func left_of(s: int) -> int:
	return posmod(s + 1, players.size())


# --- Подготовка ----------------------------------------------------------------------

## 4–5 игроков: каждый из первых четырёх откладывает одного персонажа (при пятерых — пятому).
func trim(seat: int, c: int) -> bool:
	if phase != "trim" or not seat in trim_left or not valid(c) or owner(c) != seat or chars[c]["kind"] != "char":
		return false
	if players.size() >= 5:
		chars[c]["owner"] = 4
	else:
		chars[c]["removed"] = true
		chars[c]["owner"] = -1
	trim_left.erase(seat)
	if trim_left.is_empty():
		_start_play()
	return true


func auto_trim() -> void:
	for s in trim_left.duplicate():
		var mine := []
		for c in chars.size():
			if owner(c) == s and alive(c) and chars[c]["kind"] == "char":
				mine.append(c)
		trim(s, mine[rng.randi_range(0, mine.size() - 1)])


# --- Колода --------------------------------------------------------------------------

func _draw(s: int, n: int) -> Array:
	if n > 0 and owns_story(s, "draw_extra:1"):
		n += 1  # «Мрачные перспективы»: всегда на карту больше
	var got := []
	for i in n:
		if deck.is_empty():
			if discard.is_empty():
				break
			deck = discard.duplicate()
			discard = []
			_shuffle(deck)
		var c = deck.pop_back()
		hands[s].append(c)
		got.append(c)
	return got


func _discard_cards(s: int, cards: Array) -> void:
	for c in cards:
		if hands[s].has(c):
			hands[s].erase(c)
			discard.append(c)


func _random_cards(s: int, n: int) -> Array:
	var h: Array = hands[s].duplicate()
	_shuffle(h)
	return h.slice(0, mini(n, h.size()))


## Чужой эффект забирает n случайных карт из руки from в руку to (если рука не под защитой).
func _take_random(from: int, to: int, n: int) -> Array:
	if from < 0 or to < 0 or from == to or _protected(from):
		return []
	var got := _random_cards(from, n)
	for c in got:
		hands[from].erase(c)
		hands[to].append(c)
	return got


func _discard_random(s: int, n: int) -> void:
	if not _protected(s):
		_discard_cards(s, _random_cards(s, n))


## Соперник с самой большой (и не защищённой) рукой.
func _richest_opponent(s: int) -> int:
	var best := -1
	for o in players.size():
		if o != s and not _protected(o) and (best < 0 or hands[o].size() > hands[best].size()):
			best = o
	return best


# --- Ход -----------------------------------------------------------------------------

func _ud_allowed_on(seat: int, t: int, card: int = -1) -> bool:
	if ud_any or ud_next or plays_used == 0 or owns_story(seat, "ud_second"):
		return true
	var a := _story_fx_arg(seat, "ud_second_if")
	if a != "" and has_icon(t, a):
		return true
	if card >= 0:
		var b := GLData.fx_arg(card, "ud_second_if")
		if b != "" and has_icon(t, b):
			return true
	# «Усатик» в семье: смерть вторым действием — на персонажа со смертью или зверем
	for g in _guests_of(seat):
		var arg := GLData.fx_arg_in(GLData.GUESTS[int(chars[g]["id"])]["fx"], "ud_second_on")
		if arg != "" and _guest_active(g):
			for ic in arg.split(","):
				if has_icon(t, ic):
					return true
	return false


func ud_allowed() -> bool:
	return ud_any or ud_next or plays_used == 0 or owns_story(current, "ud_second")


func _free_covers(card: int, target: int) -> bool:
	if free.is_empty() or int(free.get("left", 0)) <= 0:
		return false
	var list: Array = free.get("cards", [])
	if not list.is_empty() and not list.has(card):
		return false
	if free.get("ud_only", false) and GLData.CARDS[card]["t"] != "D":
		return false
	if free.get("guest_only", false) and not is_guest(target):
		return false
	var mi: String = free.get("mod_icon", "")
	if mi != "" and not (GLData.CARDS[card]["t"] == "M" and mi in GLData.CARDS[card]["icons"]):
		return false
	var ft := int(free.get("target", -1))
	return ft < 0 or ft == target


## Гости в семье запрещают модификаторы с иконкой: Вдова — любовь, Полковник — зверь.
func _icon_blocked(t: int, card: int) -> bool:
	var o := owner(t)
	if o < 0:
		return false
	var ics: Array = GLData.CARDS[card]["icons"]
	for g in _guests_of(o):
		if not _guest_active(g):
			continue
		var fx: Array = GLData.GUESTS[int(chars[g]["id"])]["fx"]
		if ("no_heart_mods_on_family" in fx and "heart" in ics) or ("no_beast_mods_on_family" in fx and "beast" in ics):
			return true
	return false


## Свой гость с эффектом f.
func _own_guest_fx(s: int, f: String) -> bool:
	for g in _guests_of(s):
		if _guest_active(g) and f in GLData.GUESTS[int(chars[g]["id"])]["fx"]:
			return true
	return false


## На мёртвого можно класть модификаторы (под смерть): «Слухи были туманны», мадам Зора первым действием.
func _mods_on_dead_ok(seat: int, t: int, card: int) -> bool:
	if mod_dead or "undead" in GLData.CARDS[card]["fx"]:
		return true
	if top(t) >= 0 and "mods_under_ud" in GLData.CARDS[top(t)]["fx"]:
		return true
	return plays_used == 0 and _own_guest_fx(seat, "first_mod_on_dead")


func _resp_kind(card: int) -> String:
	return str(GLData.CARDS[card]["fx"][0]) if not GLData.CARDS[card]["fx"].is_empty() else ""


func _is_response_only(card: int) -> bool:
	return _resp_kind(card) in ["cancel_event", "remove_own_guest_cancel"]


## Можно ли сыграть карту так (без побочных эффектов).
func can_play(seat: int, card: int, target: int, extra: Dictionary = {}) -> bool:
	if phase != "play" or seat != current or not hands[seat].has(card):
		return false
	var use_free := _free_covers(card, target)
	if not use_free and plays_left <= 0:
		return false
	var cd: Dictionary = GLData.CARDS[card]
	match cd["t"]:
		"M":
			if not valid(target):
				return false
			if chars[target]["dead"] and not _mods_on_dead_ok(seat, target, card):
				return false
			var only := GLData.fx_arg_in(cd["fx"], "only_on")
			if only != "" and not has_icon(target, only):
				return false
			if _icon_blocked(target, card):
				return false
			if "owner_only_mods" in active_fx(target) and owner(target) != seat:
				return false
			return true
		"D":
			if not alive(target) or is_undead(target) or _own_guest_fx(seat, "no_ud_for_owner"):
				return false
			var any_worth := GLData.fx_arg_in(cd["fx"], "ud_any_worth_if")
			if worth(target) >= 0 and not (any_worth != "" and has_icon(target, any_worth)):
				return false
			if "no_ud_on_self" in active_fx(target):
				return false
			if "not_on:heart" in cd["fx"] and has_icon(target, "heart"):
				return false
			return use_free or _ud_allowed_on(seat, target, card)
		"E":
			if events_blocked(seat) or _is_response_only(card):
				return false
			return _event_valid(seat, card, target, extra, false)
	return false


## Подходит ли событие. partial — проверяется только первый шаг (для подсветки целей).
func _fx0(card: int) -> String:
	return _resp_kind(card).split(":")[0]


func _event_valid(seat: int, card: int, t: int, extra: Dictionary, partial: bool) -> bool:
	var f := _fx0(card)
	if f in FX_NO_TARGET:
		return true
	match f:
		"free_ud_or_remove_undead":
			return t < 0 or is_undead(t)
		"remove_top_mod":
			return alive(t) and top_mod(t) >= 0
		"remove_all_mods":
			return alive(t) and not chars[t]["stack"].is_empty()
		"remove_living_char":
			return alive(t)
		"second_chance":
			return valid(t) and chars[t]["dead"] and not (top(t) >= 0 and "permanent" in GLData.CARDS[top(t)]["fx"])
		"take_guest_from_family":
			return is_guest(t) and owner(t) >= 0 and owner(t) != seat
		"swap_hands":
			return valid(t) and owner(t) >= 0 and owner(t) != seat
		"swap_top_mod_from_hand":
			if not (alive(t) and top_mod(t) >= 0):
				return false
			if partial:
				return true
			var w := int(extra.get("with", -1))
			return w != card and hands[seat].has(w) and GLData.CARDS[w]["t"] == "M"
		"swap_top_mods", "swap_all_mods_with_guest", "move_guest_between", "swap_living_chars_with_opponent":
			if not _two_first(f, seat, t):
				return false
			return partial or _two_second(f, seat, t, int(extra.get("t2", -1)))
		"ud_from_discard":
			var pick := int(extra.get("pick", -1))
			if not discard.has(pick) or GLData.CARDS[pick]["t"] != "D" or not alive(t) or is_undead(t):
				return false
			if "not_on:heart" in GLData.CARDS[pick]["fx"] and has_icon(t, "heart"):
				return false
			var need := GLData.fx_arg(card, "ud_from_discard")
			return has_icon(t, need if need != "" else "heart") or worth(t) < 0
		"play_event_or_undead_from_discard":
			return _grave_ok(int(extra.get("pick", -1)))
		"claim_any_story_then_free_play":
			var st := int(extra.get("st", -1))
			return partial or _story_idx(st) >= 0 and int(stories[_story_idx(st)]["owner"]) != seat
	return false


func _two_first(f: String, seat: int, t: int) -> bool:
	match f:
		"swap_top_mods":
			return alive(t) and top_mod(t) >= 0
		"swap_all_mods_with_guest":
			return alive(t) and not is_guest(t)
		"move_guest_between":
			return alive(t) and is_guest(t) and owner(t) >= 0
		"swap_living_chars_with_opponent":
			return alive(t) and owner(t) >= 0 and owner(t) != seat
	return false


func _two_second(f: String, seat: int, t: int, t2: int) -> bool:
	if t2 == t or not valid(t2):
		return false
	match f:
		"swap_top_mods":
			return alive(t2) and top_mod(t2) >= 0
		"swap_all_mods_with_guest":
			return alive(t2) and is_guest(t2)
		"move_guest_between":
			return owner(t2) >= 0 and owner(t2) != owner(t)
		"swap_living_chars_with_opponent":
			return alive(t2) and owner(t2) == seat
	return false


## «Расхищение могил»: событие или модификатор-нежить из сброса.
func _grave_ok(pick: int) -> bool:
	if not discard.has(pick):
		return false
	var cd: Dictionary = GLData.CARDS[pick]
	return (cd["t"] == "E" and not _is_response_only(pick) and _fx0(pick) != "second_chance") or (cd["t"] == "M" and "undead" in cd["fx"])


func _story_idx(id: int) -> int:
	for i in stories.size():
		if int(stories[i]["id"]) == id:
			return i
	return -1


## Действие: сыграть карту card на персонажа target (extra — второй выбор для некоторых событий).
func play(seat: int, card: int, target: int, extra: Dictionary = {}) -> bool:
	if not can_play(seat, card, target, extra):
		return false
	var t: String = GLData.CARDS[card]["t"]
	if _free_covers(card, target):
		free["left"] = int(free["left"]) - 1
	else:
		plays_left -= 1
		plays_used += 1
	if t == "M" and chars[target]["dead"] and not "undead" in GLData.CARDS[card]["fx"]:
		mod_dead = false  # «Вечеринка мертвеца» — один раз
	hands[seat].erase(card)
	if disc_each:
		_ask(seat, "discard", 1)
	var p := {"card": card, "target": target, "extra": extra.duplicate(), "actor": seat}
	var eligible := _responders(seat, t)
	if t in ["D", "E"] or not eligible.is_empty():
		react = {"play": p, "kind": {"D": "ud", "E": "event"}.get(t, "card"), "eligible": eligible, "passed": []}
		phase = "react"
		return true
	_resolve(p)
	_after_action()
	return true


## Кто может ответить на карту типа t: «Второй шанс» — на смерть, «Напустить туману» — на событие,
## «Подозрительный отъезд» — на что угодно (нужен свой живой гость).
func _responders(seat: int, t: String) -> Array:
	var out := []
	if players.size() < 2 or owns_story(seat, "opp_no_events_my_turn"):
		return out
	for s in players.size():
		if s != seat and _response_card(s, t) >= 0:
			out.append(s)
	return out


func _response_card(s: int, t: String) -> int:
	for c in hands[s]:
		var k := _fx0(c)
		if (t == "D" and k == "second_chance") or (t == "E" and k == "cancel_event"):
			return c
	for c in hands[s]:
		if _fx0(c) == "remove_own_guest_cancel" and not _guests_of(s).is_empty():
			return c
	return -1


## Ответ на сыгранную карту: use — отменить своей картой.
func respond(seat: int, use: bool) -> bool:
	if phase != "react" or not seat in react["eligible"] or seat in react["passed"]:
		return false
	if not use:
		react["passed"].append(seat)  # окно закрывает хост (finish_react), чтобы по паузе не угадать, у кого ответ
		return true
	var p: Dictionary = react["play"]
	var resp := _response_card(seat, GLData.CARDS[p["card"]]["t"])
	if resp < 0:
		return false
	_discard_cards(seat, [resp])
	if _fx0(resp) == "remove_own_guest_cancel":
		var g: int = _guests_of(seat)[0]  # гость уезжает из игры
		chars[g]["removed"] = true
		discard.append_array(chars[g]["stack"])
		chars[g]["stack"] = []
	discard.append(p["card"])
	_log("%s отменяет «%s» картой «%s»" % [_pname(seat), GLData.card_name(p["card"]), GLData.card_name(resp)], seat)
	react = {}
	phase = "play"
	_after_action()
	return true


## Окно ответа закрылось — карта срабатывает.
func finish_react() -> void:
	if phase != "react":
		return
	var p: Dictionary = react["play"]
	react = {}
	phase = "play"
	_resolve(p)
	_after_action()


func discard_hand(seat: int) -> bool:
	if phase != "play" or seat != current or plays_left <= 0:
		return false
	plays_left -= 1
	plays_used += 1
	_discard_cards(seat, hands[seat].duplicate())
	_log("%s сбрасывает руку" % _pname(seat), seat)
	return true


## Можно ли забрать историю: у семьи видна иконка не меньше чем у STORY_NEED персонажей
## (и больше, чем у нынешнего владельца).
func can_claim(seat: int, st: int) -> bool:
	var i := _story_idx(st)
	if i < 0 or int(stories[i]["owner"]) == seat:
		return false
	var req: Array = GLData.STORIES[st]["req"]
	var o := int(stories[i]["owner"])
	for ic in req:
		var need := req.count(ic)
		if o >= 0:
			need = maxi(need, _story_count(o, ic) + 1)  # отобрать — нужно больше, чем у владельца
		if _story_count(seat, ic) < need:
			return false
	return true


func _story_count(s: int, req: String) -> int:
	return count_family_icon(s, req) + (1 if _top_fx_count(s, "story_wild_icon") > 0 else 0)


## Действие: забрать историю.
func claim(seat: int, st: int) -> bool:
	if phase != "play" or seat != current or plays_left <= 0 or not can_claim(seat, st):
		return false
	plays_left -= 1
	plays_used += 1
	_give_story(seat, st)
	_after_action()
	return true


func _give_story(seat: int, st: int) -> void:
	stories[_story_idx(st)]["owner"] = seat
	_log("%s забирает историю «%s»" % [_pname(seat), GLData.STORIES[st]["name"]], seat)
	var mine := stories.filter(func(x): return int(x["owner"]) == seat)
	if mine.size() > GLData.STORY_MAX:
		for x in mine:
			if int(x["id"]) != st:
				x["owner"] = -1  # больше двух — одна возвращается в центр
				break


## Пропустить бесплатную карту («Бурная ночка» и т. п.).
func skip_free(seat: int) -> bool:
	if phase != "play" or seat != current or free.is_empty():
		return false
	_end_free()
	_after_action()
	return true


func end_turn(seat: int) -> bool:
	if phase != "play" or seat != current:
		return false
	ending = true
	if not free.is_empty():
		_end_free()
	_after_action()
	return true


func _end_free() -> void:
	var after: String = free.get("after", "")
	var cards: Array = free.get("cards", [])
	free = {}
	match after:
		"discard_to_limit":
			var extra_cards: int = hands[current].size() - hand_limit(current)
			if extra_cards > 0:
				_ask(current, "discard", extra_cards)
		"discard_rest":
			_discard_cards(current, cards.filter(func(c): return hands[current].has(c)))


func _after_action() -> void:
	if phase == "game_over":
		return
	if not free.is_empty() and int(free.get("left", 0)) <= 0:
		_end_free()
	if _check_end():
		return
	if not prompts.is_empty():
		phase = "prompt"
		return
	phase = "play"
	if ending:
		_finish_turn()


## Добор в конце хода (с поправками нежити и гостей), затем ход левого соседа.
func _finish_turn() -> void:
	var s := current
	if skip_draw[s]:
		skip_draw[s] = false
	else:
		var n := maxi(0, hand_limit(s) - hands[s].size())
		if n > 0 and _top_fx_count(s, "draw_from_discard") > 0:
			while n > 0 and not discard.is_empty():
				hands[s].append(discard.pop_back())
				n -= 1
		var from_opp := _top_fx_count(s, "draw_one_from_chosen_opponent") > 0
		for g in _guests_of(s):
			if _guest_active(g) and "draw_from_opponent" in GLData.GUESTS[int(chars[g]["id"])]["fx"]:
				from_opp = true
		if n > 0 and from_opp:
			n -= _take_random(_richest_opponent(s), s, 1).size()
		if n > 0 and _own_guest_fx(s, "draw_from_discard_one") and not discard.is_empty():
			hands[s].append(discard.pop_back())
			n -= 1
		_draw(s, n)
	_begin_turn(left_of(s))


func _check_end() -> bool:
	for s in players.size():
		var has := false
		for c in chars.size():
			if owner(c) == s:
				has = true
				break
		if has and living_of(s) == 0:
			_finish_game()
			return true
	return false


func _finish_game() -> void:
	phase = "game_over"
	finals = []
	var best := 1 << 30
	for s in players.size():
		var total := 0
		for c in chars.size():
			if owner(c) == s and scores(c):
				total += final_worth(c)
		for st in stories:
			if int(st["owner"]) == s:
				for pv in GLData.STORIES[int(st["id"])]["pts"]:
					total += int(pv) if pv != null else 0
		var per_dead := _story_fx_arg(s, "final_per_dead")  # «heart:-15»
		if per_dead != "":
			var parts := per_dead.split(":")
			for c in chars.size():
				if valid(c) and owner(c) == s and chars[c]["dead"] and has_icon(c, parts[0]):
					total += int(parts[1])
		for g in _guests_of(s):
			var a := GLData.fx_arg_in(GLData.GUESTS[int(chars[g]["id"])]["fx"], "final_per_family_icon")
			if a != "" and _guest_active(g):
				total -= 10 * count_family_icon(s, a)
		if owns_story(s, "final_per_char:beast,duck"):
			for c in chars.size():
				if valid(c) and owner(c) == s and (has_icon(c, "beast") or has_icon(c, "duck")):
					total -= 10
		finals.append(total)
		best = mini(best, total)
	winners = []
	for s in players.size():
		if finals[s] == best:
			winners.append(s)


# --- Срабатывание карт ---------------------------------------------------------------

func _resolve(p: Dictionary) -> void:
	var card: int = p["card"]
	var actor: int = p["actor"]
	var tg: int = p["target"]
	var cd: Dictionary = GLData.CARDS[card]
	match cd["t"]:
		"M":
			var st: Array = chars[tg]["stack"]
			if "undead" in cd["fx"] and chars[tg]["dead"]:
				# нежить: смерть снимается, персонаж «и жив, и мёртв»
				if top(tg) >= 0 and GLData.CARDS[top(tg)]["t"] == "D":
					discard.append(st.pop_back())
				chars[tg]["dead"] = false
			if chars[tg]["dead"]:
				st.insert(st.size() - 1, card)  # на мёртвого — под карту смерти
			elif not st.is_empty() and "tuck_mods_without:beast" in GLData.CARDS[st[-1]]["fx"] and not "beast" in cd["icons"]:
				st.insert(st.size() - 1, card)  # «Спасён грызунами»: ложится под эту карту
			else:
				st.append(card)
			_log("%s: «%s» → %s" % [_pname(actor), cd["name"], _cname(tg)], actor)
			_mod_effects(card, tg, actor)
			_follow(card, tg)
			_story_triggers(card)
		"D":
			_kill(tg, card, actor)
			_follow(card, tg)
		"E":
			_event(card, tg, p["extra"], actor)


## «Чёрный котёнок», «Вот так ворон»: истории срабатывают на чужие модификаторы.
func _story_triggers(card: int) -> void:
	var ics: Array = GLData.CARDS[card]["icons"]
	for st in stories:
		var o := int(st["owner"])
		if o < 0:
			continue
		var fx: Array = GLData.STORIES[int(st["id"])]["fx"]
		var a := GLData.fx_arg_in(fx, "draw_on_mod")
		if a != "" and a in ics:
			_draw(o, 1)
		var b := GLData.fx_arg_in(fx, "churn_on_mod")
		if b != "" and b in ics:
			var v := _richest_opponent(o)
			if v >= 0:
				_draw(v, 1)
				_discard_random(v, 1)


## Гости «следуют» за картами: переходят в семью персонажа, на которого её сыграли.
func _follow(card: int, tg: int) -> void:
	var o := owner(tg)
	if o < 0:
		return
	var cd: Dictionary = GLData.CARDS[card]
	for g in chars.size():
		if not _guest_active(g) or owner(g) == o:
			continue
		var gd: Dictionary = GLData.GUESTS[int(chars[g]["id"])]
		var f: String = gd["follows"]
		if "no_move_if_heart" in gd["fx"] and has_icon(g, "heart"):
			continue  # «Холостяк» не уходит, пока у него видно сердце
		var hit: bool = f == "D" and cd["t"] == "D"
		if f.begins_with("icon:"):
			for ic in f.substr(5).split(","):
				if ic in cd["icons"]:
					hit = true
		if hit:
			chars[g]["owner"] = o
			_log("%s переезжает к %s" % [_cname(g), _pname(o)], o)


func _kill(tg: int, card: int, actor: int) -> void:
	chars[tg]["stack"].append(card)
	chars[tg]["dead"] = true
	_log("%s: %s — «%s»" % [_pname(actor), _cname(tg), GLData.card_name(card)], actor)
	var ctl := owner(tg)
	for f in GLData.CARDS[card]["fx"]:
		match f:
			"discard_hand":
				if ctl >= 0:
					_discard_cards(ctl, hands[ctl].duplicate())
			"ud_second":
				ud_next = true
			"take_random_each_opponent_if:goblet":
				if ctl >= 0 and has_icon(tg, "goblet"):
					for o in players.size():
						_take_random(o, ctl, 1)
			"others_give_events_if:skull":
				if ctl >= 0 and has_icon(tg, "skull"):
					for o in players.size():
						if o != ctl and not _protected(o):
							for c in hands[o].filter(func(x): return GLData.CARDS[x]["t"] == "E"):
								hands[o].erase(c)
								hands[ctl].append(c)
			"draw_per_icon:coin":
				if ctl >= 0:
					_draw(ctl, count_icon_in_play("coin"))
			"free_ud_this_turn_if:beast":
				if has_icon(tg, "beast") and free.is_empty():
					free = {"cards": [], "ud_only": true, "target": -1, "left": 1}


func _mod_effects(card: int, tg: int, actor: int) -> void:
	var ctl := owner(tg)
	if ctl < 0:
		return  # гость без хозяина: эффект некому применять
	var n_players := players.size()
	for f in GLData.CARDS[card]["fx"]:
		var parts: PackedStringArray = str(f).split(":")
		var arg := parts[1] if parts.size() > 1 else ""
		var n := int(arg) if arg.is_valid_int() else 0
		match parts[0]:
			"draw":
				_draw(ctl, n)
			"discard":
				_ask(ctl, "discard", n)
			"give_right":
				if not _protected(ctl):
					_ask(ctl, "give", n, right_of(ctl))
			"right_discard_random", "left_discard_random":
				_discard_random(ctl, n)
			"right_take_random":
				_take_random(ctl, right_of(ctl), n)
			"skip_draw":
				skip_draw[ctl] = true
			"discard_hand":
				_discard_cards(ctl, hands[ctl].duplicate())
			"draw_per_icon":
				_draw(ctl, count_icon_in_play(arg))
			"free_ud_if_neg":
				if ctl == actor and worth(tg) < 0 and free.is_empty():
					free = {"cards": [], "ud_only": true, "target": tg, "left": 1}
			"free_ud_if_icon":
				if ctl == actor and has_icon(tg, arg) and free.is_empty():
					free = {"cards": [], "ud_only": true, "target": tg, "left": 1}
			"free_ud_on_guest":
				if ctl == actor and free.is_empty():
					free = {"cards": [], "ud_only": true, "guest_only": true, "target": -1, "left": 1}
			"refresh_hand":
				_ask(ctl, "refresh", 0)
			"refresh":
				_ask(ctl, "refresh", n)
			"guests_uncontrolled":
				for g in _guests_of(ctl, false):
					chars[g]["owner"] = -1
			"left_plays_random_from_hand", "left_takes_chosen":
				_take_random(ctl, left_of(ctl), maxi(1, n))
			"right_takes_chosen":
				_take_random(ctl, right_of(ctl), maxi(1, n))
			"take_ud_from_discard":
				_ask_discard_pick(ctl, "D")
			"take_event_from_discard":
				_ask_discard_pick(ctl, "E")
			"take_any_from_discard":
				_ask_discard_pick(ctl, "any")
			"opponents_take_random":
				for k in range(1, n_players):
					_take_random(ctl, (ctl + k) % n_players, n)
			"opponents_draw":
				for k in range(1, n_players):
					_draw((ctl + k) % n_players, n)
			"take_uncontrolled_guest":
				_ask_char(ctl, chars.size(), func(c): return alive(c) and chars[c]["kind"] == "guest" and owner(c) < 0, "take_guest")
			"take_any_guest":
				_ask_char(ctl, chars.size(), func(c): return alive(c) and chars[c]["kind"] == "guest" and owner(c) != ctl, "take_guest")
			"discard_events_from_hand":
				_discard_cards(ctl, hands[ctl].filter(func(x): return GLData.CARDS[x]["t"] == "E"))
			"left_discard_random_per_icon":
				_discard_random(ctl, count_icon_in_play(arg))
			"discard_mod_from_undead":
				_ask_char(ctl, chars.size(), func(c): return is_undead(c) and top_mod(c) >= 0, "peel")
			"everyone_discard":
				for k in n_players:
					_ask((ctl + k) % n_players, "discard", n)
			"revive_own_dead":
				_ask_char(ctl, chars.size(), func(c): return valid(c) and owner(c) == ctl and chars[c]["dead"] and top(c) >= 0 and GLData.CARDS[top(c)]["t"] == "D", "revive")
			"discard2_per_family_icon":
				_ask(ctl, "discard", 2 * count_family_icon(ctl, arg))
			"discard_per_family_icon":
				_ask(ctl, "discard", count_family_icon(ctl, arg))
			"draw2_per_family_icon":
				_draw(ctl, 2 * count_family_icon(ctl, arg))
			"take2_random_from_chosen":
				_take_random(_richest_opponent(ctl), ctl, 2)
			"take_random_each_opponent":
				for o in players.size():
					_take_random(o, ctl, 1)
			"reveal2_remove_or_discard_hand":
				if _drew_dark(_draw(ctl, 2)):
					_remove_char(tg)
				else:
					_discard_cards(ctl, hands[ctl].duplicate())
			"draw2_show_skull_beast_discard_hand":
				if _drew_dark(_draw(ctl, 2)):
					_discard_cards(ctl, hands[ctl].duplicate())
			"claim_any_story":
				var opts := stories.filter(func(x): return int(x["owner"]) != ctl).map(func(x): return int(x["id"]))
				if not opts.is_empty():
					prompts.append({"seat": ctl, "kind": "pick_story", "options": opts, "then": "claim", "optional": true})
			"take_left_2":
				_take_random(left_of(ctl), ctl, 2)
			"draw_per_icon_then_trim":
				_draw(ctl, count_icon_in_play(arg))
				_ask(ctl, "discard", hands[ctl].size() - hand_limit(ctl))
			"guest_uncontrolled_choose":
				_ask_char(ctl, chars.size(), func(c): return alive(c) and chars[c]["kind"] == "guest" and owner(c) >= 0, "free_guest")
			"others_take_random":
				for k in range(1, n_players):
					_take_random(ctl, (ctl + k) % n_players, n)
			"free_mod_with":
				if ctl == actor and free.is_empty():
					free = {"cards": [], "mod_icon": arg, "target": -1, "left": 1}
			"discard_per_icon":
				_ask(ctl, "discard", count_icon_in_play(arg))
			"stories_uncontrolled":
				for x in stories:
					if int(x["owner"]) == ctl:
						x["owner"] = -1
			"discard_other_mods":
				var st0: Array = chars[tg]["stack"]
				for c in st0.duplicate():
					if c != card and GLData.CARDS[c]["t"] == "M":
						st0.erase(c)
						discard.append(c)
			"right_random_discard", "left_random_discard":
				_discard_random(ctl, n)
			"give_right_choice":
				if not _protected(ctl):
					_ask(ctl, "give", n, right_of(ctl))
			"discard_mod_below":
				var st: Array = chars[tg]["stack"]
				var i := st.find(card)
				if i > 0 and GLData.CARDS[st[i - 1]]["t"] == "M":
					discard.append(st[i - 1])
					st.remove_at(i - 1)
	# «Сошёл с ума» / «Отравился лососем»: сыгравший модификатор сбрасывает карту за каждую такую плашку
	var k2 := _top_fx_count(actor, "discard_per_mod")
	if k2 > 0:
		_ask(actor, "discard", k2)


## Среди вытянутых карт есть иконка зверя или смерти.
func _drew_dark(got: Array) -> bool:
	for c in got:
		var ics: Array = GLData.CARDS[c]["icons"]
		if "beast" in ics or "skull" in ics:
			return true
	return false


func _remove_char(c: int) -> void:
	discard.append_array(chars[c]["stack"])
	chars[c]["stack"] = []
	chars[c]["removed"] = true


func _event(card: int, tg: int, extra: Dictionary, actor: int) -> void:
	var f := _fx0(card)
	var nm := GLData.card_name(card)
	var who := _cname(tg) if valid(tg) else ""
	var to_removed := false
	match f:
		"stormy":
			var got := _draw(actor, 4)
			free = {"cards": got, "ud_only": false, "target": -1, "left": 1, "after": "discard_to_limit"}
			_log("%s: «%s» — берёт 4 карты" % [_pname(actor), nm], actor)
		"remove_top_mod":
			discard.append(chars[tg]["stack"].pop_back())
			_log("%s: «%s» — %s" % [_pname(actor), nm, who], actor)
		"remove_all_mods":
			discard.append_array(chars[tg]["stack"])
			chars[tg]["stack"] = []
			_log("%s: «%s» — %s" % [_pname(actor), nm, who], actor)
		"remove_living_char":
			_remove_char(tg)
			to_removed = true
			_log("%s: «%s» — %s уходит из игры" % [_pname(actor), nm, who], actor)
		"swap_top_mod_from_hand":
			var w := int(extra.get("with", -1))
			var old = chars[tg]["stack"].pop_back()
			hands[actor].erase(w)
			chars[tg]["stack"].append(w)
			hands[actor].append(old)
			_log("%s: «%s» — %s: «%s» вместо «%s»" % [_pname(actor), nm, who, GLData.card_name(w), GLData.card_name(old)], actor)
		"swap_top_mods":
			var t2 := int(extra.get("t2", -1))
			var a = chars[tg]["stack"].pop_back()
			var b = chars[t2]["stack"].pop_back()
			chars[tg]["stack"].append(b)
			chars[t2]["stack"].append(a)
			_log("%s: «%s» — %s и %s" % [_pname(actor), nm, who, _cname(t2)], actor)
		"swap_all_mods_with_guest":
			var t2 := int(extra.get("t2", -1))
			var a: Array = chars[tg]["stack"]
			chars[tg]["stack"] = chars[t2]["stack"]
			chars[t2]["stack"] = a
			_log("%s: «%s» — %s и %s" % [_pname(actor), nm, who, _cname(t2)], actor)
		"take_guest_from_family":
			chars[tg]["owner"] = actor
			_log("%s: «%s» — %s переезжает" % [_pname(actor), nm, who], actor)
		"move_guest_between":
			var t2 := int(extra.get("t2", -1))
			chars[tg]["owner"] = owner(t2)
			_log("%s: «%s» — %s уходит к %s" % [_pname(actor), nm, who, _pname(owner(t2))], actor)
		"swap_living_chars_with_opponent":
			var t2 := int(extra.get("t2", -1))
			var o := owner(tg)
			chars[tg]["owner"] = actor
			chars[t2]["owner"] = o
			_log("%s: «%s» — %s ↔ %s" % [_pname(actor), nm, who, _cname(t2)], actor)
		"ud_from_discard":
			var pick := int(extra.get("pick", -1))
			discard.erase(pick)
			_log("%s: «%s»" % [_pname(actor), nm], actor)
			_kill(tg, pick, actor)
			_follow(pick, tg)
		"play_event_or_undead_from_discard":
			var pick := int(extra.get("pick", -1))
			discard.erase(pick)
			hands[actor].append(pick)
			free = {"cards": [pick], "ud_only": false, "target": -1, "left": 1}
			_log("%s: «%s» — достаёт «%s»" % [_pname(actor), nm, GLData.card_name(pick)], actor)
		"claim_any_story_then_free_play":
			_give_story(actor, int(extra.get("st", -1)))
			free = {"cards": [], "ud_only": false, "target": -1, "left": 1}
		"root_of_evil":
			var taken := []
			for s in players.size():
				if s != actor:
					taken.append_array(_take_random(s, actor, 1))
			if _controls_icon(actor, "coin") and not taken.is_empty():
				free = {"cards": taken, "ud_only": false, "target": -1, "left": taken.size()}
			_log("%s: «%s» — забирает по карте у соперников" % [_pname(actor), nm], actor)
		"extra_plays":
			plays_left += 2
			ud_any = true
			_log("%s: «%s» — ещё 2 действия" % [_pname(actor), nm], actor)
		"unlimited_plays_discard_each":
			plays_left = 99
			disc_each = true
			_log("%s: «%s» — играет сколько угодно карт" % [_pname(actor), nm], actor)
		"draw2_per_guest_play_any":
			var got := _draw(actor, 2 * _guests_of(actor).size())
			if not got.is_empty():
				free = {"cards": got, "ud_only": false, "target": -1, "left": got.size(), "after": "discard_rest"}
			_log("%s: «%s»" % [_pname(actor), nm], actor)
		"mod_on_dead":
			mod_dead = true
			_log("%s: «%s» — модификатор можно сыграть на мёртвого" % [_pname(actor), nm], actor)
		"swap_hands":
			var o := owner(tg)
			if not _protected(o):
				var h: Array = hands[actor]
				hands[actor] = hands[o]
				hands[o] = h
			_draw(actor, 2)
			_log("%s: «%s» — меняется руками с %s" % [_pname(actor), nm, _pname(o)], actor)
		"free_ud_or_remove_undead":
			if tg >= 0:
				_remove_char(tg)
				to_removed = true
				_log("%s: «%s» — нежить %s уходит из игры" % [_pname(actor), nm, who], actor)
			else:
				free = {"cards": [], "ud_only": true, "target": -1, "left": 1}
				_log("%s: «%s» — бесплатная смерть" % [_pname(actor), nm], actor)
		"everyone_removes_own_char":
			for k in players.size():
				var s := (actor + k) % players.size()
				_ask_char(s, chars.size(), func(c): return alive(c) and owner(c) == s, "remove_char", false)
			_log("%s: «%s» — каждый убирает своего персонажа" % [_pname(actor), nm], actor)
		"dramatic":
			if str(extra.get("mode", "")) == "chaos":
				for c in chars.size():
					if alive(c) and chars[c]["kind"] == "guest":
						chars[c]["owner"] = -1
				for x in stories:
					x["owner"] = -1
				_log("%s: «%s» — все гости и истории снова ничьи" % [_pname(actor), nm], actor)
			else:
				free = {"cards": [], "ud_only": false, "target": -1, "left": 1}
				_log("%s: «%s» — бесплатная карта" % [_pname(actor), nm], actor)
		"midnight":
			var got := _draw(actor, 3)
			for c in got:
				if not hands[actor].has(c):
					continue  # уже ушла (сброс руки от предыдущей карты)
				var cd: Dictionary = GLData.CARDS[c]
				var mine := range(chars.size()).filter(func(x): return alive(x) and owner(x) == actor)
				var target := -1
				if cd["t"] == "M":
					target = mine[0] if not mine.is_empty() else -1
				elif cd["t"] == "D":
					for x in mine:
						if worth(x) < 0 and not is_undead(x):
							target = x
							break
				hands[actor].erase(c)
				if target >= 0:
					_resolve({"card": c, "target": target, "extra": {}, "actor": actor})
				else:
					discard.append(c)
			_log("%s: «%s»" % [_pname(actor), nm], actor)
		"plot_twist":
			_draw(actor, 3)
			var opts := stories.filter(func(x): return int(x["owner"]) != actor).map(func(x): return 1000 + int(x["id"]))
			for c in chars.size():
				if alive(c) and chars[c]["kind"] == "guest" and owner(c) != actor:
					opts.append(c)
			if not opts.is_empty():
				prompts.append({"seat": actor, "kind": "pick_char", "options": opts, "then": "plot", "optional": true})
			_log("%s: «%s»" % [_pname(actor), nm], actor)
		"whodunnit":
			_draw(actor, count_family_icon(actor, "magnifier"))
			free = {"cards": [], "ud_only": false, "target": -1, "left": 1, "after": "discard_to_limit"}
			_log("%s: «%s»" % [_pname(actor), nm], actor)
		"others_discard_family_icons":
			var k := 0
			for ic in GLData.fx_arg(card, "others_discard_family_icons").split(","):
				k = maxi(k, count_family_icon(actor, ic))
			for o in range(1, players.size()):
				_ask((actor + o) % players.size(), "discard", k)
			_log("%s: «%s» — остальные сбрасывают по %d" % [_pname(actor), nm, k], actor)
		"second_chance":
			discard.append(chars[tg]["stack"].pop_back())
			chars[tg]["dead"] = false
			_log("%s: «%s» — %s снова жив(а)" % [_pname(actor), nm, who], actor)
	if to_removed or card == GLData.IMAGINARY_FRIEND:
		removed.append(card)
	else:
		discard.append(card)


# --- Выборы --------------------------------------------------------------------------

func _ask(seat: int, kind: String, n: int, to: int = -1) -> void:
	if seat < 0:
		return
	var size: int = hands[seat].size()
	if kind != "refresh":
		if size == 0 or n <= 0:
			return
		n = mini(n, size)
		if n == size and kind == "discard":
			_discard_cards(seat, hands[seat].duplicate())
			return
	prompts.append({"seat": seat, "kind": kind, "n": n, "to": to})


## Выбрать персонажа из подходящих (then — что с ним сделать). Один вариант — сразу.
func _ask_char(seat: int, count: int, ok: Callable, then: String, optional: bool = true) -> void:
	var opts := []
	for c in count:
		if ok.call(c):
			opts.append(c)
	if opts.is_empty():
		return
	prompts.append({"seat": seat, "kind": "pick_char", "options": opts, "then": then, "optional": optional})


## Взять карту из сброса себе на руку (filter: D / E / any).
func _ask_discard_pick(seat: int, filter: String) -> void:
	var opts := discard.filter(func(c): return filter == "any" or GLData.CARDS[c]["t"] == filter)
	if opts.is_empty():
		return
	prompts.append({"seat": seat, "kind": "pick_discard", "options": opts, "then": "hand", "optional": true})


func prompt() -> Dictionary:
	if not prompts.is_empty() and prompts[0]["kind"] in ["discard", "give"]:
		prompts[0]["n"] = mini(int(prompts[0]["n"]), hands[int(prompts[0]["seat"])].size())
	return prompts[0] if not prompts.is_empty() else {}


## Ответ на выбор карт из руки: cards — выбранные карты.
func choose(seat: int, cards: Array) -> bool:
	if phase != "prompt" or prompts.is_empty():
		return false
	var p: Dictionary = prompts[0]
	if seat != int(p["seat"]) or p["kind"] in ["pick_char", "pick_discard", "pick_story"]:
		return false
	var uniq := []
	for c in cards:
		if not hands[seat].has(int(c)) or uniq.has(int(c)):
			return false
		uniq.append(int(c))
	if p["kind"] != "refresh":
		p["n"] = mini(int(p["n"]), hands[seat].size())  # рука могла уменьшиться, пока ждали выбора
	match p["kind"]:
		"discard":
			if uniq.size() != int(p["n"]):
				return false
			_discard_cards(seat, uniq)
		"give":
			if uniq.size() != int(p["n"]):
				return false
			for c in uniq:
				hands[seat].erase(c)
				hands[int(p["to"])].append(c)
		"refresh":
			if int(p["n"]) > 0 and uniq.size() > int(p["n"]):
				return false
			_discard_cards(seat, uniq)
			_draw(seat, maxi(0, hand_limit(seat) - hands[seat].size()))
	prompts.pop_front()
	_after_action()
	return true


## Ответ на выбор персонажа / карты из сброса: value — вариант из options (-1 — отказаться).
func pick(seat: int, value: int) -> bool:
	if phase != "prompt" or prompts.is_empty():
		return false
	var p: Dictionary = prompts[0]
	if seat != int(p["seat"]) or not p["kind"] in ["pick_char", "pick_discard", "pick_story"]:
		return false
	if value < 0:
		if not p.get("optional", true):
			return false
	elif not value in p["options"]:
		return false
	elif p["kind"] == "pick_discard":
		discard.erase(value)
		hands[seat].append(value)
	elif p["kind"] == "pick_story":
		_give_story(seat, value)
	else:
		match p["then"]:
			"plot":
				if value >= 1000:
					_give_story(seat, value - 1000)
				else:
					chars[value]["owner"] = seat
					_log("%s забирает гостя: %s" % [_pname(seat), _cname(value)], seat)
			"free_guest":
				chars[value]["owner"] = -1
				_log("%s теперь ничей гость" % _cname(value), seat)
			"take_guest":
				chars[value]["owner"] = seat
				_log("%s забирает гостя: %s" % [_pname(seat), _cname(value)], seat)
			"revive":
				discard.append(chars[value]["stack"].pop_back())
				chars[value]["dead"] = false
				_log("%s: %s снова жив(а)" % [_pname(seat), _cname(value)], seat)
			"peel":
				discard.append(chars[value]["stack"].pop_back())
			"remove_char":
				_remove_char(value)
				_log("%s убирает из игры: %s" % [_pname(seat), _cname(value)], seat)
	prompts.pop_front()
	_after_action()
	return true


## Время вышло / игрок вылетел: случайный выбор (обновление руки — без сброса).
func auto_choose() -> void:
	if phase != "prompt" or prompts.is_empty():
		return
	var p: Dictionary = prompts[0]
	var s := int(p["seat"])
	if p["kind"] in ["pick_char", "pick_discard", "pick_story"]:
		var opts: Array = p["options"]
		pick(s, opts[rng.randi_range(0, opts.size() - 1)])
		return
	choose(s, [] if p["kind"] == "refresh" else _random_cards(s, mini(int(p["n"]), hands[s].size())))


# --- Журнал и вид ---------------------------------------------------------------------

func _pname(s: int) -> String:
	return players[s]["name"] if s >= 0 and s < players.size() else "центр стола"


func _cname(c: int) -> String:
	if c < 0 or c >= chars.size():
		return "?"
	var id := int(chars[c]["id"])
	return GLData.GUESTS[id]["name"] if chars[c]["kind"] == "guest" else GLData.char_name(id)


func _log(text: String, seat: int) -> void:
	log.append({"text": text, "seat": seat})
	if log.size() > 30:
		log.pop_front()


## Что текущий игрок может сыграть: {карта: {t: [цели], t2: {t: [..]}, with: [..], pick: {..}, go, stories}}.
func legal() -> Dictionary:
	var out := {}
	if phase != "play":
		return out
	var s := current
	var n := chars.size()
	for card in hands[s]:
		var cd: Dictionary = GLData.CARDS[card]
		var e := {}
		if cd["t"] in ["M", "D"]:
			e["t"] = range(n).filter(func(c): return can_play(s, card, c))
		elif not (events_blocked(s) or _is_response_only(card)) and (plays_left > 0 or _free_covers(card, -1)):
			var f := _fx0(card)
			if f == "dramatic":
				e["modes"] = ["free", "chaos"]
			elif f in FX_NO_TARGET:
				e["go"] = true
			elif f == "free_ud_or_remove_undead":
				e["go"] = true
				e["t"] = range(n).filter(func(c): return is_undead(c))
			elif f in FX_TWO:
				var t2 := {}
				for c in n:
					if _two_first(f, s, c):
						var l := range(n).filter(func(c2): return _two_second(f, s, c, c2))
						if not l.is_empty():
							t2[c] = l
				e["t"] = t2.keys()
				e["t2"] = t2
			elif f == "swap_top_mod_from_hand":
				var w: Array = hands[s].filter(func(x): return x != card and GLData.CARDS[x]["t"] == "M")
				e["t"] = [] if w.is_empty() else range(n).filter(func(c): return _event_valid(s, card, c, {}, true))
				e["with"] = w
			elif f == "ud_from_discard":
				var pk := {}
				for d in discard:
					var l := range(n).filter(func(c): return _event_valid(s, card, c, {"pick": d}, false))
					if not l.is_empty():
						pk[d] = l
				e["pick"] = pk
			elif f == "play_event_or_undead_from_discard":
				e["picks"] = discard.filter(func(d): return _grave_ok(d))
			elif f == "claim_any_story_then_free_play":
				e["stories"] = stories.filter(func(x): return int(x["owner"]) != s).map(func(x): return int(x["id"]))
			else:
				e["t"] = range(n).filter(func(c): return _event_valid(s, card, c, {}, false))
		out[card] = e
	return out


func get_view(seat: int, show_all: bool = false) -> Dictionary:
	var cv := []
	for c in chars.size():
		var ch: Dictionary = chars[c]
		var guest: bool = ch["kind"] == "guest"
		cv.append({"id": ch["id"], "kind": ch["kind"], "img": ("g%d" if guest else "ch%d") % int(ch["id"]), "name": _cname(c), "owner": ch["owner"], "stack": ch["stack"].duplicate(), "dead": ch["dead"], "removed": ch["removed"], "worth": final_worth(c) if scores(c) else worth(c), "icons": icons(c), "undead": is_undead(c), "guest": is_guest(c)})
	var hv := []
	var counts := []
	var limits := []
	for s in players.size():
		hv.append(hands[s].duplicate() if (s == seat or show_all) else [])
		counts.append(hands[s].size())
		limits.append(hand_limit(s))
	var rv := {}
	if not react.is_empty():
		var p: Dictionary = react["play"]
		var t: String = GLData.CARDS[p["card"]]["t"]
		rv = {"card": p["card"], "target": p["target"], "actor": p["actor"], "kind": react["kind"], "extra": p["extra"].duplicate()}
		var can := []
		var resp := {}
		for s in react["eligible"]:
			if not s in react["passed"] and (s == seat or show_all):
				can.append(s)
				resp[s] = _response_card(s, t)
		rv["can"] = can
		rv["resp"] = resp
	var me := current if show_all else seat
	var sv := []
	for st in stories:
		sv.append({"id": st["id"], "owner": st["owner"], "can": phase == "play" and me == current and plays_left > 0 and can_claim(me, int(st["id"])), "pick": phase == "prompt" and not prompts.is_empty() and prompts[0]["kind"] in ["pick_story", "pick_char"] and (int(st["id"]) in prompts[0]["options"] and prompts[0]["kind"] == "pick_story" or 1000 + int(st["id"]) in prompts[0]["options"])})
	return {
		"you": seat,
		"players": players.duplicate(true),
		"fam": fam.duplicate(),
		"chars": cv,
		"stories": sv,
		"sets": sets.duplicate(),
		"hands": hv,
		"hand_counts": counts,
		"limits": limits,
		"skip_draw": skip_draw.duplicate(),
		"deck_left": deck.size(),
		"discard": discard.duplicate(),
		"phase": phase,
		"current": current,
		"plays_left": plays_left,
		"ud_ok": ud_allowed(),
		"mod_dead": mod_dead,
		"disc_each": disc_each,
		"events_blocked": events_blocked(current),
		"free": free.duplicate(true),
		"prompt": prompt().duplicate(true),
		"react": rv,
		"legal": legal() if (seat == current or show_all) else {},
		"trim_left": trim_left.duplicate(),
		"draft_order": draft_order.duplicate(),
		"draft_left": draft_left() if phase == "draft" else [],
		"turn_no": turn_no,
		"log": log.duplicate(true),
		"finals": finals.duplicate(),
		"winners": winners.duplicate(),
		"hotseat": show_all,
		"clock": phase in ["trim", "draft", "play", "prompt"],
	}


# --- Новый игрок посреди партии ------------------------------------------------------

func _free_family() -> int:
	for f in 4:
		if not fam.has(f):
			return f
	return -1


func can_add_player() -> bool:
	if not "base" in sets:
		return phase in ["play", "prompt", "react"] and players.size() < 5 and draft_left().size() >= DRAFT_EACH
	return phase in ["play", "prompt", "react"] and players.size() < 4 and _free_family() >= 0


## Получает свободную семью и 5 карт.
func add_player(p: Dictionary) -> bool:
	if not can_add_player():
		return false
	var s := players.size()
	var gm := not "base" in sets
	var f := GLData.GLOOMIER if gm else _free_family()
	players.append(p.duplicate())
	fam.append(f)
	hands.append([])
	skip_draw.append(false)
	if gm:
		var left := draft_left()
		_shuffle(left)
		for i in left.slice(0, DRAFT_EACH):
			chars.append(_new_char(i, "char", s))
	else:
		for i in GLData.CHARS.size():
			if int(GLData.CHARS[i]["family"]) == f:
				chars.append(_new_char(i, "char", s))
	_draw(s, HAND)
	_log("%s присоединяется: %s" % [_pname(s), GLData.FAMILIES[f]["name"]], s)
	return true
