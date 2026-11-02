extends RefCounted
## Локальная отладка авторской игры: ограниченная история действий и восстановление вместе с RNG.

const LIMIT := 100
const BYTE_LIMIT := 32 * 1024 * 1024
var history: Array = []
var bytes := 0
var last_error := ""

func capture(rules: RefCounted) -> void:
	var revision := int(rules.state.get("revision", -1))
	if not history.is_empty() and int(history.back().snapshot.state.revision) == revision:
		return
	var snapshot: Dictionary = rules.save_state()
	var length := JSON.stringify(snapshot).to_utf8_buffer().size()
	if length > BYTE_LIMIT:
		last_error = "Снимок слишком велик для истории отладки."
		return
	history.append({"snapshot": snapshot, "bytes": length})
	bytes += length
	while history.size() > LIMIT or bytes > BYTE_LIMIT:
		bytes -= int(history.pop_front().bytes)

func back(rules: RefCounted) -> bool:
	if history.size() < 2:
		return false
	var previous: Dictionary = history[history.size() - 2].snapshot
	var revision := int(rules.state.revision) + 1
	last_error = rules.restore(previous)
	if not last_error.is_empty():
		return false
	bytes -= int(history.pop_back().bytes)
	# Старые кнопки и перетаскивания не должны стать допустимыми после отката.
	rules.state.revision = revision
	bytes -= int(history.back().bytes)
	history.back().snapshot.state.revision = revision
	history.back().bytes = JSON.stringify(history.back().snapshot).to_utf8_buffer().size()
	bytes += int(history.back().bytes)
	return true

func restart(rules: RefCounted, same_seed: bool) -> bool:
	var snapshot: Dictionary = rules.save_state()
	var seed_value: int = rules.rng.seed if same_seed else randi()
	if not same_seed and seed_value == rules.rng.seed:
		seed_value += 1
	var leader := 0
	for index in rules.players.size():
		if rules.players[index].get("role") == "leader":
			leader = index
	var options := {"seed": seed_value, "leader": leader, "turn_time": float(rules.state.get("turn_seconds", 0))}
	last_error = rules.new_game(rules.players.duplicate(true), options)
	if not last_error.is_empty():
		rules.restore(snapshot)
		return false
	rules.state.revision = int(snapshot.state.revision) + 1
	history.clear()
	bytes = 0
	capture(rules)
	return true

func describe(rules: RefCounted) -> String:
	var state: Dictionary = rules.state
	var lines: Array[String] = ["Фаза: %s · раунд %s · ход %s" % [state.phase, state.round, state.turn_no], "Игрок: %s" % rules.players[int(state.current)].name,
		"Последний блок: " + (str(state.trace.back()) if not state.trace.is_empty() else "—"), "Ожидание: " + str(state.pending.get("kind", "нет")), "", "ПЕРЕМЕННЫЕ", JSON.stringify(state.vars, "  "), "", "ЗОНЫ"]
	for zone: String in state.zones:
		var cards: Array[String] = []
		for id: String in state.zones[zone]:
			cards.append("%s %s" % [id, JSON.stringify(state.cards[id].get("data", {}))])
		lines.append("%s (%d): %s" % [zone, cards.size(), "; ".join(cards)])
	lines.append("\nЖУРНАЛ\n" + "\n".join(state.log))
	lines.append("\nПРОЙДЕННЫЕ БЛОКИ\n" + " → ".join(state.trace))
	if not rules.last_error.is_empty():
		lines.append("\nОШИБКА: " + rules.last_error)
	if not last_error.is_empty():
		lines.append("\nОТЛАДКА: " + last_error)
	return "\n".join(lines)
