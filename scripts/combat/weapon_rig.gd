class_name WeaponRig
extends Node3D
## Оружие Веры. Всё собрано из больничного мусора.
##   1 «ПЕРЧАТКА»      — забинтованный кулак + скальпель: ближний бой, парирование, взрыв
##   2 «КАПЕЛЬНИЦА»    — штатив капельницы + шприц-барабан: револьвер, бьёт по монетам
##   3 «ДЕФИБРИЛЛЯТОР» — две пластины ЭКГ на палке: дробовик + цепь на 3 врагов
##   4 «ЛОБОТОМ»       — хирургическая пила с мотором от кресла: +200% крови
##   А «ЖАР»           — горелка Бунзена: поджигание, DoT
##
## Прокачка — не уровни, а «ПРОЦЕДУРЫ»: модификации открываются только
## сюжетными выборами («согласиться на операцию»).

signal weapon_fired(slot: int)
signal weapon_switched(slot: int)
signal hit_enemy(enemy: Node, damage: float, headshot: bool)
signal enemy_killed_by_weapon(enemy: Node, slot: int)
signal ammo_changed(slot: int, ammo: int, reserve: int)
signal coin_shoot(multiplier: int)

const WEAPONS := {
	1: {
		"id": "glove", "name": "ПЕРЧАТКА", "kind": "melee",
		"damage": 26.0, "range": 2.35, "cooldown": 0.28, "arc_deg": 78.0,
		"ammo": -1, "reserve": -1, "reload": 0.0, "explode": true,
		"sfx": "hit_light", "desc": "Кулак со скальпелем в ладони. ПКМ — парирование.",
	},
	2: {
		"id": "iv", "name": "КАПЕЛЬНИЦА", "kind": "hitscan",
		"damage": 21.0, "range": 60.0, "cooldown": 0.34, "spread": 0.006,
		"ammo": 6, "reserve": 30, "reload": 1.25, "pierce": 0, "headshot_mult": 2.2,
		"sfx": "shoot", "hits_coin": true,
		"desc": "Шприц-барабан на штативе. Шесть игл. Бьёт по монетам.",
	},
	3: {
		"id": "defib", "name": "ДЕФИБРИЛЛЯТОР", "kind": "shotgun",
		"damage": 13.0, "pellets": 9, "range": 22.0, "cooldown": 0.85, "spread": 0.13,
		"ammo": 2, "reserve": 12, "reload": 1.9, "chain": 3, "chain_damage": 16.0,
		"sfx": "shotgun", "desc": "Две пластины ЭКГ. Бьёт током по цепи из трёх тел.",
	},
	4: {
		"id": "lobotome", "name": "ЛОБОТОМ", "kind": "saw",
		"damage": 9.0, "range": 2.6, "cooldown": 0.075, "arc_deg": 105.0,
		"ammo": -1, "reserve": -1, "reload": 0.0, "blood_mult": 3.0,
		"sfx": "saw", "desc": "Пила с мотором от кресла. Режет на куски. +200% крови.",
	},
	5: {
		"id": "fever", "name": "ЖАР", "kind": "flame",
		"damage": 4.5, "range": 11.0, "cooldown": 0.055, "spread": 0.20,
		"ammo": 100, "reserve": 200, "reload": 2.4, "ignite": true,
		"sfx": "saw", "desc": "Горелка Бунзена. Враги бегут от огня.",
	},
}

