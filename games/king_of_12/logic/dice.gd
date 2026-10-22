class_name K12Dice
extends RefCounted
## Двенадцатигранный кубик (додекаэдр): противоположные грани в сумме дают 13.
##
## Раскладка: верх = 1, верхнее кольцо U = 2..6, нижнее кольцо L, низ = 12.
## U[i] соседствует с верхом, U[i±1], L[i], L[i+1];
## L[j] соседствует с низом, L[j±1], U[j], U[j-1]; напротив U[i] лежит L[i+3].

const FACES := 12

static var _neighbors: Dictionary = {}


static func opposite(face: int) -> int:
	return 13 - face


static func neighbors(face: int) -> Array:
	if _neighbors.is_empty():
		_build()
	return _neighbors[face].duplicate()


static func _build() -> void:
	var top := 1
	var bottom := 12
	var u: Array[int] = [2, 3, 4, 5, 6]
	var l: Array[int] = [0, 0, 0, 0, 0]
	for i in 5:
		l[(i + 3) % 5] = 13 - u[i]
	var adj := {}
	for f in range(1, FACES + 1):
		adj[f] = []
	var link := func(a: int, b: int) -> void:
		if not adj[a].has(b):
			adj[a].append(b)
		if not adj[b].has(a):
			adj[b].append(a)
	for i in 5:
		link.call(top, u[i])
		link.call(bottom, l[i])
		link.call(u[i], u[(i + 1) % 5])
		link.call(l[i], l[(i + 1) % 5])
		link.call(u[i], l[i])
		link.call(u[i], l[(i + 1) % 5])
	for f in adj:
		adj[f].sort()
	_neighbors = adj
