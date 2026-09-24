class_name EnemyTypes
extends RefCounted
## Все враги «ОТДЕЛЕНИЯ». Один файл — один бестиарий.
## Правило: у каждого врага ровно ОДНА грязная механика, которую можно
## обернуть против него (парировать, отразить, поджечь, столкнуть).

## СЕДЫЕ — бывшие пациенты в смирительных рубашках. Бегут толпой, взрываются.
class Sedoy extends Enemy:
	func _init() -> void:
		enemy_id = "sedoy"
		max_health = 26.0
		blood_value = 4
		move_speed = 4.6
		touch_damage = 8.0
		attack_range = 1.5
		attack_cooldown = 1.5
		sight_range = 26.0
		style_on_kill = "melee_kill"
		character_id = ""

	func _behave(delta: float) -> void:
		if target == null:
			return
		var to := target.global_position - global_position
		to.y = 0
		var dist := to.length()
		if dist > sight_range:
			velocity = _ground_velocity(Vector3.ZERO, 0.0)
			return
		_face(to.normalized(), delta)
		# бежит на игрока и детонирует в упор
		velocity = _ground_velocity(to.normalized(), move_speed)
		if dist <= attack_range:
			velocity = Vector3.ZERO
			explode_on_melee()


## МЕДСЕСТРА ШВОВ (Галина Петровна) — стреляет иглами. Иглы парируются.
class Nurse extends Enemy:
	var volley := 3
	var _volley_left := 0

	func _init() -> void:
		enemy_id = "nurse"
		max_health = 68.0
		blood_value = 6
		move_speed = 2.3
		touch_damage = 12.0
		attack_range = 15.0
		attack_cooldown = 2.1
		sight_range = 30.0
		style_on_kill = "headshot"
		character_id = "медсестра_швов"

	func _behave(delta: float) -> void:
		if target == null:
			return
		var to := target.global_position - global_position
		to.y = 0
		var dist := to.length()
		_face(to.normalized(), delta)
		# держит дистанцию: 9–13 метров
		var want := Vector3.ZERO
		if dist < 8.0:
			want = -to.normalized()
		elif dist > 13.5:
			want = to.normalized()
		else:
			want = to.cross(Vector3.UP).normalized() * (1.0 if fmod(Time.get_ticks_msec() / 1000.0, 6.0) < 3.0 else -1.0)
		velocity = _ground_velocity(want, move_speed)
		if dist <= sight_range:
			ai = AI.ATTACK
			_try_attack(dist)

	func _try_attack(_dist: float) -> void:
		if _attack_timer > 0.0 or target == null:
			return
		_attack_timer = attack_cooldown
		_volley_left = volley
		_shoot_needle()

	func _shoot_needle() -> void:
		if _volley_left <= 0 or not is_instance_valid(self) or target == null:
			return
		_volley_left -= 1
		var p := Projectile.new()
		get_tree().current_scene.add_child(p)
		p.global_position = global_position + Vector3.UP * 1.5
		var aim := (target.global_position + Vector3.UP * 0.9 - p.global_position).normalized()
		p.from_player = false
		p.owner_node = self
		p.parryable = true
		p.speed = 19.0
		p.damage = 11.0
		p.gravity = 2.2
		p.lifetime = 4.0
		p.setup(aim, 19.0, 11.0, false, self)
		Audio.play("shoot", -6.0, 1.7)
		if _volley_left > 0:
			var t := get_tree().create_timer(0.22)
			t.timeout.connect(_shoot_needle)


