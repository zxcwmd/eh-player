extends CanvasLayer
## HUD. По правилам арт-дирекции здоровья-бара НЕТ:
## состояние Веры = цвет её пижамы и кровь на модели.
## На экране живут только: стиль-штампы, ранг, монеты, таблетки, этаж,
## подсказки взаимодействий, предупреждение жажды и смерть.

const RANK_COLORS := {
	"D": Color(0.62, 0.62, 0.60), "C": Color(0.55, 0.62, 0.66),
	"B": Color(0.50, 0.66, 0.74), "A": Color(0.42, 0.78, 0.72),
	"S": Color(0.95, 0.78, 0.30), "SS": Color(0.98, 0.62, 0.20),
	"SSS": Color(0.94, 0.30, 0.24), "ULR": Color(1.0, 1.0, 1.0),
}

var stamp_label: Label
var rank_label: Label
var rank_bar: ColorRect
var coins_label: Label
var pills_label: Label
var floor_label: Label
var prompt_label: Label
var thirst_label: Label
var weapon_label: Label
var death_label: Label
var hint_label: Label
var _stamps: Array[Label] = []
var _coin_shown: int = -1
var _style_score: float = 0.0
var _death_timer: Timer


func _ready() -> void:
	layer = 10
	_build()
	Style.stamp.connect(_on_stamp)
	Style.rank_changed.connect(_on_rank_changed)
	Style.score_changed.connect(_on_score_changed)
	Blood.thirst_warning.connect(_on_thirst)
	Dialogue.dialogue_started.connect(func(_id: String) -> void: hint_label.text = "1–4 — ответить · ПРОБЕЛ — дальше · молчание — тоже ответ")
	Dialogue.dialogue_ended.connect(func(_id: String) -> void: hint_label.text = "")
	GameState.floor_changed.connect(_on_floor_changed)


func _process(_delta: float) -> void:
	pills_label.text = "ТАБЛЕТКИ: %d [T]" % GameState.pills
	var p: Player = _player()
	if p != null and p.rig != null:
		weapon_label.text = "%s  ·  %s" % [p.rig.current_name(), p.rig.ammo_text()]
	# подсказка взаимодействия
	prompt_label.text = ""
	if p != null:
		for n in p.get_tree().get_nodes_in_group("interactable"):
			if not is_instance_valid(n) or not (n is Node3D):
				continue
			if (n as Node3D).global_position.distance_to(p.global_position) < 2.6:
				prompt_label.text = str(n.get_meta("prompt", "[E]"))
				break
	# монеты в воздухе: сигнал инстанса недоступен через class_name — читаем счётчик
	var cc := Coin.current_combo
	if cc != _coin_shown:
		_coin_shown = cc
		if cc > 0:
			coins_label.text = "МОНЕТЫ В ВОЗДУХЕ ×%d — СТРЕЛЯЙ ПО НИМ" % cc
			coins_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		else:
			coins_label.text = "МОНЕТЫ ×0 [R — бросок]"
			coins_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))

	# шкала стиля
	rank_bar.scale.x = clampf(_style_score / 4200.0, 0.02, 1.0)
	if Style.hallucinating():
		rank_bar.color = Color(0.5, 0.12, 0.10)
	else:
		rank_bar.color = RANK_COLORS.get(Style.rank_current, Color.WHITE)


func _build() -> void:
	var root := Control.new()
	root.name = "HUD"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- стиль-штампы (центр сверху)
	stamp_label = Label.new()
	stamp_label.name = "StampLabel"
	stamp_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	stamp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp_label.position = Vector2(-300, 18)
	stamp_label.size = Vector2(600, 40)
	stamp_label.add_theme_font_size_override("font_size", 26)
	stamp_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	stamp_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	stamp_label.add_theme_constant_override("shadow_offset_x", 2)
	stamp_label.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(stamp_label)

	rank_label = Label.new()
	rank_label.name = "RankLabel"
	rank_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	rank_label.position = Vector2(16, 12)
	rank_label.add_theme_font_size_override("font_size", 30)
	rank_label.add_theme_color_override("font_color", Color(0.94, 0.30, 0.24))
	root.add_child(rank_label)

	rank_bar = ColorRect.new()
	rank_bar.name = "RankBar"
	rank_bar.position = Vector2(16, 52)
	rank_bar.size = Vector2(220, 6)
	rank_bar.color = Color(0.62, 0.62, 0.60)
	root.add_child(rank_bar)

	coins_label = Label.new()
	coins_label.name = "CoinsLabel"
	coins_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	coins_label.position = Vector2(16, 70)
	coins_label.add_theme_font_size_override("font_size", 18)
	coins_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	coins_label.text = "МОНЕТЫ ×0 [R — бросок]"
	root.add_child(coins_label)

	pills_label = Label.new()
	pills_label.name = "PillsLabel"
	pills_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pills_label.position = Vector2(16, 96)
	pills_label.add_theme_font_size_override("font_size", 16)
	pills_label.add_theme_color_override("font_color", Color(0.80, 0.86, 0.84))
	root.add_child(pills_label)

	floor_label = Label.new()
	floor_label.name = "FloorLabel"
	floor_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	floor_label.position = Vector2(-260, 12)
	floor_label.size = Vector2(240, 30)
	floor_label.add_theme_font_size_override("font_size", 20)
	floor_label.add_theme_color_override("font_color", Color(0.86, 0.20, 0.18))
	floor_label.text = "ЭТАЖ 0 · ПАЛАТА №0"
	root.add_child(floor_label)

	weapon_label = Label.new()
	weapon_label.name = "WeaponLabel"
	weapon_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.position = Vector2(-340, -64)
	weapon_label.size = Vector2(320, 30)
	weapon_label.add_theme_font_size_override("font_size", 18)
	weapon_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.88))
	root.add_child(weapon_label)

	prompt_label = Label.new()
	prompt_label.name = "PromptLabel"
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.position = Vector2(-300, -120)
	prompt_label.size = Vector2(600, 26)
	prompt_label.add_theme_font_size_override("font_size", 18)
	prompt_label.add_theme_color_override("font_color", Color(1, 1, 1))
	root.add_child(prompt_label)

	thirst_label = Label.new()
	thirst_label.name = "ThirstLabel"
	thirst_label.set_anchors_preset(Control.PRESET_CENTER)
	thirst_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thirst_label.position = Vector2(-320, 96)
	thirst_label.size = Vector2(640, 30)
	thirst_label.add_theme_font_size_override("font_size", 22)
	thirst_label.add_theme_color_override("font_color", Color(0.86, 0.10, 0.10))
	thirst_label.text = ""
	root.add_child(thirst_label)

	hint_label = Label.new()
	hint_label.name = "HintLabel"
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.position = Vector2(-420, -28)
	hint_label.size = Vector2(840, 24)
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.77))
	root.add_child(hint_label)

	death_label = Label.new()
	death_label.name = "DeathLabel"
	death_label.set_anchors_preset(Control.PRESET_CENTER)
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.position = Vector2(-400, -40)
	death_label.size = Vector2(800, 120)
	death_label.add_theme_font_size_override("font_size", 34)
	death_label.add_theme_color_override("font_color", Color(0.9, 0.1, 0.1))
	death_label.text = ""
	death_label.visible = false
	root.add_child(death_label)

	_death_timer = Timer.new()
	_death_timer.one_shot = true
	_death_timer.timeout.connect(_respawn)
	add_child(_death_timer)


