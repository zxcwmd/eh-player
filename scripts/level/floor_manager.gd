class_name FloorManager
extends Node3D
## FloorManager — строит этаж из JSON, спавнит волны, ведёт учёт смертей
## и переходы между этажами. Вертикальный срез: этаж 0 (пролог) и этаж 1
## (приёмное отделение, босс — МЕДСЕСТРА ШВОВ ×3).
##
## Смерть = новая процедура: на каждый рестарт этаж строится заново,
## а в Архив уходит новое дело.

signal floor_started(floor_index: int)
signal room_spawned(room: Node)
signal wave_started(room_name: String, count: int)
signal floor_cleared(floor_index: int)
signal phantom_spawned(count: int)

const FLOORS_DIR := "res://content/floors/"

var floor_index: int = -1
var data: Dictionary = {}
var rooms_root: Node3D
var enemies_root: Node3D
var player: Player
var camera: IsaacCamera
var _active_waves: Dictionary = {}     # room_trigger -> remaining enemies
var _phantom_timer := 8.0
var _floor_intro_played: Dictionary = {}


func _ready() -> void:
	add_to_group("floor_manager")
	rooms_root = Node3D.new()
	rooms_root.name = "Rooms"
	add_child(rooms_root)
	enemies_root = Node3D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)
	Coin.set_scene_root(enemies_root)
	Dialogue.dialogue_ended.connect(_on_dialogue_ended)


func _process(delta: float) -> void:
	# фантомы при низком стиле (ранг ≤ C): галлюцинации становятся плотью
	if Style.hallucinating() and floor_index >= 1:
		_phantom_timer -= delta
		if _phantom_timer <= 0.0:
			_phantom_timer = randf_range(9.0, 14.0)
			_spawn_phantom()


# ============================================================ ЭТАЖ

func start_floor(index: int) -> void:
	floor_index = index
	GameState.set_floor(index)
	Style.reset_for_next_floor()
	if player != null:
		player.reset_floor_stats()
		player.revive_silent()

	_clear_floor()
	data = _load_floor(index)
	if data.is_empty():
		push_warning("FloorManager: данные этажа %d отсутствуют" % index)
		return

	for room_def in data.get("rooms", []):
		_build_room(room_def)

	_spawn_player()
	_spawn_camera()
	_place_elevator()
	_connect_triggers()

	floor_started.emit(index)
	SaveSystem.write_case_file(GameState.case_file_number, index, Style.rank_current)

	var intro_id := str(data.get("intro", ""))
	if intro_id != "" and not bool(_floor_intro_played.get(index, false)):
		_floor_intro_played[index] = true
		Dialogue.start(intro_id)
	Audio.set_ambient(Reality.layer_name())
	Audio.set_music_layer(0)


func _clear_floor() -> void:
	for c in rooms_root.get_children():
		c.queue_free()
	for c in enemies_root.get_children():
		c.queue_free()
	_active_waves.clear()
	Coin.active_coins.clear()
	Coin.current_combo = 0


func _load_floor(index: int) -> Dictionary:
	var path := FLOORS_DIR + ("floor%d.json" % index)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _build_room(rd: Dictionary) -> void:
	var name: String = str(rd.get("name", "Комната"))
	var size: Array = rd.get("size", [18, 18])
	var doors: Array[String] = []
	for d in rd.get("doors", []):
		doors.append(str(d))
	var pos: Array = rd.get("pos", [0, 0])
	var center := Vector3(float(pos[0]), 0, float(pos[1]))

	var room := RoomFactory.room(name, Vector2(float(size[0]), float(size[1])), doors, rooms_root, center)

	# триггер: скрипт назначается ДО входа в дерево, иначе _ready не вызовется
	var trigger := Area3D.new()
	trigger.set_script(load("res://scripts/level/room_trigger.gd"))
	trigger.name = "RoomTrigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 2
	trigger.monitorable = false
	trigger.room_name = name
	trigger.wave_group = str(rd.get("wave", ""))
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(size[0]), 3.4, float(size[1]))
	col.shape = shape
	col.position = Vector3(0, 1.7, 0)
	trigger.add_child(col)
	trigger.set_meta("room_size", Vector2(float(size[0]), float(size[1])))
	trigger.set_meta("room_center", center)
	room.add_child(trigger)

	# реквизит
	for prop in rd.get("props", []):
		_place_prop(str(prop), room, rd)

	# точка выхода / дверь-рисунок
	if bool(rd.get("exit", false)):
		_mark_exit(room)

	room_spawned.emit(room)


