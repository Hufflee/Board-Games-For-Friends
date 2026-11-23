extends RefCounted
## Хостовая подготовка дуэли или командной партии. Места идут в порядке А–Б–А–Б.

const Board := preload("res://games/unmatched/logic/um_board.gd")
const Maps := preload("res://games/unmatched/logic/um_maps.gd")
const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")
const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Piles := preload("res://hub/card_piles.gd")

var board: Board
var random: RandomNumberGenerator
var heroes: PackedStringArray
var controllers: PackedInt32Array
var fighters: Array[Array] = []
var decks: Array[Array] = []
var hands: Array[Array] = []
var discards: Array[Array] = []
var alice_large := false
var _size_chosen := false
var _seat := 0
var fog: Array[int] = []


static func create(arena: String, roster: PackedStringArray, owners: PackedInt32Array, rng: RandomNumberGenerator) -> RefCounted:
	var field: Board = Maps.create(arena)
	if field == null or rng == null or roster.size() not in [2, 4] or owners.size() != roster.size():
		return null
	var teams: Dictionary = {}
	var selected: Dictionary = {}
	for seat in roster.size():
		var hero: String = roster[seat]
		var owner: int = owners[seat]
		if field.start_for(seat) < 0 or not Roster.HEROES.has(hero) or selected.has(hero) or owner < 0:
			return null
		if field.cell_count() == 2:
			var helpers: Dictionary = Roster.HEROES[hero].get("sidekick", {})
			if not helpers.is_empty() and not helpers.get("reserve", false):
				return null
		if teams.has(owner) and teams[owner] != seat % 2:
			return null
		teams[owner] = seat % 2
		selected[hero] = true
	if roster.size() == 4 and teams.size() < 3:
		return null
	return new(field, roster, owners, rng)


func _init(field: Board, roster: PackedStringArray, owners: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	board = field
	random = rng
	heroes = roster.duplicate()
	controllers = owners.duplicate()
	for seat in heroes.size():
		var info: Dictionary = Roster.HEROES[heroes[seat]]
		var sidekicks: Dictionary = info.get("sidekick", {})
		var group: Array = [_fighter(heroes[seat], info, true)]
		for i in int(sidekicks.get("count", 0)):
			var helper := _fighter(sidekicks.id, sidekicks, sidekicks.get("heroes", false))
			if heroes[seat] == "witches":
				helper["token"] = "witch_%d" % (i + 1)
			group.append(helper)
		fighters.append(group)
		var deck := Catalog.deck_for(heroes[seat], seat)
		Piles.shuffle(deck, rng)
		var hand: Array = []
		Piles.draw_many(deck, hand, 5)
		decks.append(deck)
		hands.append(hand)
		discards.append([])
	_enter_seat()


func pending() -> Dictionary:
	if _seat == heroes.size():
		return {}
	if heroes[_seat] == "invisible_man" and fog.size() < 3:
		return {"seat": _seat, "fog": true, "cells": _placement_cells()}
	for i in range(1, fighters[_seat].size()):
		var figure: Dictionary = fighters[_seat][i]
		if figure.space < 0 and not figure.reserve:
			return {"seat": _seat, "fighter": i, "cells": _placement_cells()}
	return {"seat": _seat, "choose_size": true}


func place(viewer: int, cell: int) -> bool:
	var request := pending()
	if not request.has("cells") or viewer != controllers[_seat] or cell not in request.cells:
		return false
	if request.get("fog", false):
		fog.append(cell)
	else:
		fighters[_seat][request.fighter].space = cell
	_enter_seat()
	return true


func choose_size(viewer: int, large: bool) -> bool:
	var request := pending()
	if not request.has("choose_size") or viewer != controllers[_seat]:
		return false
	alice_large = large
	_size_chosen = true
	_enter_seat()
	return true


func alice_size_selected() -> bool:
	return _size_chosen


func _enter_seat() -> void:
	while _seat < heroes.size():
		fighters[_seat][0].space = board.start_for(_seat)
		for figure: Dictionary in fighters[_seat]:
			if figure.space < 0 and not figure.reserve:
				return
		if heroes[_seat] == "alice" and not _size_chosen:
			return
		if heroes[_seat] == "invisible_man" and fog.size() < 3:
			return
		_seat += 1


func _reserved(cell: int) -> bool:
	if cell in fog:
		return true
	for seat in heroes.size():
		if cell == board.start_for(seat):
			return true
		for figure: Dictionary in fighters[seat]:
			if cell == figure.space:
				return true
	return false


func _placement_cells() -> PackedInt32Array:
	var cells := PackedInt32Array()
	var adjacent := PackedInt32Array()
	for cell in board.cell_count():
		if _reserved(cell):
			continue
		if board.same_zone(board.start_for(_seat), cell):
			cells.append(cell)
		elif heroes.size() == 4 and fighters[_seat].any(func(figure: Dictionary) -> bool: return board.adjacent(figure.space, cell)):
			adjacent.append(cell)
	# Если зона команды заполнена, оставшиеся помощники встают рядом с уже размещёнными.
	return adjacent if cells.is_empty() else cells


static func _fighter(id: String, info: Dictionary, is_hero: bool) -> Dictionary:
	return {
		"id": id, "space": -1, "is_hero": is_hero, "ranged": info.ranged,
		"health": info.health, "max_health": info.health, "reserve": info.get("reserve", false),
	}
