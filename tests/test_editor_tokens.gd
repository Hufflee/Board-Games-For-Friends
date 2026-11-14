extends SceneTree
## Жетоны и монеты пользовательской игры: проверка вида, набор у каждого игрока/команды,
## переворот двустороннего (номиналы меняются местами), «без ограничения» — запас пополняется.
## Запуск: APPDATA=<папка в build> godot --headless --audio-driver Dummy --path . --script res://tests/test_editor_tokens.gd
const Rules := preload("res://games/custom/logic/cg_rules.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
var checks := 0
var errors := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func example() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/card_race.json"))

func tokens_in(r: Object, zone: String, deck: String) -> Array:
	return r.state.zones[zone].filter(func(id: String): return str(r.state.cards[id].deck) == deck)

func _run() -> void:
	var data := example()
	data.rules.chains = []
	data.elements.decks = []
	data.elements.tokens = [
		{"id": "coin", "title": "Монета", "count": 1, "value": 1, "shape": "circle", "color": "#d9a441", "zone": "table", "unlimited": true},
		{"id": "chip", "title": "Фишка", "count": 2, "value": 1, "shape": "hex", "color": "player", "zone": "hand"},
		{"id": "flag", "title": "Флаг", "count": 2, "value": 0, "shape": "square", "color": "team", "zone": "table"},
		{"id": "medal", "title": "Медаль", "count": 1, "value": 1, "back_value": 3, "two_sided": true, "zone": "table"},
	]
	for item: Dictionary in data.layout.screens[0].items:
		if item.kind == "zone":
			item.free = true
	check(Definition.validate(data).errors.is_empty(), "Вид жетонов допустим: %s" % str(Definition.validate(data).errors))
	var r := Rules.new()
	var players: Array = [{"name": "А", "team": 0}, {"name": "Б", "team": 1}, {"name": "В", "team": 0}]
	check(r.load_definition(data).is_empty() and r.new_game(players, {"seed": 5}).is_empty(), "Партия с жетонами")
	# Цвет игрока: у каждого в руке свой набор с местом.
	for seat in 3:
		var own: Array = tokens_in(r, "hand@%d" % seat, "chip")
		check(own.size() == 2 and own.all(func(id: String): return int(r.state.cards[id].data.seat) == seat), "У игрока %d свои 2 фишки" % seat)
	# Цвет команды: набор на команду (2 команды), место — первый игрок команды.
	var flags: Array = tokens_in(r, "table", "flag")
	check(flags.size() == 4, "Флагов по 2 на каждую из 2 команд: %d" % flags.size())
	check(flags.filter(func(id: String): return int(r.state.cards[id].data.seat) == 0).size() == 2 and flags.filter(func(id: String): return int(r.state.cards[id].data.seat) == 1).size() == 2, "Флаги помечены первым игроком команды")
	# Двусторонний: переворот доступен и меняет номиналы.
	var medal: String = tokens_in(r, "table", "medal")[0]
	var legal: Array = r.legal_actions(0)
	check(legal.any(func(a: Dictionary): return a.kind == "manual_flip" and a.get("card") == medal), "Двусторонний жетон можно перевернуть")
	check(not legal.any(func(a: Dictionary): return a.kind == "manual_flip" and a.get("card") == flags[0]), "Односторонний жетон не переворачивается")
	check(r.act(0, "manual_flip", {"id": "table", "card": medal, "revision": r.state.revision}), "Переворот выполнен")
	check(bool(r.state.cards[medal].data.flipped) and int(r.state.cards[medal].data.value) == 3 and int(r.state.cards[medal].data.back_value) == 1, "Оборот: номинал 3, лицо запомнено")
	check(r.state.cards[medal].face_up, "Жетон остаётся открытым всем")
	check(r.act(0, "manual_flip", {"id": "table", "card": medal, "revision": r.state.revision}) and int(r.state.cards[medal].data.value) == 1, "Обратно — номинал 1")
	# Без ограничения: взяли последнюю монету — в запасе новая.
	var coin: String = tokens_in(r, "table", "coin")[0]
	check(r.act(0, "manual_move", {"id": "table", "card": coin, "to": "hand@0", "revision": r.state.revision}), "Монета взята в руку")
	check(tokens_in(r, "table", "coin").size() == 1 and tokens_in(r, "hand@0", "coin").size() == 1, "Запас монет пополнился")
	var fresh: String = tokens_in(r, "table", "coin")[0]
	check(fresh != coin and not r.state.cards[fresh].data.has("seat"), "Новая монета — отдельный компонент")
	var saved := r.save_state()
	var restored := Rules.new()
	restored.load_definition(data)
	check(restored.restore(saved).is_empty(), "Партия с новыми жетонами сохраняется и восстанавливается")
	# Ограниченный жетон не пополняется.
	var before: int = r.state.cards.size()
	var chip: String = tokens_in(r, "hand@0", "chip")[0]
	check(r.act(0, "manual_move", {"id": "hand@0", "card": chip, "to": "table", "revision": r.state.revision}), "Фишка выложена")
	check(r.state.cards.size() == before and tokens_in(r, "hand@0", "chip").size() == 1, "Обычные жетоны не множатся")

	var broken := example()
	broken.elements.tokens = [{"id": "t", "title": "Кривой", "count": 1, "value": "много", "shape": "звезда", "color": "не цвет", "image": "x", "two_sided": "да"}]
	var report: Array = Definition.validate(broken).errors
	for part: String in ["номинал", "форма", "цвет", "картинка лица", "two_sided"]:
		check(report.any(func(text: String): return text.contains("«Кривой»") and text.contains(part)), "Ошибка «%s» названа с жетоном: %s" % [part, str(report)])
	broken.elements.tokens = [{"id": "t", "title": "Без картинки", "count": 1, "shape": "image"}]
	check(Definition.validate(broken).errors.any(func(text: String): return text.contains("нужна картинка")), "Форма «своя картинка» без картинки — ошибка")
	broken.elements.decks = []
	broken.elements.tokens = [{"id": "t", "count": 100, "color": "player"}]
	check(Definition.validate(broken).errors.any(func(text: String): return text.contains("300")), "Жетоны цвета игрока умножаются на места в лимите")

	# Вид: без картинок и с цветом игрока рисуется (UI грузим после старта дерева — rulebook).
	var style: GDScript = load("res://games/custom/ui/cg_style.gd")
	var face: Control = style.TokenFace.new({"value": 5, "flipped": true, "back_value": 2}, null, Color.RED)
	check(face.tint == Color.RED and face._picture() == null, "Жетон с цветом игрока без картинки")
	face.free()
	print("TOKENS: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors > 0 else 0)