## САНТАР — огромный, с носилками вместо щита. Таранит, ломает стены.
class Orderly extends Enemy:
	var charging := false

	func _init() -> void:
		enemy_id = "orderly"
		max_health = 190.0
		blood_value = 14
		move_speed = 2.1
		touch_damage = 22.0
		attack_range = 9.0
		attack_cooldown = 3.4
		sight_range = 28.0
		style_on_kill = "multikill_3"
		character_id = ""

	func _try_attack(_dist: float) -> void:
		if _attack_timer > 0.0 or charging or target == null:
			return
		_attack_timer = attack_cooldown
		charging = true
		melee_active = true
		add_to_group("melee_threat")
		Audio.play("shotgun", -12.0, 0.45)
		var dir := (target.global_position - global_position)
		dir.y = 0
		dir = dir.normalized()
		# таран: 1.6 секунды вперёд, можно парировать в любой момент
		var tw := create_tween()
		tw.tween_property(self, "velocity", dir * 17.0 + Vector3.UP * 0.4, 0.18)
		tw.tween_interval(1.1)
		tw.tween_callback(_end_charge)

	func _end_charge() -> void:
		if not is_instance_valid(self):
			return
		charging = false
		melee_active = false
		remove_from_group("melee_threat")
		# врезался в стену — сам себя оглушает
		if is_on_wall():
			stagger(2.2)
			Audio.play("slam", -8.0)
			Style.award("parry_boost")

	func _physics_process(delta: float) -> void:
		if charging:
			if target != null and is_instance_valid(target):
				var d: float = target.global_position.distance_to(global_position)
				if d <= 1.9 and "take_hit" in target:
					target.take_hit(touch_damage, (target.global_position - global_position).normalized(), target.global_position, false)
					_end_charge()
			velocity.y -= 26.0 * delta
			move_and_slide()
			_animate(delta)
			return
		super(delta)


## ХОР — 14 детей, поющих одну ноту. Все они предыдущие Веры.
## Убиваются ТОЛЬКО парированием их собственного крика.
class Chorister extends Enemy:
	var _scream_ready := false

	func _init() -> void:
		enemy_id = "chorister"
		max_health = 22.0
		blood_value = 2
		move_speed = 3.8
		touch_damage = 5.0
		attack_range = 12.0
		attack_cooldown = 2.6
		sight_range = 34.0
		unkillable = false
		style_on_kill = "parry"
		character_id = "хор"

	func _ready() -> void:
		super()
		gravity_scale_hack()

	func gravity_scale_hack() -> void:
		pass

	func _physics_process(delta: float) -> void:
		if is_dead:
			return
		_timers(delta)
		if target == null or not is_instance_valid(target):
			target = _find_player()
		if target == null:
			return
		# летает роем: синусоида вокруг цели
		var to := target.global_position + Vector3.UP * 1.4 - global_position
		var dist := to.length()
		var t := Time.get_ticks_msec() / 1000.0
		var orbit := Vector3(cos(t * 1.7 + float(get_index()) * 0.9), sin(t * 2.3) * 0.5, sin(t * 1.7 + float(get_index()) * 0.9))
		var wanted := Vector3.ZERO
		if dist > 2.6:
			wanted = to.normalized() * move_speed + orbit * 2.2
		else:
			wanted = orbit * 3.0
		velocity = velocity.lerp(wanted, clampf(delta * 3.0, 0.0, 1.0))
		_face(to, delta)
		if dist <= attack_range and _attack_timer <= 0.0:
			_attack_timer = attack_cooldown
			_scream()
		move_and_slide()
		_animate(delta)

	func _scream() -> void:
		if target == null:
			return
		_scream_ready = true
		melee_active = true
		add_to_group("melee_threat")
		Audio.play("hurt", -8.0, 0.62)
		var p := Projectile.new()
		get_tree().current_scene.add_child(p)
		p.global_position = global_position
		var aim := (target.global_position + Vector3.UP * 0.9 - p.global_position).normalized()
		p.owner_node = self
		p.parryable = true
		p.speed = 12.0
		p.lifetime = 2.2
		p.setup(aim, 12.0, 7.0, false, self)
		var tw := create_tween()
		tw.tween_interval(0.45)
		tw.tween_callback(func() -> void:
			if is_instance_valid(self):
				melee_active = false
				remove_from_group("melee_threat")
				_scream_ready = false)

	## Хориста нельзя застрелить: пули проходят сквозь него.
	func take_hit(amount: float, dir: Vector3, _point: Vector3, from_player: bool, count_style: bool = true) -> void:
		if is_dead:
			return
		if from_player and not _scream_ready:
			Audio.play("ui", -14.0, 0.5)
			return
		super(amount, dir, _point, from_player, count_style)


