class_name RoomFactory
extends RefCounted
## Процедурная геометрия больницы «Святого Ипатия».
## Каждая комната строится дважды: в БЕЛОМ и в РЖАВОМ слое (группы
## white_layer / rust_layer). RealityManager переключает их таблеткой.

const WALL_H := 3.4

static var _white_tile: ImageTexture
static var _white_floor: ImageTexture
static var _rust_tex: ImageTexture


static func _tex_white() -> ImageTexture:
	if _white_tile == null:
		_white_tile = FxFactory.tile_texture(256, 8)
	return _white_tile


static func _tex_floor() -> ImageTexture:
	if _white_floor == null:
		_white_floor = FxFactory.linoleum_texture(256, Color(0.58, 0.64, 0.60))
	return _white_floor


static func _tex_rust() -> ImageTexture:
	if _rust_tex == null:
		_rust_tex = FxFactory.rust_texture(256)
	return _rust_tex


## Полная комната: пол, 4 стены с проёмами под дверь, потолок, свет.
## doors: массив направлений ["north","south","east","west"], где есть двери.
static func room(name: String, size: Vector2, doors: Array[String], parent: Node3D, center := Vector3.ZERO) -> Node3D:
	var root := Node3D.new()
	root.name = name
	root.position = center
	parent.add_child(root)

	var white := Node3D.new()
	white.name = "WhiteLayer"
	white.add_to_group("white_layer")
	root.add_child(white)

	var rust := Node3D.new()
	rust.name = "RustLayer"
	rust.add_to_group("rust_layer")
	root.add_child(rust)

	_build_layer(white, size, doors, false)
	_build_layer(rust, size, doors, true)

	# триггер комнаты строит FloorManager (скрипт назначается ДО входа в дерево)
	Reality.register(white)
	Reality.register(rust)
	return root


static func _build_layer(layer: Node3D, size: Vector2, doors: Array[String], is_rust: bool) -> void:
	var sx := size.x
	var sy := size.y
	var wall_mat: StandardMaterial3D
	var floor_mat: StandardMaterial3D
	var ceil_mat: StandardMaterial3D

	if is_rust:
		wall_mat = FxFactory.mat(Color(0.20, 0.12, 0.10), {"texture": _tex_rust(), "roughness": 1.0})
		floor_mat = FxFactory.mat(Color(0.28, 0.16, 0.12), {"texture": _tex_rust(), "roughness": 1.0})
		ceil_mat = FxFactory.mat(Color(0.10, 0.06, 0.05), {"roughness": 1.0})
	else:
		wall_mat = FxFactory.mat(Color(0.90, 0.93, 0.91), {"texture": _tex_white(), "roughness": 0.6})
		floor_mat = FxFactory.mat(Color(0.70, 0.76, 0.72), {"texture": _tex_floor(), "roughness": 0.55})
		ceil_mat = FxFactory.mat(Color(0.86, 0.89, 0.87), {"roughness": 0.9})

	# пол
	var floor_mi := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(sx, sy)
	floor_mi.mesh = floor_mesh
	floor_mi.material_override = floor_mat
	layer.add_child(floor_mi)

	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorBody"
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(sx, 0.4, sy)
	floor_col.shape = floor_shape
	floor_col.position = Vector3(0, -0.2, 0)
	floor_body.add_child(floor_col)
	floor_body.collision_layer = 1
	layer.add_child(floor_body)

	# потолок
	var ceil_mi := MeshInstance3D.new()
	var ceil_mesh := PlaneMesh.new()
	ceil_mesh.size = Vector2(sx, sy)
	ceil_mi.mesh = ceil_mesh
	ceil_mi.material_override = ceil_mat
	ceil_mi.position = Vector3(0, WALL_H, 0)
	ceil_mi.rotation.x = PI
	layer.add_child(ceil_mi)

	# стены: север (-Z), юг (+Z), запад (-X), восток (+X)
	_wall(layer, "north", Vector3(0, 0, -sy * 0.5), Vector2(sx, WALL_H), 0.0, doors.has("north"), wall_mat)
	_wall(layer, "south", Vector3(0, 0, sy * 0.5), Vector2(sx, WALL_H), PI, doors.has("south"), wall_mat)
	_wall(layer, "west", Vector3(-sx * 0.5, 0, 0), Vector2(sy, WALL_H), PI * 0.5, doors.has("west"), wall_mat)
	_wall(layer, "east", Vector3(sx * 0.5, 0, 0), Vector2(sy, WALL_H), -PI * 0.5, doors.has("east"), wall_mat)

	# свет
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.position = Vector3(0, WALL_H - 0.35, 0)
	lamp.light_energy = 1.6 if not is_rust else 0.9
	lamp.omni_range = maxf(sx, sy) * 0.85
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = false
	if is_rust:
		lamp.light_color = Reality.PALETTE[Reality.Layer.RUST]["light"]
	else:
		lamp.light_color = Reality.PALETTE[Reality.Layer.WHITE]["light"]
	layer.add_child(lamp)

	var fixture := MeshInstance3D.new()
	fixture.mesh = _box(Vector3(1.2, 0.08, 0.30))
	fixture.material_override = FxFactory.mat(Color(0.96, 0.97, 0.94), {"emission": true, "emission_color": lamp.light_color, "emission_energy": 2.2 if not is_rust else 0.7})
	fixture.position = Vector3(0, WALL_H - 0.12, 0)
	layer.add_child(fixture)

	# плинтус — больничная деталь
	var skirt_mat := FxFactory.mat(Color(0.42, 0.47, 0.45) if not is_rust else Color(0.14, 0.09, 0.07))
	for i in 4:
		var sk := MeshInstance3D.new()
		var long: float = sx if i < 2 else sy
		sk.mesh = _box(Vector3(long, 0.14, 0.06))
		sk.material_override = skirt_mat
		match i:
			0: sk.position = Vector3(0, 0.07, -sy * 0.5 + 0.03)
			1: sk.position = Vector3(0, 0.07, sy * 0.5 - 0.03)
			2:
				sk.position = Vector3(-sx * 0.5 + 0.03, 0.07, 0)
				sk.rotation.y = PI * 0.5
			3:
				sk.position = Vector3(sx * 0.5 - 0.03, 0.07, 0)
				sk.rotation.y = PI * 0.5
		layer.add_child(sk)


