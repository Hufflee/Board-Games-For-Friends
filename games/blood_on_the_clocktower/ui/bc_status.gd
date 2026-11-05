extends RefCounted
## Русские памятки гримуара: внутренние ключи планировщика не выводятся игрокам.
const Data := preload("res://games/blood_on_the_clocktower/logic/bc_data.gd")
const FLAGS := {"fool_used": "Первое спасение Шута потрачено", "virgin_used": "Способность Девы потрачена",
	"slayer_claimed": "Выстрел Истребителя заявлен", "once": "Однократная способность потрачена",
	"po_charged": "По готовит тройную атаку", "zombuul_dead": "Зомбул выглядит мёртвым",
	"snake_poison": "Отравлен после обмена с Заклинателем змей", "barber_dead": "Ожидается обмен Парикмахера",
	"gossip_true": "Истинная сплетня", "woke": "Просыпался из-за своей способности", "goon_used": "Первый выбор Громилы уже сработал"}
const PEOPLE := {"poison_source": "Отравитель", "monk_source": "Защита Монаха", "advocate_source": "Защита Адвоката дьявола",
	"exorcist_source": "Экзорцист", "innkeeper_source": "Защита Трактирщика", "pukka_source": "Отравлен Пуккой",
	"pukka_target": "Предыдущая жертва Пукки", "master": "Хозяин Дворецкого", "grandchild": "Внук/внучка",
	"moon_target": "Выбор Лунного дитя", "twin": "Противоположный близнец", "witch_source": "Проклятие Ведьмы",
	"mad_source": "Безумие Цереновуса", "vig_source": "Сохранение способности Вигормортисом"}

static func describe(status: Dictionary, players: Array) -> String:
	var result: Array[String] = []
	for key: String in FLAGS:
		if bool(status.get(key, false)): result.append(FLAGS[key])
	for key: String in PEOPLE:
		if not status.has(key): continue
		var seat := int(status[key])
		if seat >= 0 and seat < players.size(): result.append("%s: %s" % [PEOPLE[key], players[seat].name])
	if status.has("mad_role"):
		result.append("Изображает роль: %s" % Data.catalog().get(str(status.mad_role), {}).get("name", "—"))
	for entry: Dictionary in status.get("drunks", []):
		var source := int(entry.get("source", -1))
		result.append("Опьянение: %s · до ночи %d" % [str(players[source].name) if source >= 0 and source < players.size() else "эффект роли", int(entry.get("until", 0))])
	if not status.get("sweet_sources", []).is_empty(): result.append("Опьянение после смерти Милашки")
	if not status.get("vig_poison", []).is_empty(): result.append("Яд Вигормортиса")
	return "\n".join(result)
