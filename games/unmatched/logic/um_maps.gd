extends RefCounted
## Разметка полей. Координаты измерены на одном контрольном кадре печатных листов 792×560.

const Board := preload("res://games/unmatched/logic/um_board.gd")
const PRINT_AREA := Rect2(39, 48, 714, 464)
const PRINT_SIZE := Vector2(792, 560)
const Workshop := preload("res://games/unmatched/logic/um_workshop_maps.gd")
const Battlefields := preload("res://games/unmatched/logic/um_battlefields.gd")
const BASE_NAMES := {"marmoreal": "Мармореал", "sarpedon": "Сарпедон", "gardens": "Висячие сады"}
const IMAGES := {"marmoreal": "vol1_a", "sarpedon": "vol1_b"}
# Временно исключены: на этих аренах нет места для начальной расстановки помощников.
const HIDDEN_ARENAS := ["phone_booth", "bathroom_stall"]
const BASE_MAPS := {
	"marmoreal": {
		"spaces": [
			[139, 95, "gy"], [228, 86, "g"], [314, 86, "g"], [399, 109, "gev"],
			[491, 86, "g"], [582, 86, "g"], [669, 148, "v"], [122, 173, "yer"],
			[208, 182, "ye"], [301, 188, "ev"], [492, 190, "ev"], [585, 184, "ev"],
			[398, 216, "ev"], [123, 252, "yr"], [250, 252, "ev"], [337, 283, "evm"],
			[460, 283, "evm"], [547, 255, "ev"], [672, 236, "vp"], [132, 330, "yr"],
			[215, 340, "r"], [312, 390, "evb"], [398, 330, "evm"], [481, 390, "evb"],
			[599, 354, "p"], [668, 316, "p"], [171, 449, "b"], [266, 469, "b"],
			[358, 465, "mb"], [439, 471, "mb"], [555, 439, "pb"],
		],
		"starts": [13, 30, 2, 11],
		"edges": [
			[0, 1], [0, 7], [1, 2], [2, 3], [3, 4], [3, 12], [4, 5], [5, 6],
			[6, 11], [6, 18], [7, 8], [7, 13], [8, 9], [8, 14], [9, 12], [9, 14], [9, 15],
			[10, 11], [10, 12], [10, 16], [10, 17], [11, 17],
			[13, 19], [14, 15], [15, 22], [16, 17], [16, 22],
			[17, 18], [18, 25], [19, 20], [19, 26], [20, 21], [21, 23],
			[22, 28], [22, 29], [23, 24], [24, 25], [24, 30], [26, 27], [27, 28], [28, 29], [29, 30],
		],
	},
	"sarpedon": {
		"spaces": [
			[81, 103, "e"], [164, 86, "e"], [236, 114, "e"], [310, 88, "e"],
			[402, 94, "y"], [640, 122, "b"], [712, 90, "b"], [77, 187, "e"],
			[151, 162, "e"], [219, 194, "e"], [295, 176, "e"], [378, 190, "y"],
			[448, 156, "y"], [518, 198, "y"], [599, 189, "b"], [715, 175, "r"],
			[76, 277, "v"], [147, 307, "v"], [222, 271, "v"], [325, 264, "yp"],
			[571, 260, "ybp"], [713, 251, "r"], [79, 354, "v"], [155, 395, "v"],
			[273, 335, "yp"], [347, 387, "p"], [525, 322, "ybp"], [607, 326, "p"],
			[716, 328, "r"], [87, 431, "v"], [173, 471, "p"], [237, 410, "p"],
			[410, 433, "p"], [481, 471, "p"], [492, 394, "p"], [579, 476, "r"],
			[652, 460, "r"], [663, 386, "r"],
		],
		"starts": [18, 34, 2, 14],
		"edges": [
			[0, 1], [0, 7], [0, 8], [1, 2], [1, 8], [2, 3], [2, 9], [2, 10], [3, 4], [3, 10],
			[4, 11], [4, 12], [5, 6], [5, 14], [5, 15], [6, 15], [7, 8], [7, 16],
			[8, 9], [9, 10], [9, 18], [10, 11], [10, 19], [11, 12], [11, 19], [12, 13], [13, 14],
			[13, 20], [14, 20], [15, 21], [16, 17], [16, 22], [17, 18], [17, 22],
			[18, 19], [18, 24], [19, 24], [19, 25], [20, 26], [20, 27], [21, 28],
			[22, 23], [22, 29], [23, 29], [23, 30], [23, 31], [24, 25], [24, 31], [25, 31], [25, 32],
			[26, 27], [26, 34], [27, 37], [28, 37], [29, 30], [30, 31], [32, 33],
			[33, 34], [33, 35], [35, 36], [36, 37],
		],
	},
	"gardens": {
		"size": Vector2(1337, 866),
		"spaces": [
			[145, 110, "r"], [313, 88, "gl"], [491, 79, "gl"], [647, 83, "g"],
			[798, 113, "g"], [970, 95, "gel"], [1203, 111, "e"], [1238, 271, "e"],
			[1230, 445, "e"], [1242, 618, "e"], [1218, 772, "e"], [950, 679, "p"],
			[809, 784, "yp"], [559, 785, "y"], [378, 789, "y"], [171, 755, "ry"],
			[126, 598, "ro"], [127, 436, "ro"], [132, 276, "r"], [345, 408, "rol"],
			[407, 274, "l"], [556, 272, "l"], [707, 291, "bgl"], [912, 272, "g"],
			[1048, 345, "gp"], [1034, 528, "p"], [910, 436, "bp"], [732, 435, "b"],
			[697, 573, "by"], [553, 613, "by"], [409, 569, "oy"], [267, 534, "ro"],
			[556, 440, "bol"],
		],
		"starts": [3, 13, 18, 9],
		"edges": [
			[0, 1], [0, 18], [1, 2], [1, 20], [2, 3], [3, 4], [3, 21], [3, 22],
			[4, 23], [5, 6], [5, 22], [6, 7], [7, 8], [7, 24], [8, 9], [8, 24],
			[8, 25], [8, 26], [9, 10], [9, 11], [10, 11], [11, 12], [11, 25], [12, 13],
			[13, 14], [13, 29], [14, 15], [15, 16], [16, 17], [16, 31], [17, 18], [17, 19],
			[17, 31], [18, 19], [19, 20], [19, 31], [20, 21], [21, 22], [22, 27], [23, 24],
			[24, 26], [25, 26], [26, 27], [27, 28], [27, 32], [28, 29], [28, 32], [29, 30],
			[29, 32], [30, 31],
		],
		"high_ground": [
			Vector2i(1, 2), Vector2i(1, 20), Vector2i(21, 3), Vector2i(22, 3),
			Vector2i(5, 22), Vector2i(5, 6), Vector2i(18, 19), Vector2i(17, 19),
			Vector2i(32, 27), Vector2i(27, 26), Vector2i(26, 8), Vector2i(24, 7),
			Vector2i(24, 8), Vector2i(25, 8), Vector2i(32, 28), Vector2i(32, 29),
			Vector2i(29, 13), Vector2i(15, 14), Vector2i(14, 13), Vector2i(13, 12),
		],
	},
}


