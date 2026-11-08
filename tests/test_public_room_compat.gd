extends SceneTree
## Комната друга с фигурками/играми, которых у нас нет (другая версия, мастерская), не отбрасывается целиком.
## godot --headless --audio-driver Dummy --path . --script res://tests/test_public_room_compat.gd

var fails := 0
var checks := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("ОШИБКА: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var room := {
		"config": {"rows": 1, "cols": 2, "cups": 0, "width": 0.6, "height": 0.36, "figure_positions": {}, "figure_cells": {"figure:abc123": 0.5, "shelf_mummy": 0.2}},
		"placements": [["perudo", "shelf_mummy", "figure:abc123"], ["word_slam", "game_from_future", "shelf_anime"]],
		"poses": {"perudo": 1, "game_from_future": 2}, "selected": "", "editor": false, "custom": {},
	}
	var clean: Dictionary = load("res://hub/public_room.gd").clean(room)
	check(not clean.is_empty(), "комната с новыми фигурками и игрой из будущей версии не отброшена")
	check(clean.get("placements", [[]])[0] == ["perudo", "shelf_mummy", "figure:abc123"], "фигурки Tripo и мастерской остаются в раскладке")
	check(not (clean.get("placements", [[], []])[1] as Array).has("game_from_future"), "незнакомая игра пропущена")
	check(clean.get("config", {}).get("figure_cells", {}).has("figure:abc123"), "место фигурки из мастерской передаётся")
	check(ShelfConfig.is_figure("figure:abc123") and ShelfConfig.is_figure("shelf_mummy") and not ShelfConfig.is_figure("perudo"), "is_figure")
	print("СОВМЕСТИМОСТЬ КОМНАТ: ", checks, " проверок, ", fails, " ошибок")
	quit(1 if fails > 0 else 0)
