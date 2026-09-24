extends CanvasLayer
## Пауза (ESC). Больница не ставится на паузу никогда —
## но бумажная карта позволяет сделать перерыв.

signal resume
signal to_menu

var root: Control


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle()


func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	if visible:
		Audio.play("ui", -8.0)


func _build() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.02, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var title := Label.new()
	title.text = "ПЕРЕРЫВ В ПРОЦЕДУРЕ"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(-300, 150)
	title.size = Vector2(600, 50)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.92, 0.90, 0.84))
	root.add_child(title)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-180, -60)
	box.add_theme_constant_override("separation", 12)
	root.add_child(box)

	var resume_b := Button.new()
	resume_b.text = "ПРОДОЛЖИТЬ"
	resume_b.custom_minimum_size = Vector2(360, 46)
	resume_b.add_theme_font_size_override("font_size", 20)
	resume_b.pressed.connect(func() -> void: toggle(); resume.emit())
	box.add_child(resume_b)

	var save_b := Button.new()
	save_b.text = "ЗАПИСАТЬ В КАРТУ (сохранить)"
	save_b.custom_minimum_size = Vector2(360, 46)
	save_b.add_theme_font_size_override("font_size", 20)
	save_b.pressed.connect(func() -> void: SaveSystem.save_game(); Audio.play("chalk", -8.0))
	box.add_child(save_b)

	var menu_b := Button.new()
	menu_b.text = "К ОБЛОЖКЕ ИСТОРИИ"
	menu_b.custom_minimum_size = Vector2(360, 46)
	menu_b.add_theme_font_size_override("font_size", 20)
	menu_b.pressed.connect(func() -> void:
		get_tree().paused = false
		visible = false
		to_menu.emit())
	box.add_child(menu_b)

	var note := Label.new()
	note.text = "пока вы читаете это, этаж продолжает дышать"
	note.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.position = Vector2(-300, -60)
	note.size = Vector2(600, 26)
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	root.add_child(note)
