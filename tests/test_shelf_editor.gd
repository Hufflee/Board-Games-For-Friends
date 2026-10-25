extends SceneTree
## Размеры ячеек, упаковка, положения коробок и сохранение без пропусков/дублей.
var checks := 0
var errors := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)


func verify(state: Dictionary, sizes: Dictionary) -> void:
	var seen: Dictionary = {}
	var limits := ShelfConfig.limits(state.config)
	check(
		state.placements.size() == int(state.config.rows) * int(state.config.cols),
		"Число ячеек соответствует рядам и столбцам"
	)
	for i in state.placements.size():
		var layout := ShelfConfig.row_layout(
			state.placements[i], sizes, state.poses, float(state.config.height)
		)
		for id in state.placements[i]:
			check(sizes.has(id) and not seen.has(id), "Каждая коробка существует и присутствует один раз")
			seen[id] = true
			var ext := ShelfConfig.item_extent(str(id), sizes[id], int(state.poses.get(id, 1)))
			check(ext.y <= float(state.config.height) + 0.0005, "Коробка влезает по высоте")
			var at: Transform3D = layout.boxes[id]
			check(
				at.origin.y + ext.y * 0.5 <= float(state.config.height) + 0.0005,
				"Стопка не задевает верхнюю полку"
			)
		check(float(layout.width) <= float(limits[i]) + 0.0005, "Коробки не заходят на перегородки и Перудо")
	check(seen.size() == sizes.size(), "Ни одна игра не потерялась")


