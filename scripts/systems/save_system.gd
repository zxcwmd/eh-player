extends Node
## SaveSystem — сохранения + АРХИВ (autoload «SaveSystem»).
## Главная сюжетная механика четвёртой стены: каждая смерть игрока создаёт
## новую историю болезни. 40 000 дел в Архиве = 40 000 спусков Веры.

const SAVE_FILE := "user://anamnesis.json"
const ARCHIVE_FILE := "user://archive.json"

var archive: Array = []          # список дел (case files)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_archive()


# ---------------------------------------------------------------- сохранение

func save_game() -> void:
	var data := {
		"version": 1,
		"state": GameState.to_dict(),
		"style": {"score": Style.score, "rank": Style.rank_current},
		"reality": {"layer": Reality.current},
		"saved_at": Time.get_datetime_string_from_system(),
	}
	var f := FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if f == null:
		push_warning("SaveSystem: не удалось открыть %s" % SAVE_FILE)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_FILE):
		return false
	var f := FileAccess.open(SAVE_FILE, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	GameState.from_dict(parsed.get("state", {}))
	var st: Dictionary = parsed.get("style", {})
	Style.score = float(st.get("score", 0.0))
	Style.use_clinical_language = GameState.lobotomy_taken
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_FILE)


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_FILE))


# ---------------------------------------------------------------- АРХИВ

## Дело заводится на каждый спуск и на каждую смерть. Номера видны в Архиве (этаж 5).
func write_case_file(number: int, floor_index: int, rank: String) -> void:
	archive.append({
		"дело": number,
		"этаж": floor_index,
		"ранг": rank,
		"время": Time.get_datetime_string_from_system(),
		"диагноз": _diagnosis_for(floor_index, rank),
	})
	_save_archive()


func archive_size() -> int:
	return archive.size()


func _save_archive() -> void:
	var f := FileAccess.open(ARCHIVE_FILE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"дела": archive}, "\t"))
	f.close()


func _load_archive() -> void:
	archive.clear()
	if not FileAccess.file_exists(ARCHIVE_FILE):
		return
	var f := FileAccess.open(ARCHIVE_FILE, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("дела"):
		var arr: Variant = parsed["дела"]
		if typeof(arr) == TYPE_ARRAY:
			archive = arr


const _DIAGNOSES := [
	"F43.8 — реакция на тяжёлый стресс, острая",
	"F44.0 — диссоциативная амнезия",
	"F44.81 — диссоциативное расстройство идентичности (под вопросом)",
	"F20.6 — простая шизофрения, вялотекущая форма",
	"F06.2 — органическое бредовое расстройство",
	"F98.8 — мутизм неуточнённый",
	"F50.9 — отказ от приёма пищи на фоне процедур",
	"Z04.6 — осмотр после пожара (повторный, 41-й)",
	"R45.4 — раздражительность и гнев",
	"R44.8 — галлюцинации неуточнённые",
]


func _diagnosis_for(floor_index: int, rank: String) -> String:
	var idx: int = (floor_index + rank.length()) % _DIAGNOSES.size()
	return _DIAGNOSES[idx]


## «Процедуры» — модификации оружия, открываются только выборами в диалогах.
func record_procedure(procedure_id: String) -> void:
	if not GameState.procedures_done.has(procedure_id):
		GameState.procedures_done.append(procedure_id)
	save_game()


func pages_percentage() -> float:
	return float(GameState.pages_found.size()) / 61.0 * 100.0