static func _wall(layer: Node3D, dir_name: String, pos: Vector3, size2: Vector2, rot_y: float, has_door: bool, mat: Material) -> void:
	var door_w := 1.7
	var door_h := 2.4
	var segs: Array[Dictionary] = []
	if has_door:
		var side := (size2.x - door_w) * 0.5
		segs.append({"w": side, "h": WALL_H, "x": -(door_w * 0.5 + side * 0.5), "y": WALL_H * 0.5})
		segs.append({"w": side, "h": WALL_H, "x": (door_w * 0.5 + side * 0.5), "y": WALL_H * 0.5})
		segs.append({"w": door_w, "h": WALL_H - door_h, "x": 0.0, "y": door_h + (WALL_H - door_h) * 0.5})
	else:
		segs.append({"w": size2.x, "h": WALL_H, "x": 0.0, "y": WALL_H * 0.5})

	var holder := Node3D.new()
	holder.name = "Wall_" + dir_name
	holder.position = pos
	holder.rotation.y = rot_y
	layer.add_child(holder)

	for s in segs:
		var mi := MeshInstance3D.new()
		mi.mesh = _box(Vector3(float(s["w"]), float(s["h"]), 0.22))
		mi.material_override = mat
		mi.position = Vector3(float(s["x"]), float(s["y"]), 0)
		holder.add_child(mi)

		var body := StaticBody3D.new()
		body.collision_layer = 1
		var col := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(float(s["w"]), float(s["h"]), 0.22)
		col.shape = sh
		col.position = mi.position
		body.add_child(col)
		holder.add_child(body)

	if has_door:
		# дверная коробка
		var frame := MeshInstance3D.new()
		frame.mesh = _box(Vector3(door_w + 0.2, 0.12, 0.28))
		frame.material_override = FxFactory.mat(Color(0.40, 0.44, 0.42), {"metallic": 0.3})
		frame.position = Vector3(0, door_h, 0)
		holder.add_child(frame)


# ============================================================ ПРОПИТы

