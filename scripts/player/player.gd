class_name Player
extends CharacterBody3D
## ВЕРА ПРОСКУРИНА. 12 лет. Молчит всю игру.
## Мобильность в духе ULTRAKILL, но в третьем лице и под «Isaac»-камерой:
##   рывок с i-frames · двойной прыжок («истерика») · скольжение · ground slam
##   wall-run + wall-jump · slide-jump · парирование левой рукой · монеты
##
## Правила:
##   • HP не регенерирует. Лечит только кровь врага в радиусе 3.2 м (BloodSystem).
##   • скорость и урон растут от ранга стиля (Style).
##   • после 4-й процедуры Вера «замолкает» окончательно: меняются штампы стиля,
##     анимация становится механической, цвет пижамы — больничным зелёным.

signal jumped(double_jump: bool)
signal dashed(in_air: bool)
signal slammed(impact_position: Vector3)
signal landed(speed: float)
signal hurt(amount: float, from: Node)
signal died
signal revived
signal screamed
signal dash_charge_refreshed

enum State { IDLE, RUN, JUMP, FALL, DASH, AIR_DASH, SLIDE, SLAM, WALL_RUN, HURT, DEAD }

const GRAVITY := 26.0
const BASE_SPEED := 7.2
const ACCEL_GROUND := 62.0
const ACCEL_AIR := 26.0
const FRICTION_GROUND := 12.0
const JUMP_SPEED := 8.9
const DOUBLE_JUMP_SPEED := 8.1
const DASH_SPEED := 21.0
const DASH_TIME := 0.16
const DASH_IFRAMES := 0.10
const DASH_COOLDOWN := 0.30
const SLIDE_TIME := 0.62
const SLIDE_MIN_SPEED := 5.4
const SLIDE_BOOST := 1.35
const SLAM_GRAVITY_MULT := 3.0
const SLAM_WAVE_RADIUS := 4.0
const WALL_RUN_TIME := 0.8
const WALL_JUMP_SPEED := 8.4
const HURT_TIME := 0.22
const IFRAME_AFTER_HURT := 0.42
const SCREAM_RADIUS := 5.5

var state: int = State.IDLE
var prev_state: int = State.IDLE

var can_double_jump := true
var air_dash_charges := 1
var max_air_dash := 1
var dash_charges := 1
var max_dash := 1
var invulnerable := false

## «истерика» — так двойной прыжок называется в штампам стиля
var scream_charge := 1.0

var _dash_timer := 0.0
var _dash_dir := Vector3.FORWARD
var _dash_cd := 0.0
var _slide_timer := 0.0
var _slide_dir := Vector3.FORWARD
var _wall_timer := 0.0
var _wall_normal := Vector3.ZERO
var _hurt_timer := 0.0
var _iframe := 0.0
var _bob := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _run_time := 0.0
var _damage_taken_this_floor := 0.0
var _floor_start_time := 0.0

var model: Node3D
var rig: WeaponRig
var parry_zone: ParryZone
var _collision: CollisionShape3D
var _pijama_materials: Array[StandardMaterial3D] = []
var _blood_overlay: StandardMaterial3D


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4 | 32
	_setup_collision()
	_build_model()
	_build_rig()
	GameState.reset_vitals()
	_floor_start_time = Time.get_ticks_msec() / 1000.0
	Style.reset(true)
	Blood.thirst_warning.connect(_on_thirst)
	Reality.layer_changed.connect(_on_layer_changed)


func _setup_collision() -> void:
	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.45
	_collision.shape = shape
	_collision.position = Vector3(0, 0.75, 0)
	add_child(_collision)


func _build_model() -> void:
	model = CharacterFactory.vera()
	model.name = "Model"
	add_child(model)
	# запоминаем материалы пижамы, чтобы красить их кровью
	_collect_pijama(model)


func _collect_pijama(n: Node) -> void:
	if n is MeshInstance3D:
		var m: Material = (n as MeshInstance3D).material_override
		if m is StandardMaterial3D:
			var col: Color = (m as StandardMaterial3D).albedo_color
			if col.b > col.r and col.g > 0.4:
				_pijama_materials.append(m as StandardMaterial3D)
	for c in n.get_children():
		_collect_pijama(c)


