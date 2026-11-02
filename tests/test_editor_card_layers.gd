extends SceneTree
## Ассеты черновика и буфер лица: безопасный рисунок/шрифт, связи колонок, пакет и undo.
const Document := preload("res://editor/ed_document.gd")
const Faces := preload("res://games/custom/logic/cg_faces.gd")
const Assets := preload("res://editor/ed_assets.gd")
const Reader := preload("res://games/custom/ui/cg_assets.gd")
const Library := preload("res://games/custom/logic/cg_library.gd")
const Clipboard := preload("res://editor/ed_clipboard.gd")
const Elements := preload("res://editor/ed_elements.gd")
var checks := 0
var errors := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("CARD ASSET CHECK: старт")
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		push_error("Нужен отдельный тестовый APPDATA в build.")
		quit(1)
		return
	var doc := Document.new()
	check(doc.create("card_race"), "Создан отдельный проект")
	print("CARD ASSET CHECK: проект")
	var image := Image.create(48, 32, false, Image.FORMAT_RGBA8)
	var noise := RandomNumberGenerator.new()
	noise.seed = 92
	for y in 32:
		for x in 48:
			image.set_pixel(x, y, Color(noise.randf(), noise.randf(), noise.randf()))
	DirAccess.make_dir_recursive_absolute("res://build/editor_card_layers")
	image.save_png("res://build/editor_card_layers/image.png")
	var imported := Assets.import_image(str(doc.data.id), "res://build/editor_card_layers/image.png", "Свой рисунок теста")
	var font := Assets.import_font(str(doc.data.id), "res://hub/art/fonts/Exo2-Variable.ttf", "Exo2/OFL")
	check(imported.error.is_empty() and font.error.is_empty(), "Импортированы собственный рисунок и разрешённый шрифт")
	print("CARD ASSET CHECK: импорт")
	var copy := doc.data.duplicate(true)
	copy.assets[imported.hash] = imported.asset
	copy.assets[font.hash] = font.asset
	var deck: Dictionary = copy.elements.decks[0]
	deck["columns"] = Faces.columns(deck)
	deck["face"] = {"layers": Faces.default_layers(deck)}
	deck.face.layers.append({"kind": "image", "asset": imported.hash, "rect": [32, 32, 48, 32]})
	deck.face.layers.append({"kind": "text", "field": "rank", "font": font.hash, "rect": [32, 100, 200, 100], "text": ""})
	check(doc.replace(copy, "Несохранённые слои") and doc.dirty and doc.issues().errors.is_empty(), "Слои с ассетами доступны в несохранённом черновике")
	var reader := Reader.new()
	reader.configure_document(doc.data)
	print("CARD ASSET CHECK: чтение")
	check(reader.image(str(imported.hash)) != null and reader.font(str(font.hash)) != null, "Предпросмотр читает новые ассеты до сохранения game.json")
	var target := Document.new()
	check(target.create("card_race"), "Создан проект назначения")
	copy = target.data.duplicate(true)
	copy.elements.decks[0]["columns"] = Faces.columns(copy.elements.decks[0])
	copy.elements.decks[0]["face"] = {"layers": []}
	target.replace(copy, "Шаблон назначения")
	var destination: Array = ["elements", "decks", 0, "face", "layers"]
	var encoded_image := Clipboard.encode(doc, "face_layer", doc.data.elements.decks[0].face.layers[-2])
	var raw_image: Dictionary = JSON.parse_string(encoded_image)
	check(str(raw_image.assets[imported.hash].bytes).length() > 4096, "В проверке действительно участвует картинка крупнее старого строкового предела")
	var image_payload := Clipboard.decode(encoded_image)
	if image_payload.is_empty():
		check(false, "Буфер обязан принять картинку в пределах16МБ")
		quit(1)
		return
	print("CARD ASSET CHECK: рисунок буфера")
	check(Clipboard.paste(target, image_payload, "face_layer", destination).is_empty(), "Слой рисунка перенесён между проектами вместе с ассетом")
	var target_reader := Reader.new()
	target_reader.configure_document(target.data)
	check(target_reader.image(str(imported.hash)) != null, "Перенесённый рисунок доступен в новом проекте")
	var text_payload := Clipboard.decode(Clipboard.encode(doc, "face_layer", doc.data.elements.decks[0].face.layers[-1]))
	print("CARD ASSET CHECK: шрифт буфера")
	if text_payload.is_empty():
		check(false, "Буфер обязан принять настоящий шрифт в пределах16МБ")
		quit(1)
		return
	check(Clipboard.paste(target, text_payload, "face_layer", destination).is_empty(), "Слой текста сохранил колонку и пользовательский шрифт")
	target_reader.configure_document(target.data)
	check(target_reader.font(str(font.hash)) != null, "Перенесённый шрифт читается из нового проекта")
	var bad := text_payload.duplicate(true)
	bad.data.field = "нет_колонки"
	var before := JSON.stringify(target.data)
	check(not Clipboard.paste(target, bad, "face_layer", destination).is_empty() and JSON.stringify(target.data) == before, "Отсутствующая колонка отклоняется без частичной вставки")
	check(not Clipboard.paste(target, text_payload, "face_layer", ["rules", "vars"]).is_empty(), "Слой лица не вставляется в несвязанную коллекцию")
	var oversized_text := Clipboard.encode(doc, "face_layer", {"kind": "text", "rect": [0, 0, 10, 10], "text": "а".repeat(4097)})
	check(Clipboard.decode(oversized_text).is_empty(), "Отдельный предел бинарных данных не отменяет предел обычного текста")
	var corrupted: Dictionary = JSON.parse_string(Clipboard.encode(doc, "face_layer", doc.data.elements.decks[0].face.layers[-1]))
	corrupted.assets[font.hash].bytes = "AA=="
	check(Clipboard.decode(JSON.stringify(corrupted)).is_empty(), "Подменённые байты шрифта отклоняются по хэшу")
	var elements := Elements.new(target)
	check(elements.remove_column(0, 0) and target.issues().errors.is_empty(), "Удаление колонки снимает привязку слоя")
	check(target.data.elements.decks[0].face.layers[-1].field == "", "Удалённая колонка не остаётся скрытой ссылкой")
	check(target.undo() and target.data.elements.decks[0].face.layers[-1].field == "rank", "Undo возвращает колонку и её привязку")
	check(doc.save() and Library.build_package(str(doc.data.id)).error.is_empty(), "Слои, рисунок и шрифт проходят настоящий пакет")
	print("EDITOR CARD LAYERS: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
