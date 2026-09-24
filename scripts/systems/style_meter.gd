extends Node
## StyleMeter — ULTRAKILL-система стиля (autoload «Style»).
## Стиль = ясность сознания Веры. Высокий ранг гасит Голоса и галлюцинации,
## низкий — красит экран гнилью и спавнит фантомных врагов.

signal rank_changed(old_rank: String, new_rank: String)
signal stamp(text: String, points: int)
signal score_changed(score: float)
signal decayed

const RANKS: Array[String] = ["D", "C", "B", "A", "S", "SS", "SSS", "ULR"]
const RANK_NAMES: Dictionary = {
	"D": "ОТПУЩЕНА",
	"C": "ПОД НАБЛЮДЕНИЕМ",
	"B": "ВОЗБУЖДЕНА",
	"A": "В СЕБЕ",
	"S": "ИСТЕРИЯ",
	"SS": "БЕЖЕНКА ИЗ ТЕЛА",
	"SSS": "АВТОР АДА",
	"ULR": "УЛЬТРАПРОСКУРИНА",
}
## Пороги очков для каждого ранга.
const RANK_THRESHOLDS: Array[float] = [0.0, 80.0, 220.0, 480.0, 900.0, 1600.0, 2600.0, 4200.0]

const DECAY_DELAY := 4.0     # секунды бездействия до начала сгорания
const DECAY_RATE := 0.55     # доля очка в секунду на каждый 100 очков сверх порога

## После 4-й процедуры язык штампов становится клиническим.
var use_clinical_language: bool = false

var score: float = 0.0
var rank_index: int = 0
var rank_current: String = "D"
var idle_time: float = 0.0
var combo_count: int = 0

## Анти-спам: сколько раз подряд сделано одно и то же действие.
var _repeat: Dictionary = {}      # stamp_id -> {count, time}
const REPEAT_WINDOW := 2.5
const REPEAT_PENALTY := [1.0, 1.0, 0.75, 0.5, 0.35, 0.25, 0.15]