func _build_rig() -> void:
	rig = WeaponRig.new()
	rig.name = "WeaponRig"
	add_child(rig)
	parry_zone = ParryZone.new()
	parry_zone.name = "ParryZone"
	parry_zone.position = Vector3(-0.24, 1.10, 0.35)
	add_child(parry_zone)
	parry_zone.parried_projectile.connect(_on_parried)
	parry_zone.parried_melee.connect(_on_parried_melee)
	rig.enemy_killed_by_weapon.connect(_on_kill)


# ============================================================ ЦИКЛ

func _unhandled_input(event: InputEvent) -> void:
	if state == State.DEAD:
		return
	if Dialogue.active and Dialogue.waiting_for_choice and event is InputEventKey and (event as InputEventKey).pressed:
		var code: int = (event as InputEventKey).physical_keycode
		var idx := -1
		match code:
			KEY_1: idx = 0
			KEY_2: idx = 1
			KEY_3: idx = 2
			KEY_4: idx = 3
		if idx >= 0:
			Dialogue.choose(idx)
			get_viewport().set_input_as_handled()
			return
	if Dialogue.active and event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_E]:
			Dialogue.advance()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("attack"):
		_primary()
	elif event.is_action_released("attack"):
		rig.primary_released()
	elif event.is_action_pressed("parry"):
		_secondary()
	elif event.is_action_pressed("coin"):
		rig.toss_coin()
	elif event.is_action_pressed("pill"):
		Reality.take_pill()
	elif event.is_action_pressed("scream"):
		scream()
	elif event.is_action_pressed("weapon_1"):
		rig.equip(1)
	elif event.is_action_pressed("weapon_2"):
		rig.equip(2)
	elif event.is_action_pressed("weapon_3"):
		rig.equip(3)
	elif event.is_action_pressed("weapon_4"):
		rig.equip(4)
	elif event.is_action_pressed("interact"):
		_try_interact()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var k: int = (event as InputEventKey).physical_keycode
		if k == KEY_R:
			rig.start_reload()
		elif k == KEY_Q and state != State.DEAD:
			pass  # Q — прыжок, обрабатывается в _physics_process


## ЛКМ: ближний бой для «ПЕРЧАТКИ»/«ЛОБОТОМА», выстрел для остального.
## Плюс: ПЕРЧАТКА всегда доступна — кулак не убирается, это парирование и взрыв.
func _primary() -> void:
	var kind := str(rig.current().get("kind", ""))
	if kind == "melee" or kind == "saw":
		rig.primary_pressed()
	else:
		rig.primary_pressed()


## ПКМ: на слоте 1 — ПАРРИРОВАНИЕ, на остальных — альтернативный огонь/подброс монеты.
func _secondary() -> void:
	if rig.slot == 1 or rig.slot == 4:
		parry()
		return
	if rig.slot == 2:
		# «КАПЕЛЬНИЦА»: ПКМ подбрасывает монету сразу под выстрел
		rig.toss_coin()
		return
	parry()


func _try_interact() -> void:
	for n in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var d: float = (n as Node3D).global_position.distance_to(global_position)
		if d > 2.4:
			continue
		if "interact_with" in n:
			n.interact_with(self)
		elif n.has_meta("convo"):
			Dialogue.start(str(n.get_meta("convo")))
		return


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_timers(delta)
	var input_dir := _camera_relative_input()

	var handled := false
	match state:
		State.DASH, State.AIR_DASH:
			_process_dash(delta)
			handled = true
		State.SLIDE:
			_process_slide(delta, input_dir)
			handled = true
		State.SLAM:
			_process_slam(delta)
			handled = true
		State.WALL_RUN:
			_process_wall_run(delta, input_dir)
			handled = true
		State.HURT:
			velocity.y -= GRAVITY * 0.55 * delta
			var planar := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, 9.0 * delta)
			velocity.x = planar.x
			velocity.z = planar.z
			if _hurt_timer <= 0.0:
				_set_state(State.FALL if not is_on_floor() else State.RUN)
		_:
			_process_ground_air(delta, input_dir)

	move_and_slide()
	_after_move(handled)
	_face_aim(delta)
	_animate(delta)
	_update_blood_visual()


