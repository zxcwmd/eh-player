extends CanvasLayer
## АНАМНЕЗ (TAB) — медицинская карта Веры, заполняющаяся по ходу игры.
## В финале карта подписана другим именем. Здесь игрок видит:
## страницы лора, счётчики тегов, встреченных персонажей, процедуры,
## список смертей (= дел в Архиве).

var root: Control
var pages_root: VBoxContainer
var facts_label: RichTextLabel
var _open := false


func _ready() -> void:
	layer = 15
	_build()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("case_history"):
		toggle()
	if _open and event.is_action_pressed("pause"):
		toggle()


func toggle() -> void:
	_open = not _open
	visible = _open
	if _open:
		_refresh()
		Audio.play("chalk", -8.0)
	else:
		Audio.play("ui", -10.0)


func _build() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.035, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var header := Label.new()
	header.text = "ИСТОРИЯ БОЛЬНИ · БОЛЬНИЦА СВЯТОГО ИПАТИЯ · ПАЦИЕНТКА: ПРОСКУРИНА В.А."
	header.position = Vector2(60, 28)
	header.add_theme_font_size_override("font_size", 24)
	header.add_theme_color_override("font_color", Color(0.92, 0.90, 0.84))
	root.add_child(header)

	var sub := Label.new()
	sub.text = "ведётся с 14.03.2017 · страницы добавляются сами · подписи подделать невозможно"
	sub.position = Vector2(62, 62)
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.55, 0.57, 0.55))
	root.add_child(sub)

	# левая колонка: факты и теги
	facts_label = RichTextLabel.new()
	facts_label.bbcode_enabled = true
	facts_label.position = Vector2(60, 100)
	facts_label.size = Vector2(560, 560)
	facts_label.add_theme_font_size_override("normal_font_size", 16)
	facts_label.add_theme_color_override("default_color", Color(0.85, 0.86, 0.84))
	root.add_child(facts_label)

	# правая колонка: страницы анамнеза
	var pages_title := Label.new()
	pages_title.text = "НАЙДЕННЫЕ СТРАНИЦЫ (%d / 61)" % GameState.pages_found.size()
	pages_title.name = "PagesTitle"
	pages_title.position = Vector2(680, 100)
	pages_title.add_theme_font_size_override("font_size", 18)
	pages_title.add_theme_color_override("font_color", Color(0.9, 0.84, 0.6))
	root.add_child(pages_title)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(680, 134)
	scroll.size = Vector2(540, 520)
	root.add_child(scroll)
	pages_root = VBoxContainer.new()
	pages_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages_root)


func _refresh() -> void:
	var txt := ""
	txt += "[color=#d9cfae]ЭТАЖ:[/color] %d из 9 вниз пройдено (%d всего зачищено)\n" % [GameState.current_floor, GameState.floors_cleared.size()]
	txt += "[color=#d9cfae]ДЕЛ В АРХИВЕ:[/color] %d  ·  [color=#b03028]СМЕРТЕЙ: %d[/color]\n" % [GameState.case_file_number, GameState.deaths]
	txt += "[color=#d9cfae]ЛУЧШИЙ РАНГ:[/color] %s\n\n" % GameState.best_rank_reached

	txt += "[color=#b03028]АНАМНЕЗ (ТЕГИ):[/color]\n"
	for t in ["правда", "ложь", "жалость", "жестокость", "молчание"]:
		var v: int = GameState.tag(t)
		var bar := ""
		for i in mini(v, 24):
			bar += "■"
		txt += "  %-12s %2d %s\n" % [t, v, bar]
	txt += "\n"

	txt += "[color=#b03028]ГОЛОСА В ГОЛОВЕ:[/color]\n"
	txt += "  ДОКТОР — %s  ·  МАМА — %s  ·  СЕСТРА — %s  ·  МОЛЧАНИЕ — %s\n\n" % [
		"да" if GameState.has_flag("голос_доктор") else "нет",
		"да" if GameState.has_flag("голос_мама") else "нет",
		"да" if GameState.has_flag("голос_сестра") else "нет",
		"да" if GameState.has_flag("голос_никто") else "нет",
	]

	txt += "[color=#b03028]ПРОЦЕДУРЫ (модификации оружия):[/color]\n"
	if GameState.procedures_done.is_empty():
		txt += "  не проводились. каждую процедуру назначает только диалог.\n"
	else:
		for proc in GameState.procedures_done:
			txt += "  · %s\n" % proc
	txt += "\n"

	txt += "[color=#b03028]СОСТОЯНИЕ КЛЮЧЕВЫХ ФИГУР:[/color]\n"
	txt += "  МАМА: %s   ·   ИВАНЫЧ: %s   ·   ЛИДА: %s   ·   ПОДПИСЬ В АРХИВЕ: %s\n\n" % [
		"жива" if GameState.mother_alive else "УБИТА",
		"жив" if GameState.ivanich_alive else "УБИТ",
		"внутри" if GameState.lida_inside else "снаружи",
		"есть" if GameState.signed_archive else "нет",
	]

	txt += "[color=#b03028]ВСТРЕЧЕНЫ:[/color]\n"
	for c in GameState.characters_met:
		txt += "  · %s\n" % c
	if GameState.characters_met.is_empty():
		txt += "  пока никого. все ещё впереди.\n"

	txt += "\n[color=#666]в конце карты стоит подпись. это не подпись Веры.[/color]"
	facts_label.text = txt

	for c in pages_root.get_children():
		c.queue_free()
	for page in GameState.pages_found:
		var l := Label.new()
		l.text = "· %s" % page
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Color(0.82, 0.80, 0.70))
		pages_root.add_child(l)
	if GameState.pages_found.is_empty():
		var l := Label.new()
		l.text = "страницы спрятаны в комнатах, диалогах и смертях"
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		pages_root.add_child(l)

	var pages_title := root.find_child("PagesTitle", true, false)
	if pages_title is Label:
		(pages_title as Label).text = "НАЙДЕННЫЕ СТРАНИЦЫ (%d / 61)" % GameState.pages_found.size()
