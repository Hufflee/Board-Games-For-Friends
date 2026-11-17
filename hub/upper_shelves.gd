extends RefCounted
## Разметка полок над шкафом. Координаты узлов хранятся в шагах сетки на задней стене.

# Общая единица 7,5 мм сохраняет прежние точки и позволяет совмещать обе новые сетки.
const UNIT := 0.0075
const LEGACY_TICKS := 20
const BASIC_TICKS := 22
const FINE_TICKS := 11
const GRID_TOP := -2
const TOP := 2.635
const HALF_WIDTH := 220
const MAX_Y := 280
const DEPTH := 0.36
const SHALLOW_DEPTH := DEPTH * 0.5
const THICKNESS := 0.03
const MAX_EDGES := 96
const PREFIX := "above:"
const FRONT := -1.60


static func point(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * UNIT, TOP - cell.y * UNIT)


static func edge(a: Vector2i, b: Vector2i) -> Array:
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		return [b, a]
	return [a, b]


## Старые сохранения и снимки используют 15-сантиметровые координаты.
static func read(config: Dictionary) -> Array:
	var edges: Array = []
	_read_edges(edges, config.get("upper_edges"), LEGACY_TICKS)
	_read_edges(edges, config.get("upper_precise_edges"), 1)
	return edges


static func _read_edges(edges: Array, raw: Variant, unit: int) -> void:
	if not raw is Array:
		return
	for value: Variant in raw:
		if edges.size() >= MAX_EDGES:
			break
		if not value is Array or value.size() != 4 or not value.all(func(i): return i is int and i >= -MAX_Y and i <= MAX_Y):
			continue
		var a := Vector2i(value[0], value[1]) * unit
		var b := Vector2i(value[2], value[3]) * unit
		if a == b or not _in_grid(a) or not _in_grid(b):
			continue
		var ordered := edge(a, b)
		if not edges.has(ordered):
			edges.append(ordered)


static func store(config: Dictionary, edges: Array) -> void:
	var legacy: Array = []
	var precise: Array = []
	for segment: Array in edges:
		var a: Vector2i = segment[0]
		var b: Vector2i = segment[1]
		if _legacy_segment(segment):
			legacy.append([a.x / LEGACY_TICKS, a.y / LEGACY_TICKS, b.x / LEGACY_TICKS, b.y / LEGACY_TICKS])
		else:
			precise.append([a.x, a.y, b.x, b.y])
	config.erase("upper_edges")
	config.erase("upper_precise_edges")
	if not legacy.is_empty():
		config.upper_edges = legacy
	if not precise.is_empty():
		config.upper_precise_edges = precise


static func _in_grid(cell: Vector2i) -> bool:
	return absi(cell.x) <= HALF_WIDTH and cell.y >= GRID_TOP and cell.y <= MAX_Y


static func _legacy_segment(segment: Array) -> bool:
	for p: Vector2i in segment:
		if p.x % LEGACY_TICKS != 0 or p.y % LEGACY_TICKS != 0:
			return false
	return true


static func surface(segment: Array) -> String:
	if _legacy_segment(segment):
		return "%s%d:%d:%d" % [PREFIX, segment[0].x / LEGACY_TICKS, segment[1].x / LEGACY_TICKS, segment[0].y / LEGACY_TICKS]
	return "%su:%d:%d:%d" % [PREFIX, segment[0].x, segment[1].x, segment[0].y]


static func segment_key(segment: Array) -> String:
	return "%d:%d:%d:%d" % [segment[0].x, segment[0].y, segment[1].x, segment[1].y]


static func shallow_keys(config: Dictionary, edges: Array) -> Array[String]:
	var keys: Array[String] = []
	var raw: Variant = config.get("upper_shallow_edges")
	if raw is Array:
		for segment: Array in edges:
			var key := segment_key(segment)
			if raw.has(key):
				keys.append(key)
	return keys


## Все отрезки, связанные с заданными узлами через общие концы.
static func connected(edges: Array, points: Array) -> Array:
	var component: Array = []
	var seen: Dictionary = {}
	var pending := points.duplicate()
	while not pending.is_empty():
		var point_id: Vector2i = pending.pop_back()
		if seen.has(point_id):
			continue
		seen[point_id] = true
		for segment: Array in edges:
			if segment.has(point_id) and not component.has(segment):
				component.append(segment)
				pending.append(segment[1] if segment[0] == point_id else segment[0])
	return component