func _timers(delta: float) -> void:
	if _dash_cd > 0.0:
		_dash_cd -= delta
	if _iframe > 0.0:
		_iframe -= delta
		if _iframe <= 0.0:
			invulnerable = false
	if _coyote > 0.0:
		_coyote -= delta
	if _jump_buffer > 0.0:
		_jump_buffer -= delta
	if state == State.DASH or state == State.AIR_DASH:
		_dash_timer -= delta
	scream_charge = minf(1.0, scream_charge + delta * 0.14)


func _camera_relative_input() -> Vector3:
	var ix := Input.get_axis("move_left", "move_right")
	var iz := Input.get_axis("move_forward", "move_back")
	# камера с фиксированным yaw=0: «вперёд» = -Z мира (от камеры)
	var forward := Vector3(0, 0, -1)
	var right := Vector3(1, 0, 0)
	var dir := (forward * (-iz) + right * ix)
	if dir.length() > 1.0:
		dir = dir.normalized()
	return dir


func _process_ground_air(delta: float, input_dir: Vector3) -> void:
	var grounded := is_on_floor()
	if grounded:
		_coyote = 0.12
		can_double_jump = true
		air_dash_charges = max_air_dash
		dash_charges = max_dash
		_run_time += delta if input_dir.length() > 0.1 else 0.0
	else:
		_run_time = 0.0
		velocity.y -= GRAVITY * delta

	var speed := BASE_SPEED * Style.speed_multiplier()
	if Dialogue.active:
		speed *= 0.85                              # во время реплик Вера идёт медленнее
	var accel := ACCEL_GROUND if grounded else ACCEL_AIR
	var wanted := input_dir * speed
	var planar := Vector3(velocity.x, 0, velocity.z)
	planar = planar.move_toward(wanted, accel * delta)
	velocity.x = planar.x
	velocity.z = planar.z

	if grounded and input_dir.length() < 0.1:
		var fr := planar.move_toward(Vector3.ZERO, FRICTION_GROUND * speed * delta)
		velocity.x = fr.x
		velocity.z = fr.z

	# --- буфер прыжка
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = 0.14
	if _jump_buffer > 0.0:
		if grounded or _coyote > 0.0:
			_do_jump(false)
		elif can_double_jump:
			_do_jump(true)

	# --- рывок
	if Input.is_action_just_pressed("dash"):
		_try_dash(input_dir)

	# --- скольжение
	if Input.is_action_just_pressed("slide"):
		if grounded and planar.length() > SLIDE_MIN_SPEED:
			_start_slide(planar.normalized())
		elif not grounded:
			_start_slam()

	# --- wall-run
	if not grounded and is_on_wall_only() and _wall_timer <= 0.0 and planar.length() > 2.0:
		_start_wall_run()

	# --- состояние (не перезаписываем, если действие уже сменило его выше)
	if state in [State.IDLE, State.RUN, State.JUMP, State.FALL]:
		if grounded:
			_set_state(State.RUN if input_dir.length() > 0.1 else State.IDLE)
		else:
			_set_state(State.FALL if velocity.y < 0.0 else State.JUMP)



func _do_jump(double_jump: bool) -> void:
	_jump_buffer = 0.0
	_coyote = 0.0
	if double_jump:
		can_double_jump = false
		velocity.y = DOUBLE_JUMP_SPEED
		Style.award("double_jump")
		jumped.emit(true)
		Audio.play("jump", -4.0, 1.35)
		_spawn_ring(Vector3.UP * 0.1, Color(0.9, 0.9, 0.95), 0.7)
	else:
		velocity.y = JUMP_SPEED
		jumped.emit(false)
		Audio.play("jump")
	_set_state(State.JUMP)


