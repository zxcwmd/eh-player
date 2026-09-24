class_name ParryZone
extends Node3D
## ПАРРИРОВАНИЕ — центральная механика боя (ULTRAKILL).
## Левая забинтованная рука Веры. Окно парирования 0.22 с — щедрое для 3-го лица,
## потому что камера наклонена и снаряды прилетают «сверху-из-за кадра».
##
## Три результата:
##   1. снаряд отражён обратно в стрелка с ×3 уроном;
##   2. если рядом есть другой враг → снаряд летит В НЕГО, штамп «ПАРАЗИТ» (+150);
##   3. если парирован удар ближнего боя → враг в ступоре 1.4 с, штамп «РУКИ УБРАЛА».

signal parried_projectile(projectile: Projectile, target: Node3D)
signal parried_melee(attacker: Node)
signal parry_whiffed

const WINDOW := 0.22
const RADIUS := 1.85
const BOOST_RADIUS := 9.0          # в этом радиусе ищем «паразита»
const MELEE_STAGGER := 1.4
const COOLDOWN := 0.32

var active: bool = false
var on_cooldown: bool = false
var successful_this_window: bool = false
var total_parries: int = 0
var total_whiffs: int = 0

var _timer := 0.0
var _cooldown := 0.0
var _owner: Node3D
var _ring: MeshInstance3D


func _ready() -> void:
	add_to_group("parry_zone")
	_owner = get_parent() as Node3D
	_build_visual()


func _process(delta: float) -> void:
	if on_cooldown:
		_cooldown -= delta
		if _cooldown <= 0.0:
			on_cooldown = false
	if active:
		_timer -= delta
		_scan()
		if _ring:
			var k: float = clampf(_timer / WINDOW, 0.0, 1.0)
			_ring.scale = Vector3.ONE * (0.7 + (1.0 - k) * 0.9)
			(_ring.material_override as StandardMaterial3D).albedo_color.a = 0.18 + k * 0.45
		if _timer <= 0.0:
			_close()


## Нажатие ПКМ.
func try_parry() -> bool:
	if on_cooldown or active:
		return false
	active = true
	successful_this_window = false
	_timer = WINDOW
	_cooldown = COOLDOWN
	if _ring:
		_ring.visible = true
	Audio.play("dash", -18.0, 2.0)
	return true


func _close() -> void:
	active = false
	if _ring:
		_ring.visible = false
	if not successful_this_window:
		total_whiffs += 1
		parry_whiffed.emit()


func _scan() -> void:
	var origin := global_position
	var space := get_world_3d().direct_space_state

	# --- снаряды
	for p in get_tree().get_nodes_in_group("projectile"):
		if not is_instance_valid(p) or not (p is Projectile):
			continue
		var proj := p as Projectile
		if proj.from_player or not proj.parryable:
			continue
		if proj.global_position.distance_to(origin) > RADIUS:
			continue
		_do_parry_projectile(proj)

	# --- ближний бой врага (помеченный как melee_threat)
	for m in get_tree().get_nodes_in_group("melee_threat"):
		if not is_instance_valid(m) or not (m is Node3D):
			continue
		var threat := m as Node3D
		if threat.global_position.distance_to(origin) > RADIUS + 0.6:
			continue
		if "melee_active" in threat and not bool(threat.melee_active):
			continue
		_do_parry_melee(threat)


func _do_parry_projectile(proj: Projectile) -> void:
	successful_this_window = true
	total_parries += 1

	# ищем «паразита»: ближайшего врага, который НЕ стрелял
	var shooter: Node = proj.owner_node
	var victim := _find_boost_victim(shooter, proj.global_position)

	proj.do_parry(_owner, victim)
	Audio.play("parry")
	Style.award("parry")
	if victim != null:
		Style.award("parry_boost")
	parried_projectile.emit(proj, victim)

	# камера и кровь
	var cam := _camera()
	if cam and cam.has_method("punch_fov"):
		cam.punch_fov(6.0, 0.1)
		cam.shake(0.3)
	_spawn_ring_flash(proj.global_position)


func _do_parry_melee(threat: Node3D) -> void:
	successful_this_window = true
	total_parries += 1
	if "stagger" in threat:
		threat.stagger(MELEE_STAGGER)
	if "melee_active" in threat:
		threat.melee_active = false
	Audio.play("parry", -2.0, 0.7)
	Style.award("parry")
	parried_melee.emit(threat.get_parent() if threat.get_parent() != null else threat)
	var cam := _camera()
	if cam and cam.has_method("punch_fov"):
		cam.punch_fov(8.0, 0.12)
		cam.shake(0.45)
	_spawn_ring_flash(threat.global_position)
	# парированный удар отбрасывает атакующего
	var owner_body := _owner as CharacterBody3D
	if owner_body != null:
		var dir := (threat.global_position - owner_body.global_position).normalized()
		threat.global_position += dir * 0.35


func _find_boost_victim(exclude: Node, from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := BOOST_RADIUS
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		if n == exclude:
			continue
		if "is_dead" in n and bool(n.is_dead):
			continue
		var d: float = (n as Node3D).global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = n as Node3D
	return best


func _camera() -> Node:
	var cams := get_tree().get_nodes_in_group("isaac_camera")
	return cams[0] if cams.size() > 0 else null


func _spawn_ring_flash(at: Vector3) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.42
	t.outer_radius = 0.62
	t.rings = 12
	t.ring_segments = 6
	mi.mesh = t
	var m := FxFactory.mat(Color(1.0, 0.92, 0.55), {"unshaded": true, "transparent": true})
	m.albedo_color.a = 0.85
	mi.material_override = m
	host.add_child(mi)
	mi.global_position = at
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 2.6, 0.24)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.24)
	tw.chain().tween_callback(mi.queue_free)


func _build_visual() -> void:
	_ring = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = RADIUS
	s.height = RADIUS * 2.0
	s.radial_segments = 12
	s.rings = 8
	_ring.mesh = s
	var m := FxFactory.mat(Color(0.95, 0.88, 0.5), {"unshaded": true, "transparent": true})
	m.albedo_color.a = 0.28
	_ring.material_override = m
	_ring.visible = false
	add_child(_ring)


func parry_accuracy() -> float:
	var total := total_parries + total_whiffs
	if total == 0:
		return 0.0
	return float(total_parries) / float(total)
