extends RefCounted
## Порядок ходов и барьер одновременной фазы. Все решения и переходы принимает хост.
const MODES := preload("res://games/custom/logic/cg_blocks.gd").TURN_MODES
const Interp := preload("res://games/custom/logic/cg_interp.gd")

static func mode(r: Object) -> String:
	return str(r.definition.rules.get("turn_mode", "circle"))

static func initialize(r: Object) -> void:
	r.state["ready_seats"] = []
	if mode(r) in ["leader_start", "leader_only"]:
		r.state.current = int(r.state.leader)

static func can_begin(r: Object, seat: int) -> bool:
	if mode(r) == "leader_only":
		return seat == int(r.state.leader)
	if mode(r) == "simultaneous":
		return not r.state.get("ready_seats", []).has(seat)
	return true

static func readiness(r: Object, seat: int) -> Array:
	if mode(r) != "simultaneous":
		return []
	return [{"kind": "unready" if r.state.get("ready_seats", []).has(seat) else "ready"}]

static func mark(r: Object, seat: int, ready: bool) -> bool:
	if mode(r) != "simultaneous":
		return false
	var seats: Array = r.state.get("ready_seats", [])
	if ready:
		if seats.has(seat):
			return false
		seats.append(seat)
	else:
		if not seats.has(seat):
			return false
		seats.erase(seat)
	r.state["ready_seats"] = seats
	return true

static func complete(r: Object) -> bool:
	if mode(r) != "simultaneous" or r.phase == "game_over" or not r.state.pending.is_empty():
		return true
	var alive := 0
	for seat in r.players.size():
		if bool(r.players[seat].get("eliminated", false)):
			continue
		alive += 1
		if not r.state.get("ready_seats", []).has(seat):
			return true
	if alive == 0:
		return true
	var phases: Array = r.definition.rules.phases
	var index: int = phases.find(r.phase)
	var next := posmod(index + 1, phases.size())
	r.state.ready_seats = []
	r.state.turn_no = int(r.state.turn_no) + 1
	if next == 0:
		r.state.round = int(r.state.round) + 1
	# Общая граница фазы принадлежит ведущему, а не тому, кто последним нажал «Готов».
	return Interp.run(r, [{"blocks": [{"op": "phase", "phase": phases[next]}], "index": 0,
		"context": {"actor": int(r.state.leader), "depth": 0}}]).is_empty()