func _try_dash(input_dir: Vector3) -> void:
	if _dash_cd > 0.0:
		return
	var dir := input_dir
	if dir.length() < 0.1:
		dir = Vector3(velocity.x, 0, velocity.z)
		if dir.length() < 0.1:
			dir = -global_basis.z
	dir = dir.normalized()
	var in_air := not is_on_floor()
	if in_air:
		if air_dash_charges <= 0:
			return
		air_dash_charges -= 1
		_set_state(State.AIR_DASH)
		Style.award("air_dash")
		velocity.y = maxf(velocity.y, 0.0)
	else:
		if dash_charges <= 0:
			return
		dash_charges -= 1
		_set_state(State.DASH)
	_dash_dir = dir
	_dash_timer = DASH_TIME
	_dash_cd = DASH_COOLDOWN
	invulnerable = true                       # i-frames на всё время рывка
	Audio.play("dash")
	dashed.emit(in_air)
	_spawn_afterimage()


func _process_dash(delta: float) -> void:
	var speed := DASH_SPEED * Style.speed_multiplier()
	velocity = _dash_dir * speed
	if state == State.AIR_DASH:
		velocity.y = 0.6
	if _dash_timer <= 0.0:
		invulnerable = false
		_iframe = 0.0
		if is_on_floor():
			_set_state(State.RUN)
		else:
			_set_state(State.FALL)
			# slide-jump: рывок в воздухе → скольжение при касании
			_dash_cd = DASH_COOLDOWN * 0.5


func _start_slide(dir: Vector3) -> void:
	_slide_dir = dir
	_slide_timer = SLIDE_TIME
	_set_state(State.SLIDE)
	velocity = dir * maxf(velocity.length(), SLIDE_MIN_SPEED) * SLIDE_BOOST
	Style.award("slide")
	Audio.play("dash", -8.0, 0.6)
	# хитбокс ниже: Вера проходит под трубам и за ширмы
	var shape := _collision.shape as CapsuleShape3D
	if shape != null:
		shape.height = 0.95
		shape.radius = 0.34
	_collision.position = Vector3(0, 0.48, 0)


func _end_slide(keep_momentum: bool) -> void:
	var shape := _collision.shape as CapsuleShape3D
	if shape != null:
		shape.height = 1.45
	_collision.position = Vector3(0, 0.75, 0)
	if keep_momentum and Input.is_action_just_pressed("jump"):
		velocity *= SLIDE_BOOST
		velocity.y = JUMP_SPEED * 1.12          # slide-jump: +35% длины прыжка
		Style.award("wall_jump")
		_set_state(State.JUMP)
	else:
		_set_state(State.RUN if is_on_floor() else State.FALL)


func _process_slide(delta: float, input_dir: Vector3) -> void:
	_slide_timer -= delta
	var k: float = clampf(_slide_timer / SLIDE_TIME, 0.0, 1.0)
	var speed := velocity.length()
	speed = maxf(SLIDE_MIN_SPEED * 0.55, speed - 12.0 * delta)
	var dir := _slide_dir
	if input_dir.length() > 0.1:
		dir = _slide_dir.lerp(input_dir.normalized(), (1.0 - k) * 0.35)
	if dir.length() > 0.001:
		dir = dir.normalized()
		velocity = dir * speed
	velocity.y -= GRAVITY * 0.4 * delta
	if _slide_timer <= 0.0 or speed < 2.4 or not is_on_floor():
		_end_slide(true)


func _start_slam() -> void:
	if is_on_floor():
		return
	_set_state(State.SLAM)
	velocity = Vector3(velocity.x * 0.35, -6.0, velocity.z * 0.35)
	Audio.play("dash", -6.0, 0.45)


func _process_slam(delta: float) -> void:
	velocity.y -= GRAVITY * SLAM_GRAVITY_MULT * delta


