extends CanvasLayer
## VN-бокс. Диалог идёт в реальном времени, в нижней трети экрана,
## игра НЕ ставится на паузу (на время выбора время замедлено до 0.6×).
## Портреты Голосов — процедурные силуэты, пока нет рисованных ассетов.

const BOX_H := 200.0
const CHOICE_TIME := 6.0

var root: Control
var panel: Panel
var name_label: Label
var text_label: RichTextLabel
var portrait: TextureRect
var choices_box: VBoxContainer
var timer_bar: ColorRect
var voice_chips: Dictionary = {}
var _choice_buttons: Array[Button] = []
var _timer_active := false

const PORTRAIT_BG := {
	"ДОКТОР": Color(0.07, 0.09, 0.11),
	"МАМА": Color(0.10, 0.06, 0.07),
	"СЕСТРА": Color(0.11, 0.09, 0.05),
	"ВЕРА": Color(0.06, 0.08, 0.10),
	"": Color(0.06, 0.06, 0.06),
}
const PORTRAIT_FG := {
	"ДОКТОР": Color(0.88, 0.90, 0.94),
	"МАМА": Color(0.90, 0.66, 0.64),
	"СЕСТРА": Color(0.94, 0.80, 0.42),
	"ВЕРА": Color(0.62, 0.74, 0.86),
	"": Color(0.75, 0.75, 0.75),
}


func _ready() -> void:
	layer = 11
	_build()
	Dialogue.dialogue_started.connect(func(_id: String) -> void: open_box())
	Dialogue.node_entered.connect(_on_node)
	Dialogue.choices_offered.connect(_on_choices_offered)
	Dialogue.dialogue_ended.connect(func(_id: String) -> void: close_box())
	Dialogue.voice_set.connect(_on_voice_set)
	Dialogue.choice_made.connect(_on_choice_made)
	Dialogue.timed_out.connect(_on_timed_out)
	visible = false


func _process(_delta: float) -> void:
	if not visible:
		return
	text_label.text = Dialogue.text_visible()
	if Dialogue.is_typing():
		return
	if _timer_active:
		var k := clampf(Dialogue.choice_time_left / CHOICE_TIME, 0.0, 1.0)
		timer_bar.scale.x = k
		if k < 0.3:
			timer_bar.color = Color(0.9, 0.2, 0.15)
		else:
			timer_bar.color = Color(0.9, 0.85, 0.55)


func _build() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	panel = Panel.new()
	panel.name = "Panel"
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 24
	panel.offset_right = -24
	panel.offset_top = _hidden_y()
	panel.offset_bottom = _hidden_y() + BOX_H
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.06, 0.92)
	sb.border_color = Color(0.65, 0.16, 0.14, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.position = Vector2(14, 14)
	portrait.size = Vector2(BOX_H - 28, BOX_H - 28)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.add_child(portrait)

	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.position = Vector2(BOX_H + 8, 10)
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.80))
	panel.add_child(name_label)

	text_label = RichTextLabel.new()
	text_label.name = "TextLabel"
	text_label.bbcode_enabled = true
	text_label.fit_content = false
	text_label.scroll_active = false
	text_label.position = Vector2(BOX_H + 8, 40)
	text_label.size = Vector2(820, 84)
	text_label.add_theme_font_size_override("normal_font_size", 17)
	text_label.add_theme_color_override("default_color", Color(0.88, 0.89, 0.88))
	panel.add_child(text_label)

	choices_box = VBoxContainer.new()
	choices_box.name = "Choices"
	choices_box.position = Vector2(BOX_H + 8, 128)
	choices_box.size = Vector2(820, 64)
	panel.add_child(choices_box)

	timer_bar = ColorRect.new()
	timer_bar.name = "TimerBar"
	timer_bar.position = Vector2(0, 0)
	timer_bar.size = Vector2(1180, 3)
	timer_bar.color = Color(0.9, 0.85, 0.55)
	timer_bar.visible = false
	panel.add_child(timer_bar)

	# индикаторы активных Голосов (правый верхний угол)
	var voices_root := HBoxContainer.new()
	voices_root.name = "VoiceChips"
	voices_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	voices_root.position = Vector2(-420, 10)
	voices_root.size = Vector2(400, 30)
	add_child(voices_root)
	for v in ["ДОКТОР", "МАМА", "СЕСТРА"]:
		var chip := Label.new()
		chip.text = v
		chip.add_theme_font_size_override("font_size", 13)
		chip.add_theme_color_override("font_color", Color(0.55, 0.56, 0.54))
		voices_root.add_child(chip)
		var pad := Control.new()
		pad.size = Vector2(14, 1)
		voices_root.add_child(pad)
		voice_chips[v] = chip


