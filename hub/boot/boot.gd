extends Control
## Однократная заставка процесса; возвраты из игр идут прямо в HubGames.HUB_SCENE.
const Splash := preload("res://hub/boot/hufflesoft_splash.gd")
var _opening := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var splash := Splash.new()
	add_child(splash)
	splash.finished.connect(_open_hub)

func _open_hub() -> void:
	if _opening:
		return
	_opening = true
	get_tree().root.set_meta(&"startup_finished_msec", Time.get_ticks_msec())
	get_tree().change_scene_to_file.call_deferred(HubGames.HUB_SCENE)
