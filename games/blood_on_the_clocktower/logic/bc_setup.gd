extends RefCounted
## Предложение законного состава рассказчику. Не бот: во время партии ничего не выбирает.
const Data := preload("res://games/blood_on_the_clocktower/logic/bc_data.gd")

static func suggest(edition: String, count: int, seed_value: int = -1) -> Dictionary:
	if not Data.EDITIONS.has(edition) or not Data.COUNTS.has(count) or count < int(Data.EDITIONS[edition].minimum):
		return {}
	var random := RandomNumberGenerator.new()
	if seed_value < 0:
		random.randomize()
	else:
		random.seed = seed_value
	var minions: Array = Data.roles(edition, "minion")
	var demons: Array = Data.roles(edition, "demon")
	var townsfolk: Array = Data.roles(edition, "townsfolk")
	var outsiders: Array = Data.roles(edition, "outsider")
	for pool: Array in [minions, demons, townsfolk, outsiders]:
		_shuffle(pool, random)
	var selected: Array = minions.slice(0, int(Data.COUNTS[count][2]))
	selected.append(demons[0])
	var delta := 0
	if selected.has("godfather"):
		delta = 1 if int(Data.COUNTS[count][1]) == 0 else (1 if random.randi_range(0, 1) == 1 else -1)
	var population: Array = Data.population(count, selected, delta)
	selected.append_array(townsfolk.slice(0, int(population[0])))
	selected.append_array(outsiders.slice(0, int(population[1])))
	var fake_drunk := ""
	if selected.has("drunk"):
		for id: String in townsfolk:
			if not selected.has(id):
				fake_drunk = id
				break
	var bluffs: Array = []
	var catalog: Dictionary = Data.catalog()
	for id: String in Data.roles(edition):
		if catalog[id].side == "good" and not selected.has(id) and id != fake_drunk:
			bluffs.append(id)
	_shuffle(bluffs, random)
	return {"bc_roles": selected, "bc_bluffs": bluffs.slice(0, 3), "bc_drunk_role": fake_drunk,
		"bc_lunatic_role": str(demons[0]), "bc_godfather_delta": delta}

static func _shuffle(items: Array, random: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := random.randi_range(0, i)
		var old: Variant = items[i]
		items[i] = items[j]
		items[j] = old
