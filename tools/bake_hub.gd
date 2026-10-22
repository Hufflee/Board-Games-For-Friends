extends Node
## Заранее считает то, что главное меню иначе делало бы при каждом открытии:
## картинку ночного города за окном и цвет края / яркость обложек коробок.
## Запуск: godot --headless res://tools/bake_hub.tscn (после смены обложек — запустить снова).


func _ready() -> void:
	NeonRoom.city_image().save_png("res://hub/art/city.png")
	var meta := ConfigFile.new()
	for g in HubGames.LIST:
		var id: String = g["id"]
		var front := GameBox.cover_texture(id, "front")
		if front:
			meta.set_value(id, "edge", GameBox._edge_color(front))
			meta.set_value(id, "luma", GameBox._mean_luma(front))
	meta.save(GameBox.META)
	print("RESULT baked ", meta.get_sections())
	get_tree().quit()
