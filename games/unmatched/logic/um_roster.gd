extends RefCounted
## Напечатанные характеристики героев двух томов. Комплект проверяется в tests/test_unmatched.gd.

const HEROES := {
	"alice": {"volume": 1, "name": "Алиса", "health": 13, "move": 2, "ranged": false,
		"sidekick": {"id": "jabberwock", "name": "Бармаглот", "health": 8, "count": 1, "ranged": false}},
	"arthur": {"volume": 1, "name": "Король Артур", "health": 18, "move": 2, "ranged": false,
		"sidekick": {"id": "merlin", "name": "Мерлин", "health": 7, "count": 1, "ranged": true}},
	"medusa": {"volume": 1, "name": "Медуза", "health": 16, "move": 3, "ranged": true,
		"sidekick": {"id": "harpy", "name": "Гарпия", "health": 1, "count": 3, "ranged": false}},
	"sinbad": {"volume": 1, "name": "Синдбад", "health": 15, "move": 2, "ranged": false,
		"sidekick": {"id": "porter", "name": "Носильщик", "health": 6, "count": 1, "ranged": false}},
	"achilles": {"volume": 2, "name": "Ахиллес", "health": 18, "move": 2, "ranged": false,
		"sidekick": {"id": "patroclus", "name": "Патрокл", "health": 6, "count": 1, "ranged": false}},
	"bloody_mary": {"volume": 2, "name": "Кровавая Мэри", "health": 16, "move": 3, "ranged": false},
	"sun_wukong": {"volume": 2, "name": "Сунь Укун", "health": 17, "move": 2, "ranged": false,
		"sidekick": {"id": "clone", "name": "Двойник", "health": 1, "count": 3, "ranged": false, "reserve": true}},
	"yennenga": {"volume": 2, "name": "Йенненга", "health": 15, "move": 2, "ranged": true,
		"sidekick": {"id": "archer", "name": "Лучник", "health": 2, "count": 2, "ranged": true}},
}
