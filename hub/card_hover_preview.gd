## Крупный просмотр рядом с картой. Фабрика возвращает Control в исходном размере.
extends RefCounted

const Magnifier = preload("res://hub/card_magnifier.gd")


static func wire(source: Control, build: Callable, zoom := 1.8, magnify_source := true) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 35
	source.add_child(layer)
	var clear := func() -> void:
		for child: Node in layer.get_children():
			layer.remove_child(child)
			child.queue_free()
	source.mouse_exited.connect(clear)
	source.visibility_changed.connect(func():
		if not source.is_visible_in_tree():
			clear.call())
	source.mouse_entered.connect(func():
		clear.call()
		if magnify_source and Magnifier.offer(source):
			return
		var preview := build.call() as Control
		if preview == null:
			return
		preview.modulate.a = 0.0
		layer.add_child(preview)
		preview.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
		await source.get_tree().process_frame
		if not is_instance_valid(preview) or not preview.is_inside_tree():
			return
		var bounds := source.get_viewport_rect().size
		var original := preview.size.max(preview.get_combined_minimum_size())
		var factor := minf(zoom, minf((bounds.x - 16.0) / maxf(1.0, original.x),
			(bounds.y - 64.0) / maxf(1.0, original.y)))
		var display_size := original * factor
		var rect := source.get_global_rect()
		var x := rect.end.x + 12.0 if rect.get_center().x < bounds.x * 0.5 else rect.position.x - display_size.x - 12.0
		preview.pivot_offset = Vector2.ZERO
		preview.scale = Vector2.ONE * factor
		preview.position = Vector2(clampf(x, 8.0, bounds.x - display_size.x - 8.0),
			clampf(rect.get_center().y - display_size.y * 0.5, 52.0, bounds.y - display_size.y - 8.0))
		preview.modulate.a = 1.0)