## ТАБЛЕТКА — турель. Плюётся капсулами. Неподвижна.
class Pill extends Enemy:
	func _init() -> void:
		enemy_id = "sedoy"
		max_health = 45.0
		blood_value = 3
		move_speed = 0.0
		touch_damage = 0.0
		attack_range = 24.0
		attack_cooldown = 1.35
		sight_range = 26.0
		style_on_kill = "headshot"

	func _ready() -> void:
		super()
		if model:
			model.queue_free()
		model = Node3D.new()
		var mi := MeshInstance3D.new()
		mi.name = "Head"
		var cap := CapsuleMesh.new()
		cap.radius = 0.26
		cap.height = 0.72
		mi.mesh = cap
		mi.material_override = FxFactory.mat(Color(0.88, 0.35, 0.32), {"roughness": 0.4})
		mi.position = Vector3(0, 0.4, 0)
		model.add_child(mi)
		var mi2 := MeshInstance3D.new()
		mi2.mesh = cap
		mi2.material_override = FxFactory.mat(Color(0.92, 0.92, 0.88), {"roughness": 0.4})
		mi2.scale = Vector3(1.0, 0.5, 1.0)
		mi2.position = Vector3(0, 0.56, 0)
		model.add_child(mi2)
		add_child(model)

	func _physics_process(_delta: float) -> void:
		if is_dead:
			return
		_timers(_delta)
		if target == null or not is_instance_valid(target):
			target = _find_player()
		if target == null:
			return
		velocity = Vector3.ZERO
		var to := target.global_position - global_position
		_face(to, _delta)
		if to.length() <= sight_range:
			_try_attack(to.length())

	func _try_attack(_dist: float) -> void:
		if _attack_timer > 0.0 or target == null:
			return
		_attack_timer = attack_cooldown
		for i in 3:
			var p := Projectile.new()
			get_tree().current_scene.add_child(p)
			p.global_position = global_position + Vector3.UP * 0.5
			var spread := Vector3(randf_range(-0.06, 0.06), randf_range(-0.02, 0.05), randf_range(-0.06, 0.06))
			var aim := (target.global_position + Vector3.UP * 0.8 - p.global_position).normalized() + spread
			p.owner_node = self
			p.parryable = true
			p.setup(aim.normalized(), 16.0, 8.0, false, self)
			p.gravity = 1.2
		Audio.play("shoot", -8.0, 1.2)


## ЗЕРКАЛО — копирует твоё последнее оружие и твоё комбо.
class Mirror extends Enemy:
	var copied_slot := 1
	var copies_left := 2

	func _init() -> void:
		enemy_id = "mirror"
		max_health = 420.0
		blood_value = 10
		move_speed = 6.2
		touch_damage = 16.0
		attack_range = 2.6
		attack_cooldown = 0.9
		sight_range = 40.0
		style_on_kill = "bloodbath"
		character_id = "зеркало"

	func _ready() -> void:
		super()

	func _physics_process(delta: float) -> void:
		if is_dead:
			return
		# зеркало повторяет текущее оружие игрока
		if target != null and "rig" in target:
			copied_slot = int((target as Player).rig.slot)
		_timers(delta)
		if target == null or not is_instance_valid(target):
			target = _find_player()
		_behave(delta)
		move_and_slide()
		_animate(delta)

	func _try_attack(dist: float) -> void:
		if _attack_timer > 0.0 or target == null:
			return
		match copied_slot:
			1, 4:
				_attack_timer = attack_cooldown
				_melee_lunge()
			2:
				_attack_timer = 0.55
				_shoot_mirror_bullet(1.0)
			3:
				_attack_timer = 1.5
				for i in 5:
					_shoot_mirror_bullet(0.12 * float(i) - 0.24)
			_:
				_attack_timer = attack_cooldown
				_melee_lunge()
		if dist > attack_range + 4.0:
			_attack_timer = minf(_attack_timer, 0.4)

	func _shoot_mirror_bullet(y_offset: float) -> void:
		if target == null or not is_instance_valid(target):
			return
		var p := Projectile.new()
		get_tree().current_scene.add_child(p)
		p.global_position = global_position + Vector3.UP * 1.2
		var aim := (target.global_position + Vector3.UP * (0.9 + y_offset) - p.global_position).normalized()
		p.owner_node = self
		p.parryable = true
		p.setup(aim, 26.0, 13.0, false, self)
		Audio.play("shoot", -5.0, 1.25)

	## Зеркало копирует и парирование: первое парирование против него не работает.
	func stagger(duration: float) -> void:
		if copies_left > 0:
			copies_left -= 1
			Audio.play("parry", -4.0, 0.7)
			Style.award("parry_boost")
			velocity = Vector3.UP * 5.0
			return
		super(duration)


