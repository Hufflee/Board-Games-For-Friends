## Сравнение всех восьми персонажей в 1280×720 и проверка сохранности арта.
## Запуск: godot --path . res://games/brodilka/ui/br_pawn_outline_fixture.tscn
extends Control

var _errors := 0


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	for i in BRStyle.PAWN_COUNT:
		var source: Texture2D = load(BRStyle.ART + "cards/pawn_%d.png" % i)
		var texture := BRStyle.pawn_tex(i)
		_check(texture == BRStyle.pawn_tex(i), "Кеш персонажа %d" % i)
		if i >= 5:
			_check(texture == source, "Новый персонаж без дополнительной кромки %d" % i)
			continue
		var before := source.get_image()
		var after := texture.get_image()
		var pad := (after.get_width() - before.get_width()) / 2
		var intact := true
		var added_outline := false
		for y in before.get_height():
			for x in before.get_width():
				var pixel := before.get_pixel(x, y)
				if pixel.a == 1.0 and pixel != after.get_pixel(x + pad, y + pad):
					intact = false
				if pixel.a == 0.0 and after.get_pixel(x + pad, y + pad).a > 0.5:
					added_outline = true
		_check(intact, "Непрозрачный рисунок сохранён %d" % i)
		_check(added_outline, "Внешняя кромка добавлена %d" % i)
		var clear_edges := true
		for x in after.get_width():
			clear_edges = clear_edges and after.get_pixel(x, 0).a == 0.0
			clear_edges = clear_edges and after.get_pixel(x, after.get_height() - 1).a == 0.0
		for y in after.get_height():
			clear_edges = clear_edges and after.get_pixel(0, y).a == 0.0
			clear_edges = clear_edges and after.get_pixel(after.get_width() - 1, y).a == 0.0
		_check(clear_edges, "Кромка не срезана %d" % i)
	for mode in ["light", "dark"]:
		Prefs.theme_mode = mode
		_build()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "res://build/shots/br_pawn_outline_%s.png" % mode
		_check(get_viewport().get_texture().get_image().save_png(path) == OK, "Скриншот " + mode)
	print("КОНТУР: ошибок ", _errors)
	get_tree().quit(_errors)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_errors += 1
		push_error(message)


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var bg := ColorRect.new()
	bg.color = BRStyle.WOOD_DARK if BRStyle.dark() else BRStyle.WOOD
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	add_child(BRStyle.label("Все 8 · %s · сверху исходники, ниже единая кромка" % Prefs.theme_mode, 22, BRStyle.PARCH))
	for row in 4:
		var top: float = [40.0, 272.0, 504.0, 656.0][row]
		var height: float = [200.0, 200.0, 130.0, 46.0][row]
		for i in BRStyle.PAWN_COUNT:
			var rect := TextureRect.new()
			rect.texture = load(BRStyle.ART + "cards/pawn_%d.png" % i) if row == 0 else BRStyle.pawn_tex(i)
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			rect.position = Vector2(24 + i * 154, top)
			rect.size = Vector2(144, height)
			add_child(rect)
			if row == 0:
				var caption := BRStyle.label(str(i + 1) + (" · старый" if i < 5 else " · новый"), 14, BRStyle.PARCH)
				caption.position = Vector2(32 + i * 154, 244)
				add_child(caption)
