class_name Enemy
extends CharacterBody3D
## Базовый враг. Все враги «ОТДЕЛЕНИЯ» — искажённые взрослые: врачи, санитары,
## учителя, родители, государство. У каждого ровно одна «грязная» механика,
## которую можно обернуть против него.
##
## Контракт, которого ждут WeaponRig / ParryZone / BloodSystem:
##   blood_value:int · bleed_multiplier:float · is_dead:bool · melee_active:bool
##   take_hit(dmg, dir, point, from_player) · stagger(t) · take_knockback(v)
##   ignite(dur, dps) · explode_on_melee() · flee_from(pos, t)

signal died(enemy: Enemy)
signal damaged(enemy: Enemy, amount: float)
signal staggered(enemy: Enemy, duration: float)
signal ignited(enemy: Enemy)

enum AI { IDLE, ALERT, CHASE, ATTACK, STRAFE, STAGGER, FLEE, DEAD }

@export var enemy_id: String = "sedoy"
@export var max_health: float = 40.0
@export var blood_value: int = 4
@export var move_speed: float = 3.4
@export var touch_damage: float = 9.0
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.2
@export var sight_range: float = 22.0
@export var style_on_kill: String = "melee_kill"
@export var unkillable: bool = false
@export var character_id: String = ""

var health: float = 40.0
var is_dead: bool = false
var melee_active: bool = false
var bleed_multiplier: float = 1.0
var ai: int = AI.IDLE
var stagger_time: float = 0.0
var flee_time: float = 0.0
var flee_from_pos := Vector3.ZERO
var burn_time: float = 0.0
var burn_dps: float = 0.0
var target: Node3D
var home := Vector3.ZERO
var model: Node3D
var _attack_timer := 0.0
var _hit_flash := 0.0
var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _registered_in_camera := false


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	health = max_health
	home = global_position
	if model == null:
		model = CharacterFactory.build(enemy_id, not Reality.is_white())
		model.name = "Model"
		add_child(model)
	_setup_collision()
	_cache_materials(model)
	Reality.layer_changed.connect(_on_layer_changed)
	var cam := _camera()
	if cam and cam.has_method("register_threat"):
		cam.register_threat(self)
		_registered_in_camera = true
	if character_id != "":
		GameState.meet(character_id)


func _setup_collision() -> void:
	if get_node_or_null("Collision") != null:
		return
	var col := CollisionShape3D.new()
	col.name = "Collision"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.6
	col.shape = shape
	col.position = Vector3(0, 0.82, 0)
	add_child(col)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_timers(delta)
	if target == null or not is_instance_valid(target):
		target = _find_player()
	_behave(delta)
	move_and_slide()
	_animate(delta)


func _timers(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer -= delta
	if stagger_time > 0.0:
		stagger_time -= delta
		ai = AI.STAGGER
		if stagger_time <= 0.0:
			ai = AI.CHASE
	if flee_time > 0.0:
		flee_time -= delta
		ai = AI.FLEE
	if burn_time > 0.0:
		burn_time -= delta
		take_hit(burn_dps * delta, Vector3.ZERO, global_position, true, false, false)
		if burn_time <= 0.0 and randf() < 0.3:
			Audio.play("hit_light", -16.0, 0.7)
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)
		_apply_flash()


## Переопределяется подклассами.
func _behave(_delta: float) -> void:
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0
	var dist := to.length()
	if dist > sight_range:
		ai = AI.IDLE
	elif dist > attack_range:
		ai = AI.CHASE
	else:
		ai = AI.ATTACK

	match ai:
		AI.CHASE:
			velocity = _ground_velocity(to.normalized(), move_speed)
			_face(to.normalized(), _delta)
		AI.ATTACK:
			velocity = _ground_velocity(Vector3.ZERO, 0.0)
			_face(to.normalized(), _delta)
			_try_attack(dist)
		AI.STAGGER:
			velocity = velocity.move_toward(Vector3.ZERO, 18.0 * _delta)
		AI.FLEE:
			var away := (global_position - flee_from_pos)
			away.y = 0
			velocity = _ground_velocity(away.normalized(), move_speed * 1.15)
		_:
			velocity = _ground_velocity(Vector3.ZERO, 0.0)


func _ground_velocity(dir: Vector3, speed: float) -> Vector3:
	var v := Vector3(velocity.x, 0, velocity.z).move_toward(dir * speed, 34.0 * get_physics_process_delta_time())
	if not is_on_floor():
		v.y = velocity.y - 26.0 * get_physics_process_delta_time()
	else:
		v.y = -1.0
	return v


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.05:
		return
	var yaw := atan2(dir.x, dir.z)
	var diff := wrapf(yaw - rotation.y + PI, 0.0, TAU) - PI
	rotation.y += diff * clampf(delta * 9.0, 0.0, 1.0)


func _try_attack(_dist: float) -> void:
	if _attack_timer > 0.0 or target == null:
		return
	_attack_timer = attack_cooldown
	_melee_lunge()


func _melee_lunge() -> void:
	if target == null:
		return
	melee_active = true
	add_to_group("melee_threat")
	var dir := (target.global_position - global_position)
	dir.y = 0
	velocity = dir.normalized() * (move_speed * 2.6) + Vector3.UP * 1.2
	Audio.play("hit_light", -10.0, 0.8)
	await get_tree().create_timer(0.22).timeout
	if not is_instance_valid(self):
		return
	if melee_active and target != null and is_instance_valid(target):
		var d: float = target.global_position.distance_to(global_position)
		if d <= attack_range + 0.7 and "take_hit" in target:
			target.take_hit(touch_damage, (target.global_position - global_position).normalized(), target.global_position, false)
	melee_active = false
	remove_from_group("melee_threat")