# ============================================================ СТИЛЬ

func _on_stamp(text: String, points: int) -> void:
	var l := Label.new()
	l.text = "%s  +%d" % [text, points]
	l.add_theme_font_size_override("font_size", clampi(16 + points / 40, 16, 30))
	l.add_theme_color_override("font_color", Color(1, 0.93, 0.75))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.position = Vector2(-320, 54.0 + _stamps.size() * 26.0)
	l.size = Vector2(640, 28)
	add_child(l)
	_stamps.append(l)
	var tw := l.create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void:
		l.queue_free()
		_stamps.erase(l))
	stamp_label.text = text


func _on_rank_changed(_old: String, new_rank: String) -> void:
	rank_label.text = Style.rank_display_name()
	rank_label.add_theme_color_override("font_color", RANK_COLORS.get(new_rank, Color.WHITE))
	if Style.hallucinating():
		thirst_label.text = "ГОЛОСА ВЕРНУЛИСЬ · СТИЛЬ НИЗКИЙ · ЭКРАН ГНИЁТ"
		var tw := thirst_label.create_tween()
		tw.tween_interval(3.0)
		tw.tween_callback(func() -> void: thirst_label.text = "")


func _on_score_changed(score: float) -> void:
	_style_score = score


# ============================================================ СОБЫТИЯ

func _on_thirst() -> void:
	thirst_label.text = "КРОВЬ РЯДОМ = ЖИЗНЬ. ПОДОЙДИ БЛИЖЕ К ВРАГУ."
	var tw := thirst_label.create_tween()
	tw.tween_interval(2.4)
	tw.tween_callback(func() -> void: thirst_label.text = "")


func _on_floor_changed(index: int) -> void:
	var names := [
		"ЭТАЖ 0 · ПАЛАТА №0", "ЭТАЖ −1 · ПРИЁМНОЕ ОТДЕЛЕНИЕ",
		"ЭТАЖ −2 · ДЕТСКИЙ КОРПУС", "ЭТАЖ −3 · ОПЕРАЦИОННЫЙ БЛОК",
		"ЭТАЖ −4 · ЛОБОТОМИЧЕСКОЕ КРЫЛО", "ЭТАЖ −5 · АРХИВ",
		"ЭТАЖ −6 · МОРГ", "ЭТАЖ −7 · КОТЕЛЬНАЯ",
		"ЭТАЖ −8 · КАРАНТИН", "ЭТАЖ −9 · ЗЕРКАЛЬНЫЙ ЭТАЖ",
	]
	floor_label.text = names[clampi(index, 0, names.size() - 1)]
	var tw := floor_label.create_tween()
	floor_label.modulate.a = 0.0
	tw.tween_property(floor_label, "modulate:a", 1.0, 0.6)


func show_death(case_number: int) -> void:
	death_label.text = "ПАЦИЕНТКА НЕДОСТАТОЧНО МЁРТВА.\nЗАВЕДЕНО ДЕЛО №%d.\nПРОДОЛЖАЕМ ПРОЦЕДУРУ." % case_number
	death_label.visible = true
	death_label.modulate.a = 0.0
	var tw := death_label.create_tween()
	tw.tween_property(death_label, "modulate:a", 1.0, 0.4)
	_death_timer.start(2.6)


func _respawn() -> void:
	# перестроением этажа и возрождением занимается FloorManager;
	# HUD только убирает экран смерти, чтобы дело №% не задвоилось
	death_label.visible = false


func _player() -> Player:
	var nodes := get_tree().get_nodes_in_group("player")
	return (nodes[0] as Player) if nodes.size() > 0 else null
