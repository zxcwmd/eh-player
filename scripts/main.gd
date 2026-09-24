extends Node3D
## Корневая сцена. Порядок вещей:
##   1. главное меню (обложка истории болезни);
##   2. по «НОВАЯ ПРОЦЕДУРА» строится этаж 0, спавнится Вера и камера;
##   3. смерть = перестроение этажа + новое дело в Архиве;
##   4. лифт ведёт вниз; когда данные этажей заканчиваются — конец среза.

var menu_ui: Node
var hud_ui: Node
var dialogue_ui: Node
var anamnesis_ui: Node
var pause_ui: Node
var ending_ui: Node
var floor_manager: FloorManager
var env: WorldEnvironment
var world_root: Node3D
var _running := false


func _ready() -> void:
	_build_world_env()
	_build_world_root()

	floor_manager = FloorManager.new()
	floor_manager.name = "FloorManager"
	world_root.add_child(floor_manager)

	menu_ui = load("res://scripts/ui/main_menu.gd").new()
	menu_ui.name = "MainMenu"
	add_child(menu_ui)
	menu_ui.new_game.connect(_on_new_game)
	menu_ui.continue_game.connect(_on_continue)
	menu_ui.show_archive.connect(_on_show_archive_from_menu)
	menu_ui.quit_game.connect(func() -> void: get_tree().quit())

	hud_ui = load("res://scripts/ui/hud.gd").new()
	hud_ui.name = "HUD"
	add_child(hud_ui)
	hud_ui.visible = false

	dialogue_ui = load("res://scripts/ui/dialogue_box.gd").new()
	dialogue_ui.name = "DialogueBox"
	add_child(dialogue_ui)

	anamnesis_ui = load("res://scripts/ui/anamnesis_ui.gd").new()
	anamnesis_ui.name = "Anamnesis"
	add_child(anamnesis_ui)

	pause_ui = load("res://scripts/ui/pause_ui.gd").new()
	pause_ui.name = "PauseUI"
	add_child(pause_ui)
	pause_ui.to_menu.connect(_to_menu)

	ending_ui = load("res://scripts/ui/ending_ui.gd").new()
	ending_ui.name = "EndingUI"
	add_child(ending_ui)
	ending_ui.closed.connect(_to_menu)

	floor_manager.floor_started.connect(_on_floor_started)
	floor_manager.floor_cleared.connect(_on_floor_cleared)
	Dialogue.dialogue_ended.connect(_on_dialogue_ended)
	Reality.layer_changed.connect(_on_layer_changed)

	Audio.set_ambient("white")


func _build_world_env() -> void:
	env = WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.06)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.64)
	e.ambient_light_energy = 0.55
	e.fog_enabled = true
	e.fog_light_color = Color(0.82, 0.86, 0.84)
	e.fog_density = 0.004
	e.volumetric_fog_enabled = false
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.glow_bloom = 0.12
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.92
	e.adjustment_contrast = 1.06
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.light_energy = 0.28
	sun.light_color = Color(0.9, 0.94, 0.92)
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(18.0), 0)
	sun.shadow_enabled = true
	add_child(sun)


func _build_world_root() -> void:
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)


# ============================================================ ПОТОК ИГРЫ

func _on_new_game() -> void:
	# новая процедура: чистая карта, новое дело №41
	GameState.deaths = 0
	GameState.case_file_number = 41
	GameState.tags.clear()
	GameState.pages_found.clear()
	GameState.characters_met.clear()
	GameState.flags.clear()
	GameState.lida_inside = false
	GameState.mother_alive = true
	GameState.ivanich_alive = true
	GameState.signed_archive = false
	GameState.lobotomy_taken = false
	GameState.weapons_unlocked = [1, 2]
	GameState.pills = 3
	GameState.hp = GameState.hp_max
	GameState.style_points_total = 0
	GameState.milk = 0
	GameState.floors_cleared.clear()
	GameState.procedures_done.clear()
	GameState.bosses_killed.clear()
	GameState.mercy_kills_avoided.clear()
	GameState.ending_chosen = ""
	GameState.chose_nobody = false
	Style.reset(true)
	SaveSystem.delete_save()
	_start_run(0)


func _on_continue() -> void:
	if SaveSystem.load_game():
		_start_run(GameState.current_floor)
	else:
		_start_run(0)


func _start_run(floor_idx: int) -> void:
	_running = true
	menu_ui.visible = false
	hud_ui.visible = true
	world_root.visible = true
	floor_manager.start_floor(floor_idx)
	_connect_player_signals()
	SaveSystem.save_game()


func _connect_player_signals() -> void:
	var p := floor_manager.player
	if p == null:
		return
	if not p.died.is_connected(_on_player_died):
		p.died.connect(_on_player_died)


func _on_player_died() -> void:
	GameState.register_death()
	hud_ui.show_death(GameState.case_file_number)
	Audio.play("enemy_die", -8.0, 0.55)
	# перестроение этажа: как в ULTRAKILL рестарт, но Архив помнит всё
	var idx := floor_manager.floor_index
	await get_tree().create_timer(2.7).timeout
	if _running:
		floor_manager.start_floor(idx)
		_connect_player_signals()
		Audio.play("chalk", -10.0)


func _to_menu() -> void:
	_running = false
	SaveSystem.save_game()
	hud_ui.visible = false
	get_tree().paused = false
	world_root.visible = false
	menu_ui.visible = true
	menu_ui.refresh()
	Dialogue.end()
	Style.reset(true)


func _on_show_archive_from_menu() -> void:
	# Анамнез доступен и из меню — игрок видит дела до начала игры
	anamnesis_ui.toggle()


func _on_floor_started(index: int) -> void:
	_connect_player_signals()
	if index >= 1:
		Audio.play("rank_up", -16.0, 0.6)


func _on_floor_cleared(_index: int) -> void:
	SaveSystem.save_game()


func _on_dialogue_ended(convo_id: String) -> void:
	if convo_id == "vertical_slice_end":
		_end_of_slice()
	if convo_id == "mother_boss" and GameState.has_flag("мама_убита"):
		Style.score = maxf(0.0, Style.score - 400.0)


func _end_of_slice() -> void:
	# конец вертикального среза: показать концовку по текущим флагам
	var avail := GameState.available_endings()
	var pick := "D"
	if avail.has("A"):
		pick = "A"
	elif avail.has("C"):
		pick = "C"
	ending_ui.show_ending(pick)


func _on_layer_changed(layer: String) -> void:
	Audio.set_ambient(layer)
	var e := env.environment
	if e == null:
		return
	if layer == "rust":
		e.background_color = Color(0.035, 0.02, 0.018)
		e.ambient_light_color = Color(0.75, 0.5, 0.34)
		e.fog_light_color = Color(0.16, 0.09, 0.06)
		e.fog_density = 0.010
		e.adjustment_saturation = 1.05
	else:
		e.background_color = Color(0.05, 0.06, 0.06)
		e.ambient_light_color = Color(0.62, 0.66, 0.64)
		e.fog_light_color = Color(0.82, 0.86, 0.84)
		e.fog_density = 0.004
		e.adjustment_saturation = 0.92


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		var k: int = (event as InputEventKey).keycode
		# сервисные клавиши финальных экранов (для показа всех концовок среза)
		if k >= KEY_F1 and k <= KEY_F6:
			var ids := ["A", "B", "C", "D", "E", "F"]
			ending_ui.show_ending(ids[k - KEY_F1])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveSystem.save_game()