func _do_slam_impact() -> void:
	Audio.play("slam")
	Style.award("slam")
	var cam := _camera()
	if cam and cam.has_method("shake"):
		cam.shake(0.65)
		cam.punch_fov(7.0, 0.15)
	_spawn_ring(Vector3.ZERO, Color(0.85, 0.78, 0.65), SLAM_WAVE_RADIUS)
	var killed := 0
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var e := n as Node3D
		var d: float = e.global_position.distance_to(global_position)
		if d > SLAM_WAVE_RADIUS:
			continue
		if "take_hit" in e:
			e.take_hit(46.0 * Style.damage_multiplier(), (e.global_position - global_position).normalized(), e.global_position, true)
			killed += 1
		if "take_knockback" in e:
			e.take_knockback((e.global_position - global_position).normalized() * 9.0)
	if killed >= 3:
		Style.award("multikill_3")
	slammed.emit(global_position)
	_set_state(State.RUN)


func _start_wall_run() -> void:
	_wall_normal = get_wall_normal()
	if _wall_normal.length() < 0.2:
		return
	_wall_timer = WALL_RUN_TIME
	_set_state(State.WALL_RUN)
	Audio.play("dash", -12.0, 1.6)


func _process_wall_run(delta: float, input_dir: Vector3) -> void:
	_wall_timer -= delta
	velocity.y = 3.4
	var along := _wall_normal.cross(Vector3.UP).normalized()
	var sign_dir := 1.0
	if along.dot(input_dir) < 0.0:
		sign_dir = -1.0
	var want := along * sign_dir * BASE_SPEED
	velocity.x = want.x
	velocity.z = want.z
	if _wall_timer <= 0.0 or not is_on_wall():
		_set_state(State.FALL)
	if Input.is_action_just_pressed("jump"):
		velocity = (_wall_normal * 6.6 + Vector3.UP * WALL_JUMP_SPEED)
		_wall_timer = 0.25
		Style.award("wall_jump")
		_set_state(State.JUMP)
		can_double_jump = true


func _face_aim(delta: float) -> void:
	# в третьем лице Вера смотрит туда, куда целится игрок (центр экрана)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var center := get_viewport().get_visible_rect().size * 0.5
	var from := cam.project_ray_origin(center)
	var dir := cam.project_ray_normal(center)
	var t := (global_position.y + 1.0 - from.y) / dir.y if absf(dir.y) > 0.001 else 20.0
	t = clampf(t, 1.0, 40.0)
	var aim_point := from + dir * t
	var to := aim_point - global_position
	to.y = 0
	if to.length() < 0.4:
		return
	var target_yaw := atan2(to.x, to.z)
	var cur := rotation.y
	var diff := wrapf(target_yaw - cur + PI, 0.0, TAU) - PI
	rotation.y = cur + diff * clampf(delta * 14.0, 0.0, 1.0)


# ============================================================ БОЙ / УРОН

func take_hit(damage: float, from_dir: Vector3, _point: Vector3, _from_player: bool) -> void:
	if state == State.DEAD or invulnerable or _iframe > 0.0:
		return
	if Reality.morphing:
		return                                   # во время морфа Вера неуязвима
	var dmg := damage
	if Dialogue.active_voice == "МАМА":
		dmg *= 0.85                              # щит МАМЫ на один удар
	GameState.damage(dmg)
	_damage_taken_this_floor += dmg
	_set_state(State.HURT)
	_hurt_timer = HURT_TIME
	_iframe = IFRAME_AFTER_HURT
	invulnerable = true
	velocity += from_dir * 4.2
	Style.score = maxf(0.0, Style.score - 30.0)
	Style.combo_count = 0
	Audio.play("hurt")
	hurt.emit(dmg, null)
	var cam := _camera()
	if cam and cam.has_method("shake"):
		cam.shake(0.55)
	if GameState.is_dead():
		die()


func die() -> void:
	if state == State.DEAD:
		return
	_set_state(State.DEAD)
	velocity = Vector3.ZERO
	Audio.play("enemy_die", -4.0, 0.6)
	Audio.set_music_layer(0)
	died.emit()


## Перестроение этажа без смерти: просто вернуть тело в порядок.
func revive_silent() -> void:
	if state == State.DEAD:
		_set_state(State.IDLE)
	GameState.reset_vitals()
	invulnerable = true
	_iframe = 0.8
	if model:
		model.rotation = Vector3.ZERO


