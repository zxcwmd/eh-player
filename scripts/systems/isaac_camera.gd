class_name IsaacCamera
extends Node3D
## Камера как в The Binding of Isaac, но в 3D и от третьего лица.
##
##   • фиксированный наклон -52°, всегда за спиной Веры;
##   • «комнатный» snap: при входе в новую комнату камера резко переставляется
##     к центру комнаты и только потом переходит в плавное следование;
##   • боевой отъезд: если враг вне кадра — камера отъезжает и поднимается,
##     чтобы угроза НИКОГДА не пряталась за спиной (правило Isaac);
##   • стиль-панч: FOV +6 и тряска на каждое S-событие;
##   • хоррор-кадр: камера ОТПУСКАЕТ игрока и уезжает в угол комнаты,
##     снимая Веру издалека — игрок становится наблюдателем своего ребёнка;
##   • ржавый слой: угол -38°, крен roll ±4°, «дышит».

signal camera_snap(room_name: String)
signal detached(active: bool)

@export var target_path: NodePath
@export var follow_speed: float = 9.0
@export var snap_speed: float = 16.0

## Базовые параметры «Isaac-угла»
const WHITE_PITCH := -52.0
const RUST_PITCH := -38.0
const BASE_DISTANCE := 9.5
const COMBAT_DISTANCE := 13.0
const BASE_FOV := 62.0
const FOLLOW_HEIGHT := 1.05

var target: Node3D
var cam: Camera3D
var _focus := Vector3.ZERO
var _distance := BASE_DISTANCE
var _pitch := WHITE_PITCH
var _roll := 0.0
var _roll_phase := 0.0
var _fov_punch := 0.0
var _shake := 0.0
var _shake_seed := 1.0

## Комнатная логика
var _room_center := Vector3.ZERO
var _room_size := Vector2(18.0, 18.0)
var _snapping := false
var _snap_timer := 0.0
var _room_name := ""

## Боевой отъезд
var _threats: Array[Node3D] = []

## Хоррор-кадр
var _detached := false
var _detach_timer := 0.0
var _detach_point := Vector3.ZERO

## Слои
var _rust := false


func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = BASE_FOV
	cam.current = true
	cam.near = 0.05
	cam.far = 120.0
	add_child(cam)

	if target_path != NodePath():
		target = get_node_or_null(target_path) as Node3D
	if target == null:
		var nodes := get_tree().get_nodes_in_group("player")
		if nodes.size() > 0:
			target = nodes[0] as Node3D
	_focus = global_position

	Style.stamp.connect(_on_style_stamp)
	Style.rank_changed.connect(_on_rank_changed)
	Reality.layer_changed.connect(_on_layer_changed)
	Blood.healed.connect(_on_healed)
	GameState.floor_changed.connect(_on_floor_changed)


func _process(delta: float) -> void:
	_rust = not Reality.is_white()

	# --- цель
	if target == null:
		var nodes := get_tree().get_nodes_in_group("player")
		if nodes.size() > 0:
			target = nodes[0] as Node3D
	if target == null:
		return

	var wanted := _compute_wanted_position(delta)
	var lerp_k := snap_speed if _snapping else follow_speed
	global_position = global_position.lerp(wanted, clampf(lerp_k * delta, 0.0, 1.0))

	# --- ориентация
	var target_pitch := lerpf(_pitch, RUST_PITCH if _rust else WHITE_PITCH, clampf(delta * 3.0, 0.0, 1.0))
	_pitch = target_pitch

	_roll_phase += delta * (0.9 if _rust else 0.35)
	var wanted_roll := 0.0
	if _rust:
		wanted_roll = sin(_roll_phase) * deg_to_rad(4.0)
	wanted_roll += clampf(_shake, 0.0, 1.0) * sin(_roll_phase * 23.0) * deg_to_rad(1.6)
	_roll = lerpf(_roll, wanted_roll, clampf(delta * 8.0, 0.0, 1.0))

	# фиксированный yaw (как в Isaac): вращается только pitch + roll-крен
	rotation = Vector3(deg_to_rad(_pitch), 0.0, _roll)

	# --- FOV / тряска
	_fov_punch = maxf(0.0, _fov_punch - delta * 26.0)
	_shake = maxf(0.0, _shake - delta * 2.4)
	cam.fov = BASE_FOV + _fov_punch + (6.0 if _distance > 11.0 else 0.0)
	if _shake > 0.001:
		var rng := RandomNumberGenerator.new()
		rng.seed = _shake_seed
		_shake_seed += 1.0
		cam.position = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		) * _shake * 0.35
	else:
		cam.position = cam.position.lerp(Vector3.ZERO, clampf(delta * 12.0, 0.0, 1.0))


