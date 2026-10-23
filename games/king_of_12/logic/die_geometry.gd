class_name K12DieGeometry
extends RefCounted
## Геометрия настоящего додекаэдра с нумерацией, совпадающей с K12Dice:
## грань 1 сверху, кольцо 2..6 вокруг неё, противоположные грани в сумме дают 13.

const PHI := 1.6180339887

static var _data: Dictionary = {}
static var _d6: Dictionary = {}


## {face: {normal, up, verts: PackedVector3Array (по кругу), center}}
static func faces() -> Dictionary:
	if _data.is_empty():
		_build()
	return _data


## Поворот кубика, при котором грань face смотрит на камеру (+Z), а число стоит ровно (+Y).
static func orientation(face: int) -> Quaternion:
	var f: Dictionary = faces()[face]
	var n: Vector3 = f["normal"]
	var u: Vector3 = f["up"]
	return Quaternion(Basis(u.cross(n), u, n).transposed())


## Шестигранник (куб): противоположные грани в сумме дают 7. Тот же формат, что faces().
static func faces_d6() -> Dictionary:
	if _d6.is_empty():
		var h := 0.86
		for spec in [[1, Vector3(0, 0, 1), Vector3.UP], [6, Vector3(0, 0, -1), Vector3.UP], [2, Vector3.UP, Vector3(0, 0, -1)],
				[5, Vector3.DOWN, Vector3(0, 0, 1)], [3, Vector3.RIGHT, Vector3.UP], [4, Vector3.LEFT, Vector3.UP]]:
			var n: Vector3 = spec[1]
			var u: Vector3 = spec[2]
			var r := u.cross(n)
			var c := n * h
			_d6[spec[0]] = {"normal": n, "up": u, "center": c,
				"verts": PackedVector3Array([c + (-r - u) * h, c + (r - u) * h, c + (r + u) * h, c + (-r + u) * h])}
	return _d6


static func orientation_d6(face: int) -> Quaternion:
	var f: Dictionary = faces_d6()[face]
	var n: Vector3 = f["normal"]
	var u: Vector3 = f["up"]
	return Quaternion(Basis(u.cross(n), u, n).transposed())


static func _build() -> void:
	var normals: Array[Vector3] = []
	for a in [-1.0, 1.0]:
		for b in [-PHI, PHI]:
			normals.append(Vector3(a, 0, b).normalized())
			normals.append(Vector3(0, b, a).normalized())
			normals.append(Vector3(b, a, 0).normalized())
	var verts: Array[Vector3] = []
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				verts.append(Vector3(x, y, z))
	var ip := 1.0 / PHI
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			verts.append(Vector3(0, a * ip, b * PHI))
			verts.append(Vector3(a * ip, b * PHI, 0))
			verts.append(Vector3(a * PHI, 0, b * ip))

	var top := normals[0]
	var e1 := (Vector3.UP if absf(top.y) < 0.9 else Vector3.RIGHT).cross(top).normalized()
	var e2 := top.cross(e1)
	var number := {}
	number[top] = 1
	number[-top] = 12
	var ring: Array = normals.filter(func(n): return n.dot(top) > 0.1 and n.dot(top) < 0.99)
	ring.sort_custom(func(a, b): return atan2(a.dot(e2), a.dot(e1)) < atan2(b.dot(e2), b.dot(e1)))
	for i in ring.size():
		number[ring[i]] = 2 + i
		number[-ring[i]] = 13 - (2 + i)

	for n in normals:
		var face_verts: Array = verts.filter(func(v): return v.dot(n) > 1.3)
		var c := Vector3.ZERO
		for v in face_verts:
			c += v
		c /= face_verts.size()
		var fe1: Vector3 = (face_verts[0] - c).normalized()
		var fe2 := n.cross(fe1)
		face_verts.sort_custom(func(a, b): return atan2((a - c).dot(fe2), (a - c).dot(fe1)) < atan2((b - c).dot(fe2), (b - c).dot(fe1)))
		var up := top - n * top.dot(n)
		if up.length() < 0.01:
			up = e1 - n * e1.dot(n)
		_data[number[n]] = {
			"normal": n,
			"up": up.normalized(),
			"verts": PackedVector3Array(face_verts),
			"center": c,
		}