## МАМА — неубиваема. Единственный босс, которого нельзя победить:
## можно только парировать её крик 12 раз подряд и НЕ убить.
class Mother extends Enemy:
	const REQUIRED_PARRIES := 12
	var parries_taken := 0

	func _init() -> void:
		enemy_id = "mother_jar"
		max_health = 9999.0
		blood_value = 0
		move_speed = 3.1
		touch_damage = 14.0
		attack_range = 16.0
		attack_cooldown = 2.3
		sight_range = 44.0
		unkillable = true
		style_on_kill = "mother_spared"
		character_id = "мама"

	func _ready() -> void:
		super()
		GameState.mother_alive = true

	func _behave(delta: float) -> void:
		if target == null:
			return
		var to := target.global_position - global_position
		to.y = 0
		_face(to.normalized(), delta)
		# МАМА не бежит — она подходит медленно, как во сне
		velocity = _ground_velocity(to.normalized(), move_speed if to.length() > 3.0 else 0.0)
		if _attack_timer <= 0.0:
			_attack_timer = attack_cooldown
			_cry()

	func _cry() -> void:
		if target == null:
			return
		melee_active = true
		add_to_group("melee_threat")
		Audio.play("hurt", -2.0, 0.5)
		Audio.play("chalk", -8.0)
		for i in 5:
			var p := Projectile.new()
			get_tree().current_scene.add_child(p)
			p.global_position = global_position + Vector3.UP * 1.5
			var ang := TAU * float(i) / 5.0
			var aim := Vector3(cos(ang), 0.06, sin(ang))
			if i == 0 and is_instance_valid(target):
				aim = (target.global_position + Vector3.UP * 0.8 - p.global_position).normalized()
			p.owner_node = self
			p.parryable = true
			p.setup(aim, 10.0, 12.0, false, self)
			p.lifetime = 3.2
		var tw := create_tween()
		tw.tween_interval(0.9)
		tw.tween_callback(func() -> void:
			if is_instance_valid(self):
				melee_active = false
				remove_from_group("melee_threat"))

	func take_hit(amount: float, dir: Vector3, point: Vector3, from_player: bool, count_style: bool = true) -> void:
		if from_player:
			# каждое попадание по МАМЕ — это #жестокость и минус к концовке A
			GameState.add_tag("жестокость", 2)
			Style.score = maxf(0.0, Style.score - 120.0)
			Audio.play("chalk", -6.0)
		super(amount, dir, point, from_player, count_style)

	## Парирование её крика засчитывается как «шаг к прощению».
	func on_cry_parried() -> void:
		parries_taken += 1
		Audio.play("parry", 0.0, 1.25)
		if parries_taken >= REQUIRED_PARRIES:
			Style.award("mother_spared")
			GameState.mother_alive = true
			GameState.set_flag("мама_прощена")
			_die()


## ИВАНЫЧ — кочегар. Не нападает первым: 90 секунд защищается и умоляет остановиться.
class Ivanich extends Enemy:
	var begging := true
	var beg_timer := 90.0

	func _init() -> void:
		enemy_id = "ivanich"
		max_health = 520.0
		blood_value = 20
		move_speed = 3.0
		touch_damage = 26.0
		attack_range = 3.4
		attack_cooldown = 2.0
		sight_range = 30.0
		style_on_kill = "ivanich_spared"
		character_id = "иваныч"

	func _ready() -> void:
		super()
		GameState.ivanich_alive = true

	func _physics_process(delta: float) -> void:
		if is_dead:
			return
		if begging:
			beg_timer -= delta
			if beg_timer <= 0.0:
				begging = false
		super(delta)

	func _behave(delta: float) -> void:
		if begging:
			# он только закрывается кочергой и отходит
			if target == null:
				return
			var away := (global_position - target.global_position)
			away.y = 0
			_face(-away.normalized(), delta)
			velocity = _ground_velocity(away.normalized(), move_speed * 0.55)
			return
		super(delta)

	func _die() -> void:
		GameState.ivanich_alive = false
		GameState.add_tag("жестокость", 8)
		super()