func _on_node(node: Dictionary) -> void:
	if not visible:
		open_box()
	name_label.text = str(node.get("speaker", ""))
	text_label.text = ""
	var speaker := str(node.get("speaker", ""))
	var kind := ""
	if speaker.contains("ДОКТОР") or speaker.contains("АСКОНЧЕНСКИЙ"):
		kind = "doctor"
	elif speaker.contains("МАМА") or speaker.contains("ЕКАТЕРИНА"):
		kind = "mother"
	elif speaker.contains("СЕСТРА") or speaker.contains("ЛИДА"):
		kind = "sister"
	var key := speaker
	if key.contains("("):
		key = key.substr(key.find("(") + 1)
		key = key.substr(0, key.find(")"))
	var bg: Color = PORTRAIT_BG.get(key, Color(0.06, 0.06, 0.06))
	var fg: Color = PORTRAIT_FG.get(key, Color(0.75, 0.75, 0.75))
	portrait.texture = FxFactory.portrait_placeholder(128, bg, fg, kind)
	Audio.play("ui", -16.0, randf_range(0.9, 1.1))
	_clear_choices()
	timer_bar.visible = false


func _on_choices_offered(choices: Array, _time_left: float) -> void:
	if _choice_buttons.size() == choices.size() and choices.size() > 0:
		return
	_clear_choices()
	timer_bar.visible = choices.size() > 0
	for i in choices.size():
		var c: Dictionary = choices[i]
		var b := Button.new()
		var tag: String = str(c.get("tag", ""))
		var suffix := ""
		if tag != "":
			suffix = "  [%s]" % tag.to_upper()
		b.text = "%d. %s%s" % [i + 1, str(c.get("text", "…")), suffix]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		var idx := i
		b.pressed.connect(func() -> void: Dialogue.choose(idx))
		choices_box.add_child(b)
		_choice_buttons.append(b)


func _on_choice_made(_c: Dictionary) -> void:
	timer_bar.visible = false
	_clear_choices()
	Audio.play("ui", -8.0, 0.8)


func _on_timed_out(_node_id: String) -> void:
	timer_bar.visible = false
	_clear_choices()
	name_label.text = "ВЕРА (МОЛЧИТ)"


func _on_voice_set(voice_id: String) -> void:
	for v in voice_chips.keys():
		var chip: Label = voice_chips[v]
		if v == voice_id:
			chip.add_theme_color_override("font_color", Color(0.98, 0.9, 0.55))
			chip.text = "● " + v
		else:
			chip.add_theme_color_override("font_color", Color(0.5, 0.51, 0.49))
			chip.text = v


func _clear_choices() -> void:
	for b in _choice_buttons:
		if is_instance_valid(b):
			b.queue_free()
	_choice_buttons.clear()


func _hidden_y() -> float:
	return get_viewport().get_visible_rect().size.y + 10.0


func _shown_y() -> float:
	return get_viewport().get_visible_rect().size.y - BOX_H - 16.0


func open_box() -> void:
	visible = true
	panel.offset_top = _hidden_y()
	var tw := panel.create_tween()
	tw.tween_property(panel, "offset_top", _shown_y(), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(panel, "offset_bottom", _shown_y() + BOX_H, 0.18)


func close_box() -> void:
	var tw := panel.create_tween()
	tw.tween_property(panel, "offset_top", _hidden_y(), 0.16)
	tw.parallel().tween_property(panel, "offset_bottom", _hidden_y() + BOX_H, 0.16)
	tw.tween_callback(func() -> void: visible = false)
	_clear_choices()