## Перезапуск этажа. Каждое возрождение = новая история болезни в Архиве.
func revive() -> void:
	_set_state(State.IDLE)
	GameState.register_death()
	GameState.reset_vitals()
	Style.reset_for_next_floor()
	_damage_taken_this_floor = 0.0
	invulnerable = true
	_iframe = 1.2
	revived.emit()


func parry() -> bool:
	return parry_zone.try_parry()


func scream() -> void:
	if scream_charge < 1.0:
		return
	scream_charge = 0.0
	Audio.play("hurt", 0.0, 0.55)
	Audio.play("chalk", -4.0)
	Style.award("scream")
	_spawn_ring(Vector3.UP * 1.1, Color(0.95, 0.92, 0.85), SCREAM_RADIUS)
	var cam := _camera()
	if cam and cam.has_method("shake"):
		cam.shake(0.4)
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var e := n as Node3D
		if e.global_position.distance_to(global_position) > SCREAM_RADIUS:
			continue
		if "stagger" in e:
			e.stagger(1.1)
		if "flee_from" in e:
			e.flee_from(global_position, 2.5)
	screamed.emit()


func damage_taken_this_floor() -> float:
	return _damage_taken_this_floor


func floor_time() -> float:
	return Time.get_ticks_msec() / 1000.0 - _floor_start_time


func reset_floor_stats() -> void:
	_damage_taken_this_floor = 0.0
	_floor_start_time = Time.get_ticks_msec() / 1000.0


# ============================================================ РЕАКЦИИ

func _on_kill(enemy: Node, _slot: int) -> void:
	if not is_instance_valid(enemy) or not (enemy is Node3D):
		return
	var d: float = (enemy as Node3D).global_position.distance_to(global_position)
	# рывок восстанавливается при касании врага ударом (ULTRAKILL)
	if d <= 2.6:
		air_dash_charges = max_air_dash
		dash_charges = max_dash
		_dash_cd = 0.0
		dash_charge_refreshed.emit()
		Style.award("melee_kill")
	# кровь начисляет сам враг в Enemy._die(); здесь только бонус за близость


func _on_parried(_proj: Projectile, _victim: Node3D) -> void:
	invulnerable = true
	_iframe = maxf(_iframe, 0.28)


func _on_parried_melee(_attacker: Node) -> void:
	invulnerable = true
	_iframe = maxf(_iframe, 0.35)


func _on_thirst() -> void:
	Audio.play("chalk", -10.0, 0.7)


func _on_layer_changed(_layer: String) -> void:
	invulnerable = true
	_iframe = maxf(_iframe, Reality.MORPH_TIME)
	if model:
		model.queue_free()
	model = CharacterFactory.vera(1.0, not Reality.is_white())
	model.name = "Model"
	add_child(model)
	move_child(model, 0)
	_pijama_materials.clear()
	_collect_pijama(model)


func _after_move(handled: bool) -> void:
	if state == State.SLAM and is_on_floor():
		_do_slam_impact()
	if handled:
		return
	if is_on_floor() and prev_state == State.FALL and velocity.y <= 0.0:
		Audio.play("land", -10.0, randf_range(0.9, 1.1))


func _update_blood_visual() -> void:
	# кровь на пижаме: HP-бар — это цвет одежды Веры
	if _pijama_materials.is_empty():
		return
	var blood := Blood.blood_stain_amount()
	var base := PIJAMA_BASE if Reality.is_white() else PIJAMA_BASE_RUST
	var bloody := BLOOD_ON_CLOTH
	for m in _pijama_materials:
		if m.albedo_texture != null:
			continue
		m.albedo_color = base.lerp(bloody, blood * 0.85)

const PIJAMA_BASE := Color(0.62, 0.74, 0.86)
const PIJAMA_BASE_RUST := Color(0.42, 0.28, 0.24)
const BLOOD_ON_CLOTH := Color(0.30, 0.04, 0.06)


# ============================================================ АНИМАЦИЯ