func _initialize() -> void:
	_four_poses()
	var sizes: Dictionary = {
		"a": Vector3(0.05, 0.3, 0.25), "b": Vector3(0.08, 0.3, 0.2), "c": Vector3(0.06, 0.28, 0.3)
	}
	var config: Dictionary = {"rows": 4, "cols": 1, "width": 0.65, "height": 0.36, "cups": 2}
	var state := ShelfConfig.solve(config, [["a", "b"], ["c"], [], []], sizes, {})
	check(state.ok, "Исходная раскладка допустима")
	verify(state, sizes)
	var wider := config.duplicate()
	wider.cols = 3
	state = ShelfConfig.solve(wider, state.placements, sizes, {}, 1)
	check(state.ok, "Добавление столбцов")
	verify(state, sizes)
	var fewer := config.duplicate()
	fewer.rows = 1
	fewer.width = 0.7
	fewer.cups = 0
	state = ShelfConfig.solve(fewer, [["a", "b"], ["c"]], sizes, {}, 1)
	check(state.ok, "Уменьшение рядов переносит все коробки")
	verify(state, sizes)
	var impossible := config.duplicate()
	impossible.rows = 1
	impossible.width = 0.2
	var impossible_sizes := sizes.duplicate()
	impossible_sizes.extra = Vector3(0.1, 0.3, 0.2)
	impossible.cups = 0
	check(
		not ShelfConfig.solve(impossible, [["a", "b", "c", "extra"]], impossible_sizes, {}, 1).ok,
		"Тесный шкаф отклоняется без потери игр"
	)
	check(
		ShelfConfig.solve(config, [["a", "b", "c"]], sizes, {"a": 0, "b": 0, "c": 0}, 1).ok,
		"Коробки обложкой размещаются на разных полках"
	)
	check(ShelfConfig.pose_basis(0).x.dot(Vector3.BACK) > 0.99, "Обложка смотрит на игрока")
	check(ShelfConfig.pose_basis(1).z.dot(Vector3.BACK) > 0.99, "Вертикальный корешок смотрит на игрока")
	check(
		(
			ShelfConfig.pose_basis(2).z.dot(Vector3.BACK) > 0.99
			and ShelfConfig.pose_basis(2).y.dot(Vector3.RIGHT) > 0.99
		),
		"Лежащая коробка корешком к игроку, надпись слева направо"
	)
	for mode in 3:
		var basis := ShelfConfig.pose_basis(mode)
		var size_value := Vector3(0.05, 0.3, 0.25)
		var actual := (
			basis.x.abs() * size_value.x + basis.y.abs() * size_value.y + basis.z.abs() * size_value.z
		)
		check(
			actual.is_equal_approx(ShelfConfig.extent(size_value, mode)),
			"Размеры соответствуют повороту коробки"
		)
	var short := config.duplicate()
	short.height = 0.14
	check(
		not ShelfConfig.solve(short, [["a", "b", "c"]], sizes, {}).ok, "Высота защищает вертикальные коробки"
	)
	state = ShelfConfig.solve(short, [["a", "b", "c"]], sizes, {"a": 2, "b": 2, "c": 2})
	check(state.ok, "Лежащие коробки помещаются на низких полках")
	verify(state, sizes)
	var tricky: Dictionary = {}
	var widths: Array = [0.3, 0.3, 0.13, 0.13, 0.2, 0.2]
	for i in widths.size():
		tricky[str(i)] = Vector3(float(widths[i]), 0.3, 0.3)
	state = ShelfConfig.solve(
		{"rows": 1, "cols": 3, "width": 0.506, "height": 0.36, "cups": 2},
		[["0", "1", "2", "3", "4", "5"]],
		tricky,
		{}
	)
	check(state.ok, "Поиск находит упаковку, когда исходный жадный порядок не подходит")
	verify(state, tricky)
	var path := "user://test_shelf_editor_%d.cfg" % Time.get_ticks_usec()
	check(
		ShelfConfig.save_state(config, [["a", "a", "deleted"], ["b"]], {"a": 0, "b": 2}, path) == OK,
		"Конфигурация сохраняется"
	)
	state = ShelfConfig.load_state(config, [["a", "b", "c"]], sizes, path)
	check(state.ok and state.poses.a == 0 and state.poses.b == 2, "Положения восстанавливаются")
	verify(state, sizes)
	DirAccess.remove_absolute(path)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 120:
		var modes: Dictionary = {}
		for id in sizes:
			modes[id] = rng.randi_range(0, 2)
		var random_config: Dictionary = {
			"rows": rng.randi_range(1, 8),
			"cols": rng.randi_range(1, 6),
			"width": rng.randf_range(0.2, 1.2),
			"height": rng.randf_range(0.14, 0.7),
			"cups": 0
		}
		state = ShelfConfig.solve(random_config, [["a", "b", "c"]], sizes, modes)
		if state.ok:
			verify(state, sizes)
	var stack_modes := {"a": 2, "b": 2, "c": 2}
	var stack := ShelfConfig.row_layout(["a", "b", "c"], sizes, stack_modes, 0.36)
	check(stack.piles.size() == 1, "Лежащие коробки складываются друг на друга")
	check(
		(stack.boxes.b as Transform3D).origin.y > (stack.boxes.a as Transform3D).origin.y,
		"Вторая коробка находится над первой"
	)
	check(
		not (stack.boxes.a as Transform3D).basis.is_equal_approx((stack.boxes.b as Transform3D).basis),
		"Повороты коробок в стопке немного различаются"
	)
	check(
		stack == ShelfConfig.row_layout(["a", "b", "c"], sizes, stack_modes, 0.36),
		"Укладка не меняется при повторном обновлении"
	)
	check(
		ShelfConfig.row_layout(["a", "b", "c"], sizes, stack_modes, 0.14).piles.size() == 2,
		"Переполненная по высоте стопка продолжается рядом"
	)
	var tight_stack := config.duplicate()
	tight_stack.rows = 1
	tight_stack.width = 0.4
	tight_stack.cups = 0
	var with_cups := sizes.duplicate()
	with_cups.perudo = Vector3(0.38, 0.17, 0.26)
	state = ShelfConfig.solve(tight_stack, [["a", "b", "c", "perudo"]], with_cups, stack_modes)
	check(not state.ok, "Стопка учитывает фактическое место переносимого Перудо")
	tight_stack.cols = 2
	tight_stack.cups = 1
	state = ShelfConfig.solve(tight_stack, [["a", "b", "c", "perudo"]], with_cups, stack_modes)
	check(
		state.ok and state.placements[0].size() == 3,
		"Стопка помещается там, где три коробки рядом не влезают"
	)
	verify(state, with_cups)
	for id in stack.boxes:
		var home: Transform3D = stack.boxes[id]
		var actual: Vector3 = (
			home.basis.x.abs() * sizes[id].x
			+ home.basis.y.abs() * sizes[id].y
			+ home.basis.z.abs() * sizes[id].z
		)
		check(
			(
				home.origin.x - actual.x * 0.5 >= -0.0005
				and home.origin.x + actual.x * 0.5 <= float(stack.width) + 0.0005
			),
			"Неровная стопка не выходит за отведённую ширину"
		)
		check(
			(
				home.origin.z - actual.z * 0.5 >= -0.0005
				and home.origin.z + actual.z * 0.5 <= ShelfConfig.CELL_DEPTH + 0.0005
			),
			"Поворот не выталкивает коробку за глубину полки"
		)
	var maximum := ShelfConfig.normalized({"rows": 8, "cols": 6, "width": 100.0, "height": 100.0})
	check(
		(
			float(maximum.width) * int(maximum.cols) + (int(maximum.cols) + 1) * ShelfConfig.BOARD
			<= ShelfConfig.MAX_WIDTH + 0.0001
		),
		"Ширина ограничена свободным местом комнаты"
	)
	check(
		(
			float(maximum.height) * int(maximum.rows) + (int(maximum.rows) + 1) * ShelfConfig.BOARD
			<= ShelfConfig.MAX_HEIGHT + 0.0001
		),
		"Высота ограничена свободным местом комнаты"
	)
	for mode in 3:
		var icon_image := ShelfIcons.icon(mode).get_image()
		check(icon_image.get_pixel(16, 16).a > 0.99, "Иконка положения заполнена цветом")
	for size_value: Vector3 in [Vector3(0.044, 0.3, 0.205), Vector3(0.07, 0.3, 0.162)]:
		for mode in 3:
			var atypical_sizes := {"atypical": size_value}
			var atypical_modes := {"atypical": mode}
			state = ShelfConfig.solve(config, [["atypical"]], atypical_sizes, atypical_modes)
			check(state.ok, "Нетипичная коробка помещается во всех трёх положениях")
			var layout := ShelfConfig.row_layout(["atypical"], atypical_sizes, atypical_modes, 0.36)
			if mode == 0:
				var front: float = (
					(layout.boxes.atypical as Transform3D).origin.z
					+ ShelfConfig.extent(size_value, mode).z * 0.5
				)
				check(
					is_equal_approx(front, ShelfConfig.CELL_DEPTH - 0.024),
					"Обложки любой толщины стоят на одинаковом переднем крае"
				)
	var figure_sizes := {"shelf_girl": Vector3(0.14, 0.285, 0.14), "book": Vector3(0.05, 0.3, 0.25)}
	for ratio: float in [0.0, 0.5, 1.0]:
		var free := ShelfConfig.row_layout(["book", "shelf_girl"], figure_sizes, {}, 0.36, ratio, 0.5)
		var figure_home: Transform3D = free.boxes.shelf_girl
		check(
			is_equal_approx(figure_home.origin.x, 0.07 + 0.36 * ratio),
			"Фигурка свободно занимает выбранную часть полки"
		)
		check(
			is_equal_approx(figure_home.origin.z, ShelfConfig.CELL_DEPTH - 0.024 - 0.07),
			"Глубина фигурки фиксирована у края"
		)
		var book_home: Transform3D = free.boxes.book
		check(
			absf(book_home.origin.x - figure_home.origin.x) >= 0.095 - 0.0005,
			"Коробки не пересекают фигурку в свободной позиции"
		)
	var supported := ShelfConfig.row_layout(
		["a", "b"], {"a": Vector3(0.05, 0.3, 0.25), "b": Vector3(0.06, 0.3, 0.25)}, {"a": 2, "b": 0}, 0.36
	)
	check(supported.piles.size() == 1, "Коробка обложкой устанавливается поверх лежащей")
	check(
		is_equal_approx((supported.boxes.b as Transform3D).origin.y - 0.15, 0.05),
		"Обложка опирается на верх лежащей коробки"
	)
	check(
		(
			(
				ShelfConfig
				. row_layout(
					["a", "b"],
					{"a": Vector3(0.08, 0.3, 0.25), "b": Vector3(0.06, 0.3, 0.25)},
					{"a": 2, "b": 0},
					0.36
				)
				. piles
				. size()
			)
			== 2
		),
		"Недостаточная высота не позволяет пересечь верхнюю полку"
	)
	for mode in 2:
		var cups := ShelfConfig.item_extent("perudo", Vector3(0.38, 0.17, 0.26), mode)
		check(
			cups.y > 0.1 and cups.z < ShelfConfig.CELL_DEPTH, "Оба положения Перудо имеют корректные габариты"
		)
	check(
		ShelfConfig.item_basis("perudo", 0).z.normalized().dot(Vector3.BACK) > 0.99,
		"Перудо поворачивается передней стороной к игроку"
	)
	print("SHELF EDITOR: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)


## Проверяем реальную ориентацию крышки, габариты и единый передний край четырёх поз.
func _four_poses() -> void:
	var size_value := Vector3(0.05, 0.3, 0.2)
	for mode in 4:
		var basis := ShelfConfig.pose_basis(mode)
		var actual := (
			basis.x.abs() * size_value.x + basis.y.abs() * size_value.y + basis.z.abs() * size_value.z
		)
		check(
			actual.is_equal_approx(ShelfConfig.extent(size_value, mode)),
			"Габариты новой позы совпадают с поворотом модели"
		)
		var layout := ShelfConfig.row_layout(["a"], {"a": size_value}, {"a": mode}, 0.5)
		var ext := ShelfConfig.item_occupied("a", size_value, mode)
		var at: Transform3D = layout.boxes.a
		# Лежащие позы содержат стабильный небольшой сдвиг по глубине.
		check(
			absf(at.origin.z + ext.z * 0.5 - (ShelfConfig.CELL_DEPTH - 0.024)) < 0.01,
			"Все позы выровнены по переднему краю"
		)
	check(
		ShelfConfig.item_basis("dangerous_words", 2).x.dot(Vector3.UP) > 0.99,
		"У Опасных слов сверху крышка, а не задник"
	)
	check(
		ShelfConfig.item_basis("dangerous_words", 2).y.dot(Vector3.LEFT) > 0.99,
		"Торец Опасных слов развёрнут для чтения"
	)
	check(ShelfConfig.pose_basis(3).x.dot(Vector3.BACK) > 0.99, "В четвёртой позе крышка смотрит к игроку")
