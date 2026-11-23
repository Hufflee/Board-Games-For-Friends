extends RefCounted
## Изображения карт и портретов стола Unmatched.

const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const CORNERS := preload("res://hub/card_corners.gdshader")
# Фон и панели всегда выбираются одной темой; неизвестная арена использует нейтральную Венецию.
const ARENA_THEMES := {
	"marmoreal": "marmoreal", "sarpedon": "sarpedon", "gardens": "gardens",
	"azuchi_castle": "sarpedon", "b_p_r_d_hq": "heorot", "baskerville_manor": "venice",
	"bathroom_stall": "venice", "fayrlund_forest": "raptor_paddock", "globe_theatre": "marmoreal",
	"helicarrier": "venice", "hell_s_kitchen": "venice", "heorot": "heorot",
	"kaer_morhen": "heorot", "king_solomon_s_mine": "heorot", "mcminnville_or": "raptor_paddock",
	"naglfar": "gardens", "navy_pier": "sarpedon", "new_york_city": "venice",
	"pandemonium": "heorot", "phone_booth": "raptor_paddock", "point_pleasant": "gardens",
	"raptor_paddock": "raptor_paddock", "sanctum_sanctorum": "heorot", "santa_s_workshop": "raptor_paddock",
	"sherwood": "raptor_paddock", "soho": "venice", "streets_of_novigrad": "venice",
	"sunnydale_high": "raptor_paddock", "t_rex_paddock": "gardens", "technodrome": "gardens",
	"the_alamo": "sarpedon", "the_bronze": "marmoreal", "the_raft": "venice",
	"the_white_house": "sarpedon", "thrilla_in_manila": "venice", "tsing_shan_monastery": "raptor_paddock",
	"venice": "venice", "yukon": "heorot", "yukon_1900": "heorot",
}
const IMMEDIATE_BOUNDS := {
	"robin_hood:13": Vector2(0.73, 0.90), "robin_hood:25": Vector2(0.73, 0.83),
	"bigfoot:09": Vector2(0.73, 0.83), "bigfoot:28": Vector2(0.73, 0.83),
	"alice:25": Vector2(0.733, 0.820), "arthur:05": Vector2(0.736, 0.823),
	"medusa:04": Vector2(0.736, 0.826), "sinbad:06": Vector2(0.735, 0.820),
	"achilles:11": Vector2(0.746, 0.838), "bloody_mary:10": Vector2(0.745, 0.837),
	"achilles:23": Vector2(0.746, 0.934), "yennenga:03": Vector2(0.705, 0.942),
	"yennenga:24": Vector2(0.744, 0.933), "sun_wukong:07": Vector2(0.750, 0.893),
	"blackbeard:10": Vector2(0.73, 0.89), "blackbeard:16": Vector2(0.73, 0.85),
	"blackbeard:29": Vector2(0.67, 0.78), "chupacabra:17": Vector2(0.73, 0.84),
	"loki:08": Vector2(0.73, 0.91), "loki:23": Vector2(0.73, 0.91),
	"pandora:15": Vector2(0.73, 0.84), "pandora:25": Vector2(0.73, 0.80),
	"dracula:01": Vector2(0.735, 0.830),
	"dracula:21": Vector2(0.731, 0.926),
	"sherlock:01": Vector2(0.739, 0.832),
	"invisible_man:20": Vector2(0.735, 0.938),
	"invisible_man:29": Vector2(0.739, 0.810),
	"jekyll_hyde:01": Vector2(0.735, 0.828),
	"genie:25": Vector2(0.735, 0.818),
	"genie:28": Vector2(0.735, 0.820),
	"houdini:03": Vector2(0.721, 0.800),
	"houdini:11": Vector2(0.745, 0.952),
	"houdini:13": Vector2(0.735, 0.900),
	"houdini:20": Vector2(0.762, 0.846),
}
# Верх и низ печатного блока «Во время боя» в долях высоты лицевой стороны.
const DURING_BOUNDS := {
	"robin_hood:17": Vector2(0.73, 0.87),
	"bigfoot:25": Vector2(0.73, 0.87),
	"blackbeard:13": Vector2(0.73, 0.83), "blackbeard:19": Vector2(0.80, 0.92),
	"blackbeard:24": Vector2(0.68, 0.86), "chupacabra:08": Vector2(0.73, 0.91),
	"chupacabra:20": Vector2(0.73, 0.91), "chupacabra:22": Vector2(0.73, 0.88),
	"chupacabra:28": Vector2(0.73, 0.88), "loki:03": Vector2(0.61, 0.76),
	"loki:05": Vector2(0.73, 0.90), "loki:11": Vector2(0.67, 0.77),
	"loki:16": Vector2(0.72, 0.91), "loki:19": Vector2(0.68, 0.90),
	"loki:29": Vector2(0.78, 0.90), "pandora:06": Vector2(0.67, 0.78),
	"pandora:08": Vector2(0.73, 0.85), "pandora:12": Vector2(0.67, 0.82),
	"pandora:28": Vector2(0.72, 0.86),
	"alice:17": Vector2(0.734, 0.905),
	"arthur:08": Vector2(0.734, 0.905),
	"sinbad:09": Vector2(0.737, 0.908),
	"yennenga:16": Vector2(0.746, 0.887),
	"sinbad:15": Vector2(0.784, 0.899),
	"sinbad:16": Vector2(0.784, 0.890),
	"sinbad:19": Vector2(0.775, 0.922),
	"alice:15": Vector2(0.734, 0.861),
	"alice:23": Vector2(0.740, 0.954),
	"arthur:28": Vector2(0.734, 0.905),
	"medusa:10": Vector2(0.740, 0.827),
	"sinbad:17": Vector2(0.781, 0.882),
	"sinbad:18": Vector2(0.784, 0.893),
	"sinbad:20": Vector2(0.781, 0.890),
	"sinbad:26": Vector2(0.737, 0.844),
	"bloody_mary:01": Vector2(0.720, 0.801),
	"bloody_mary:03": Vector2(0.711, 0.838),
	"bloody_mary:05": Vector2(0.743, 0.879),
	"bloody_mary:15": Vector2(0.697, 0.781),
	"bloody_mary:18": Vector2(0.740, 0.876),
	"bloody_mary:22": Vector2(0.743, 0.882),
	"sun_wukong:01": Vector2(0.740, 0.879),
	"sun_wukong:10": Vector2(0.807, 0.890),
	"sun_wukong:24": Vector2(0.743, 0.885),
	"sun_wukong:26": Vector2(0.729, 0.827),
	"yennenga:11": Vector2(0.746, 0.885),
	"yennenga:19": Vector2(0.743, 0.934),
	"arthur:20": Vector2(0.738, 0.825),
	"sun_wukong:22": Vector2(0.734, 0.816),
	"dracula:09": Vector2(0.735, 0.950),
	"dracula:19": Vector2(0.739, 0.910),
	"dracula:25": Vector2(0.737, 0.908),
	"dracula:29": Vector2(0.735, 0.958),
	"sherlock:16": Vector2(0.733, 0.910),
	"sherlock:22": Vector2(0.788, 0.928),
	"invisible_man:24": Vector2(0.739, 0.910),
	"jekyll_hyde:07": Vector2(0.737, 0.952),
	"jekyll_hyde:14": Vector2(0.741, 0.920),
	"genie:05": Vector2(0.792, 0.914),
	"houdini:01": Vector2(0.703, 0.784),
	"houdini:03": Vector2(0.816, 0.898),
	"houdini:17": Vector2(0.671, 0.752),
	"houdini:27": Vector2(0.760, 0.838),
}
static var _rounding: ShaderMaterial


