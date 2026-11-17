extends RefCounted
## Поиск достижимых узлов в графе поля. Правила прохода задаёт игра.

static func reachable(links: Array[PackedInt32Array], start: int, distance: int, can_cross: Callable, can_stop: Callable, previous: Dictionary = {}) -> PackedInt32Array:
	var destinations := PackedInt32Array()
	if start < 0 or start >= links.size() or distance <= 0:
		return destinations
	var visited: Dictionary = {start: 0}
	var queue: Array[int] = [start]
	var cursor := 0
	while cursor < queue.size():
		var space := queue[cursor]
		cursor += 1
		var steps := int(visited[space]) + 1
		if steps > distance:
			continue
		for neighbor in links[space]:
			if neighbor < 0 or neighbor >= links.size() or visited.has(neighbor) or not can_cross.call(neighbor):
				continue
			visited[neighbor] = steps
			previous[neighbor] = space
			queue.append(neighbor)
			if can_stop.call(neighbor):
				destinations.append(neighbor)
	return destinations