var slot: int = 1
var ammo: Dictionary = {}
var reserve: Dictionary = {}
var reloading: bool = false
var _reload_timer := 0.0
var _cooldown := 0.0
var _saw_held := false
var _owner_body: CharacterBody3D
var _aim_origin: Node3D
var _models: Dictionary = {}
var _muzzle: Node3D
var _tracer_pool: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("weapon_rig")
	_owner_body = get_parent() as CharacterBody3D
	_aim_origin = Node3D.new()
	_aim_origin.name = "AimOrigin"
	_aim_origin.position = Vector3(0.22, 1.18, 0.18)
	add_child(_aim_origin)
	_muzzle = Node3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0, 0, 0.30)
	_aim_origin.add_child(_muzzle)

	for key in WEAPONS.keys():
		var w: Dictionary = WEAPONS[key]
		ammo[key] = int(w.get("ammo", -1))
		reserve[key] = int(w.get("reserve", -1))
		_models[key] = _build_model(key)
		_models[key].visible = (key == slot)
		_aim_origin.add_child(_models[key])

	_build_tracers()


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	if reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()
	if _saw_held and current().get("kind", "") == "saw":
		_fire_once()


# ============================================================ API

func current() -> Dictionary:
	return WEAPONS.get(slot, WEAPONS[1])


func current_name() -> String:
	return str(current().get("name", "—"))


func equip(new_slot: int) -> bool:
	if not GameState.weapons_unlocked.has(new_slot) or new_slot == slot:
		return false
	slot = new_slot
	reloading = false
	_saw_held = false
	for key in _models.keys():
		_models[key].visible = (key == slot)
	weapon_switched.emit(slot)
	Audio.play("ui", -6.0, 0.7 + slot * 0.06)
	GameState.current_weapon = slot
	return true


func cycle(dir: int = 1) -> void:
	var list: Array = GameState.weapons_unlocked.duplicate()
	list.sort()
	if list.is_empty():
		return
	var i := list.find(slot)
	i = (i + dir) % list.size()
	equip(int(list[i]))


func start_reload() -> void:
	if reloading:
		return
	var w := current()
	var max_ammo := int(w.get("ammo", -1))
	if max_ammo < 0 or int(ammo[slot]) >= max_ammo:
		return
	if int(reserve[slot]) <= 0:
		return
	reloading = true
	_reload_timer = float(w.get("reload", 1.2))
	Audio.play("ui", -8.0, 0.55)


func _finish_reload() -> void:
	var w := current()
	var max_ammo := int(w.get("ammo", -1))
	var need: int = max_ammo - int(ammo[slot])
	var take: int = mini(need, int(reserve[slot]))
	ammo[slot] = int(ammo[slot]) + take
	reserve[slot] = int(reserve[slot]) - take
	reloading = false
	ammo_changed.emit(slot, int(ammo[slot]), int(reserve[slot]))
	Audio.play("coin", -16.0, 0.5)


func primary_pressed() -> void:
	if current().get("kind", "") == "saw":
		_saw_held = true
	_fire_once()


func primary_released() -> void:
	_saw_held = false
	if current().get("kind", "") == "flame":
		GameState.set_flag("жар_активен", false)


func toss_coin() -> void:
	if _owner_body == null:
		return
	Coin.toss(_owner_body.global_position, _owner_body.global_basis.z * -1.0)


# ============================================================ ВЫСТРЕЛ

func _fire_once() -> bool:
	if _cooldown > 0.0 or reloading:
		return false
	var w := current()
	if not _consume_ammo(w):
		return false
	_cooldown = float(w.get("cooldown", 0.3))
	weapon_fired.emit(slot)
	Audio.play(str(w.get("sfx", "shoot")), -2.0, randf_range(0.96, 1.06))
	_muzzle_flash()

	match str(w.get("kind", "")):
		"melee":   _do_melee(w)
		"saw":     _do_melee(w)
		"hitscan": _do_hitscan(w)
		"shotgun": _do_shotgun(w)
		"flame":   _do_flame(w)
	ammo_changed.emit(slot, int(ammo[slot]), int(reserve[slot]))
	return true


func _consume_ammo(w: Dictionary) -> bool:
	var max_ammo := int(w.get("ammo", -1))
	if max_ammo < 0:
		return true
	if int(ammo[slot]) <= 0:
		start_reload()
		Audio.play("ui", -10.0, 0.4)
		return false
	ammo[slot] = int(ammo[slot]) - 1
	return true


