extends SceneTree
## Тиражирование колод по местам/командам, закрытые личные стопки и предел компонентов.

const Rules := preload("res://games/custom/logic/cg_rules.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
var checks := 0
var errors := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)

func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/card_race.json"))
	data.rules.chains = []
	data.elements.decks[0].rows = [{"title": "Своя карта", "copies": 2}]
	data.elements.decks[0].owner = "player"
	data.elements.decks[0].zone = "hand"
	for n in [2, 4, 8]:
		var seats: Array = []
		for index in n:
			seats.append({"name": "Игрок %d" % index, "team": index % 2})
		var rules := Rules.new()
		check(rules.load_definition(data).is_empty() and rules.new_game(seats).is_empty(), "Личные колоды созданы для %d мест" % n)
		check(rules.state.cards.size() == 2 * n, "Количество компонентов учитывает экземпляры по игрокам")
		for seat in n:
			var view: Dictionary = rules.get_view(seat)
			check(view.zones["hand@%d" % seat].size() == 2 and view.zones["hand@%d" % seat][0].has("id"), "Владелец видит свои карты")
			check(view.zones["hand@%d" % ((seat + 1) % n)][0] == {"hidden": true}, "Чужой экземпляр колоды не раскрывается")
		for zone: Dictionary in rules.definition.layout.screens[0].items:
			if zone.get("id") == "hand":
				zone.view = "pile"
		check(rules.get_view(0).zones["hand@0"][0] == {"hidden": true}, "Даже владелец не видит закрытую личную колоду")
		var saved := rules.save_state()
		var restored := Rules.new()
		check(restored.restore(JSON.parse_string(JSON.stringify(saved))).is_empty() and restored.state.cards.size() == n * 2, "Личные колоды переживают JSON-снимок")
		var teams := data.duplicate(true)
		teams.elements.decks[0].owner = "team"
		teams.elements.decks[0].zone = "team_deck"
		teams.layout.screens[0].items.append({"kind": "zone", "id": "team_deck", "owner": "team", "view": "row"})
		check(rules.load_definition(teams).is_empty() and rules.new_game(seats).is_empty(), "Командные колоды созданы")
		check(rules.state.cards.size() == 4 and rules.state.zones["team_deck#0"].size() == 2, "У команды один экземпляр, независимо от числа участников")
		check(rules.get_view(0).zones["team_deck#0"][0].has("id") and rules.get_view(1).zones["team_deck#0"][0] == {"hidden": true}, "Командная колода раскрывается только своей команде")
	data.elements.decks[0].rows[0].copies = 40
	check(not Definition.validate(data).errors.is_empty(), "Лимит 300 учитывает максимальное число экземпляров")
	data.elements.decks[0].rows[0].copies = 2
	data.elements.decks[0].zone = "draw"
	check(not Definition.validate(data).errors.is_empty(), "Личная колода не может стартовать в общей зоне")
	data.elements.decks[0].owner = "shared"
	data.elements.decks[0].zone = "table"
	for zone: Dictionary in data.layout.screens[0].items:
		if zone.get("id") == "table":
			zone.view = "free"
			zone.free = true
	var free := Rules.new()
	check(free.load_definition(data).is_empty() and free.new_game([{"name": "А"}, {"name": "Б"}]).is_empty(), "Свободная зона запущена")
	var flip: Dictionary = free.legal_actions(0).filter(func(action: Dictionary): return action.kind == "manual_flip_top")[0].duplicate(true)
	flip.revision = free.state.revision
	check(not flip.has("card") and free.act(0, "manual_flip_top", flip), "Закрытая верхняя карта переворачивается без раскрытия ID в действии")
	var place: Dictionary = free.legal_actions(0).filter(func(action: Dictionary): return action.kind == "manual_place")[0].duplicate(true)
	place.revision = free.state.revision
	place.pos = [0.25, 0.75]
	check(free.act(0, "manual_place", place) and free.state.cards[place.card].pos == [0.25, 0.75], "Положение свободной карты сохраняется хостом")
	var stable: Dictionary = free.save_state()
	for invalid: Variant in [[-0.1, 0.5], [0.5, 1.1], ["лево", 0.5], [0.5], {"x": 0.2, "y": 0.8}]:
		place.revision = free.state.revision
		place.pos = invalid
		check(not free.act(0, "manual_place", place) and free.save_state() == stable, "Неверное положение отвергается без изменения партии")
	var restored := Rules.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(stable))).is_empty() and restored.state.cards[place.card].pos == [0.25, 0.75], "Положение переживает сериализацию")
	var bad := stable.duplicate(true)
	bad.state.cards[place.card].pos = [2.0, 0.0]
	check(not restored.restore(bad).is_empty(), "Повреждённые координаты снимка отвергаются")
	print("CUSTOM_COMPONENTS: %d проверок, ошибок %d" % [checks, errors])
	quit(1 if errors else 0)