static func geometry(edges: Array, smoothing: float) -> Dictionary:
	var neighbors: Dictionary = {}
	for segment: Array in edges:
		for i in 2:
			var list: Array = neighbors.get_or_add(segment[i], [])
			list.append(segment[1 - i])
	var corners: Dictionary = {}
	var lines: Array[PackedVector2Array] = []
	for cell: Vector2i in neighbors:
		var adjoining: Array = neighbors[cell]
		if adjoining.size() != 2 or smoothing <= 0.0:
			continue
		var center := point(cell)
		var left := point(adjoining[0])
		var right := point(adjoining[1])
		var first := (left - center).normalized()
		var second := (right - center).normalized()
		if absf(first.cross(second)) < 0.001:
			continue
		var trim := minf(0.13 * smoothing, minf(left.distance_to(center), right.distance_to(center)) * 0.46)
		var a := center + first * trim
		var b := center + second * trim
		corners[cell] = {adjoining[0]: a, adjoining[1]: b}
		var curve := PackedVector2Array()
		for i in 13:
			var t := float(i) / 12.0
			curve.append(a if i == 0 else b if i == 12 else a.lerp(center, t).lerp(center.lerp(b, t), t))
		lines.append(curve)
	var flat: Dictionary = {}
	var support: Dictionary = {}
	for segment: Array in edges:
		var start: Vector2i = segment[0]
		var end: Vector2i = segment[1]
		var a: Vector2 = corners.get(start, {}).get(end, point(start))
		var b: Vector2 = corners.get(end, {}).get(start, point(end))
		lines.append(PackedVector2Array([a, b]))
		if start.y == end.y:
			var id := surface(segment)
			flat[id] = [a, b]
			support[id] = [point(start), point(end)]
	return {"lines": lines, "flat": _flat_runs(flat), "support": _flat_runs(support)}



## Смежные горизонтальные отрезки поддерживают коробку по всей длине общей площадки.
static func _flat_runs(flat: Dictionary) -> Dictionary:
	var ids := flat.keys()
	ids.sort_custom(func(a, b):
		var first: Vector2 = flat[a][0]
		var second: Vector2 = flat[b][0]
		return first.y < second.y if first.y != second.y else first.x < second.x
	)
	var merged: Dictionary = {}
	var span: Array = []
	for id: String in ids:
		var start: Vector2 = flat[id][0]
		var end: Vector2 = flat[id][1]
		if span.is_empty() or span[0].y != start.y or start.x > span[1].x + 0.0001:
			span = [start, end]
		elif end.x > span[1].x:
			span[1] = end
		merged[id] = span
	return merged


## Строит меш и возвращает его передние грани для проверки вместимости.
static func build(parent: Node3D, lines: Array[PackedVector2Array], material: Material, depth: float) -> Array[PackedVector2Array]:
	var faces: Array[PackedVector2Array] = []
	if lines.is_empty():
		return faces
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.set_smooth_group(-1)
	for path: PackedVector2Array in _stitch(lines):
		_extrude(mesh, path, depth, faces)
	mesh.generate_normals()
	mesh.set_material(material)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh.commit()
	parent.add_child(instance)
	return faces