func _aim_ray() -> Dictionary:
	var from := _muzzle.global_position
	var cam := get_viewport().get_camera_3d()
	var dir := Vector3.FORWARD
	if cam != null:
		# прицел — центр экрана (камера наклонена, как в Isaac)
		var center := get_viewport().get_visible_rect().size * 0.5
		var p_from := cam.project_ray_origin(center)
		var p_dir := cam.project_ray_normal(center)
		from = p_from
		dir = p_dir
	else:
		dir = -_aim_origin.global_basis.z
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0)
	q.collision_mask = 5
	if _owner_body != null:
		q.exclude = [_owner_body.get_rid()]
	var hit := space.intersect_ray(q)
	return {"from": from, "dir": dir, "hit": hit}


func _do_hitscan(w: Dictionary) -> void:
	var r := _aim_ray()
	var spread := float(w.get("spread", 0.0))
	var dir: Vector3 = r["dir"]
	if spread > 0.0:
		dir = (dir + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))).normalized()
	var end: Vector3 = r["from"] + dir * float(w.get("range", 60.0))
	if not r["hit"].is_empty():
		end = r["hit"]["position"]

	# монеты в воздухе перехватывают пулю
	if bool(w.get("hits_coin", false)):
		var coin := _nearest_airborne_coin(r["from"], dir, float(w.get("range", 60.0)))
		if coin != null:
			var target := _nearest_enemy(coin.global_position, 45.0)
			coin.shoot_at(target, float(w["damage"]))
			coin_shoot.emit(Coin.current_combo)
			_spawn_tracer(r["from"], coin.global_position, Color(1.0, 0.86, 0.4))
			return

	var target_node: Node = null
	var point := end
	var headshot := false
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(r["from"], end)
	q.collision_mask = 1 | 4
	if _owner_body != null:
		q.exclude = [_owner_body.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		point = hit["position"]
		target_node = hit.get("collider")
		headshot = _is_headshot(target_node, point)

	_spawn_tracer(r["from"], point, Color(0.85, 0.93, 0.98))
	_apply_damage(target_node, float(w["damage"]), dir, point, headshot, float(w.get("headshot_mult", 2.0)), 0)


func _do_shotgun(w: Dictionary) -> void:
	var r := _aim_ray()
	var pellets := int(w.get("pellets", 8))
	var spread := float(w.get("spread", 0.12))
	var hit_enemies: Dictionary = {}
	for i in pellets:
		var dir: Vector3 = (r["dir"] + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))).normalized()
		var end: Vector3 = r["from"] + dir * float(w.get("range", 20.0))
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(r["from"], end)
		q.collision_mask = 5
		if _owner_body != null:
			q.exclude = [_owner_body.get_rid()]
		var hit := space.intersect_ray(q)
		var point := end
		if not hit.is_empty():
			point = hit["position"]
			var t: Node = hit.get("collider")
			if t != null:
				var dmg := float(w["damage"]) * (randf_range(0.9, 1.15))
				_apply_damage(t, dmg, dir, point, _is_headshot(t, point), 2.0, 0)
				if t.is_in_group("enemies"):
					hit_enemies[t] = point
		_spawn_tracer(r["from"], point, Color(0.75, 0.95, 1.0), 0.05)

	# цепь молнии: «ДЕФИБРИЛЛЯТОР» перескакивает на 3 ближайших врага
	var chain_left := int(w.get("chain", 0))
	if chain_left > 0 and hit_enemies.size() > 0:
		var from_node: Node = hit_enemies.keys()[0]
		var from_pos: Vector3 = (from_node as Node3D).global_position + Vector3.UP
		for c in chain_left:
			var next := _nearest_enemy_excluding(from_pos, 8.0, hit_enemies.keys())
			if next == null:
				break
			var npos := next.global_position + Vector3.UP
			_spawn_arc(from_pos, npos)
			_apply_damage(next, float(w.get("chain_damage", 15.0)), (npos - from_pos).normalized(), npos, false, 1.0, 0)
			hit_enemies[next] = npos
			from_pos = npos
			Audio.play("shoot", -6.0, 1.5 + c * 0.1)

	if _owner_body != null:
		_owner_body.velocity -= r["dir"] * 2.4      # отдача толкает назад — можно «прыгать» выстрелом


