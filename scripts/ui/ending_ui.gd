extends CanvasLayer
## Финальные титры шести концовок.
## Текст концовки — единственный момент игры, где Вера ГОВОРИТ.

signal closed

var root: Control

const ENDINGS := {
	"A": {
		"title": "ВЫПИСАНА",
		"color": Color(0.86, 0.90, 0.88),
		"text": "Вера открывает глаза в настоящей палате. Год 2026. Ей семнадцать.\nИваныча нет уже девять лет — стул у кровати продавлен его телом.\nЗа окном — настоящее окно.\nОна делает вдох и говорит первое слово:\n«лида».",
	},
	"B": {
		"title": "ПРОЦЕДУРА ЗАВЕРШЕНА",
		"color": Color(0.55, 0.60, 0.72),
		"text": "Вера исчезает из карты. Аскоченский просыпается в своём кабинете,\nпишет методичку «ЭТАЖИ: практика погружения» и отправляет её в двенадцать клиник.\nПрограмма уходит в массовое производство.\nНа последней странице методички — детский рисунок двери, перечёркнутый краской.",
	},
	"C": {
		"title": "СЕСТРА",
		"color": Color(0.95, 0.80, 0.42),
		"text": "Лида поднимается наверх. Девять этажей вверх, навстречу огню.\nВ квартире на пятом — 14 марта 2017 года, три часа ночи.\nОна выносит на руках двух девочек сразу.\nОдна из них потом всю жизнь молчит. Но живёт.\nОбе живут.",
	},
	"D": {
		"title": "НИКТО",
		"color": Color(0.30, 0.32, 0.31),
		"text": "Вера садится на пол карантина и не двигается.\nКамера уезжает в угол комнаты и смотрит.\nЧетыре минуты тишины. Ни одного врага. Ни одного голоса.\nБольница ждёт. Больница умеет ждать.\n(Самая страшная концовка — потому что ничего не происходит.)",
	},
	"E": {
		"title": "МЕТОД АСКОНЧЕНСКОГО",
		"color": Color(0.86, 0.18, 0.16),
		"text": "Аскоченский вспоминает всё на последнем ударе.\nОн остаётся внутри навсегда — главным врачом собственного пациента.\nКруг замыкается. Девять этажей строятся заново.\nГде-то в палате ноль девочка рисует мелом дверь.\nКто-то внутри неё берёт карандаш.",
	},
	"F": {
		"title": "МЕЛ",
		"color": Color(0.96, 0.96, 0.93),
		"text": "Вера рисует новую дверь. Не вниз. НАРУЖУ.\nБольница складывается, как лист бумаги: коридоры в гармошку,\nэтажи — стопкой, голоса — в один штрих.\nОстаётся настоящий детский рисунок: дом, солнце, две фигуры.\nПодпись внизу сделана рукой, которая умеет держать карандаш.",
	},
}


func _ready() -> void:
	layer = 30
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	visible = false


func show_ending(ending_id: String) -> void:
	for c in root.get_children():
		c.queue_free()
	var e: Dictionary = ENDINGS.get(ending_id, ENDINGS["D"])

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.02, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var title := Label.new()
	title.text = "КОНЦОВКА: %s" % str(e["title"])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-400, 120)
	title.size = Vector2(800, 60)
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", e["color"])
	root.add_child(title)

	var body := Label.new()
	body.text = str(e["text"])
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.set_anchors_preset(Control.PRESET_CENTER)
	body.position = Vector2(-460, -140)
	body.size = Vector2(920, 280)
	body.add_theme_font_size_override("font_size", 19)
	body.add_theme_color_override("font_color", Color(0.85, 0.86, 0.84))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(body)

	var stats := Label.new()
	stats.text = "ДЕЛ В АРХИВЕ: %d · СМЕРТЕЙ: %d · ЛУЧШИЙ РАНГ: %s · СТРАНИЦ: %d/61 · МАМА: %s · ИВАНЫЧ: %s" % [
		GameState.case_file_number, GameState.deaths, GameState.best_rank_reached,
		GameState.pages_found.size(),
		"жива" if GameState.mother_alive else "убита",
		"жив" if GameState.ivanich_alive else "убит",
	]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	stats.position = Vector2(-560, -120)
	stats.size = Vector2(1120, 30)
	stats.add_theme_font_size_override("font_size", 15)
	stats.add_theme_color_override("font_color", Color(0.55, 0.56, 0.55))
	root.add_child(stats)

	var back := Button.new()
	back.text = "ВЕРНУТЬСЯ В КАРТУ"
	back.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	back.position = Vector2(-140, -70)
	back.size = Vector2(280, 46)
	back.add_theme_font_size_override("font_size", 18)
	back.pressed.connect(_close)
	root.add_child(back)

	visible = true
	Audio.play("chalk", -6.0)


func _close() -> void:
	visible = false
	closed.emit()