## Цепочки проходят через обычные стыки, заканчиваются на развилках и могут замыкаться в кольцо.
static func _stitch(lines: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var paths: Array[PackedVector2Array] = []
	var links: Dictionary = {}
	for index in lines.size():
		var line := lines[index]
		(links.get_or_add(line[0], []) as Array).append(index)
		(links.get_or_add(line[-1], []) as Array).append(index)
	var used: Dictionary = {}
	for origin: Vector2 in links:
		if links[origin].size() != 2:
			for index: int in links[origin]:
				if not used.has(index):
					paths.append(_walk(lines, links, used, index, origin))
	for index in lines.size():
		if not used.has(index):
			paths.append(_walk(lines, links, used, index, lines[index][0]))
	return paths


static func _walk(lines: Array[PackedVector2Array], links: Dictionary, used: Dictionary, index: int, origin: Vector2) -> PackedVector2Array:
	var path := PackedVector2Array([origin])
	while not used.has(index):
		used[index] = true
		var line := lines[index].duplicate()
		if line[0] != path[-1]:
			line.reverse()
		path.append_array(line.slice(1))
		var next: Array = links[line[-1]]
		if next.size() != 2:
			break
		index = next[1] if next[0] == index else next[0]
	return path


static func _extrude(mesh: SurfaceTool, path: PackedVector2Array, shelf_depth: float, faces: Array[PackedVector2Array]) -> void:
	var closed := path[0] == path[-1]
	var count := path.size() - int(closed)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in count:
		var previous := path[posmod(i - 1, count)] if closed or i > 0 else path[0] * 2.0 - path[1]
		var following := path[(i + 1) % count] if closed or i < count - 1 else path[i] * 2.0 - path[i - 1]
		var a := (path[i] - previous).normalized()
		var b := (following - path[i]).normalized()
		var normal := Vector2(-a.y, a.x)
		var bisector := (normal + Vector2(-b.y, b.x)).normalized()
		var offset := normal * THICKNESS * 0.5 if bisector.is_zero_approx() else (
			bisector * THICKNESS * 0.5 / maxf(0.25, normal.dot(bisector))
		)
		left.append(path[i] + offset)
		right.append(path[i] - offset)
	var front := FRONT - DEPTH + shelf_depth
	for i in count - int(not closed):
		var j := (i + 1) % count
		var a := Vector3(left[i].x, left[i].y, front)
		var b := Vector3(left[j].x, left[j].y, front)
		var c := Vector3(right[j].x, right[j].y, front)
		var d := Vector3(right[i].x, right[i].y, front)
		faces.append(PackedVector2Array([left[i], left[j], right[j], right[i]]))
		var depth := Vector3(0.0, 0.0, -shelf_depth)
		_quad(mesh, a, b, c, d)
		_quad(mesh, d + depth, c + depth, b + depth, a + depth)
		_quad(mesh, b, a, a + depth, b + depth)
		_quad(mesh, d, c, c + depth, d + depth)
		if not closed and i == 0:
			_quad(mesh, a, d, d + depth, a + depth)
		if not closed and j == count - 1:
			_quad(mesh, c, b, b + depth, c + depth)


## Проекция части доски, которая попадает в диапазон высот корпуса коробки.
static func face_range_at_height(face: PackedVector2Array, bottom: float, top: float) -> Vector2:
	var span := Vector2(INF, -INF)
	for i in face.size():
		var a := face[i]
		var b := face[(i + 1) % face.size()]
		if a.y >= bottom and a.y <= top:
			span = Vector2(minf(span.x, a.x), maxf(span.y, a.x))
		var low := minf(a.y, b.y)
		var high := maxf(a.y, b.y)
		if low < bottom and high > bottom:
			var at := lerpf(a.x, b.x, inverse_lerp(a.y, b.y, bottom))
			span = Vector2(minf(span.x, at), maxf(span.y, at))
		if low < top and high > top:
			var at := lerpf(a.x, b.x, inverse_lerp(a.y, b.y, top))
			span = Vector2(minf(span.x, at), maxf(span.y, at))
	return span


static func _quad(mesh: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	mesh.add_vertex(a)
	mesh.add_vertex(b)
	mesh.add_vertex(c)
	mesh.add_vertex(a)
	mesh.add_vertex(c)
	mesh.add_vertex(d)

## Столкновение шара с объёмом доски, включая наклон и скругление.
static func ball_contact(faces: Array[PackedVector2Array], at: Vector3, radius: float, depth: float) -> Array:
	var rear := FRONT - DEPTH
	var z := clampf(at.z, rear, rear + depth)
	if absf(at.z - z) >= radius:
		return []
	var point_xy := Vector2(at.x, at.y)
	var best: Array = []
	var penetration := 0.0
	for face: PackedVector2Array in faces:
		var nearest := Vector2.INF
		var distance := INF
		for i in face.size():
			var candidate := Geometry2D.get_closest_point_to_segment(point_xy, face[i], face[(i + 1) % face.size()])
			var gap := candidate.distance_squared_to(point_xy)
			if gap < distance:
				nearest = candidate
				distance = gap
		var inside := Geometry2D.is_point_in_polygon(point_xy, face)
		var xy := point_xy if inside else nearest
		var direction := at - Vector3(xy.x, xy.y, z)
		var length := direction.length()
		var overlap := radius - length
		if length <= 0.00001:
			direction = Vector3(nearest.x - at.x, nearest.y - at.y, 0.0)
			overlap = radius + direction.length()
			if direction.is_zero_approx():
				direction = Vector3.UP
		if overlap > penetration:
			penetration = overlap
			best = [direction.normalized(), overlap]
	return best