static func hospital_bed(pos: Vector3, parent: Node3D, rust: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Bed"
	root.position = pos
	parent.add_child(root)
	var frame := MeshInstance3D.new()
	frame.mesh = _box(Vector3(0.95, 0.10, 2.0))
	frame.material_override = FxFactory.mat(Color(0.78, 0.80, 0.80), {"metallic": 0.6, "roughness": 0.35})
	frame.position = Vector3(0, 0.55, 0)
	root.add_child(frame)
	var mat := MeshInstance3D.new()
	mat.mesh = _box(Vector3(0.88, 0.14, 1.9))
	mat.material_override = FxFactory.mat(Color(0.86, 0.88, 0.86) if not rust else Color(0.42, 0.24, 0.20), {"roughness": 0.95})
	mat.position = Vector3(0, 0.66, 0)
	root.add_child(mat)
	for i in 4:
		var leg := MeshInstance3D.new()
		leg.mesh = _box(Vector3(0.06, 0.55, 0.06))
		leg.material_override = frame.material_override
		leg.position = Vector3(-0.42 + (i % 2) * 0.84, 0.275, -0.9 + int(i / 2) * 1.8)
		root.add_child(leg)
	var head := MeshInstance3D.new()
	head.mesh = _box(Vector3(0.95, 0.55, 0.06))
	head.material_override = frame.material_override
	head.position = Vector3(0, 0.85, -1.0)
	root.add_child(head)
	_add_collision(root, Vector3(0.95, 0.8, 2.0), Vector3(0, 0.4, 0))
	return root


static func iv_stand(pos: Vector3, parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "IVStand"
	root.position = pos
	parent.add_child(root)
	var pole := MeshInstance3D.new()
	pole.mesh = _box(Vector3(0.04, 1.85, 0.04))
	pole.material_override = FxFactory.mat(Color(0.82, 0.84, 0.85), {"metallic": 0.85, "roughness": 0.25})
	pole.position = Vector3(0, 0.92, 0)
	root.add_child(pole)
	var bag := MeshInstance3D.new()
	bag.mesh = _box(Vector3(0.16, 0.26, 0.07))
	var bm := FxFactory.mat(Color(0.78, 0.86, 0.80), {"transparent": true})
	bm.albedo_color.a = 0.55
	bag.material_override = bm
	bag.position = Vector3(0, 1.72, 0)
	root.add_child(bag)
	var tube := MeshInstance3D.new()
	tube.mesh = _box(Vector3(0.012, 1.1, 0.012))
	tube.material_override = FxFactory.mat(Color(0.85, 0.88, 0.85))
	tube.position = Vector3(0.02, 1.05, 0.03)
	root.add_child(tube)
	var base := MeshInstance3D.new()
	base.mesh = _cylinder(0.24, 0.24, 0.05)
	base.material_override = pole.material_override
	base.position = Vector3(0, 0.025, 0)
	root.add_child(base)
	_add_collision(root, Vector3(0.5, 1.9, 0.5), Vector3(0, 0.95, 0))
	return root


## Лампа-рефлектор Минина («синяя лампа») — советская больничная деталь.
static func blue_lamp(pos: Vector3, parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "BlueLamp"
	root.position = pos
	parent.add_child(root)
	var shade := MeshInstance3D.new()
	shade.mesh = _cylinder(0.02, 0.19, 0.14)
	shade.material_override = FxFactory.mat(Color(0.86, 0.85, 0.80), {"metallic": 0.7, "roughness": 0.3})
	shade.rotation.x = deg_to_rad(35.0)
	root.add_child(shade)
	var bulb := MeshInstance3D.new()
	bulb.mesh = _sphere_mesh(0.07)
	bulb.material_override = FxFactory.mat(Color(0.35, 0.55, 1.0), {"emission": true, "emission_color": Color(0.28, 0.48, 1.0), "emission_energy": 3.0})
	bulb.position = Vector3(0, -0.03, 0.05)
	root.add_child(bulb)
	var l := OmniLight3D.new()
	l.light_color = Color(0.35, 0.5, 1.0)
	l.light_energy = 0.9
	l.omni_range = 3.2
	l.position = Vector3(0, -0.05, 0.08)
	root.add_child(l)
	return root


## Кресло-каталка с ремнями (лоботомическое крыло).
static func restraint_chair(pos: Vector3, parent: Node3D, rust: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "RestraintChair"
	root.position = pos
	parent.add_child(root)
	var metal := FxFactory.mat(Color(0.74, 0.76, 0.77) if not rust else Color(0.34, 0.20, 0.16), {"metallic": 0.8, "roughness": 0.4})
	var seat := MeshInstance3D.new()
	seat.mesh = _box(Vector3(0.62, 0.08, 0.60))
	seat.material_override = metal
	seat.position = Vector3(0, 0.52, 0)
	root.add_child(seat)
	var back := MeshInstance3D.new()
	back.mesh = _box(Vector3(0.62, 0.90, 0.08))
	back.material_override = metal
	back.position = Vector3(0, 0.98, -0.28)
	root.add_child(back)
	var head := MeshInstance3D.new()
	head.mesh = _box(Vector3(0.34, 0.30, 0.10))
	head.material_override = FxFactory.mat(Color(0.42, 0.36, 0.32))
	head.position = Vector3(0, 1.55, -0.30)
	root.add_child(head)
	for i in 4:
		var leg := MeshInstance3D.new()
		leg.mesh = _box(Vector3(0.05, 0.52, 0.05))
		leg.material_override = metal
		leg.position = Vector3(-0.26 + (i % 2) * 0.52, 0.26, -0.24 + int(i / 2) * 0.48)
		root.add_child(leg)
	# ремни
	var strap := FxFactory.mat(Color(0.30, 0.24, 0.20), {"roughness": 1.0})
	for i in 3:
		var s := MeshInstance3D.new()
		s.mesh = _box(Vector3(0.72, 0.06, 0.03))
		s.material_override = strap
		s.position = Vector3(0, 0.66 + i * 0.30, 0.02 - i * 0.10)
		root.add_child(s)
	_add_collision(root, Vector3(0.7, 1.7, 0.7), Vector3(0, 0.85, -0.1))
	return root


## Картотечный шкаф (Архив, 40 000 дел).
static func cabinet(pos: Vector3, parent: Node3D, rot_y: float = 0.0, rust: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Cabinet"
	root.position = pos
	root.rotation.y = rot_y
	parent.add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = _box(Vector3(0.9, 2.2, 0.6))
	body.material_override = FxFactory.mat(Color(0.52, 0.58, 0.54) if not rust else Color(0.28, 0.16, 0.12), {"metallic": 0.5, "roughness": 0.6})
	body.position = Vector3(0, 1.1, 0)
	root.add_child(body)
	for i in 5:
		var drawer := MeshInstance3D.new()
		drawer.mesh = _box(Vector3(0.82, 0.34, 0.04))
		drawer.material_override = FxFactory.mat(Color(0.46, 0.52, 0.48) if not rust else Color(0.34, 0.19, 0.14), {"metallic": 0.6})
		drawer.position = Vector3(0, 0.28 + i * 0.40, 0.31)
		root.add_child(drawer)
		var handle := MeshInstance3D.new()
		handle.mesh = _box(Vector3(0.20, 0.035, 0.035))
		handle.material_override = FxFactory.mat(Color(0.78, 0.80, 0.80), {"metallic": 0.9, "roughness": 0.2})
		handle.position = Vector3(0, 0.28 + i * 0.40, 0.34)
		root.add_child(handle)
	_add_collision(root, Vector3(0.9, 2.2, 0.6), Vector3(0, 1.1, 0))
	return root


## Печь котельной.
static func furnace(pos: Vector3, parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Furnace"
	root.position = pos
	parent.add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = _cylinder(0.85, 0.85, 2.1)
	body.material_override = FxFactory.mat(Color(0.16, 0.14, 0.13), {"metallic": 0.7, "roughness": 0.7})
	body.position = Vector3(0, 1.05, 0)
	root.add_child(body)
	var mouth := MeshInstance3D.new()
	mouth.mesh = _box(Vector3(0.7, 0.55, 0.1))
	mouth.material_override = FxFactory.mat(Color(1.0, 0.42, 0.10), {"emission": true, "emission_color": Color(1.0, 0.45, 0.12), "emission_energy": 5.0})
	mouth.position = Vector3(0, 0.7, 0.82)
	root.add_child(mouth)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.45, 0.14)
	l.light_energy = 2.4
	l.omni_range = 8.0
	l.position = Vector3(0, 0.9, 1.1)
	root.add_child(l)
	var pipe := MeshInstance3D.new()
	pipe.mesh = _cylinder(0.22, 0.22, 1.8)
	pipe.material_override = body.material_override
	pipe.position = Vector3(0.3, 2.9, -0.2)
	root.add_child(pipe)
	_add_collision(root, Vector3(1.8, 2.2, 1.8), Vector3(0, 1.1, 0))
	return root


## Холодильник морга.
static func morgue_drawer(pos: Vector3, parent: Node3D, open: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "MorgueDrawer"
	root.position = pos
	parent.add_child(root)
	var metal := FxFactory.mat(Color(0.70, 0.74, 0.75), {"metallic": 0.9, "roughness": 0.28})
	var shell := MeshInstance3D.new()
	shell.mesh = _box(Vector3(0.85, 0.62, 2.1))
	shell.material_override = metal
	shell.position = Vector3(0, 0, -0.55)
	root.add_child(shell)
	var tray := MeshInstance3D.new()
	tray.mesh = _box(Vector3(0.78, 0.06, 1.9))
	tray.material_override = FxFactory.mat(Color(0.80, 0.84, 0.85), {"metallic": 0.95, "roughness": 0.15})
	tray.position = Vector3(0, -0.22, 0.45 if open else -0.5)
	root.add_child(tray)
	var door := MeshInstance3D.new()
	door.name = "Door"
	door.mesh = _box(Vector3(0.85, 0.62, 0.05))
	door.material_override = metal
	door.position = Vector3(0, 0, 0.5)
	door.visible = not open
	root.add_child(door)
	var tag := MeshInstance3D.new()
	tag.mesh = _box(Vector3(0.14, 0.08, 0.01))
	tag.material_override = FxFactory.mat(Color(0.92, 0.90, 0.82), {"texture": FxFactory.paper_texture(32, false)})
	tag.position = Vector3(0.28, 0.18, 0.53)
	root.add_child(tag)
	_add_collision(root, Vector3(0.85, 0.62, 2.1), Vector3(0, 0, -0.55))
	return root


## Нарисованная мелом дверь (пролог, концовка «МЕЛ»).
static func chalk_door(pos: Vector3, parent: Node3D, rot_y: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "ChalkDoor"
	root.position = pos
	root.rotation.y = rot_y
	parent.add_child(root)
	var chalk := FxFactory.mat(Color(0.95, 0.95, 0.93), {"unshaded": true})
	var frame_pts: Array[Vector3] = []
	for i in 26:
		var t := float(i) / 25.0
		frame_pts.append(Vector3(-0.55 + t * 1.1, 2.1, 0))
	for i in 26:
		var t2 := float(i) / 25.0
		frame_pts.append(Vector3(-0.55, t2 * 2.1, 0))
		frame_pts.append(Vector3(0.55, t2 * 2.1, 0))
	for p in frame_pts:
		var seg := MeshInstance3D.new()
		seg.mesh = _box(Vector3(0.035, 0.035, 0.02))
		seg.material_override = chalk
		seg.position = p
		root.add_child(seg)
	var handle := MeshInstance3D.new()
	handle.mesh = _sphere_mesh(0.05)
	handle.material_override = chalk
	handle.position = Vector3(0.40, 1.05, 0.02)
	root.add_child(handle)
	var area := Area3D.new()
	area.name = "InteractZone"
	area.collision_layer = 128
	area.collision_mask = 2
	area.add_to_group("interactable")
	area.set_meta("prompt", "НАРИСОВАНО МЕЛОМ. ОТКРЫТЬ? [E]")
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.6
	col.shape = sh
	col.position = Vector3(0, 1.0, 0.6)
	area.add_child(col)
	root.add_child(area)
	return root


## Стойка регистратуры.
static func reception_desk(pos: Vector3, parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "ReceptionDesk"
	root.position = pos
	parent.add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = _box(Vector3(3.2, 1.1, 0.7))
	body.material_override = FxFactory.mat(Color(0.62, 0.52, 0.40), {"roughness": 0.7})
	body.position = Vector3(0, 0.55, 0)
	root.add_child(body)
	var top := MeshInstance3D.new()
	top.mesh = _box(Vector3(3.3, 0.06, 0.8))
	top.material_override = FxFactory.mat(Color(0.80, 0.82, 0.80), {"metallic": 0.3, "roughness": 0.3})
	top.position = Vector3(0, 1.12, 0)
	root.add_child(top)
	var glass := MeshInstance3D.new()
	glass.mesh = _box(Vector3(3.0, 0.9, 0.03))
	var gm := FxFactory.mat(Color(0.72, 0.84, 0.86), {"transparent": true})
	gm.albedo_color.a = 0.28
	glass.material_override = gm
	glass.position = Vector3(0, 1.62, -0.1)
	root.add_child(glass)
	for i in 6:
		var paper := MeshInstance3D.new()
		paper.mesh = _box(Vector3(0.21, 0.005, 0.30))
		paper.material_override = FxFactory.mat(Color(0.93, 0.91, 0.84), {"texture": FxFactory.paper_texture(32)})
		paper.position = Vector3(-1.3 + i * 0.5, 1.16, 0.1)
		paper.rotation.y = float(i) * 0.3
		root.add_child(paper)
	_add_collision(root, Vector3(3.2, 1.2, 0.7), Vector3(0, 0.6, 0))
	return root


## Ростовые отметки на стене детского корпуса.
static func growth_marks(pos: Vector3, parent: Node3D, rot_y: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "GrowthMarks"
	root.position = pos
	root.rotation.y = rot_y
	parent.add_child(root)
	var chalk := FxFactory.mat(Color(0.90, 0.89, 0.84), {"unshaded": true})
	for i in 12:
		var m := MeshInstance3D.new()
		m.mesh = _box(Vector3(0.16 - i * 0.004, 0.012, 0.01))
		m.material_override = chalk
		m.position = Vector3(0, 0.45 + i * 0.09, 0)
		root.add_child(m)
	return root


## Детские рисунки на стенах (главная механика мира: что Вера рисует — то и есть).
static func child_drawing(pos: Vector3, parent: Node3D, rot_y: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "ChildDrawing"
	root.position = pos
	root.rotation.y = rot_y
	parent.add_child(root)
	var img := Image.create(128, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.94, 0.92, 0.85))
	var rng := RandomNumberGenerator.new()
	rng.seed = pos.length() * 100.0 + 11
	var pencil := Color(0.25, 0.30, 0.55)
	# «домик» — то, чего у Веры никогда не было
	for i in 60:
		var x := int(34.0 + rng.randf_range(-1.0, 1.0) * 0.0 + float(i) * 0.0)
		img.set_pixel(clampi(30 + i, 30, 98), 70, pencil)
	for i in 40:
		img.set_pixel(30, 70 - i, pencil)
		img.set_pixel(98, 70 - i, pencil)
	for i in 40:
		var y: int = 30 + abs(i - 20)
		img.set_pixel(30 + i + 14, clampi(y, 20, 40), Color(0.6, 0.2, 0.2))
	# солнце
	for a in 64:
		var ang := float(a) / 64.0 * TAU
		img.set_pixel(clampi(int(106 + cos(ang) * 10), 0, 127), clampi(int(18 + sin(ang) * 10), 0, 95), Color(0.85, 0.70, 0.15))
	# две фигуры (Вера и Лида)
	for f in 2:
		var bx := 44 + f * 30
		for i in 22:
			img.set_pixel(bx, clampi(52 + i, 0, 95), pencil)
		for a2 in 40:
			var ang2 := float(a2) / 40.0 * TAU
			img.set_pixel(clampi(int(bx + cos(ang2) * 5), 0, 127), clampi(int(46 + sin(ang2) * 5), 0, 95), pencil)
	var tex := ImageTexture.create_from_image(img)
	var sheet := MeshInstance3D.new()
	sheet.mesh = _box(Vector3(0.9, 0.68, 0.01))
	var m := FxFactory.mat(Color.WHITE, {"texture": tex, "unshaded": true})
	sheet.material_override = m
	root.add_child(sheet)
	return root


# ============================================================ СЛУЖЕБНОЕ

static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cylinder(rt: float, rb: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	return c


static func _sphere_mesh(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 6
	return s


static func _add_collision(root: Node3D, size: Vector3, offset: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	col.shape = sh
	col.position = offset
	body.add_child(col)
	root.add_child(body)


## Коридор между двумя комнатами.
static func corridor(name: String, length: float, width: float, axis: String, parent: Node3D, center: Vector3) -> Node3D:
	var size := Vector2(length, width) if axis == "x" else Vector2(width, length)
	return room(name, size, ["north", "south"] if axis == "z" else ["east", "west"], parent, center)
