extends Control
## Отдельное окно «Общение» с той же сетью, чатом и мини-играми, что у основного приложения.

const COMPACT := Vector2i(150, 42)
const EXPANDED := Vector2i(640, 510)
var _panel: Control
var _attempted := false
var _friends: PopupMenu
var _lobbies: Array = []


func _ready() -> void:
	var window := get_window()
	window.title = "BGSocial"
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.min_size = Vector2i(1, 1)
	window.mode = Window.MODE_WINDOWED
	window.always_on_top = true
	window.close_requested.connect(get_tree().quit)
	const ICON_PATH := "res://hub/art/brand/social.png"
	var icon: Image
	if ResourceLoader.exists(ICON_PATH):
		icon = (load(ICON_PATH) as Texture2D).get_image()
	else:
		icon = Image.load_from_file(ProjectSettings.globalize_path(ICON_PATH))
	if icon != null and not icon.is_empty():
		DisplayServer.set_icon(icon)
	_panel = Net.chat.panel()
	await get_tree().process_frame
	_panel.mode_changed.connect(_resize)
	var desktop := DisplayServer.screen_get_usable_rect()
	window.position = desktop.end - COMPACT - Vector2i(30, 40)
	_resize()
	_panel.set_mode(1)
	_friends = PopupMenu.new()
	add_child(_friends)
	_friends.index_pressed.connect(_join_friend)


func _process(_delta: float) -> void:
	if Net.steam_ok and not _attempted and not Net._joining and not Net._hosting_steam:
		_attempted = true
		if not Net.is_party():
			Net.host_steam()


func _resize() -> void:
	var window := get_window()
	var open := bool(_panel.is_open())
	var next := EXPANDED if open else COMPACT
	var desktop := DisplayServer.screen_get_usable_rect(window.current_screen)
	var corner := window.position + window.size
	window.borderless = not open
	window.size = next
	window.position = (corner - next).clamp(desktop.position, (desktop.end - next).max(desktop.position))
	_panel.base_size = Vector2(next - Vector2i(16, 16))
	_panel._apply()


func show_friends(anchor: Button) -> void:
	_lobbies = Net.steam_friend_parties()
	_friends.clear()
	for lobby: Dictionary in _lobbies:
		_friends.add_item(str(lobby.name))
	if _lobbies.is_empty():
		_friends.add_item("У друзей пока нет открытых лобби" if Net.steam_ok else "Войдите в Steam")
		_friends.set_item_disabled(0, true)
	var at := Vector2i(anchor.global_position + Vector2(0, anchor.size.y))
	if not get_window().gui_embed_subwindows:
		at += get_window().position
	_friends.popup(Rect2i(at, Vector2i(250, 0)))


func _join_friend(index: int) -> void:
	if index < _lobbies.size():
		Net.join_steam(int(_lobbies[index].lobby))