func _do_melee(w: Dictionary) -> void:
	var origin := _aim_origin.global_position
	var forward := -_aim_origin.global_basis.z
	if _owner_body != null:
		forward = -_owner_body.global_basis.z
	var range_m := float(w.get("range", 2.3))
	var half_arc := deg_to_rad(float(w.get("arc_deg", 80.0)) * 0.5)
	var blood_mult := float(w.get("blood_mult", 1.0))
	var explode := bool(w.get("explode", false))
	var hits := 0

	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var e := n as Node3D
		if "is_dead" in e and bool(e.is_dead):
			continue
		var to := e.global_position - origin
		var dist := to.length()
		if dist > range_m:
			continue
		if forward.dot(to.normalized()) < cos(half_arc):
			continue
		hits += 1
		if "bleed_multiplier" in e:
			e.bleed_multiplier = blood_mult
		else:
			e.set("bleed_multiplier", blood_mult)
		_apply_damage(e, float(w["damage"]) * Style.damage_multiplier(), to.normalized(), e.global_position, false, 1.0, 0)
		if explode and "explode_on_melee" in e:
			e.explode_on_melee()
			Style.award("punch_explode")
		elif "take_knockback" in e:
			e.take_knockback(to.normalized() * 6.0)
		Audio.play("hit_heavy", -6.0, randf_range(0.9, 1.15))

	# удар сбивает вражеские снаряды вблизи (не только ПКМ-парирование)
	for p in get_tree().get_nodes_in_group("projectile"):
		if not is_instance_valid(p) or not (p is Projectile):
			continue
		var pr := p as Projectile
		if pr.from_player or not pr.parryable:
			continue
		if pr.global_position.distance_to(origin) <= range_m:
			pr.do_parry(_owner_body, _nearest_enemy(pr.global_position, 12.0))
			Style.award("projectile_boost")
			hits += 1

	if hits == 0:
		Audio.play("hit_light", -14.0, 0.8)
	_swing_arm()


func _do_flame(w: Dictionary) -> void:
	GameState.set_flag("жар_активен", true)
	var origin := _aim_origin.global_position
	var forward := -_owner_body.global_basis.z
	var range_m := float(w.get("range", 11.0))
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var e := n as Node3D
		var to := e.global_position + Vector3.UP - origin
		if to.length() > range_m:
			continue
		if forward.dot(to.normalized()) < cos(deg_to_rad(26.0)):
			continue
		_apply_damage(e, float(w["damage"]), to.normalized(), e.global_position, false, 1.0, 0)
		if bool(w.get("ignite", false)) and "ignite" in e:
			e.ignite(4.0, 6.0)
	_spawn_flame_puff(origin + forward * 1.4)


# ============================================================ УРОН

func _apply_damage(target: Node, damage: float, dir: Vector3, point: Vector3, headshot: bool, head_mult: float, _unused: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var dmg := damage
	if headshot:
		dmg *= head_mult
		Style.award("headshot")
	if not target.is_in_group("enemies"):
		if "take_hit" in target:
			target.take_hit(dmg, dir, point, true)
		return
	hit_enemy.emit(target, dmg, headshot)
	if "take_hit" in target:
		target.take_hit(dmg, dir, point, true)
		if "is_dead" in target and bool(target.is_dead):
			enemy_killed_by_weapon.emit(target, slot)


func _is_headshot(target: Node, point: Vector3) -> bool:
	if target == null or not (target is Node3D):
		return false
	var head := (target as Node3D).get_node_or_null("Head")
	if head == null:
		head = (target as Node3D).find_child("Head", true, false)
	if head == null or not (head is Node3D):
		return false
	return point.distance_to((head as Node3D).global_position) < 0.42


# ============================================================ ПОИСК ЦЕЛЕЙ

func _nearest_enemy(from: Vector3, max_dist: float) -> Node3D:
	return _nearest_enemy_excluding(from, max_dist, [])


func _nearest_enemy_excluding(from: Vector3, max_dist: float, exclude: Array) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n) or not (n is Node3D) or exclude.has(n):
			continue
		if "is_dead" in n and bool(n.is_dead):
			continue
		var d: float = (n as Node3D).global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = n as Node3D
	return best


