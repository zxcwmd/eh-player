class_name Coin
extends RigidBody3D
## МОНЕТА (Marksman). Вера подбрасывает зубные коронки и монеты из копилки.
## Выстрел по монете в воздухе = рикошет с гарантированным критом в голову
## ближайшего врага. Каждая следующая монета до попадания → «МОНЕТА ×N».
## «МОНЕТА ×4» = +1200 стиля, самая желанная комбинация в игре.

signal combo_changed(count: int)
signal coin_shot(coin: Coin, target: Node3D, multiplier: int)

const LIFETIME := 2.6
const AIR_GRAVITY := 9.0
const TOSS_SPEED := 6.2

static var active_coins: Array[Coin] = []
static var current_combo: int = 0

var shot: bool = false
var _age := 0.0
var _mesh: MeshInstance3D
var _light: OmniLight3D


## Монеты живут в сцене уровня, а не в игроке.
static var _scene_root: Node = null

static func set_scene_root(n: Node) -> void:
	_scene_root = n

static func scene_root() -> Node:
	if _scene_root != null and is_instance_valid(_scene_root):
		return _scene_root
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).current_scene
	return null


static func toss(at: Vector3, forward: Vector3) -> Coin:
	var host := scene_root()
	if host == null:
		return null
	var c := Coin.new()
	c.add_to_group("coin")
	host.add_child(c)
	c.global_position = at + Vector3.UP * 1.05
	c.linear_velocity = forward * 1.4 + Vector3.UP * TOSS_SPEED
	c.angular_velocity = Vector3(6.0, 12.0, 3.0)
	c.register_combo()
	Audio.play("coin", -12.0, 1.4)
	return c


static func reset_combo() -> void:
	if current_combo > 0:
		current_combo = 0


static func airborne_count() -> int:
	var n := 0
	for c in active_coins:
		if is_instance_valid(c) and not c.shot:
			n += 1
	return n


func _ready() -> void:
	gravity_scale = AIR_GRAVITY / 9.8
	continuous_cd = true
	collision_layer = 64
	collision_mask = 1
	_build()


func register_combo() -> void:
	active_coins.append(self)
	current_combo += 1
	combo_changed.emit(current_combo)


func _process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME and not shot:
		_expire()
	if shot and _age > 0.6:
		queue_free()


## Выстрел по монете. Вызывается WeaponRig при хитскане/попадании снаряда.
func shoot_at(target: Node3D, base_damage: float) -> void:
	if shot:
		return
	shot = true
	freeze = true
	var mult := current_combo
	var stamp := "coin_%d" % clampi(mult, 1, 4)
	Style.award(stamp)

	if target != null and is_instance_valid(target):
		var head := Vector3.UP * 1.35
		if target.get_node_or_null("Head") != null:
			head = (target.get_node("Head") as Node3D).global_position - target.global_position
		var p := Projectile.new()
		p.from_player = true
		p.damage = base_damage * 3.0
		p.speed = 60.0
		p.crit_on_head = true
		p.headshot_multiplier = 1.0
		get_tree().current_scene.add_child(p)
		p.global_position = global_position
		p.setup((target.global_position + head - global_position).normalized(), 60.0, base_damage * 3.0, true)
		p.impact(target, target.global_position + head, true)
		p.queue_free()

	coin_shot.emit(self, target, mult)
	Audio.play("coin", -4.0, 0.8 + mult * 0.12)
	Audio.play("parry", -10.0, 1.6)
	_spawn_spark()
	# комбо сбрасывается только когда все монеты израсходованы
	if airborne_count() <= 1:
		current_combo = 0
		combo_changed.emit(0)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.18)
	tw.tween_callback(queue_free)


func _expire() -> void:
	current_combo = maxi(0, current_combo - 1)
	combo_changed.emit(current_combo)
	queue_free()


func _spawn_spark() -> void:
	for i in 8:
		var s := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 0.05
		m.height = 0.1
		s.mesh = m
		s.material_override = FxFactory.mat(Color(1.0, 0.86, 0.35), {"emission": true, "emission_color": Color(1.0, 0.85, 0.3), "emission_energy": 4.0})
		var host := get_tree().current_scene
		if host == null:
			return
		host.add_child(s)
		s.global_position = global_position
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var tw := s.create_tween()
		tw.set_parallel(true)
		tw.tween_property(s, "global_position", s.global_position + dir * 0.9, 0.35)
		tw.tween_property(s, "scale", Vector3(0.05, 0.05, 0.05), 0.35)
		tw.chain().tween_callback(s.queue_free)


func _build() -> void:
	_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.10
	cyl.bottom_radius = 0.10
	cyl.height = 0.022
	_mesh.mesh = cyl
	_mesh.material_override = FxFactory.mat(Color(0.93, 0.82, 0.42), {"metallic": 1.0, "roughness": 0.22, "emission": true, "emission_color": Color(0.9, 0.75, 0.3), "emission_energy": 0.9})
	add_child(_mesh)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.85, 0.4)
	_light.light_energy = 0.6
	_light.omni_range = 1.8
	add_child(_light)


func _exit_tree() -> void:
	active_coins.erase(self)
