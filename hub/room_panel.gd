class_name RoomPanel
extends VBoxContainer
## Блок «Комната» для меню игры: создать комнату для этой игры в Steam или войти по коду.
## Комната — это та же пати, только с уже выбранной игрой: все сразу попадают в её лобби,
## а хост потом может сменить игру, не переподключая друзей.

var game_id := ""
var _code: LineEdit
var _status: Label


## make_button(text, size) -> Button, make_label(text, size) -> Label — кнопки и подписи в стиле игры.
static func make(id: String, make_button: Callable, make_label: Callable) -> RoomPanel:
	var p := RoomPanel.new()
	p.game_id = id
	p.add_theme_constant_override("separation", 8)
	p.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(make_label.call("Играть по сети — комната для этой игры:", 15))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	var steam: Button = make_button.call("Создать комнату (Steam)", 15)
	steam.disabled = not Net.steam_ok
	steam.tooltip_text = "Друзья заходят по приглашению Steam или по коду комнаты" if Net.steam_ok else Net.steam_error
	steam.pressed.connect(func(): Net.host_steam(id))
	row.add_child(steam)
	p.add_child(row)
	var join := HBoxContainer.new()
	join.alignment = BoxContainer.ALIGNMENT_CENTER
	join.add_theme_constant_override("separation", 6)
	p._code = LineEdit.new()
	p._code.placeholder_text = "код комнаты (Steam)"
	p._code.custom_minimum_size.x = 170
	join.add_child(p._code)
	var jb: Button = make_button.call("Войти", 14)
	jb.disabled = not Net.steam_ok
	jb.pressed.connect(func(): Net.join_steam(int(p._code.text.strip_edges())))
	join.add_child(jb)
	p.add_child(join)
	p._status = make_label.call("", 13)
	p._status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(p._status)
	Net.status_changed.connect(p._on_status_changed)
	return p


## Метод принадлежит панели: Godot отключит его при её удалении.
func _on_status_changed(text: String) -> void:
	if is_instance_valid(_status):
		_status.text = text