static func backdrop(arena: String) -> Texture2D:
	return texture("res://games/unmatched/art/backgrounds/%s.webp" % arena_theme(arena))


static func arena_theme(arena: String) -> String:
	return ARENA_THEMES.get(arena, "venice")


static func face(card: Dictionary) -> Texture2D:
	if card.get("cauldron_rules", false):
		return texture("res://games/unmatched/art/references/cauldron.webp")
	if card.has("enchantment"):
		return texture("res://games/unmatched/art/references/enchantment_%d.webp" % (int(card.enchantment) + 1))
	if card.has("battlefield_item"):
		return texture("res://games/unmatched/art/items/%d.webp" % card.battlefield_item)
	var hero := str(card.get("hero", ""))
	if hero == "pandora" and int(card.get("misery", 0)) in range(1, 8):
		return texture("res://games/unmatched/art/references/misery_%d.webp" % card.misery)
	var raw: Variant = card.get("face", 0)
	var number := int(raw.get_file().get_basename()) if raw is String else int(raw)
	if not Roster.HEROES.has(hero) or number < 1 or number > 30:
		return null
	return texture("res://games/unmatched/art/cards/%s/%02d.webp" % [hero, number])


static func back(hero: String) -> Texture2D:
	if not Roster.HEROES.has(hero):
		return null
	return texture("res://games/unmatched/art/backs/%s.webp" % hero)


static func reference_face(key: String) -> Texture2D:
	if key != "actions" and not Roster.HEROES.has(key):
		return null
	return texture("res://games/unmatched/art/references/%s.webp" % key)


static func round_corners(card: TextureRect) -> void:
	if _rounding == null:
		_rounding = ShaderMaterial.new()
		_rounding.shader = CORNERS
		_rounding.set_shader_parameter("outline_width", 0.0)
	card.material = _rounding


static func outlined_back(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CORNERS
	material.set_shader_parameter("outline_color", color)
	material.set_shader_parameter("outline_width", 1.5)
	return material


static func texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"):
		return load(path) as Texture2D
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			return ImageTexture.create_from_image(image)
	return null