## ГЛАВВРАЧ / финальный босс. Дерётся твоим же стилем: если ты играл красиво —
## он SSS-ранга с полным набором твоих приёмов. Игра наказывает за мастерство
## и награждает за него одновременно.
class HeadDoctor extends Enemy:
	var phase := 1
	var mirror_rank := 0
	var _combo := 0

	func _init() -> void:
		enemy_id = "doctor"
		max_health = 900.0
		blood_value = 30
		move_speed = 5.4
		touch_damage = 20.0
		attack_range = 3.0
		attack_cooldown = 1.1
		sight_range = 60.0
		style_on_kill = "multikill_5"
		character_id = "асконченский"

	func _ready() -> void:
		super()
		# босс наследует стиль игрока: грязная игра = слабый босс
		mirror_rank = Style.rank_index
		max_health = 620.0 + float(mirror_rank) * 130.0
		health = max_health
		move_speed = 4.2 + float(mirror_rank) * 0.28
		attack_cooldown = maxf(0.42, 1.35 - float(mirror_rank) * 0.11)

	func _behave(delta: float) -> void:
		super(delta)
		if health_ratio() < 0.55 and phase == 1:
			phase = 2
			attack_cooldown *= 0.62
			move_speed *= 1.22
			Audio.play("rank_up", -6.0, 0.7)
		if health_ratio() < 0.22 and phase == 2:
			phase = 3
			attack_cooldown *= 0.7
			Audio.play("rank_up", -4.0, 0.55)

	func _try_attack(dist: float) -> void:
		if _attack_timer > 0.0 or target == null:
			return
		_attack_timer = attack_cooldown
		_combo = (_combo + 1) % 4
		match _combo:
			0:
				_melee_lunge()
			1:
				_diagnosis_burst(5 + phase * 2)
			2:
				_procedure_beam()
			3:
				if dist > 6.0:
					_teleport()
				else:
					_melee_lunge()

	## «Перечисляет диагнозы» — веер игл по кругу. Парируется.
	func _diagnosis_burst(count: int) -> void:
		Audio.play("hurt", -10.0, 0.7)
		for i in count:
			var p := Projectile.new()
			get_tree().current_scene.add_child(p)
			p.global_position = global_position + Vector3.UP * 1.6
			var ang := TAU * float(i) / float(count) + float(phase) * 0.2
			var aim := Vector3(cos(ang), 0.02, sin(ang))
			if target != null and is_instance_valid(target) and i == 0:
				aim = (target.global_position + Vector3.UP * 0.9 - p.global_position).normalized()
			p.owner_node = self
			p.parryable = true
			p.setup(aim, 15.0 + float(phase) * 3.0, 12.0, false, self)

	## «Процедура» — луч, который надо перепрыгнуть или переехать рывком.
	func _procedure_beam() -> void:
		if target == null:
			return
		melee_active = true
		add_to_group("melee_threat")
		Audio.play("slam", -6.0, 0.8)
		var dir := (target.global_position - global_position)
		dir.y = 0
		dir = dir.normalized()
		var host := get_tree().current_scene
		if host != null:
			for i in 16:
				var mi := MeshInstance3D.new()
				var b := BoxMesh.new()
				b.size = Vector3(0.5, 0.06, 0.5)
				mi.mesh = b
				mi.material_override = FxFactory.mat(Color(1.0, 0.95, 0.7), {"unshaded": true, "transparent": true})
				host.add_child(mi)
				mi.global_position = global_position + dir * (1.2 + float(i) * 0.9) + Vector3.UP * 0.35
				var tw := mi.create_tween()
				tw.tween_property((mi.material_override as StandardMaterial3D), "albedo_color:a", 0.0, 0.5)
				tw.tween_callback(mi.queue_free)
		var tw2 := create_tween()
		tw2.tween_interval(0.42)
		tw2.tween_callback(func() -> void:
			if not is_instance_valid(self) or target == null:
				return
			if not is_instance_valid(target):
				return
			var to := target.global_position - global_position
			to.y = 0
			var along := to.dot(dir)
			var side := (to - dir * along).length()
			if along > 0.0 and along < 15.0 and side < 1.1:
				if target.global_position.y - global_position.y < 1.1:
					if "take_hit" in target:
						target.take_hit(24.0 + float(phase) * 6.0, dir, target.global_position, false)
			melee_active = false
			remove_from_group("melee_threat"))

	func _teleport() -> void:
		if target == null:
			return
		Audio.play("dash", -4.0, 0.5)
		var around := target.global_position + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
		global_position = around
		velocity = Vector3.ZERO


