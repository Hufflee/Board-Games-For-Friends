extends RefCounted
## Граф мест, связей, зон и направленных бонусов поля Unmatched.
## Проверка графа и правил движения: tests/test_unmatched.gd.

const Paths := preload("res://hub/board_paths.gd")

var _spaces: Array[Dictionary] = []
var _links: Array[PackedInt32Array] = []
var _movement_links: Array[PackedInt32Array] = []
var _high_ground: Dictionary = {}
var _starts: PackedInt32Array = []
var doors: Array = []
var closed_doors: Array[int] = []
var item_pool: Array = []
var item_slots: Array = []
var dangerous_paths: Array[Vector2i] = []
var conveyor := PackedInt32Array()
var conveyor_exit := PackedInt32Array()
var fog_links: Array = []


func _init(spaces: Array[Dictionary], links: Array[PackedInt32Array], starts: PackedInt32Array,
		high_ground: Array[Vector2i], movement_links: Array[PackedInt32Array] = []) -> void:
	_spaces = spaces.duplicate(true)
	_links = links.duplicate(true)
	_movement_links = (_links if movement_links.is_empty() else movement_links).duplicate(true)
	_starts = starts.duplicate()
	for edge in high_ground:
		_high_ground[edge] = true


func valid_space(space: int) -> bool:
	return space >= 0 and space < _spaces.size()


func cell_count() -> int:
	return _spaces.size()


func position_for(space: int) -> Vector2:
	return _spaces[space].get("at", Vector2.ZERO) if valid_space(space) else Vector2.ZERO


func zones_for(space: int) -> Array:
	return _spaces[space].get("zones", []).duplicate() if valid_space(space) else []


func valid() -> bool:
	if _spaces.is_empty() or _links.size() != _spaces.size() or _starts.size() not in [2, 4]:
		return false
	for space in _spaces.size():
		if _spaces[space].get("zones", []).is_empty() or _links[space].is_empty():
			return false
		for neighbor in _links[space]:
			if neighbor == space or not valid_space(neighbor):
				return false
	for edge: Vector2i in _high_ground:
		if not adjacent(edge.x, edge.y):
			return false
	var seen: Dictionary = {}
	for space in _starts:
		if not valid_space(space) or seen.has(space):
			return false
		seen[space] = true
	return true


func start_for(seat: int) -> int:
	if seat < 0 or seat >= _starts.size():
		return -1
	return _starts[seat]


func adjacent(from: int, to: int) -> bool:
	return valid_space(from) and valid_space(to) and to in _links[from] and not _door_blocks(from, to)


func door_is_adjacent(door: int, space: int) -> bool:
	if door < 0 or door >= doors.size():
		return false
	return doors[door].any(func(edge: Vector2i) -> bool: return space in [edge.x, edge.y])


func toggle_door(door: int) -> void:
	if door in closed_doors:
		closed_doors.erase(door)
	else:
		closed_doors.append(door)


func _door_blocks(from: int, to: int) -> bool:
	var edge := Vector2i(mini(from, to), maxi(from, to))
	for door: int in closed_doors:
		if edge in doors[door]:
			return true
	return false


func _without_closed_doors(links: Array[PackedInt32Array]) -> Array[PackedInt32Array]:
	if closed_doors.is_empty():
		return links
	var available: Array[PackedInt32Array] = links.duplicate(true)
	for door: int in closed_doors:
		for edge: Vector2i in doors[door]:
			available[edge.x].erase(edge.y)
			available[edge.y].erase(edge.x)
	return available


func _distance_in(links: Array[PackedInt32Array], first: int, second: int) -> int:
	var queue := PackedInt32Array([first])
	var distances := {first: 0}
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		if cell == second:
			return distances[cell]
		for next: int in links[cell]:
			if not distances.has(next):
				distances[next] = distances[cell] + 1
				queue.append(next)
		index += 1
	return -1


func same_zone(first: int, second: int) -> bool:
	if not valid_space(first) or not valid_space(second):
		return false
	var other: Array = _spaces[second].zones
	for zone: String in _spaces[first].zones:
		if zone in other:
			return closed_doors.is_empty() or _distance_in(_links, first, second) == _distance_in(_without_closed_doors(_links), first, second)
	return false


func in_attack_range(from: int, to: int, ranged: bool) -> bool:
	return from != to and (adjacent(from, to) or (ranged and same_zone(from, to)))


func attack_bonus(from: int, to: int) -> int:
	return int(_high_ground.has(Vector2i(from, to)))


## Проходит через союзников, но останавливается только на свободных местах.
## В occupied ключ — место, значение — команда фигуры на нём.
func reachable(from: int, distance: int, team: int, occupied: Dictionary, through_enemies: bool = false, previous: Dictionary = {}, stop_on_allies: bool = false) -> PackedInt32Array:
	var can_cross := func(space: int) -> bool:
		return through_enemies or not occupied.has(space) or int(occupied[space]) == team
	var can_stop := func(space: int) -> bool:
		return not occupied.has(space) or (stop_on_allies and int(occupied[space]) == team)
	var links: Array[PackedInt32Array] = _without_closed_doors(_movement_links).duplicate(true)
	for cell: int in fog_links:
		for other: int in fog_links:
			if cell != other and other not in links[cell]:
				links[cell].append(other)
	return Paths.reachable(links, from, distance, can_cross, can_stop, previous)


func route(from: int, to: int, distance: int, team: int, occupied: Dictionary, through_enemies: bool = false, stop_on_allies: bool = false) -> PackedInt32Array:
	var previous := {}
	if to not in reachable(from, distance, team, occupied, through_enemies, previous, stop_on_allies):
		return []
	var cells := PackedInt32Array([to])
	while cells[0] != from:
		cells.insert(0, previous[cells[0]])
	return cells


func movement_neighbors(from: int) -> PackedInt32Array:
	if not valid_space(from):
		return PackedInt32Array()
	var links: PackedInt32Array = _without_closed_doors(_movement_links)[from].duplicate()
	if from in fog_links:
		for other: int in fog_links:
			if other != from and other not in links:
				links.append(other)
	return links