func _animate(delta: float) -> void:
	if model == null:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	_bob += delta * (2.0 + speed * 1.35)

	# покачивание при беге (косолапое, тапочки шаркают)
	model.position.y = absf(sin(_bob)) * 0.055 * clampf(speed / BASE_SPEED, 0.0, 1.4)
	model.rotation.z = sin(_bob * 0.5) * 0.035 * clampf(speed / BASE_SPEED, 0.0, 1.0)

	var leg_l := model.get_node_or_null("LegL")
	var leg_r := model.get_node_or_null("LegR")
	var foot_l := model.get_node_or_null("FootL")
	var foot_r := model.get_node_or_null("FootR")
	var swing := sin(_bob) * clampf(speed / BASE_SPEED, 0.0, 1.25)
	if leg_l:
		leg_l.rotation.x = swing * 0.62
	if leg_r:
		leg_r.rotation.x = -swing * 0.62
	if foot_l:
		foot_l.rotation.x = maxf(0.0, swing) * 0.5
	if foot_r:
		foot_r.rotation.x = maxf(0.0, -swing) * 0.5

	var arm_l := model.get_node_or_null("ArmL")
	var arm_r := model.get_node_or_null("ArmR")
	if arm_l:
		arm_l.rotation.x = -swing * 0.45
	if arm_r and not (state == State.SLIDE):
		arm_r.rotation.x = swing * 0.45

	match state:
		State.SLIDE:
			model.rotation.x = deg_to_rad(-62.0)
			model.position.y = 0.0
		State.SLAM:
			model.rotation.x = deg_to_rad(24.0)
		State.DASH, State.AIR_DASH:
			model.rotation.x = deg_to_rad(-16.0)
		State.HURT:
			model.rotation.x = deg_to_rad(12.0)
		State.DEAD:
			model.rotation.x = deg_to_rad(84.0)
			model.position.y = 0.0
		_:
			model.rotation.x = lerpf(model.rotation.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))

	# «процедурная» поза после лоботомии — движения механические
	if GameState.lobotomy_taken:
		model.rotation.z *= 0.25
		model.position.y *= 0.4


func _spawn_ring(offset: Vector3, color: Color, radius: float) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = radius * 0.72
	t.outer_radius = radius
	t.rings = 24
	t.ring_segments = 6
	mi.mesh = t
	var m := FxFactory.mat(color, {"unshaded": true, "transparent": true})
	m.albedo_color.a = 0.6
	mi.material_override = m
	host.add_child(mi)
	mi.global_position = global_position + offset + Vector3.UP * 0.12
	mi.rotation.x = PI * 0.5
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 1.5, 0.28)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.28)
	tw.chain().tween_callback(mi.queue_free)


func _spawn_afterimage() -> void:
	if model == null:
		return
	var host := get_tree().current_scene
	if host == null:
		return
	var ghost := Node3D.new()
	host.add_child(ghost)
	ghost.global_transform = model.global_transform
	for c in model.get_children():
		if c is MeshInstance3D:
			var mi := MeshInstance3D.new()
			mi.mesh = (c as MeshInstance3D).mesh
			var m := FxFactory.mat(Color(0.7, 0.85, 0.95), {"unshaded": true, "transparent": true})
			m.albedo_color.a = 0.32
			mi.material_override = m
			mi.transform = (c as MeshInstance3D).transform
			ghost.add_child(mi)
	var tw := ghost.create_tween()
	tw.tween_interval(0.16)
	tw.tween_callback(ghost.queue_free)


func _camera() -> Node:
	var cams := get_tree().get_nodes_in_group("isaac_camera")
	return cams[0] if cams.size() > 0 else null


func _set_state(s: int) -> void:
	if s == state:
		return
	prev_state = state
	state = s
	if s == State.SLIDE:
		pass


func is_dead() -> bool:
	return state == State.DEAD


func state_name() -> String:
	match state:
		State.IDLE: return "IDLE"
		State.RUN: return "RUN"
		State.JUMP: return "JUMP"
		State.FALL: return "FALL"
		State.DASH: return "DASH"
		State.AIR_DASH: return "AIR_DASH"
		State.SLIDE: return "SLIDE"
		State.SLAM: return "SLAM"
		State.WALL_RUN: return "WALL_RUN"
		State.HURT: return "HURT"
		State.DEAD: return "DEAD"
	return "?"