func _nearest_airborne_coin(from: Vector3, dir: Vector3, max_dist: float) -> Coin:
	var best: Coin = null
	var best_score := 1e9
	for c in Coin.active_coins:
		if not is_instance_valid(c) or c.shot:
			continue
		var to: Vector3 = c.global_position - from
		var dist := to.length()
		if dist > max_dist:
			continue
		var align := dir.dot(to.normalized())
		if align < 0.965:
			continue
		var score := dist * (2.0 - align)
		if score < best_score:
			best_score = score
			best = c
	return best


# ============================================================ ВИЗУАЛ

func _muzzle_flash() -> void:
	var l := _aim_origin.get_node_or_null("MuzzleFlash") as OmniLight3D
	if l == null:
		l = OmniLight3D.new()
		l.name = "MuzzleFlash"
		l.omni_range = 3.0
		_aim_origin.add_child(l)
	l.light_color = Color(1.0, 0.9, 0.6)
	l.light_energy = 3.4
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.10)


func _swing_arm() -> void:
	var hand := _owner_body.find_child("ArmR", true, false)
	if hand == null:
		return
	var tw := hand.create_tween()
	tw.tween_property(hand, "rotation:x", deg_to_rad(-85.0), 0.07)
	tw.tween_property(hand, "rotation:x", 0.0, 0.16)


func _spawn_tracer(from: Vector3, to: Vector3, color: Color, life: float = 0.07) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var mi: MeshInstance3D
	if _tracer_pool.size() > 0:
		mi = _tracer_pool.pop_back()
	else:
		mi = MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(to - from)
	im.surface_end()
	mi.mesh = im
	var m := FxFactory.mat(color, {"unshaded": true, "transparent": true})
	m.albedo_color.a = 0.9
	mi.material_override = m
	if mi.get_parent() == null:
		host.add_child(mi)
	mi.global_position = from
	mi.visible = true
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, life)
	tw.tween_callback(func() -> void: mi.visible = false; _tracer_pool.append(mi))


func _spawn_arc(from: Vector3, to: Vector3) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var steps := 9
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := from.lerp(to, t)
		if i > 0 and i < steps:
			p += Vector3(randf_range(-0.22, 0.22), randf_range(-0.22, 0.22), randf_range(-0.22, 0.22))
		im.surface_add_vertex(p - from)
	im.surface_end()
	mi.mesh = im
	var m := FxFactory.mat(Color(0.65, 0.95, 1.0), {"unshaded": true, "transparent": true})
	m.albedo_color.a = 1.0
	mi.material_override = m
	host.add_child(mi)
	mi.global_position = from
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.22)
	tw.tween_callback(mi.queue_free)


func _spawn_flame_puff(at: Vector3) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.22
	s.height = 0.44
	s.radial_segments = 6
	s.rings = 4
	mi.mesh = s
	var m := FxFactory.mat(Color(1.0, 0.55, 0.15), {"unshaded": true, "transparent": true})
	m.albedo_color.a = 0.65
	mi.material_override = m
	host.add_child(mi)
	mi.global_position = at
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 2.2, 0.18)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.18)
	tw.chain().tween_callback(mi.queue_free)


func _build_tracers() -> void:
	for i in 6:
		_tracer_pool.append(MeshInstance3D.new())


