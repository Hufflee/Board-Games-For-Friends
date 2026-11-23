extends RefCounted
## Сложность героев из столбца Complexity Aggregation в Unmatched - COMPLEXITY.pdf.

const CATEGORY := {
	"achilles": "Easy", "alice": "Moderate", "arthur": "Easy", "bigfoot": "Novice",
	"blackbeard": "Moderate", "bloody_mary": "Hard", "chupacabra": "Easy",
	"dracula": "Moderate", "genie": "Complex", "hamlet": "Hard", "houdini": "Hard",
	"invisible_man": "Hard", "jekyll_hyde": "Moderate", "loki": "Hard", "medusa": "Easy",
	"oda": "Hard", "pandora": "Hard", "robin_hood": "Easy", "shakespeare": "Complex",
	"sherlock": "Moderate", "sinbad": "Novice", "sun_wukong": "Moderate", "titania": "Hard",
	"tomoe": "Moderate", "witches": "Complex", "yennenga": "Moderate",
}
const STARS := {
	"Novice": "★☆☆☆☆",
	"Easy": "★★☆☆☆",
	"Moderate": "★★★☆☆",
	"Hard": "★★★★☆",
	"Complex": "★★★★★",
}


static func label(hero: String) -> String:
	var stars: String = STARS.get(CATEGORY.get(hero, ""), "")
	return "Сложность: %s" % stars if not stars.is_empty() else "Сложность: нет оценки"


static func level(hero: String) -> int:
	return ["Novice", "Easy", "Moderate", "Hard", "Complex"].find(CATEGORY.get(hero, "")) + 1