## Таблица действий. id -> [очки, текст обычный, текст клинический]
const STAMPS: Dictionary = {
	"parry":            [80,  "ПАРРИРОВАНО",              "РЕФЛЕКС СОХРАНЕН"],
	"parry_boost":      [150, "ПАРАЗИТ",                  "ПЕРЕКРЁСТНОЕ ЗАРАЖЕНИЕ"],
	"projectile_boost": [180, "СНАРЯД В ОБРАТНЫЙ ПУТЬ",   "РЕАКЦИЯ ОТТОРЖЕНИЯ"],
	"coin_1":           [100, "МОНЕТА",                   "МАРКЕР №1"],
	"coin_2":           [250, "МОНЕТА ×2",                "МАРКЕРЫ ×2"],
	"coin_3":           [550, "МОНЕТА ×3",                "МАРКЕРЫ ×3"],
	"coin_4":           [1200,"МОНЕТА ×4 (ЭТО УЖЕ СЛИШКОМ)", "МАРКЕРЫ ×4 (ПАТОЛОГИЯ)"],
	"air_dash":         [30,  "ВОЗДУШНЫЙ РЫВОК",          "ДИССОЦИАЦИЯ"],
	"double_jump":      [40,  "ИСТЕРИКА",                 "ПАРАДОКСАЛЬНАЯ РЕАКЦИЯ"],
	"slide":            [20,  "ПОД КАПЕЛЬНИЦЕЙ",          "ГОРИЗОНТАЛЬНОЕ ПОЛОЖЕНИЕ"],
	"slam":             [90,  "ЗЕМЛЯ ЕСТ",                "ОБЕЗБОЛИВАНИЕ НЕ ТРЕБУЕТСЯ"],
	"wall_jump":        [35,  "ПО СТЕНЕ",                 "ПОПЫТКА БЕГСТВА"],
	"fresh_blood":      [60,  "СВЕЖАЯ КРОВЬ",             "ПЕРЕЛИВАНИЕ"],
	"bloodbath":        [140, "КРОВАВАЯ БАНЯ",            "МАССИРОВАННАЯ ИНФУЗИЯ"],
	"headshot":         [70,  "ТОЧНО В ГЛАЗ",             "СЕЛЕКТИВНОЕ ПОРАЖЕНИЕ"],
	"multikill_3":      [200, "ТРОЕ СРАЗУ",               "СЕРИЙНАЯ ВЫПИСКА"],
	"multikill_5":      [420, "ПАЛАТА ПУСТА",             "ПОЛНАЯ ОЧИСТКА ОТДЕЛЕНИЯ"],
	"melee_kill":       [50,  "РУКАМИ",                   "КОНТАКТНЫЙ МЕТОД"],
	"punch_explode":    [110, "РАЗОРВАЛА",                "ДЕСТРУКЦИЯ ТКАНЕЙ"],
	"burn_kill":        [65,  "ГОРИТ ДОКУМЕНТАЦИЯ",       "ТЕРМООБРАБОТКА"],
	"no_damage_floor":  [600, "НИ ЦАРАПИНЫ",              "РЕМИССИЯ"],
	"speed_floor":      [350, "БЫСТРЕЕ ОБХОДА",           "ДОСРОЧНАЯ ВЫПИСКА"],
	"pacifist_room":    [500, "НИКОГО НЕ ТРОНУЛА",        "НЕГАТИВНАЯ СИМПТОМАТИКА"],
	"lida_pleased":     [300, "ЛИДА ДОВОЛЬНА",            "АЛЬТЕР-ЭГО СТАБИЛЬНО"],
	"mother_spared":    [800, "МАМА ЦЕЛА",                "ОБЪЕКТ ПРИВЯЗАННОСТИ СОХРАНЁН"],
	"ivanich_spared":   [900, "ИВАНЫЧ ЖИВ",               "ЕДИНСТВЕННЫЙ КОНТАКТ С РЕАЛЬНОСТЬЮ"],
	"secret_found":     [150, "ЗА ШИРМОЙ",                "СКРЫТЫЙ АНАМНЕЗ"],
	"layer_swap":       [45,  "ТАБЛЕТКА ПОД ЯЗЫК",        "СМЕНА КЛИНИЧЕСКОЙ КАРТИНЫ"],
	"scream":           [120, "КРИК",                     "ВОКАЛИЗАЦИЯ"],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	# анти-спам: устаревшие повторы
	for id in _repeat.keys():
		var rec: Dictionary = _repeat[id]
		if float(rec.get("time", 0.0)) + REPEAT_WINDOW < Time.get_ticks_msec() / 1000.0:
			_repeat.erase(id)

	idle_time += delta
	if idle_time > DECAY_DELAY and score > 0.0:
		var over: float = maxf(0.0, score - RANK_THRESHOLDS[rank_index])
		var loss: float = (18.0 + over * DECAY_RATE) * delta
		_add_score(-loss, false)
		decayed.emit()


## Основная точка входа. Возвращает реально начисленные очки.
func award(stamp_id: String, multiplier: float = 1.0) -> int:
	var data: Array = STAMPS.get(stamp_id, [50, stamp_id.to_upper(), stamp_id.to_upper()])
	var base: float = float(data[0])

	# анти-спам одного и того же действия
	var now := Time.get_ticks_msec() / 1000.0
	var rec: Dictionary = _repeat.get(stamp_id, {"count": 0, "time": 0.0})
	if now - float(rec["time"]) <= REPEAT_WINDOW:
		rec["count"] = int(rec["count"]) + 1
	else:
		rec["count"] = 0
	rec["time"] = now
	_repeat[stamp_id] = rec
	var penalty_idx: int = clampi(int(rec["count"]), 0, REPEAT_PENALTY.size() - 1)
	base *= REPEAT_PENALTY[penalty_idx]

	var total: float = base * multiplier * (1.0 + float(combo_count) * 0.02)
	var text: String = data[2] if use_clinical_language else data[1]
	stamp.emit(text, int(round(total)))
	idle_time = 0.0
	combo_count += 1
	_add_score(total, true)
	GameState.add_style_points(int(round(total)))
	return int(round(total))


func _add_score(amount: float, allow_rank_up: bool) -> void:
	score = maxf(0.0, score + amount)
	score_changed.emit(score)
	if amount < 0.0:
		_refresh_rank(allow_rank_up)
	else:
		_refresh_rank(true)


func _refresh_rank(allow_rank_up: bool) -> void:
	var new_index := 0
	for i in RANK_THRESHOLDS.size():
		if score >= RANK_THRESHOLDS[i]:
			new_index = i
	if not allow_rank_up and new_index > rank_index:
		new_index = rank_index
	if new_index != rank_index:
		var old := rank_current
		rank_index = new_index
		rank_current = RANKS[rank_index]
		rank_changed.emit(old, rank_current)


func reset(hard: bool = false) -> void:
	score = 0.0
	rank_index = 0
	rank_current = "D"
	idle_time = 0.0
	combo_count = 0
	if hard:
		_repeat.clear()
		use_clinical_language = GameState.lobotomy_taken


## Ранг сбрасывается между этажами только до «B» — стиль помнят.
func reset_for_next_floor() -> void:
	score = minf(score, 200.0)
	_refresh_rank(false)
	idle_time = 0.0
	combo_count = 0


func rank_value(rank: String) -> int:
	return RANKS.find(rank)


func damage_multiplier() -> float:
	return 1.0 + float(rank_index) * 0.0667        # D=1.00 … ULR≈1.47


func speed_multiplier() -> float:
	return 1.0 + float(rank_index) * 0.0286        # D=1.00 … ULR≈1.20


func heal_multiplier() -> float:
	return 1.0 + float(rank_index) * 0.10


## Голоса в голове замолкают, когда Вера «в себе».
func voices_suppressed() -> bool:
	return rank_index >= rank_value("A")


## Ранг ≤ C → галлюцинации, фантомы, гнилой постпроцесс.
func hallucinating() -> bool:
	return rank_index <= rank_value("C")


func rank_display_name() -> String:
	return "%s — %s" % [rank_current, RANK_NAMES.get(rank_current, "")]