## БИБЛИОТЕКАРЬ Пелагея — не хочет драться. Просит расписаться за дело.
class Librarian extends Enemy:
	func _init() -> void:
		enemy_id = "librarian"
		max_health = 300.0
		blood_value = 8
		move_speed = 1.4
		touch_damage = 6.0
		attack_range = 12.0
		attack_cooldown = 2.8
		sight_range = 26.0
		unkillable = true
		style_on_kill = "secret_found"
		character_id = "пелагея"

	func _behave(delta: float) -> void:
		if target == null:
			return
		var to := target.global_position - global_position
		to.y = 0
		_face(to.normalized(), delta)
		# она не атакует — она предлагает подпись
		velocity = _ground_velocity(Vector3.ZERO, 0.0)
		if to.length() < 5.0 and _attack_timer <= 0.0:
			_attack_timer = attack_cooldown
			_offer_paper()

	func _offer_paper() -> void:
		Audio.play("chalk", -6.0)
		var host := get_tree().current_scene
		if host == null:
			return
		host.add_child(_paper_prompt())

	func _paper_prompt() -> Node3D:
		var n := Node3D.new()
		n.add_to_group("interactable")
		n.set_meta("prompt", "РАСПИСАТЬСЯ ЗА ПОЛУЧЕНИЕ ДЕЛА №%d [E]" % GameState.case_file_number)
		n.set_meta("convo", "floor5_librarian")
		n.global_position = global_position + Vector3.UP * 1.2
		return n


## ФАНТОМ — спавнится только когда стиль низкий (ранг ≤ C). Не даёт кровь.
class Phantom extends Enemy:
	func _init() -> void:
		enemy_id = "mirror"
		max_health = 14.0
		blood_value = 0
		move_speed = 5.2
		touch_damage = 6.0
		attack_range = 1.6
		attack_cooldown = 1.0
		sight_range = 40.0
		style_on_kill = "secret_found"

	func _ready() -> void:
		super()
		add_to_group("phantom")
		# фантом полупрозрачен и не отбрасывает кровь — это не человек
		for i in _materials.size():
			_materials[i].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var c := _base_colors[i]
			c.a = 0.34
			_materials[i].albedo_color = c

	func _physics_process(delta: float) -> void:
		super(delta)
		# исчезает, как только Вера «приходит в себя»
		if not Style.hallucinating():
			_fade_out()

	func _fade_out() -> void:
		remove_from_group("enemies")
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3(0.02, 0.02, 0.02), 0.6)
		tw.tween_callback(queue_free)


# ============================================================ ФАБРИКА

static func spawn(kind: String, at: Vector3, parent: Node) -> Enemy:
	var e: Enemy
	match kind:
		"sedoy":     e = Sedoy.new()
		"nurse":     e = Nurse.new()
		"orderly":   e = Orderly.new()
		"chorister": e = Chorister.new()
		"pill":      e = Pill.new()
		"mirror":    e = Mirror.new()
		"mother":    e = Mother.new()
		"ivanich":   e = Ivanich.new()
		"doctor":    e = HeadDoctor.new()
		"librarian": e = Librarian.new()
		"phantom":   e = Phantom.new()
		_:           e = Sedoy.new()
	e.name = "Enemy_%s_%d" % [kind, randi() % 9999]
	parent.add_child(e)
	e.global_position = at
	return e