## Модели оружия из мусора.
func _build_model(key: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Weapon%d" % key
	var steel := FxFactory.mat(Color(0.78, 0.81, 0.83), {"metallic": 0.9, "roughness": 0.22})
	var plastic := FxFactory.mat(Color(0.35, 0.40, 0.42), {"roughness": 0.7})
	match key:
		1:
			var blade := MeshInstance3D.new()
			blade.mesh = _box(Vector3(0.02, 0.02, 0.26))
			blade.material_override = steel
			blade.position = Vector3(0, 0, 0.14)
			root.add_child(blade)
		2:
			var barrel := MeshInstance3D.new()
			barrel.mesh = _box(Vector3(0.05, 0.05, 0.62))
			barrel.material_override = steel
			barrel.position = Vector3(0, 0.02, 0.30)
			root.add_child(barrel)
			var drum := MeshInstance3D.new()
			drum.mesh = _cyl(0.10, 0.16)
			drum.material_override = plastic
			drum.rotation.x = PI * 0.5
			drum.position = Vector3(0, -0.03, 0.06)
			root.add_child(drum)
			for i in 6:
				var syringe := MeshInstance3D.new()
				syringe.mesh = _cyl(0.022, 0.14)
				syringe.material_override = FxFactory.mat(Color(0.86, 0.90, 0.88), {"transparent": true})
				syringe.rotation.x = PI * 0.5
				var a := float(i) / 6.0 * TAU
				syringe.position = Vector3(cos(a) * 0.07, -0.03 + sin(a) * 0.07, 0.06)
				root.add_child(syringe)
		3:
			var pole := MeshInstance3D.new()
			pole.mesh = _box(Vector3(0.045, 0.045, 0.7))
			pole.material_override = plastic
			pole.position = Vector3(0, 0, 0.32)
			root.add_child(pole)
			for side in [-1.0, 1.0]:
				var pad := MeshInstance3D.new()
				pad.mesh = _cyl(0.075, 0.05)
				pad.material_override = FxFactory.mat(Color(0.85, 0.20, 0.18), {"emission": true, "emission_color": Color(0.9, 0.3, 0.2), "emission_energy": 0.8})
				pad.rotation.z = PI * 0.5
				pad.position = Vector3(side * 0.11, 0.02, 0.66)
				root.add_child(pad)
		4:
			var body := MeshInstance3D.new()
			body.mesh = _box(Vector3(0.12, 0.16, 0.36))
			body.material_override = plastic
			body.position = Vector3(0, 0, 0.10)
			root.add_child(body)
			var saw := MeshInstance3D.new()
			saw.name = "SawBlade"
			var c := CylinderMesh.new()
			c.top_radius = 0.22
			c.bottom_radius = 0.22
			c.height = 0.02
			c.radial_segments = 18
			saw.mesh = c
			saw.material_override = FxFactory.mat(Color(0.86, 0.88, 0.90), {"metallic": 1.0, "roughness": 0.15})
			saw.rotation.z = PI * 0.5
			saw.position = Vector3(0, 0.10, 0.40)
			root.add_child(saw)
		5:
			var burner := MeshInstance3D.new()
			burner.mesh = _cyl(0.035, 0.4)
			burner.material_override = steel
			burner.rotation.x = PI * 0.5
			burner.position = Vector3(0, 0, 0.20)
			root.add_child(burner)
			var hose := MeshInstance3D.new()
			hose.mesh = _box(Vector3(0.03, 0.03, 0.5))
			hose.material_override = FxFactory.mat(Color(0.22, 0.24, 0.22))
			hose.position = Vector3(0.03, -0.06, -0.12)
			root.add_child(hose)
	return root


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	return c


func ammo_text() -> String:
	var w := current()
	if int(w.get("ammo", -1)) < 0:
		return "∞"
	return "%d / %d" % [int(ammo[slot]), int(reserve[slot])]
