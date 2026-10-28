extends SceneTree
## Доступные сигналы установленного Steam расширения, без входа в сеть/аккаунт.
func _init() -> void:
	for type_name in ["Steam", "SteamMultiplayerPeer"]:
		print(type_name, " exists=", ClassDB.class_exists(type_name))
		if ClassDB.class_exists(type_name):
			for signal_info: Dictionary in ClassDB.class_get_signal_list(type_name):
				if str(signal_info.name).contains("network") or str(signal_info.name).contains("session") or str(signal_info.name).contains("debug"):
					print(JSON.stringify(signal_info))
	quit()
