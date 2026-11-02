extends SceneTree
## Разовый просмотр API транспортных настроек, без подключения к сети.
func _initialize() -> void:
	for type_name in ["Steam", "SteamMultiplayerPeer"]:
		if not ClassDB.class_exists(type_name):
			continue
		for method: Dictionary in ClassDB.class_get_method_list(type_name):
			if str(method.name).contains("ConfigValue") or str(method.name).contains("config_value"):
				print(type_name, " ", JSON.stringify(method))
		for key: String in ClassDB.class_get_integer_constant_list(type_name):
			if key.contains("TIMEOUT"):
				print(key, "=", ClassDB.class_get_integer_constant(type_name, key))
	quit()
