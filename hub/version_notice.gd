extends Control
## Однократное представление новой игры после заставки, с локальным флагом версии.
const CACHE := "user://announcements.cfg"
const VERSION := "0.8.5"
const GAME_ID := "the_gang"
const AFTER_SPLASH_MS := 2000

static func pending() -> bool:
	if str(ProjectSettings.get_setting("application/config/version", "")) != VERSION:
		return false
	var cache := ConfigFile.new()
	cache.load(CACHE)
	return not bool(cache.get_value("seen", VERSION, false))

static func schedule(hub: Control) -> void:
	var tree := hub.get_tree()
	if not tree.root.has_meta(&"startup_finished_msec") or not pending():
		return
	var deadline := int(tree.root.get_meta(&"startup_finished_msec")) + AFTER_SPLASH_MS
	var delay := maxf(0.001, float(deadline - Time.get_ticks_msec()) / 1000.0)
	await tree.create_timer(delay).timeout
	if not is_instance_valid(hub) or not hub.is_inside_tree() or hub.is_queued_for_deletion():
		return
	if tree.current_scene != hub or hub.get("_leaving") or not pending():
		return
	if Net.in_game or (Net.is_party() and not Net.party_game.is_empty()):
		return
	var room: Node = hub.get("_room")
	if not is_instance_valid(room) or room.get("_editor_on") or not hub.get("_selected").is_empty():
		return
	if not room.boxes.any(func(box): return str(box.game.get("id", "")) == GAME_ID):
		return
	room.focus_id(GAME_ID)
	var banner = load("res://hub/version_notice.gd").new()
	banner.name = "NewGameNotice"
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.z_index = 110
	hub.add_child(banner)
	var cache := ConfigFile.new()
	cache.load(CACHE)
	cache.set_value("seen", VERSION, true)
	var error := cache.save(CACHE)
	if error != OK:
		push_warning("Не удалось сохранить показ новой игры: %d" % error)
	Diag.mark("Представлена новая игра", {"игра": GAME_ID})

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = 76
	panel.offset_bottom = 208
	panel.add_theme_stylebox_override("panel", HubStyle.box(Color(0.025, 0.04, 0.07, 0.90), 14, HubStyle.CYAN))
	add_child(panel)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var title := HubStyle.neon_label("НОВАЯ ИГРА", 52, HubStyle.CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)
	var name_label := HubStyle.neon_label("THE GANG", 26, HubStyle.PINK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.45)
	tween.tween_interval(3.0)
	tween.tween_property(self, "modulate:a", 0.0, 0.6)
	tween.tween_callback(queue_free)
