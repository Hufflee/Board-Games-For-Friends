extends RefCounted
## Аварийная панель Four Souls: только локальному хосту через общую «Панель хоста».
const Operations := preload("res://games/four_souls/logic/fs_ops.gd")

static func make() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	var note := Label.new()
	note.text = "Аварийное исправление эффекта\nВсе операции записываются в журнал."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	if Net.fours.resolving.is_empty():
		_add_triggers(col)
		return col
	var target := OptionButton.new()
	for player: Dictionary in Net.fours.players:
		target.add_item(str(player.name))
	if not Net.fours.resolving.is_empty():
		target.select(int(Net.fours.resolving.owner))
	col.add_child(target)
	var operations: Array = Operations.MAIN + Operations.EXTRA
	var op := OptionButton.new()
	op.fit_to_longest_item = false
	for entry: Array in operations:
		op.add_item(str(entry[1]))
	col.add_child(op)
	var amount := SpinBox.new()
	amount.min_value = -99
	amount.max_value = 99
	amount.value = 1
	col.add_child(amount)
	var index := SpinBox.new()
	index.min_value = 1
	index.max_value = 99
	index.value = 1
	index.tooltip_text = "Номер карты / предмета слева направо"
	col.add_child(index)
	var other := SpinBox.new()
	other.min_value = 1
	other.max_value = 99
	other.value = 1
	other.tooltip_text = "Номер второго предмета при обмене"
	col.add_child(other)
	var fields := func(selected: int) -> void:
		var spec: Dictionary = operations[selected][2]
		target.visible = bool(spec.get("target", false))
		amount.visible = bool(spec.get("amount", false))
		index.visible = spec.has("item")
		other.visible = bool(spec.get("other", false))
	op.item_selected.connect(fields)
	fields.call(0)
	var apply := Button.new()
	apply.text = "Применить исправление"
	apply.pressed.connect(func(): Net.host_tools.four_souls_effect("effect", {"op": operations[op.selected][0], "target": target.selected, "amount": int(amount.value), "item": int(index.value) - 1, "other_item": int(other.value) - 1}))
	col.add_child(apply)
	for entry in [["Завершить текущий эффект", "effect_done"], ["Бросок по эффекту", "effect_roll"]]:
		var button := Button.new()
		button.text = str(entry[0])
		button.pressed.connect(func(): Net.host_tools.four_souls_effect(str(entry[1]), {}))
		col.add_child(button)
	if not Net.fours.resolving.is_empty():
		var view: Dictionary = Net.fours.get_view(int(Net.fours.resolving.owner))
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
	return col

static func _add_triggers(col: VBoxContainer) -> void:
	var seat := OptionButton.new()
	for player: Dictionary in Net.fours.players:
		seat.add_item(str(player.name))
	seat.select(int(Net.fours.current))
	col.add_child(seat)
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
	seat.item_selected.connect(refresh)
	refresh.call(seat.selected)
	trigger.pressed.connect(func():
		if cards.selected >= 0:
			var command: Dictionary = cards.get_item_metadata(cards.selected)
			Net.host_tools.four_souls_effect(str(command.kind), command.arg, seat.selected))
