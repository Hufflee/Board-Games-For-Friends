extends RefCounted
## Изображения карт и портретов стола Unmatched.

const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const CORNERS := preload("res://hub/card_corners.gdshader")
const IMMEDIATE_BOUNDS := {
	"alice:25": Vector2(0.733, 0.820), "arthur:05": Vector2(0.736, 0.823),
	"medusa:04": Vector2(0.736, 0.826), "sinbad:06": Vector2(0.735, 0.820),
	"achilles:11": Vector2(0.746, 0.838), "bloody_mary:10": Vector2(0.745, 0.837),
	"achilles:23": Vector2(0.746, 0.934), "yennenga:03": Vector2(0.705, 0.942),
	"yennenga:24": Vector2(0.744, 0.933), "sun_wukong:07": Vector2(0.750, 0.893),
}
# Верх и низ печатного блока «Во время боя» в долях высоты лицевой стороны.
const DURING_BOUNDS := {
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
}
static var _rounding: ShaderMaterial


static func face(card: Dictionary) -> Texture2D:
	var hero := str(card.get("hero", ""))
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