func _place_prop(kind: String, room: Node3D, rd: Dictionary) -> void:
	var host := room.get_node("WhiteLayer")
	var size: Array = rd.get("size", [18, 18])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float(size[0]) * 13.0 + float(size[1]) * 7.0 + kind.length())
	var p := Vector3(rng.randf_range(-size[0] * 0.3, size[0] * 0.3), 0, rng.randf_range(-size[1] * 0.3, size[1] * 0.3))
	match kind:
		"bed":           RoomFactory.hospital_bed(p, host)
		"iv_stand":      RoomFactory.iv_stand(p, host)
		"blue_lamp":     RoomFactory.blue_lamp(p + Vector3(0, 1.2, 0), host)
		"chair":         RoomFactory.restraint_chair(p, host)
		"cabinet":       RoomFactory.cabinet(p, host, rng.randf_range(0, PI), false)
		"furnace":       RoomFactory.furnace(p, host)
		"morgue":        RoomFactory.morgue_drawer(p, host, rng.randf() > 0.5)
		"chalk_door":
			var d := RoomFactory.chalk_door(Vector3(0, 0, -float(size[1]) * 0.5 + 0.14), host)
			d.set_meta("convo", "floor0_chalk_door")
		"desk":          RoomFactory.reception_desk(p, host)
		"growth_marks":  RoomFactory.growth_marks(Vector3(-float(size[0]) * 0.5 + 0.12, 0, 0), host, PI * 0.5)
		"drawing":       RoomFactory.child_drawing(Vector3(float(size[0]) * 0.5 - 0.12, 1.4, 0), host, -PI * 0.5)


func _mark_exit(room: Node3D) -> void:
	# шахта лифта в дальней стене: только вниз
	var white := room.get_node("WhiteLayer")
	var lift := Node3D.new()
	lift.name = "Elevator"
	lift.position = Vector3(0, 0, 0)
	white.add_child(lift)
	var shaft := MeshInstance3D.new()
	shaft.mesh = _box(Vector3(2.4, 3.0, 2.0))
	shaft.material_override = FxFactory.mat(Color(0.30, 0.33, 0.32), {"metallic": 0.6, "roughness": 0.5})
	shaft.position = Vector3(0, 1.5, 0)
	lift.add_child(shaft)
	var sign := MeshInstance3D.new()
	sign.mesh = _box(Vector3(1.6, 0.34, 0.06))
	sign.material_override = FxFactory.mat(Color(0.85, 0.20, 0.18), {"emission": true, "emission_color": Color(0.9, 0.22, 0.2), "emission_energy": 1.6})
	sign.position = Vector3(0, 3.2, 0.3)
	lift.add_child(sign)
	var zone := Area3D.new()
	zone.name = "InteractZone"
	zone.add_to_group("interactable")
	zone.add_to_group("elevator")
	zone.set_meta("prompt", "ЛИФТ ИДЁТ ТОЛЬКО ВНИЗ [E]")
	zone.set_meta("convo", "floor_elevator")
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 2.4
	col.shape = sh
	col.position = Vector3(0, 1.2, 0)
	zone.add_child(col)
	lift.add_child(zone)


func _spawn_player() -> void:
	var start: Array = data.get("player_start", [0, 0])
	if player == null:
		player = Player.new()
		player.name = "Player"
		add_child(player)
	player.global_position = Vector3(float(start[0]), 0.1, float(start[1]))
	player.velocity = Vector3.ZERO
	GameState.reset_vitals()


func _spawn_camera() -> void:
	if camera == null:
		camera = IsaacCamera.new()
		camera.name = "IsaacCamera"
		camera.add_to_group("isaac_camera")
		add_child(camera)
	if camera.target == null:
		camera.target = player
	var center := player.global_position
	camera.enter_room("start", center, Vector2(14, 14), false)
	camera.global_position = center + Vector3(0, 8.2, 7.4)


