extends SceneTree
## Проверка ролей, приватности и ключевых переходов двух игр.
const Drawing := preload("res://games/in_broad_strokes/logic/ibs_rules.gd")
const Contact := preload("res://games/first_contact/logic/fc_rules.gd")

var failures := 0

func _initialize() -> void:
	var drawing := Drawing.new()
	drawing.new_game([{}, {}, {}])
	_check(drawing.get_view(drawing.critic).word.is_empty(), 11)
	var stroke := PackedVector2Array([Vector2(0,0),Vector2(1,1)])
	_check(not drawing.action(drawing.critic,"draw",{"serial":0,"strokes":[stroke]},false), 13)
	_check(drawing.action(drawing.artist,"draw",{"serial":0,"strokes":[stroke]},false), 14)
	_check(drawing.tick(1), 15)
	_check(drawing.action(drawing.critic,"guess",{"serial":drawing.serial,"word":drawing.word},false), 16)
	_check(drawing.score == 1 and drawing.remaining == 24, 17)
	var contact := Contact.new()
	contact.new_game([{}, {}, {}, {}])
	_check(contact.get_view(0).targets.is_empty(), 20)
	_check(contact.get_view(2).targets.size() == 2, 21)
	# первый раунд — только обучение (владелец, 14.11): подсказка и голосование — со второго
	for round_no in 2:
		for seat in 2:
			_check(contact.action(seat,"ask",{"serial":contact.serial,"slots":[0]},false), 23)
			_check(contact.action(2,"teach",{"serial":contact.serial,"feature":0},false), 24)
		if round_no == 0:
			_check(contact.phase == "ask" and contact.turn_no == 2, 26)
	_check(contact.action(2,"clue",{"serial":contact.serial,"signs":[1,-2]},false), 25)
	var target: int = contact.targets[0][0]
	_check(contact.action(0,"vote",{"serial":contact.serial,"slots":[target]},false), 27)
	_check(contact.get_view(1).votes.is_empty(), 28)
	_check(contact.action(1,"vote",{"serial":contact.serial,"slots":[target]},false), 29)
	_check(contact.favor == [1,1] and contact.owned.size() == 1, 30)
	print("Две игры: роли, скрытые данные и ключевые переходы проверены")
	quit(1 if failures else 0)

func _check(ok: bool, line: int) -> void:
	if not ok:
		failures += 1
		printerr("Проверка не прошла, строка ", line)
