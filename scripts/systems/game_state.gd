extends Node
## GameState — глобальное состояние прохождения (autoload «GameState»).
## Единственный источник правды о том, что произошло с Верой.

signal floor_changed(floor_index: int)
signal ending_locked(ending_id: String)
signal flag_set(flag: String)

const FLOOR_COUNT := 10            # 0..9
const SAVE_PATH := "user://anamnesis.json"

## Игрок
var hp_max: float = 100.0
var hp: float = 100.0

## Прогресс
var current_floor: int = 0
var floors_cleared: Array[int] = []

## Оружие: 4 слота, слот 4 открывается только через «ПРОЦЕДУРУ»
var weapons_unlocked: Array[int] = [1, 2]
var current_weapon: int = 1
var procedures_done: Array[String] = []   # модификации, полученные выборами

## Ресурсы
var pills: int = 3                 # таблетки переключения слоя реальности
var milk: int = 0                  # восстанавливает заряд рывка
var style_points_total: int = 0    # накоплено за всю игру

## Анамнез
var pages_found: Array[String] = []      # 61 страница лора
var tags: Dictionary = {}                # #жестокость / #жалость / #правда / #ложь / ...
var characters_met: Array[String] = []
var bosses_killed: Array[String] = []
var mercy_kills_avoided: Array[String] = []  # кого НЕ убили (нужно для концовки F)

## Сюжетные флаги
var flags: Dictionary = {}

## Мета / четвёртая стена
var deaths: int = 0                # каждое возрождение = новая история болезни в Архиве
var case_file_number: int = 41     # «дело №41» — стартовый номер
var best_rank_reached: String = "D"
var ending_chosen: String = ""

## Ключевые необратимые выборы
var lida_inside: bool = false      # сестра-голос впущена в голову
var mother_alive: bool = true      # МАМА не убита на 6 этаже
var ivanich_alive: bool = true     # Иваныч не убит в котельной
var signed_archive: bool = false   # расписалась за дело (концовка E)
var lobotomy_taken: bool = false   # 4-я процедура, меняет тон всей игры
var chose_nobody: bool = false

const ENDINGS := {
	"A": "ВЫПИСАНА",
	"B": "ПРОЦЕДУРА ЗАВЕРШЕНА",
	"C": "СЕСТРА",
	"D": "НИКТО",
	"E": "МЕТОД АСКОНЧЕНСКОГО",
	"F": "МЕЛ",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# ---------------------------------------------------------------- жизнь

func damage(amount: float) -> void:
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		register_death()


func heal(amount: float) -> void:
	hp = minf(hp_max, hp + amount)


func is_dead() -> bool:
	return hp <= 0.0


func reset_vitals() -> void:
	hp = hp_max


## Смерть = новая процедура. Пишем дело в Архив. Это сюжет, а не статистика.
func register_death() -> void:
	deaths += 1
	case_file_number += 1
	SaveSystem.write_case_file(case_file_number, current_floor, Style.rank_current)


# ---------------------------------------------------------------- этаж

func set_floor(index: int) -> void:
	current_floor = clampi(index, 0, FLOOR_COUNT - 1)
	floor_changed.emit(current_floor)


func clear_floor(index: int) -> void:
	if not floors_cleared.has(index):
		floors_cleared.append(index)


# ---------------------------------------------------------------- флаги

func set_flag(flag: String, value: bool = true) -> void:
	flags[flag] = value
	flag_set.emit(flag)
	match flag:
		"сестра_внутри":
			lida_inside = value
		"мама_убита":
			mother_alive = not value
		"иваныч_убит":
			ivanich_alive = not value
		"подпись":
			signed_archive = value
		"процедура_4":
			lobotomy_taken = value
			Style.use_clinical_language = true
		"никто":
			chose_nobody = value


func has_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))


func add_tag(tag: String, weight: int = 1) -> void:
	tags[tag] = int(tags.get(tag, 0)) + weight


func tag(tag_name: String) -> int:
	return int(tags.get(tag_name, 0))


func add_page(page_id: String) -> bool:
	if pages_found.has(page_id):
		return false
	pages_found.append(page_id)
	return true


func meet(character_id: String) -> void:
	if not characters_met.has(character_id):
		characters_met.append(character_id)


func add_style_points(amount: int) -> void:
	style_points_total += amount
	if Style.rank_current > best_rank_reached:
		best_rank_reached = Style.rank_current


func add_pills(n: int) -> void:
	pills += n


func use_pill() -> bool:
	if pills <= 0:
		return false
	pills -= 1
	return true


# ---------------------------------------------------------------- концовки

## Вычисляет доступные концовки на основе всех флагов.
func available_endings() -> Array[String]:
	var out: Array[String] = []
	var rank_ok := Style.rank_value(Style.rank_current) >= Style.rank_value("A")

	if mother_alive and ivanich_alive and not lobotomy_taken:
		out.append("A")
	if not mother_alive:
		out.append("B")
	if lida_inside:
		out.append("C")
	out.append("D")                                   # «НИКТО» доступен всегда
	if procedures_done.size() >= 4 and signed_archive:
		out.append("E")
	if pages_found.size() >= 61 and mercy_kills_avoided.size() >= 20:
		out.append("F")
	if rank_ok and bosses_killed.size() >= 6:
		if not out.has("A") and mother_alive:
			out.append("A")
	return out


func choose_ending(ending_id: String) -> String:
	var avail := available_endings()
	if not avail.has(ending_id):
		ending_id = "D"
	ending_chosen = ending_id
	return ending_id


# ---------------------------------------------------------------- сериализация

func to_dict() -> Dictionary:
	return {
		"hp_max": hp_max, "hp": hp,
		"current_floor": current_floor, "floors_cleared": floors_cleared,
		"weapons_unlocked": weapons_unlocked, "current_weapon": current_weapon,
		"procedures_done": procedures_done,
		"pills": pills, "milk": milk, "style_points_total": style_points_total,
		"pages_found": pages_found, "tags": tags,
		"characters_met": characters_met, "bosses_killed": bosses_killed,
		"mercy_kills_avoided": mercy_kills_avoided,
		"flags": flags,
		"deaths": deaths, "case_file_number": case_file_number,
		"best_rank_reached": best_rank_reached, "ending_chosen": ending_chosen,
		"lida_inside": lida_inside, "mother_alive": mother_alive,
		"ivanich_alive": ivanich_alive, "signed_archive": signed_archive,
		"lobotomy_taken": lobotomy_taken, "chose_nobody": chose_nobody,
	}


func from_dict(d: Dictionary) -> void:
	var known := to_dict()
	for k in known.keys():
		if d.has(k):
			set(k, d[k])
