class_name Projectile
extends Area3D
## Снаряд, который можно ПАРРИРОВАТЬ. Общий для вражеских игл, капсул,
## криков ХОРА и для собственных пуль Веры после отражения.

signal hit_target(target: Node, damage: float)
signal parried(by: Node)

@export var speed: float = 22.0
@export var damage: float = 8.0
@export var fall_gravity: float = 0.0
@export var lifetime: float = 6.0
@export var parryable: bool = true
@export var crit_on_head: bool = true
@export var headshot_multiplier: float = 2.2
@export var from_player: bool = false
@export var pierce: int = 0              # сколько целей пробивает насквозь
@export var chain: int = 0               # «ДЕФИБРИЛЛЯТОР»: перескоки между врагами

var owner_node: Node
var direction := Vector3.FORWARD
var _age := 0.0
var _is_parried := false
var _hits: Array[Node] = []
var _mesh: MeshInstance3D
var _trail: MeshInstance3D


func _ready() -> void:
	collision_layer = 16 if not from_player else 8
	collision_mask = 0 if not from_player else 0
	# коллизии решает ParryZone и ручные сферические запросы, а не физика Area:
	# снаряды должны пролетать сквозь стены визуала, но не сквозь парирование
	monitoring = false
	monitorable = true
	add_to_group("projectile")
	if parryable:
		add_to_group("parryable")
	_build_visual()


func setup(dir: Vector3, spd: float, dmg: float, by_player: bool, owner: Node = null) -> void:
	direction = dir.normalized()
	speed = spd
	damage = dmg
	from_player = by_player
	owner_node = owner
	collision_layer = 8 if by_player else 16
	global_rotation = _look_basis(dir).get_euler()


func launch() -> void:
	_age = 0.0


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		queue_free()
		return
	if fall_gravity > 0.0:
		direction.y -= fall_gravity * delta
		direction = direction.normalized()
	global_position += direction * speed * delta
	if _trail:
		_trail.look_at(global_position + direction, Vector3.UP)


## Вызывается ParryZone / хитбоксом цели.
func impact(target: Node, point: Vector3, is_head: bool = false) -> void:
	if _is_parried:
		return
	if _hits.has(target) and pierce <= 0:
		return
	_hits.append(target)

	var dmg := damage
	if from_player:
		dmg *= Style.damage_multiplier()
	if is_head and crit_on_head:
		dmg *= headshot_multiplier
		Style.award("headshot")

	hit_target.emit(target, dmg)
	if "take_hit" in target:
		target.take_hit(dmg, direction, point, from_player)

	if pierce > 0:
		pierce -= 1
		return
	if chain > 0:
		_do_chain(target)
		return
	_despawn(point)


func _do_chain(from_target: Node) -> void:
	chain -= 1
	var best: Node3D
	var best_d := 5.5
	for n in get_tree().get_nodes_in_group("enemies"):
		if n == from_target or not is_instance_valid(n) or not (n is Node3D):
			continue
		var d: float = (n as Node3D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = (n as Node3D)
	if best == null:
		_despawn(global_position)
		return
	var dir := (best.global_position + Vector3.UP * 1.0 - global_position).normalized()
	setup(dir, speed * 1.05, damage * 0.85, from_player, owner_node)
	Audio.play("shoot", -8.0, 1.35)


## Отражение: снаряд летит обратно в стрелка с ×3 уроном.
func do_parry(by: Node, toward: Node3D = null) -> void:
	if _is_parried or not parryable:
		return
	_is_parried = true
	from_player = true
	owner_node = by
	damage *= 3.0
	speed *= 1.35
	collision_layer = 8
	var dir := -direction
	if toward != null and is_instance_valid(toward):
		dir = (toward.global_position + Vector3.UP * 1.1 - global_position).normalized()
	direction = dir.normalized()
	global_rotation = _look_basis(direction).get_euler()
	_is_parried = false          # теперь это снаряд игрока, его можно парировать обратно
	if _mesh:
		var m := FxFactory.mat(Color(0.95, 0.80, 0.30), {"emission": true, "emission_color": Color(1.0, 0.82, 0.30), "emission_energy": 3.0})
		_mesh.material_override = m
	parried.emit(by)


func _despawn(_point: Vector3) -> void:
	queue_free()


func _look_basis(dir: Vector3) -> Basis:
	var d := dir.normalized()
	if absf(d.y) > 0.999:
		return Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), d)
	return Basis.looking_at(d, Vector3.UP)


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.075
	s.height = 0.15
	s.radial_segments = 6
	s.rings = 4
	_mesh.mesh = s
	var col: Color = Color(0.86, 0.90, 0.92) if not from_player else Color(0.95, 0.80, 0.30)
	var emis: Color = Color(0.7, 0.9, 1.0) if not from_player else Color(1.0, 0.8, 0.3)
	_mesh.material_override = FxFactory.mat(col, {"emission": true, "emission_color": emis, "emission_energy": 2.4})
	add_child(_mesh)

	var l := OmniLight3D.new()
	var lcol: Color = Color(0.7, 0.9, 1.0) if not from_player else Color(1.0, 0.8, 0.3)
	l.light_color = lcol
	l.light_energy = 0.5
	l.omni_range = 1.6
	add_child(l)