static var MAPS: Dictionary = BASE_MAPS.merged(Workshop.MAPS)
static var NAMES: Dictionary = _names()


static func _names() -> Dictionary:
	var names := BASE_NAMES.duplicate()
	for id: String in Workshop.MAPS:
		if id not in HIDDEN_ARENAS:
			names[id] = Workshop.MAPS[id].name
	return names


static func supports(arena: String, seats: int) -> bool:
	return NAMES.has(arena) and MAPS[arena].starts.size() >= seats


static func create(arena: String) -> RefCounted:
	if not MAPS.has(arena):
		return null
	var map: Dictionary = MAPS[arena]
	var spaces: Array[Dictionary] = []
	var links: Array[PackedInt32Array] = []
	for entry: Array in map.spaces:
		var zones: Array = Array(str(entry[2]).split("", false))
		var point := Vector2(entry[0], entry[1])
		var dimensions: Variant = map.get("size")
		var at := normalize(point)
		if dimensions is Array:
			at = point / Vector2(dimensions[0], dimensions[1])
		elif dimensions is Vector2:
			at = point / dimensions
		spaces.append({"at": at, "zones": zones})
		links.append(PackedInt32Array())
	for edge: Array in map.edges:
		links[edge[0]].append(edge[1])
		links[edge[1]].append(edge[0])
	var high_ground: Array[Vector2i] = []
	high_ground.assign(map.get("high_ground", []))
	var movement_links: Array[PackedInt32Array] = links.duplicate(true)
	for edge: Array in map.get("one_way", []):
		movement_links[edge[1]].erase(edge[0])
	for edge: Array in map.get("move_only", []):
		movement_links[edge[0]].append(edge[1])
		movement_links[edge[1]].append(edge[0])
	var board := Board.new(spaces, links, PackedInt32Array(map.starts), high_ground, movement_links)
	board.item_pool = Battlefields.POOLS.get(arena, []).duplicate()
	board.item_slots = Battlefields.SLOTS.get(arena, []).duplicate(true)
	if arena == "pandemonium":
		board.dangerous_paths = [Vector2i(2, 20), Vector2i(3, 20), Vector2i(4, 5),
			Vector2i(17, 19), Vector2i(8, 24), Vector2i(8, 25), Vector2i(14, 15)]
	if arena == "heorot":
		# У каждой из трёх дверей один наружный вход и две дорожки внутрь.
		board.doors = [[Vector2i(17, 19), Vector2i(17, 26)], [Vector2i(3, 20), Vector2i(3, 21)],
			[Vector2i(12, 24), Vector2i(12, 25)]]
	if arena == "santa_s_workshop":
		board.conveyor = PackedInt32Array([21, 27, 13, 12, 11, 10])
		board.conveyor_exit = PackedInt32Array([5, 6, 7, 8, 23, 24, 33])
	return board


static func normalize(point: Vector2) -> Vector2:
	return (point - PRINT_AREA.position) / PRINT_AREA.size
