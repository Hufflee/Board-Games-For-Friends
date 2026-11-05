extends SceneTree
## Диагностика сохранённой фазз-трассы: --script res://tools/fs_replay_probe.gd -- путь.json
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if not args.is_empty() else "res://build/fs_tests/fuzz_failures/171107.json"
	var trace: Dictionary = _integers(JSON.parse_string(FileAccess.get_file_as_string(path)))
	var fuzz := preload("res://tests/fs/fs_fuzz.gd")
	var scenario = fuzz._start(trace.config)
	var g: FSRules = scenario.g
	var faces: Array = []
	g.roll_source = func() -> int: return int(faces.pop_front()) if not faces.is_empty() else 3
	var accepted := 0
	for entry: Array in trace.log:
		faces.clear()
		faces.append_array(entry[3])
		if not fuzz.perform(g, int(entry[0]), str(entry[1]), entry[2]):
			print("REPLAY_REJECT ", accepted, " ", entry)
			print("REJECT_STATE ", {"phase": g.phase, "actor": g.actor(), "current": g.current, "resolving": g.resolving, "invariants": preload("res://games/four_souls/logic/fs_invariants.gd").check(g, false)})
			quit(1)
			return
		accepted += 1
	var copy := g.clone()
	print("RESOLVING ", g.resolving)
	print("STACK ", g.stack)
	print("REPLAY ", {"actions": accepted, "phase": g.phase, "current": g.current, "actor": g.actor(), "copy_actor": copy.actor(), "battle": g.battle, "hp": g.hp, "queue": g._team_queue15, "source": g._team_source15.get("id", -1), "copy_queue": copy._team_queue15})
	print("SOURCE_ALIAS ", is_same(g._team_source15, g.monsters[g.battle]) if g.battle >= 0 else false, " COPY_ALIAS ", is_same(copy._team_source15, copy.monsters[copy.battle]) if copy.battle >= 0 else false)
	print("ACTUAL_ROLL ", g.action(g.actor(), "roll"))
	print("TURN_BLOCKS ", {"room": g.room, "dead": g.dead, "hp": g.hp, "battle_player": g.battle_player, "attack_left": g.attack_left, "forced": g._forced_slots14(), "required_players": g._required_player_remaining(), "required_deck": g._forced_deck_remaining(), "lust": g._permitted_lust_targets(), "must": g._must_attack(), "encounter_must": g._encounter_must_attack(), "player_targets": g._permitted_player_attack_targets()})
	print("LEGAL_CURRENT ", g.legal_actions(g.current))
	quit()

func _integers(value: Variant) -> Variant:
	if value is float:
		return int(value) if value == floor(value) else value
	if value is Array:
		for index in value.size():
			value[index] = _integers(value[index])
	elif value is Dictionary:
		for key in value:
			value[key] = _integers(value[key])
	return value
