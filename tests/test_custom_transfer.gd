extends SceneTree
## Проверка границ входящих частей без сети. Настоящая передача/докачка — test_custom_net --custom.

const Transfer := preload("res://games/custom/logic/cg_transfer.gd")
const Package := preload("res://games/custom/logic/cg_package.gd")
var checks := 0
var errors := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)

func _init() -> void:
	var transfer := Transfer.new()
	var bytes := PackedByteArray()
	bytes.resize(Package.CHUNK * 2 + 17)
	bytes.fill(45)
	var hash_value := Package.sha(bytes)
	transfer.manifest = {"hash": hash_value, "size": bytes.size()}
	transfer._requested = true
	var first := bytes.slice(0, Package.CHUNK)
	check(not transfer.accept_chunk("0".repeat(64), 0, bytes.size(), first), "Чужой хэш части отклоняется")
	check(not transfer.accept_chunk(hash_value, Package.CHUNK, bytes.size(), first), "Будущая часть отклоняется")
	check(not transfer.accept_chunk(hash_value, -1, bytes.size(), first), "Отрицательное смещение отклоняется")
	check(not transfer.accept_chunk(hash_value, 0, Package.LIMIT + 1, first), "Подмена общего размера отклоняется")
	check(not transfer.accept_chunk(hash_value, 0, bytes.size(), first.slice(0, 10)), "Укороченная промежуточная часть отклоняется")
	check(transfer._incoming.is_empty(), "Отклонённые части ничего не записали")
	check(transfer.accept_chunk(hash_value, 0, bytes.size(), first), "Первая часть принята")
	check(not transfer.accept_chunk(hash_value, 0, bytes.size(), first), "Повторная часть не дублируется")
	transfer.reset()
	check(transfer._incoming.size() == Package.CHUNK, "Сброс соединения сохраняет частичную загрузку")
	transfer.manifest = {"hash": hash_value, "size": bytes.size()}
	transfer._requested = true
	check(transfer.accept_chunk(hash_value, Package.CHUNK, bytes.size(), bytes.slice(Package.CHUNK, Package.CHUNK * 2)), "Следующая часть докачана")
	check(transfer.accept_chunk(hash_value, Package.CHUNK * 2, bytes.size(), bytes.slice(Package.CHUNK * 2)), "Последняя неполная часть принята")
	check(transfer._incoming == bytes and Package.sha(transfer._incoming) == hash_value, "Собранные данные совпадают побайтно")
	transfer.free()
	print("CUSTOM_TRANSFER: %d проверок, ошибок %d" % [checks, errors])
	quit(1 if errors else 0)
