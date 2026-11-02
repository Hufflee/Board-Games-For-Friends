extends SceneTree
## Два независимых запуска с общим тестовым APPDATA: принятие части, аварийный хвост, восстановление и SHA.
const Partial := preload("res://games/custom/logic/cg_partial.gd")
const Package := preload("res://games/custom/logic/cg_package.gd")
const Transfer := preload("res://games/custom/logic/cg_transfer.gd")
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _init() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		quit(1)
		return
	var bytes := PackedByteArray()
	bytes.resize(Package.CHUNK * 2 + 17)
	for index: int in bytes.size():
		bytes[index] = (index * 31 + index / 7919) % 251
	var hash_value := Package.sha(bytes)
	var transfer := Transfer.new()
	transfer.manifest = {"hash": hash_value, "size": bytes.size()}
	transfer._incoming_hash = hash_value
	transfer._requested = true
	if OS.get_cmdline_user_args().has("--produce-partial"):
		check(transfer.accept_chunk(hash_value, 0, bytes.size(), bytes.slice(0, Package.CHUNK)), "Первый процесс принял настоящую часть передачи")
		check(FileAccess.file_exists(Partial.PATH), "Принятая часть сохранена на диск")
		var file := FileAccess.open(Partial.PATH, FileAccess.READ_WRITE)
		file.seek_end()
		file.store_buffer(bytes.slice(Package.CHUNK, Package.CHUNK + 17))
		file.flush()
		check(file.get_length() == Partial.HEADER + Package.CHUNK + 17, "Подготовлен хвост незавершённой следующей части")
	else:
		transfer._incoming = Partial.restore(hash_value, bytes.size())
		check(transfer._incoming == bytes.slice(0, Package.CHUNK), "Новый процесс восстановил только полные части, отбросив аварийный хвост")
		check(Partial.restore("0".repeat(64), bytes.size()).is_empty(), "Другой hash не получает старую загрузку")
		check(Partial.restore(hash_value, bytes.size() + 1).is_empty(), "Подмена размера не принимает прежние байты")
		check(Partial.restore(hash_value, Package.LIMIT + 1).is_empty(), "Предельный размер проверен до чтения")
		check(transfer.accept_chunk(hash_value, Package.CHUNK, bytes.size(), bytes.slice(Package.CHUNK, Package.CHUNK * 2)), "Докачана следующая часть после перезапуска")
		check(transfer.accept_chunk(hash_value, Package.CHUNK * 2, bytes.size(), bytes.slice(Package.CHUNK * 2)), "Принят окончательный хвост ZIP")
		check(transfer._incoming == bytes and Package.sha(transfer._incoming) == hash_value, "Докачка побайтно равна исходнику и совпадает SHA")
		check(Partial.restore(hash_value, bytes.size()) == bytes, "Полностью принятый файл восстанавливается до окончательной проверки пакета")
		var file := FileAccess.open(Partial.PATH, FileAccess.READ_WRITE)
		file.seek(Partial.HEADER + 1)
		file.store_8(255)
		file.flush()
		file = null
		check(Partial.restore(hash_value, bytes.size()).is_empty(), "Повреждённый полный файл не принимается по одному заголовку")
		Partial.discard("0".repeat(64), bytes.size())
		check(FileAccess.file_exists(Partial.PATH), "Очистка чужого hash не удаляет текущую загрузку")
		Partial.discard(hash_value, bytes.size())
		check(not FileAccess.file_exists(Partial.PATH), "Завершённая или повреждённая загрузка удаляется только для своего hash")
		check(Partial.save(hash_value, bytes.size(), bytes.slice(0, Package.CHUNK), 0), "Смена пакета создаёт единственный новый checkpoint")
		var other_hash := "0".repeat(64)
		check(Partial.save(other_hash, bytes.size(), bytes.slice(0, Package.CHUNK), 0), "Другой пакет заменяет прежний checkpoint")
		check(Partial.restore(hash_value, bytes.size()).is_empty() and Partial.restore(other_hash, bytes.size()).size() == Package.CHUNK, "Два пакета не смешиваются")
		Partial.discard(other_hash, bytes.size())
	transfer.free()
	print("CUSTOM PARTIAL %s: %d проверок, %d ошибок" % ["WRITE" if OS.get_cmdline_user_args().has("--produce-partial") else "READ", checks, errors])
	quit(1 if errors else 0)