# ============================================================ УРОН

func take_hit(amount: float, dir: Vector3, _point: Vector3, from_player: bool, count_style: bool = true) -> void:
	if is_dead:
		return
	if unkillable:
		# неубиваемых (МАМА) можно только парировать и отталкивать.
		# убийство МАМЫ блокирует лучшую концовку — игра честно это запомнит.
		take_knockback(dir * 1.6)
		if from_player:
			GameState.add_tag("жестокость", 1)
		return
	health -= amount
	_hit_flash = 1.0
	_apply_flash()
	damaged.emit(self, amount)
	if dir.length() > 0.01:
		take_knockback(dir * minf(6.0, amount * 0.22))
	if from_player and count_style and amount > 0.0:
		Audio.play("hit_light", -12.0, randf_range(0.9, 1.2))
	if health <= 0.0 and not unkillable:
		_die()


func take_knockback(v: Vector3) -> void:
	if is_dead:
		return
	velocity += v


func stagger(duration: float) -> void:
	if is_dead or unkillable:
		return
	stagger_time = maxf(stagger_time, duration)
	ai = AI.STAGGER
	staggered.emit(self, duration)


func ignite(duration: float, dps: float) -> void:
	if is_dead:
		return
	burn_time = maxf(burn_time, duration)
	burn_dps = maxf(burn_dps, dps)
	ignited.emit(self)


func flee_from(pos: Vector3, duration: float) -> void:
	flee_from_pos = pos
	flee_time = maxf(flee_time, duration)
	ai = AI.FLEE


## «ПЕРЧАТКА» взрывает СЕДЫХ в упор.
func explode_on_melee() -> void:
	if is_dead:
		return
	take_hit(max_health * 2.0, Vector3.ZERO, global_position, true, false)
	_spawn_burst(global_position, 1.2)


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	health = 0.0
	ai = AI.DEAD
	melee_active = false
	remove_from_group("melee_threat")
	if _registered_in_camera:
		var cam := _camera()
		if cam and cam.has_method("unregister_threat"):
			cam.unregister_threat(self)
	Audio.play("enemy_die")
	Style.award(style_on_kill)
	Blood.on_enemy_died(self, global_position)
	_spawn_burst(global_position, 0.9)
	died.emit(self)
	_despawn_sequence()


func _despawn_sequence() -> void:
	if model == null:
		queue_free()
		return
	# тело падает и растворяется — в «ОТДЕЛЕНИИ» ничего не остаётся
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "rotation:x", deg_to_rad(78.0), 0.45)
	tw.tween_property(self, "position:y", position.y - 0.2, 0.45)
	tw.chain().tween_interval(0.85)
	tw.chain().tween_callback(_finish_despawn)


func _finish_despawn() -> void:
	collision_layer = 0
	collision_mask = 0
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.55)
	tw.tween_callback(queue_free)


func _spawn_burst(at: Vector3, radius: float) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var color: Color = Reality.color("blood")
	for i in 12:
		var mi := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.07
		s.height = 0.14
		mi.mesh = s
		mi.material_override = FxFactory.mat(color, {"unshaded": true})
		host.add_child(mi)
		mi.global_position = at + Vector3.UP * 0.9
		var dir := Vector3(randf_range(-1, 1), randf_range(0.1, 1.4), randf_range(-1, 1)).normalized()
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "global_position", mi.global_position + dir * radius, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.chain().tween_callback(mi.queue_free)


# ============================================================ ВИЗУАЛ

func _cache_materials(n: Node) -> void:
	if n is MeshInstance3D:
		var m: Material = (n as MeshInstance3D).material_override
		if m is StandardMaterial3D:
			_materials.append(m as StandardMaterial3D)
			_base_colors.append((m as StandardMaterial3D).albedo_color)
	for c in n.get_children():
		_cache_materials(c)


func _apply_flash() -> void:
	for i in _materials.size():
		var m := _materials[i]
		if m.albedo_texture != null:
			continue
		m.albedo_color = _base_colors[i].lerp(Color(1.0, 0.92, 0.92), _hit_flash * 0.8)


func _animate(delta: float) -> void:
	if model == null:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var bob := sin(Time.get_ticks_msec() / 1000.0 * (3.0 + speed)) * 0.04 * clampf(speed / 3.0, 0.0, 1.0)
	model.position.y = bob
	if ai == AI.STAGGER:
		model.rotation.z = sin(Time.get_ticks_msec() / 60.0) * 0.16
	else:
		model.rotation.z = lerpf(model.rotation.z, 0.0, clampf(delta * 6.0, 0.0, 1.0))


func _on_layer_changed(_layer: String) -> void:
	if model:
		model.queue_free()
	model = CharacterFactory.build(enemy_id, not Reality.is_white())
	model.name = "Model"
	add_child(model)
	move_child(model, 0)
	_materials.clear()
	_base_colors.clear()
	_cache_materials(model)


func _find_player() -> Node3D:
	var nodes := get_tree().get_nodes_in_group("player")
	if nodes.size() == 0:
		return null
	var p: Node = nodes[0]
	if "is_dead" in p and bool(p.is_dead):
		return null
	return p as Node3D


func _camera() -> Node:
	var cams := get_tree().get_nodes_in_group("isaac_camera")
	return cams[0] if cams.size() > 0 else null


func _exit_tree() -> void:
	if _registered_in_camera:
		var cam := _camera()
		if cam and cam.has_method("unregister_threat"):
			cam.unregister_threat(self)


func health_ratio() -> float:
	return clampf(health / maxf(1.0, max_health), 0.0, 1.0)
