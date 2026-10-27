extends Control
## Каталог публичных карт: полный состав, поиск/типы/DLC, пагинация, просмотр и720p.
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func settle() -> void:
	await get_tree().create_timer(0.2).timeout

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	_run.call_deferred()

func _run() -> void:
	for id in ["brodilka", "four_souls"]:
		var app: Control = load("res://games/%s/ui/main.tscn" % id).instantiate()
		get_tree().root.add_child(app)
		get_tree().current_scene = app
		for mode in ["light", "dark"]:
			Prefs.theme_mode = mode
			get_tree().root.theme = load("res://games/brodilka/ui/br_style.gd").theme() if id == "brodilka" else load("res://games/four_souls/ui/fs_style.gd").theme()
			app.show_card_pool()
			await settle()
			var browser: Control = app.get_node("CardPool")
			var count: int = browser.entries.size()
			var expected: int = load("res://games/four_souls/logic/fs_data.gd").data().cards.size() if id == "four_souls" else BRData.GOODBAD.size() + BRData.TADAM.size() + BRData.SHOP.size()
			check(count == expected, "Полный печатный каталог " + id)
			check(browser._grid.get_child_count() == 12, "Только12 карт на странице")
			for entry: Dictionary in browser.entries:
				check(ResourceLoader.exists(entry.path), "Изображение существует: " + str(entry.path))
			check(browser._preview.texture == null, "До выбора нет чужого игрового состояния")
			browser._grid.get_child(0).mouse_entered.emit()
			check(browser._preview.texture != null, "Крупный просмотр по наведению")
			var rotate: Button = browser._preview.get_parent().get_child(2)
			rotate.pressed.emit()
			check(is_equal_approx(browser._preview.rotation, PI), "Перевёрнутую половину можно прочитать")
			browser._grid.get_child(1).pressed.emit()
			check(is_zero_approx(browser._preview.rotation), "Новая карта показывается прямо")
			browser._next.pressed.emit()
			check(browser._page == 1, "Следующая страница")
			browser._group.select(1)
			browser._group.item_selected.emit(1)
			check(browser._page == 0 and browser._filtered.all(func(entry): return entry.group == browser._group.get_item_text(1)), "Фильтр типа и сброс страницы")
			browser._group.select(0)
			browser._query.text = "НЕСУЩЕСТВУЮЩАЯКАРТА123"
			browser._filter()
			check(browser._filtered.is_empty() and browser._grid.get_child_count() == 0 and browser._next.disabled, "Пустой результат без лишних страниц")
			browser._query.text = str(browser.entries[0].title).to_lower()
			browser._filter()
			check(not browser._filtered.is_empty(), "Поиск без учёта регистра")
			browser._query.text = ""
			if id == "four_souls":
				browser._edition.select(1)
				browser._filter()
				var base_count: int = browser._filtered.size()
				check(browser._filtered.all(func(entry): return entry.base), "Только базовые")
				browser._edition.select(2)
				browser._filter()
				check(browser._filtered.all(func(entry): return not entry.base) and browser._filtered.size() + base_count == count, "DLC дополняет базу без потерь")
				browser._edition.select(0)
			browser._filter()
			browser._grid.get_child(0).pressed.emit()
			await settle()
			check(get_viewport_rect().encloses(browser._preview.get_global_rect()), "Просмотр помещается в720p")
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://build/card_pool/%s-%s.png" % [id, mode])
			browser.queue_free()
			await settle()
		get_tree().current_scene = self
		app.queue_free()
		await settle()
	print("КАТАЛОГ: проверок=", checks, " ошибок=", errors)
	await Sfx.request_quit(1 if errors else 0)
