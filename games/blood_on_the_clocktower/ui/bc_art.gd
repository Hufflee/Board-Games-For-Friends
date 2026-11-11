extends RefCounted
## Кэш иллюстраций, эмблем и присланной владельцем коробки.
static var cache: Dictionary = {}

static func texture(path: String) -> Texture2D:
	if cache.has(path):
		return cache[path]
	var result: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if result == null:
		var source := Image.load_from_file(path)
		if source != null:
			result = ImageTexture.create_from_image(source)
	cache[path] = result
	return result

static func role(id: String) -> Texture2D:
	return texture("res://games/blood_on_the_clocktower/art/roles/%s.png" % id) if not id.is_empty() else null

static func cover(part: String) -> Texture2D:
	if part in ["spine", "top"]:
		var strip := AtlasTexture.new()
		strip.atlas = texture("res://hub/covers/Blood-In-The-Clocktower-Board-Game-box sideway.webp")
		strip.region = Rect2(128, 102, 35, 408)
		strip.filter_clip = true
		return strip
	return texture("res://hub/covers/blood on the clocktower good quality.jpg")

static func backdrop(parent: Control) -> void:
	var image := TextureRect.new()
	image.texture = texture("res://games/blood_on_the_clocktower/art/town_night.png")
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(image)
	preload("res://hub/cursor_parallax.gd").follow_texture(image)
