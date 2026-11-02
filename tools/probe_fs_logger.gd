extends SceneTree
## Локальная сигнатура API Logger текущего Godot, без сети.
func _initialize() -> void:
	for method: Dictionary in ClassDB.class_get_method_list("Logger"):
		if str(method.name).begins_with("_log"):
			print(JSON.stringify(method))
	for method: Dictionary in ClassDB.class_get_method_list("OS"):
		if str(method.name).contains("logger"):
			print(JSON.stringify(method))
	quit()