## Точка, куда камера хочет встать на этом кадре.
func _compute_wanted_position(delta: float) -> Vector3:
	# --- хоррор-кадр: игрок отпущен, камера снимает из угла комнаты
	if _detached:
		_detach_timer -= delta
		if _detach_timer <= 0.0:
			set_detached(false)
		return _detach_point

	var anchor := target.global_position

	_update_threats()
	var wanted_distance := BASE_DISTANCE
	var wanted_pitch := WHITE_PITCH if not _rust else RUST_PITCH
	if _threats.size() > 0:
		var max_off: float = 0.0
		for t in _threats:
			if not is_instance_valid(t):
				continue
			var to_t := (t.global_position - anchor)
			var planar := Vector2(to_t.x, to_t.z)
			max_off = maxf(max_off, planar.length())
		if max_off > 6.5:
			wanted_distance = minf(COMBAT_DISTANCE, BASE_DISTANCE + (max_off - 6.5) * 0.9)
			wanted_pitch = -44.0
	_distance = lerpf(_distance, wanted_distance, clampf(delta * 4.0, 0.0, 1.0))
	_pitch = lerpf(_pitch, wanted_pitch, clampf(delta * 3.0, 0.0, 1.0))

	# комнатный snap: держим кадр в пределах комнаты
	var room_pos := Vector3(_room_center.x, 0.0, _room_center.z)
	var half := Vector3(_room_size.x * 0.5, 0.0, _room_size.y * 0.5)
	var clamped := anchor.clamp(room_pos - half, room_pos + half)
	var planar_focus := Vector3(clamped.x, anchor.y, clamped.z)

	if _snapping:
		_snap_timer -= delta
		if _snap_timer <= 0.0:
			_snapping = false
		planar_focus = Vector3(room_pos.x, anchor.y, room_pos.z)

	var offset := Vector3.ZERO
	offset.y = sin(deg_to_rad(_pitch)) * -_distance
	offset.z = cos(deg_to_rad(_pitch)) * _distance
	return planar_focus + offset


# ============================================================ API

## Вызывается RoomTrigger при входе игрока в комнату.
func enter_room(room_name: String, center: Vector3, size: Vector2, snap := true) -> void:
	_room_name = room_name
	_room_center = center
	_room_size = size
	if snap:
		_snapping = true
		_snap_timer = 0.22
		punch_fov(3.0, 0.15)
		camera_snap.emit(room_name)


## Хоррор-кадр (P4): камера бросает игрока и снимает из угла.
func set_detached(on: bool, seconds := 12.0) -> void:
	_detached = on
	if on:
		_detach_timer = seconds
		var corner := _room_center + Vector3(_room_size.x * 0.42, 3.2, _room_size.y * 0.42)
		_detach_point = corner
		Audio.play("chalk", -14.0)
	detached.emit(on)


func punch_fov(amount := 6.0, _duration := 0.1) -> void:
	_fov_punch = maxf(_fov_punch, amount)


func shake(amount := 0.4) -> void:
	_shake = clampf(maxf(_shake, amount), 0.0, 1.4)


func register_threat(n: Node3D) -> void:
	if not _threats.has(n):
		_threats.append(n)


func unregister_threat(n: Node3D) -> void:
	_threats.erase(n)


func _update_threats() -> void:
	for i in range(_threats.size() - 1, -1, -1):
		if not is_instance_valid(_threats[i]):
			_threats.remove_at(i)


# ============================================================ реакции

func _on_floor_changed(_floor_index: int) -> void:
	punch_fov(4.0, 0.4)
	shake(0.25)


func _on_style_stamp(_text: String, points: int) -> void:
	var amount := clampf(float(points) / 220.0, 0.4, 7.0)
	punch_fov(amount, 0.1)
	shake(amount * 0.09)


func _on_rank_changed(_old: String, new_rank: String) -> void:
	if Style.rank_value(new_rank) >= Style.rank_value("S"):
		punch_fov(8.0, 0.25)
		shake(0.5)


func _on_healed(_amount: float, _from: Node) -> void:
	punch_fov(2.0, 0.08)


func _on_layer_changed(_layer: String) -> void:
	punch_fov(10.0, 0.3)
	shake(0.7)
	_roll_phase = 0.0


func room_name_current() -> String:
	return _room_name
