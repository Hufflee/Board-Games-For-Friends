class_name ReadyDots
## Кружки цветов игроков, которые уже нажали «Дальше» / «Готово» — видно, кого ещё ждём.


## players — players из состояния игры ({name, color, bot?}); done — имена (или места) нажавших.
static func make(players: Array, done: Array, size: int = 16) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	for s in players.size():
		var p: Dictionary = players[s]
		if p.get("bot", false):
			continue
		var on: bool = done.has(p["name"]) or done.has(s)
		var d := TextureRect.new()
		d.texture = PlayerTag.dot(Net.color_of(int(p.get("color", 0))), size)
		d.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		d.modulate = Color.WHITE if on else Color(1, 1, 1, 0.18)
		d.tooltip_text = p["name"] + (" — готов" if on else " — ещё не нажал")
		d.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(d)
	return row


## Нажавшие «Дальше»: все живые игроки, кого нет в списке ожидания хоста (v["waiting"] — имена).
static func pressed_next(v: Dictionary) -> Array:
	var waiting: Array = v.get("waiting", [])
	var out := []
	for p in v.get("players", []):
		if not p.get("bot", false) and not waiting.has(p["name"]):
			out.append(p["name"])
	return out
