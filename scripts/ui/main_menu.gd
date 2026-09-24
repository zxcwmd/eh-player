extends CanvasLayer
## Главное меню = обложка истории болезни больницы «Святого Ипатия».

signal new_game
signal continue_game
signal show_archive
signal quit_game

var root: Control
var _buttons: Array[Button] = []


func _ready() -> void:
	layer = 20
	_build()


func _build() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.042, 0.042, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	# «линованная бумага» фона
	for i in 26:
		var line := ColorRect.new()
		line.color = Color(0.09, 0.11, 0.10, 0.5)
		line.position = Vector2(0, 30 + i * 27)
		line.size = Vector2(1280, 1)
		root.add_child(line)
	var margin := ColorRect.new()
	margin.color = Color(0.42, 0.10, 0.10, 0.55)
	margin.position = Vector2(96, 0)
	margin.size = Vector2(1, 720)
	root.add_child(margin)

	var stamp := Label.new()
	stamp.text = "МИНЗДАВ · ФОРМА №112/у · НЕ ПОДЛЕЖИТ РАЗГЛАШЕНИЮ"
	stamp.position = Vector2(620, 18)
	stamp.add_theme_font_size_override("font_size", 13)
	stamp.add_theme_color_override("font_color", Color(0.6, 0.2, 0.18, 0.85))
	root.add_child(stamp)

	var title := Label.new()
	title.text = "ОТДЕЛЕНИЕ: НИЖЕ"
	title.position = Vector2(120, 90)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.93, 0.93, 0.90))
	title.add_theme_color_override("font_shadow_color", Color(0.86, 0.16, 0.14, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 3)
	root.add_child(title)

	var sub := Label.new()
	sub.text = "хоррор-экшен-новелла · пациентка: ПРОСКУРИНА В.А., 12 лет · диагноз: см. ниже"
	sub.position = Vector2(124, 172)
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(0.66, 0.68, 0.66))
	root.add_child(sub)

	var quote := Label.new()
	quote.text = "«Лифт идёт только вниз. Кнопки ВВЕРХ не было с 2017 года.»\n«Кровь — единственное лекарство. Стиль — единственная ясность.»"
	quote.position = Vector2(124, 214)
	quote.add_theme_font_size_override("font_size", 15)
	quote.add_theme_color_override("font_color", Color(0.5, 0.55, 0.53))
	root.add_child(quote)

	var menu := VBoxContainer.new()
	menu.position = Vector2(124, 330)
	menu.add_theme_constant_override("separation", 10)
	root.add_child(menu)
	_btn(menu, "НОВАЯ ПРОЦЕДУРА (начать)", _new)
	_btn(menu, "ПРОДОЛЖИТЬ ЛЕЧЕНИЕ (загрузить)", _cont, not SaveSystem.has_save())
	_btn(menu, "АРХИВ (дел и смертей: %d)" % SaveSystem.archive_size(), _arch)
	_btn(menu, "ВЫПИСАТЬСЯ (выход)", _quit)

	var credits := Label.new()
	credits.text = "УПРАВЛЕНИЕ: WASD — движение · ЛКМ — атака · ПКМ — парирование · ПРОБЕЛ/SHIFT — рывок · Q — прыжок/истерика · CTRL — скольжение/slam · R — монета/перезарядка · T — таблетка · E — взаимодействие · TAB — анамнез"
	credits.position = Vector2(124, 640)
	credits.add_theme_font_size_override("font_size", 13)
	credits.add_theme_color_override("font_color", Color(0.45, 0.47, 0.46))
	credits.size = Vector2(1000, 60)
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(credits)

	var case_no := Label.new()
	case_no.text = "ДЕЛО №%d" % GameState.case_file_number
	case_no.position = Vector2(1100, 660)
	case_no.add_theme_font_size_override("font_size", 22)
	case_no.add_theme_color_override("font_color", Color(0.86, 0.18, 0.16, 0.9))
	case_no.rotation = deg_to_rad(-6.0)
	root.add_child(case_no)


func _btn(parent: VBoxContainer, text: String, cb: Callable, disabled: bool = false) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(460, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.disabled = disabled
	b.pressed.connect(cb)
	parent.add_child(b)
	_buttons.append(b)


func _new() -> void:
	Audio.play("ui")
	new_game.emit()


func _cont() -> void:
	Audio.play("ui")
	continue_game.emit()


func _arch() -> void:
	Audio.play("ui")
	show_archive.emit()


func _quit() -> void:
	Audio.play("ui")
	quit_game.emit()


func refresh() -> void:
	for b in _buttons:
		if "ПРОДОЛЖИТЬ" in b.text:
			b.disabled = not SaveSystem.has_save()
		if "АРХИВ" in b.text:
			b.text = "АРХИВ (дел и смертей: %d)" % SaveSystem.archive_size()
		if "ДЕЛО" in b.text:
			b.text = "ДЕЛО №%d" % GameState.case_file_number