func _connect_triggers() -> void:
	for t in get_tree().get_nodes_in_group("room_trigger"):
		if not t.is_connected("room_cleared", _on_room_cleared):
			t.room_cleared.connect(_on_room_cleared)


func _place_elevator() -> void:
	pass


# ============================================================ ВОЛНЫ

## Возвращает число врагов волны — его ждёт RoomTrigger.
func start_waves(group: String, trigger: RoomTrigger) -> int:
	var waves: Dictionary = data.get("waves", {})
	var list: Array = waves.get(group, [])
	if list.is_empty():
		return 0
	var room_center: Vector3 = trigger.global_position
	if trigger.get_parent() != null:
		room_center = (trigger.get_parent() as Node3D).global_position
	var room_size: Vector2 = trigger.get_meta("room_size", Vector2(16, 16))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(room_center.x * 31.0 + room_center.z * 17.0 + group.length())
	var total := 0
	var delay := 0.0
	for wave in list:
		if typeof(wave) != TYPE_DICTIONARY:
			continue
		for kind in wave.keys():
			var count := int(wave[kind])
			for i in count:
				var at := room_center + Vector3(
					rng.randf_range(-room_size.x * 0.34, room_size.x * 0.34),
					0.0,
					rng.randf_range(-room_size.y * 0.34, room_size.y * 0.34)
				)
				if player != null and at.distance_to(player.global_position) < 4.5:
					at += (at - player.global_position).normalized() * 4.5
				var spawn_delay := delay
				if spawn_delay <= 0.0:
					var e := EnemyTypes.spawn(str(kind), at, enemies_root)
					_link_enemy(e, trigger)
				else:
					var captured_kind := str(kind)
					var captured_at := at
					get_tree().create_timer(spawn_delay).timeout.connect(
						func() -> void:
							if is_instance_valid(trigger):
								var e2 := EnemyTypes.spawn(captured_kind, captured_at, enemies_root)
								_link_enemy(e2, trigger)
					)
				total += 1
		delay += 1.6
	wave_started.emit(group, total)
	_active_waves[trigger] = total

	# сюжетные вставки перед боссом
	if group == "f1_boss" and not GameState.has_flag("босс1_представлен"):
		GameState.set_flag("босс1_представлен")
		Dialogue.start("floor1_boss_intro")
	return total


func _link_enemy(e: Enemy, trigger: RoomTrigger) -> void:
	e.died.connect(func(_e: Enemy) -> void:
		if is_instance_valid(trigger):
			trigger.on_enemy_died())


# ============================================================ ФАНТОМЫ

func _spawn_phantom() -> void:
	if player == null:
		return
	var around := player.global_position + Vector3(randf_range(-9, 9), 0, randf_range(-9, 9))
	var e := EnemyTypes.spawn("phantom", around, enemies_root)
	phantom_spawned.emit(1)
	Audio.play("chalk", -8.0, 0.6)


# ============================================================ КОНЦОВКИ ЭТАЖА

func _on_room_cleared(room_name: String) -> void:
	if player != null and player.damage_taken_this_floor() == 0.0:
		Style.award("no_damage_floor")
	if player != null and player.floor_time() < 150.0:
		Style.award("speed_floor")
	# после босса приёмного отделения приходит Лида
	if floor_index == 1 and room_name == "Выписка" and not GameState.has_flag("босс1_послесловие"):
		GameState.set_flag("босс1_послесловие")
		Dialogue.start("floor1_boss_done")
		return
	# случайная реплика Голосов после зачистки
	if randf() < 0.35 and not Dialogue.active:
		Dialogue.start_pool("voices_pool")


func _on_dialogue_ended(convo_id: String) -> void:
	if convo_id == "floor_elevator":
		_descend()


func _descend() -> void:
	GameState.clear_floor(floor_index)
	floor_cleared.emit(floor_index)
	SaveSystem.save_game()
	var next := floor_index + 1
	if FileAccess.file_exists(FLOORS_DIR + ("floor%d.json" % next)):
		start_floor(next)
	else:
		# вертикальный срез заканчивается: стена с надписью
		Dialogue.start("vertical_slice_end")


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
