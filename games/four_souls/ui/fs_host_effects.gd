extends RefCounted
## Аварийная панель Four Souls: только локальному хосту через общую «Панель хоста».
## 07.11 (владелец): все аварийные функции доступны всегда, чтобы чинить ошибки прямо во время игры.
## Действия — выпадающими списками (как раньше), выбор в списках сохраняется при обновлении панели.
## Операция без текущего эффекта выполняется от имени ходящего и сразу завершается.
const Operations := preload("res://games/four_souls/logic/fs_ops.gd")

## Выбранные пункты списков переживают пересборку панели (она обновляется по каждому действию).
static var _chosen := {}

static func make() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	var game: Object = Net.fours
	var resolving: Dictionary = game.resolving
	var note := Label.new()
	var current_text := "эффекта нет"
	if not resolving.is_empty():
		var card := int(resolving.get("card", -1))
		current_text = "эффект «%s» (%s)" % [FSData.title(card) if card >= 0 else str(resolving.get("kind", "")), str(game.players[int(resolving.get("owner", 0))].name)]
	note.text = "Аварийное исправление · всё пишется в журнал.\nСейчас: фаза %s · %s" % [str(game.phase), current_text]
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	_add_rescue(col, game)
	_add_operations(col, game)
	if not resolving.is_empty():
		_add_peek(col, game)
	_add_triggers(col)
	return col

static func _list(col: VBoxContainer, key: String, items: Array) -> OptionButton:
	var list := OptionButton.new()
	list.fit_to_longest_item = false
	for text in items:
		list.add_item(str(text))
	list.select(clampi(int(_chosen.get(key, 0)), 0, maxi(0, items.size() - 1)))
	list.item_selected.connect(func(index: int): _chosen[key] = index)
	col.add_child(list)
	return list

## Действия над партией: снять зависание, разрешить стек, закончить ход, завершить/бросить по эффекту.
static func _add_rescue(col: VBoxContainer, game: Object) -> void:
	var actions: Array = [["Снять зависание (вернуть ход)", "recover"], ["Разрешить стек сейчас", "resolve"], ["Закончить ход принудительно", "end_turn"]]
	if not game.resolving.is_empty():
		actions.append(["Завершить текущий эффект", "effect_done"])
		actions.append(["Бросок по эффекту", "effect_roll"])
	var list := _list(col, "rescue", actions.map(func(entry): return entry[0]))
	var run := Button.new()
	run.text = "Выполнить действие"
	run.pressed.connect(func():
		var mode: String = str(actions[clampi(list.selected, 0, actions.size() - 1)][1])
		if mode in ["effect_done", "effect_roll"]:
			Net.host_tools.four_souls_effect(mode, {})
		else:
			Net.host_tools.four_souls_unstick(mode))
	col.add_child(run)

## Любая операция: при текущем эффекте — в нём, иначе временный эффект от имени ходящего.
static func _add_operations(col: VBoxContainer, game: Object) -> void:
	var target := _list(col, "target", game.players.map(func(player): return str(player.name)))
	if not _chosen.has("target"):
		target.select(int(game.resolving.get("owner", game.current)))
	var operations: Array = Operations.MAIN + Operations.EXTRA
	var op := _list(col, "op", operations.map(func(entry): return str(entry[1])))
	var amount := SpinBox.new()
	amount.min_value = -99
	amount.max_value = 99
	amount.value = float(_chosen.get("amount", 1))
	amount.value_changed.connect(func(value: float): _chosen["amount"] = value)
	col.add_child(amount)
	var index := SpinBox.new()
	index.min_value = 1
	index.max_value = 99
	index.value = float(_chosen.get("index", 1))
	index.value_changed.connect(func(value: float): _chosen["index"] = value)
	index.tooltip_text = "Номер карты / предмета слева направо"
	col.add_child(index)
	var other := SpinBox.new()
	other.min_value = 1
	other.max_value = 99
	other.value = float(_chosen.get("other", 1))
	other.value_changed.connect(func(value: float): _chosen["other"] = value)
	other.tooltip_text = "Номер второго предмета при обмене"
	col.add_child(other)
	var fields := func(selected: int) -> void:
		var spec: Dictionary = operations[selected][2]
		target.visible = bool(spec.get("target", false))
		amount.visible = bool(spec.get("amount", false))
		index.visible = spec.has("item")
		other.visible = bool(spec.get("other", false))
	op.item_selected.connect(fields)
	fields.call(op.selected)
	var apply := Button.new()
	apply.text = "Применить исправление"
	apply.pressed.connect(func():
		var argument := {"op": operations[op.selected][0], "target": target.selected, "amount": int(amount.value), "item": int(index.value) - 1, "other_item": int(other.value) - 1}
		if Net.fours.resolving.is_empty():
			Net.host_tools.four_souls_host_apply(int(Net.fours.current), argument)
		else:
			Net.host_tools.four_souls_effect("effect", argument))
	col.add_child(apply)

static func _add_peek(col: VBoxContainer, game: Object) -> void:
	var view: Dictionary = game.get_view(int(game.resolving.owner))
	for revealed: Dictionary in view.peek.get("hands", []):
		var name := Label.new()
		name.text = str(view.players[int(revealed.seat)].name)
		col.add_child(name)
		for id in revealed.cards:
			var title := Label.new()
			title.text = FSData.title(int(id))
			col.add_child(title)
	for id in view.peek.get("cards", []):
		var title := Label.new()
		title.text = FSData.title(int(id))
		col.add_child(title)
		for entry in [["Наверх", "top"], ["Вниз", "bottom"], ["В руку", "hand"], ["В предметы", "item"], ["В сброс", "discard"]]:
			var button := Button.new()
			button.text = str(entry[0])
			button.pressed.connect(func(): Net.host_tools.four_souls_effect("peek_take", {"card": int(id), "dest": str(entry[1])}))
			col.add_child(button)

## Ручное срабатывание карты (предметы с условием, монстры без полной автоматики).
static func _add_triggers(col: VBoxContainer) -> void:
	var seat := _list(col, "trigger_seat", Net.fours.players.map(func(player): return str(player.name)))
	if not _chosen.has("trigger_seat"):
		seat.select(int(Net.fours.current))
	var cards := OptionButton.new()
	cards.fit_to_longest_item = false
	col.add_child(cards)
	var trigger := Button.new()
	trigger.text = "Запустить ручной эффект"
	col.add_child(trigger)
	var refresh := func(owner: int) -> void:
		cards.clear()
		for index in Net.fours.items[owner].size():
			var item: Dictionary = Net.fours.items[owner][index]
			if FSData.manual_item_trigger(int(item.id)):
				cards.add_item(FSData.title(int(item.id)))
				cards.set_item_metadata(cards.item_count - 1, {"kind": "item_trigger", "arg": {"item": index}})
		for index in Net.fours.monsters.size():
			var id: int = int(Net.fours.monsters[index].id)
			if preload("res://games/four_souls/logic/fs_support.gd").status(id) != "auto":
				cards.add_item(FSData.title(id))
				cards.set_item_metadata(cards.item_count - 1, {"kind": "monster_trigger", "arg": {"slot": index}})
		trigger.disabled = cards.item_count == 0
		trigger.tooltip_text = "" if cards.item_count > 0 else "У этого игрока нет карт с ручным срабатыванием"
	seat.item_selected.connect(refresh)
	refresh.call(seat.selected)
	trigger.pressed.connect(func():
		if cards.selected >= 0:
			var command: Dictionary = cards.get_item_metadata(cards.selected)
			Net.host_tools.four_souls_effect(str(command.kind), command.arg, seat.selected))
