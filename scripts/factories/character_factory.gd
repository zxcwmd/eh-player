class_name CharacterFactory
extends RefCounted
## Low-poly модели персонажей, собранные из примитивов (1200–2500 трисов).
## Правило арт-дирекции: у большинства NPC вместо лица — ОДНА деталь
## (очки, бейдж, маска, шов). Дешевле в производстве и страшнее.
##
## Возвращает Node3D «model_root», у которого обязательные точки:
##   Head, Torso, ArmL, ArmR, LegL, LegR, HandL, HandR, FootL, FootR, Face

const PIJAMA := Color(0.62, 0.74, 0.86)          # голубая полоска
const PIJAMA_STRIPE := Color(0.36, 0.50, 0.66)
const SKIN := Color(0.90, 0.79, 0.72)
const SKIN_PALE := Color(0.83, 0.80, 0.80)
const BANDAGE := Color(0.93, 0.92, 0.88)
const COAT := Color(0.95, 0.96, 0.95)            # идеально белый халат
const NURSE_BLUE := Color(0.35, 0.44, 0.62)
const RUST_SKIN := Color(0.62, 0.34, 0.25)

static var _pijama_tex: ImageTexture
static var _bandage_tex: ImageTexture


# ============================================================ ВЕРА

## Вера Проскурина, 12 лет. Молчит. Левая рука забинтована до плеча.
## Один глаз заклеен повязкой (она сама его выцарапала в 9 лет).
static func vera(scale_factor: float = 1.0, rust: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "VeraModel"
	var skin := SKIN if not rust else RUST_SKIN
	var pijama := PIJAMA if not rust else Color(0.42, 0.28, 0.24)

	if _pijama_tex == null:
		_pijama_tex = _striped_texture(PIJAMA, PIJAMA_STRIPE)

	var body_mat := FxFactory.mat(pijama, {"texture": _pijama_tex, "roughness": 0.92})
	var skin_mat := FxFactory.mat(skin, {"roughness": 0.85})
	var band_mat := FxFactory.mat(BANDAGE, {"roughness": 0.98})
	var hair_mat := FxFactory.mat(Color(0.24, 0.21, 0.19), {"roughness": 1.0})

	# торс
	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	torso.mesh = _box(Vector3(0.34, 0.44, 0.22))
	torso.material_override = body_mat
	torso.position = Vector3(0, 0.94, 0)
	root.add_child(torso)

	# голова (острижена под машинку)
	var head := MeshInstance3D.new()
	head.name = "Head"
	head.mesh = _sphere(0.155)
	head.material_override = skin_mat
	head.position = Vector3(0, 1.30, 0)
	root.add_child(head)

	var hair := MeshInstance3D.new()
	hair.name = "Hair"
	hair.mesh = _sphere(0.163, 10, 6, true)
	hair.material_override = hair_mat
	hair.position = Vector3(0, 1.335, -0.005)
	root.add_child(hair)

	# повязка на левом глазу
	var patch := MeshInstance3D.new()
	patch.name = "EyePatch"
	patch.mesh = _box(Vector3(0.10, 0.045, 0.02))
	patch.material_override = band_mat
	patch.position = Vector3(-0.055, 1.315, 0.145)
	root.add_child(patch)

	var strap := MeshInstance3D.new()
	strap.mesh = _box(Vector3(0.34, 0.022, 0.02))
	strap.material_override = band_mat
	strap.position = Vector3(0, 1.318, 0.14)
	root.add_child(strap)

	# правый глаз — единственный живой
	var eye := MeshInstance3D.new()
	eye.name = "Eye"
	eye.mesh = _sphere(0.022)
	eye.material_override = FxFactory.mat(Color(0.08, 0.07, 0.07), {"unshaded": true})
	eye.position = Vector3(0.055, 1.315, 0.148)
	root.add_child(eye)

	var face := Node3D.new()
	face.name = "Face"
	face.position = Vector3(0, 1.31, 0.16)
	root.add_child(face)

	# руки: правая голая, левая — бинт до плеча
	var arm_r := _limb("ArmR", Vector3(0.24, 1.10, 0), Vector3(0.085, 0.40, 0.085), skin_mat)
	var arm_l := _limb("ArmL", Vector3(-0.24, 1.10, 0), Vector3(0.085, 0.40, 0.085), band_mat)
	root.add_child(arm_r)
	root.add_child(arm_l)

	var hand_r := _limb("HandR", Vector3(0.24, 0.86, 0), Vector3(0.075, 0.09, 0.075), skin_mat)
	var hand_l := _limb("HandL", Vector3(-0.24, 0.86, 0), Vector3(0.080, 0.10, 0.080), band_mat)
	root.add_child(hand_r)
	root.add_child(hand_l)

	# скальпель в правой ладони (оружие 1 — «ПЕРЧАТКА»)
	var scalpel := MeshInstance3D.new()
	scalpel.name = "Scalpel"
	scalpel.mesh = _box(Vector3(0.018, 0.20, 0.005))
	scalpel.material_override = FxFactory.mat(Color(0.80, 0.84, 0.86), {"metallic": 0.9, "roughness": 0.18})
	scalpel.position = Vector3(0.24, 0.78, 0.05)
	scalpel.rotation = Vector3(deg_to_rad(-18.0), 0, 0)
	root.add_child(scalpel)

	# ноги + больничные тапочки на босу ногу
	var leg_r := _limb("LegR", Vector3(0.10, 0.52, 0), Vector3(0.11, 0.42, 0.11), body_mat)
	var leg_l := _limb("LegL", Vector3(-0.10, 0.52, 0), Vector3(0.11, 0.42, 0.11), body_mat)
	root.add_child(leg_r)
	root.add_child(leg_l)

	var foot_r := _limb("FootR", Vector3(0.10, 0.055, 0.05), Vector3(0.12, 0.07, 0.24), FxFactory.mat(Color(0.72, 0.75, 0.78)))
	var foot_l := _limb("FootL", Vector3(-0.10, 0.055, 0.05), Vector3(0.12, 0.07, 0.24), FxFactory.mat(Color(0.72, 0.75, 0.78)))
	root.add_child(foot_r)
	root.add_child(foot_l)

	# бинт-обмотка на левой руке (кольца)
	for i in 5:
		var ring := MeshInstance3D.new()
		ring.mesh = _box(Vector3(0.10, 0.03, 0.10))
		ring.material_override = band_mat
		ring.position = Vector3(-0.24, 1.24 - i * 0.085, 0)
		root.add_child(ring)

	root.scale = Vector3.ONE * scale_factor
	return root


## Лида — сестра-близнец. Та же модель, но забинтована ПРАВАЯ рука,
## оба глаза открыты, волосы отросли, улыбка слишком широкая.
static func lida(scale_factor: float = 1.0, rust: bool = false) -> Node3D:
	var root := vera(scale_factor, rust)
	root.name = "LidaModel"
	var band := root.get_node_or_null("ArmR")
	var skin := root.get_node_or_null("ArmL")
	if band != null and skin != null and band is MeshInstance3D and skin is MeshInstance3D:
		var b := band as MeshInstance3D
		var k := skin as MeshInstance3D
		var m1: Material = b.material_override
		var m2: Material = k.material_override
		b.material_override = m2
		k.material_override = m1
	var patch := root.get_node_or_null("EyePatch")
	if patch:
		patch.visible = false
	var eye2 := MeshInstance3D.new()
	eye2.name = "Eye2"
	eye2.mesh = _sphere(0.022)
	eye2.material_override = FxFactory.mat(Color(0.08, 0.07, 0.07), {"unshaded": true})
	eye2.position = Vector3(-0.055, 1.315, 0.148)
	root.add_child(eye2)
	# «улыбка слишком широкая»
	var smile := MeshInstance3D.new()
	smile.name = "Smile"
	smile.mesh = _box(Vector3(0.11, 0.012, 0.012))
	smile.material_override = FxFactory.mat(Color(0.32, 0.06, 0.08), {"unshaded": true})
	smile.position = Vector3(0, 1.255, 0.147)
	root.add_child(smile)
	var hair := root.get_node_or_null("Hair")
	if hair != null and hair is MeshInstance3D:
		var h := hair as MeshInstance3D
		h.scale = Vector3(1.0, 1.5, 1.05)
	return root


# ============================================================ ГОЛОСА / NPC

## Асконченский — главврач. Высокий, сутулый, идеально белый халат,
## очки с толстыми линзами, один зрачок стеклянный.
static func doctor(scale_factor: float = 1.0) -> Node3D:
	var root := _humanoid(COAT, SKIN_PALE, Color(0.20, 0.20, 0.22), 1.92, "DoctorModel")
	var glasses := MeshInstance3D.new()
	glasses.name = "Glasses"
	glasses.mesh = _box(Vector3(0.22, 0.05, 0.03))
	glasses.material_override = FxFactory.mat(Color(0.85, 0.92, 0.95), {"metallic": 0.6, "roughness": 0.1, "transparent": true})
	glasses.position = Vector3(0, 1.72 * (scale_factor), 0.15)
	glasses.material_override.albedo_color.a = 0.55
	root.add_child(glasses)
	# стеклянный зрачок
	var pupil := MeshInstance3D.new()
	pupil.name = "GlassEye"
	pupil.mesh = _sphere(0.026)
	pupil.material_override = FxFactory.mat(Color(0.88, 0.94, 0.96), {"unshaded": true})
	pupil.position = Vector3(-0.052, 1.72, 0.155)
	root.add_child(pupil)
	# сутулость
	var torso := root.get_node_or_null("Torso")
	if torso:
		torso.rotation.x = deg_to_rad(9.0)
	root.scale = Vector3.ONE * scale_factor
	return root


## Екатерина — мама. Синий халат медсестры, бейдж, красные руки от дезинфектанта.
static func mother(scale_factor: float = 1.0, in_formalin: bool = false) -> Node3D:
	var col := NURSE_BLUE
	var root := _humanoid(col, SKIN, Color(0.32, 0.20, 0.14), 1.68, "MotherModel")
	var badge := MeshInstance3D.new()
	badge.name = "Badge"
	badge.mesh = _box(Vector3(0.07, 0.045, 0.01))
	badge.material_override = FxFactory.mat(Color(0.94, 0.94, 0.90), {"unshaded": true})
	badge.position = Vector3(0.08, 1.30, 0.20)
	root.add_child(badge)
	var hands := FxFactory.mat(Color(0.82, 0.42, 0.40))
	for n in ["ArmL", "ArmR", "HandL", "HandR"]:
		var c := root.get_node_or_null(n)
		if c != null and c is MeshInstance3D:
			var cc := c as MeshInstance3D
			cc.material_override = hands
	if in_formalin:
		var jar := MeshInstance3D.new()
		jar.name = "FormalinJar"
		jar.mesh = _box(Vector3(1.5, 2.2, 1.5))
		var jm := FxFactory.mat(Color(0.62, 0.72, 0.55), {"transparent": true, "roughness": 0.05})
		jm.albedo_color.a = 0.28
		jar.material_override = jm
		jar.position = Vector3(0, 1.1, 0)
		root.add_child(jar)
	root.scale = Vector3.ONE * scale_factor
	return root


## Медсестра Швов (Галина Петровна). 3 метра, сшита из разных пациентов,
## вместо пальцев — иглы. Вместо лица — шов.
static func nurse_of_stitches(scale_factor: float = 1.0, rust: bool = false) -> Node3D:
	var skin := Color(0.78, 0.70, 0.68) if not rust else Color(0.52, 0.28, 0.22)
	var root := _humanoid(Color(0.86, 0.88, 0.87), skin, Color(0.3, 0.24, 0.2), 3.0, "NurseModel")
	# шов через всё лицо
	var seam := MeshInstance3D.new()
	seam.name = "Seam"
	seam.mesh = _box(Vector3(0.025, 0.30, 0.02))
	seam.material_override = FxFactory.mat(Color(0.35, 0.08, 0.10), {"unshaded": true})
	seam.position = Vector3(0, 1.62, 0.20)
	root.add_child(seam)
	# стежки
	for i in 7:
		var st := MeshInstance3D.new()
		st.mesh = _box(Vector3(0.10, 0.012, 0.012))
		st.material_override = FxFactory.mat(Color(0.22, 0.06, 0.07))
		st.position = Vector3(0, 1.50 + i * 0.042, 0.205)
		root.add_child(st)
	# иглы вместо пальцев
	for side in [-1.0, 1.0]:
		for i in 5:
			var needle := MeshInstance3D.new()
			needle.mesh = _box(Vector3(0.014, 0.44, 0.014))
			needle.material_override = FxFactory.mat(Color(0.85, 0.87, 0.88), {"metallic": 0.95, "roughness": 0.12})
			needle.position = Vector3(side * 0.42 + (i - 2) * 0.035, 0.62, 0.05 + i * 0.02)
			needle.rotation.z = deg_to_rad(side * (6.0 + i * 2.0))
			root.add_child(needle)
	# заплатки из чужой кожи
	for i in 5:
		var patch := MeshInstance3D.new()
		patch.mesh = _box(Vector3(0.24, 0.20, 0.02))
		patch.material_override = FxFactory.mat(Color(0.66, 0.52, 0.48), {"roughness": 1.0})
		patch.position = Vector3(-0.20 + i * 0.10, 1.05 + (i % 3) * 0.16, 0.19)
		patch.rotation.z = deg_to_rad(i * 17.0)
		root.add_child(patch)
	root.scale = Vector3.ONE * scale_factor
	return root


## Сантар Семён. 2.5 м, носилки вместо щита. Тупой, добрый, исполняет приказы.
static func orderly(scale_factor: float = 1.0, rust: bool = false) -> Node3D:
	var root := _humanoid(Color(0.44, 0.52, 0.48), Color(0.80, 0.68, 0.62) if not rust else RUST_SKIN, Color(0.2, 0.17, 0.15), 2.5, "OrderlyModel")
	var stretcher := MeshInstance3D.new()
	stretcher.name = "Shield"
	stretcher.mesh = _box(Vector3(0.90, 1.90, 0.08))
	stretcher.material_override = FxFactory.mat(Color(0.72, 0.74, 0.72), {"metallic": 0.5, "roughness": 0.4})
	stretcher.position = Vector3(0.60, 1.15, 0.35)
	stretcher.rotation.y = deg_to_rad(-22.0)
	root.add_child(stretcher)
	var cap := MeshInstance3D.new()
	cap.mesh = _box(Vector3(0.30, 0.06, 0.30))
	cap.material_override = FxFactory.mat(Color(0.90, 0.92, 0.90))
	cap.position = Vector3(0, 1.66, 0)
	root.add_child(cap)
	root.scale = Vector3.ONE * scale_factor
	return root


## Хирург без лица. Марлевая маска, под ней — ещё одна маска.
static func surgeon(scale_factor: float = 1.0) -> Node3D:
	var root := _humanoid(Color(0.42, 0.66, 0.60), Color(0.84, 0.78, 0.76), Color(0.24, 0.22, 0.2), 1.86, "SurgeonModel")
	for i in 4:
		var mask := MeshInstance3D.new()
		mask.name = "Mask%d" % i
		mask.mesh = _box(Vector3(0.24 - i * 0.03, 0.18 - i * 0.02, 0.03))
		mask.material_override = FxFactory.mat(Color(0.88 - i * 0.12, 0.90 - i * 0.12, 0.88 - i * 0.12))
		mask.position = Vector3(0, 1.66, 0.16 + i * 0.028)
		root.add_child(mask)
	var lamp := MeshInstance3D.new()
	lamp.name = "HeadLamp"
	lamp.mesh = _sphere(0.05)
	lamp.material_override = FxFactory.mat(Color(1, 0.98, 0.8), {"emission": true, "emission_color": Color(1, 0.97, 0.82), "emission_energy": 4.0})
	lamp.position = Vector3(0, 1.82, 0.12)
	root.add_child(lamp)
	root.scale = Vector3.ONE * scale_factor
	return root


## Иваныч — кочегар. Обожжённый, с кочергой. Единственный добрый персонаж.
static func ivanich(scale_factor: float = 1.0) -> Node3D:
	var root := _humanoid(Color(0.30, 0.26, 0.24), Color(0.52, 0.30, 0.24), Color(0.62, 0.60, 0.58), 1.80, "IvanichModel")
	var poker := MeshInstance3D.new()
	poker.name = "Poker"
	poker.mesh = _box(Vector3(0.04, 1.30, 0.04))
	poker.material_override = FxFactory.mat(Color(0.22, 0.20, 0.19), {"metallic": 0.8, "roughness": 0.5})
	poker.position = Vector3(0.34, 0.95, 0.10)
	poker.rotation.z = deg_to_rad(12.0)
	root.add_child(poker)
	var hook := MeshInstance3D.new()
	hook.mesh = _box(Vector3(0.20, 0.04, 0.04))
	hook.material_override = poker.material_override
	hook.position = Vector3(0.44, 1.58, 0.10)
	root.add_child(hook)
	# ожоги
	for i in 6:
		var burn := MeshInstance3D.new()
		burn.mesh = _sphere(0.06 + i * 0.01)
		burn.material_override = FxFactory.mat(Color(0.24, 0.11, 0.09), {"roughness": 1.0})
		burn.position = Vector3(-0.16 + i * 0.06, 0.9 + (i % 3) * 0.2, 0.19)
		root.add_child(burn)
	root.scale = Vector3.ONE * scale_factor
	return root


## СЕДЫЕ — бывшие пациенты в смирительных рубашках. Бегут толпой, взрываются.
static func sedoy(scale_factor: float = 1.0, rust: bool = false) -> Node3D:
	var jacket := Color(0.88, 0.87, 0.82) if not rust else Color(0.50, 0.36, 0.28)
	var root := _humanoid(jacket, Color(0.72, 0.66, 0.64), Color(0.75, 0.75, 0.74), 1.60, "SedoyModel")
	# длинные пустые рукава, скрещённые на груди
	for side in [-1.0, 1.0]:
		var sleeve := MeshInstance3D.new()
		sleeve.mesh = _box(Vector3(0.11, 0.62, 0.11))
		sleeve.material_override = FxFactory.mat(jacket, {"roughness": 0.95})
		sleeve.position = Vector3(side * 0.10, 1.16, 0.20)
		sleeve.rotation.z = deg_to_rad(side * 58.0)
		root.add_child(sleeve)
	var buckle := MeshInstance3D.new()
	buckle.mesh = _box(Vector3(0.10, 0.10, 0.03))
	buckle.material_override = FxFactory.mat(Color(0.55, 0.56, 0.54), {"metallic": 0.7})
	buckle.position = Vector3(0, 1.20, 0.26)
	root.add_child(buckle)
	root.scale = Vector3.ONE * scale_factor
	return root


## ХОР — дети, поющие одну ноту. Все они предыдущие Веры.
static func chorister(scale_factor: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "ChoristerModel"
	var body := MeshInstance3D.new()
	body.name = "Torso"
	body.mesh = _sphere(0.22)
	body.material_override = FxFactory.mat(Color(0.90, 0.90, 0.88), {"transparent": true})
	body.material_override.albedo_color.a = 0.72
	root.add_child(body)
	var mouth := MeshInstance3D.new()
	mouth.name = "Mouth"
	mouth.mesh = _sphere(0.11)
	mouth.material_override = FxFactory.mat(Color(0.05, 0.02, 0.03), {"unshaded": true})
	mouth.position = Vector3(0, 0.04, 0.16)
	root.add_child(mouth)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.2, 0)
	root.add_child(head)
	root.scale = Vector3.ONE * scale_factor
	return root


## ЗЕРКАЛО — точная копия Веры, но без повязки на глазу.
static func mirror_vera(scale_factor: float = 1.0) -> Node3D:
	var root := vera(scale_factor, false)
	root.name = "MirrorModel"
	var patch := root.get_node_or_null("EyePatch")
	if patch:
		patch.visible = false
	var eye2 := MeshInstance3D.new()
	eye2.mesh = _sphere(0.022)
	eye2.material_override = FxFactory.mat(Color(1.0, 0.95, 0.9), {"unshaded": true})
	eye2.position = Vector3(-0.055, 1.315, 0.148)
	root.add_child(eye2)
	_apply_mirror_material(root)
	return root


static func _apply_mirror_material(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.material_override = FxFactory.mat(Color(0.78, 0.85, 0.88), {"metallic": 1.0, "roughness": 0.06})
	for c in n.get_children():
		_apply_mirror_material(c)


## Библиотекарь Пелагея — из 40 000 склеенных страниц.
static func librarian(scale_factor: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "LibrarianModel"
	var paper := FxFactory.mat(Color(0.90, 0.88, 0.80), {"roughness": 1.0, "texture": FxFactory.paper_texture(64)})
	var rng := RandomNumberGenerator.new()
	rng.seed = 40000
	for i in 46:
		var sheet := MeshInstance3D.new()
		sheet.mesh = _box(Vector3(rng.randf_range(0.20, 0.62), 0.012, rng.randf_range(0.28, 0.50)))
		sheet.material_override = paper
		sheet.position = Vector3(rng.randf_range(-0.35, 0.35), 0.20 + i * 0.035, rng.randf_range(-0.25, 0.25))
		sheet.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-1.5, 1.5), rng.randf_range(-0.2, 0.2))
		root.add_child(sheet)
	var head := MeshInstance3D.new()
	head.name = "Head"
	head.mesh = _sphere(0.19)
	head.material_override = paper
	head.position = Vector3(0.06, 1.92, 0)
	root.add_child(head)
	var torso := Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0, 1.1, 0)
	root.add_child(torso)
	root.scale = Vector3.ONE * scale_factor
	return root


# ============================================================ ОБЩЕЕ

## Базовый гуманоид с обязательными точками скелета.
static func _humanoid(cloth: Color, skin: Color, hair: Color, height: float, model_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = model_name
	var k := height / 1.72
	var cloth_mat := FxFactory.mat(cloth, {"roughness": 0.9})
	var skin_mat := FxFactory.mat(skin, {"roughness": 0.85})
	var hair_mat := FxFactory.mat(hair, {"roughness": 1.0})

	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	torso.mesh = _box(Vector3(0.44 * k, 0.70 * k, 0.28 * k))
	torso.material_override = cloth_mat
	torso.position = Vector3(0, 1.05 * k, 0)
	root.add_child(torso)

	var head := MeshInstance3D.new()
	head.name = "Head"
	head.mesh = _sphere(0.18 * k)
	head.material_override = skin_mat
	head.position = Vector3(0, 1.62 * k, 0)
	root.add_child(head)

	var hairm := MeshInstance3D.new()
	hairm.mesh = _sphere(0.187 * k, 10, 6, true)
	hairm.material_override = hair_mat
	hairm.position = Vector3(0, 1.66 * k, -0.01)
	root.add_child(hairm)

	root.add_child(_limb("ArmL", Vector3(-0.31 * k, 1.18 * k, 0), Vector3(0.11 * k, 0.62 * k, 0.11 * k), cloth_mat))
	root.add_child(_limb("ArmR", Vector3(0.31 * k, 1.18 * k, 0), Vector3(0.11 * k, 0.62 * k, 0.11 * k), cloth_mat))
	root.add_child(_limb("HandL", Vector3(-0.31 * k, 0.80 * k, 0), Vector3(0.10 * k, 0.12 * k, 0.10 * k), skin_mat))
	root.add_child(_limb("HandR", Vector3(0.31 * k, 0.80 * k, 0), Vector3(0.10 * k, 0.12 * k, 0.10 * k), skin_mat))
	root.add_child(_limb("LegL", Vector3(-0.13 * k, 0.40 * k, 0), Vector3(0.15 * k, 0.72 * k, 0.15 * k), cloth_mat))
	root.add_child(_limb("LegR", Vector3(0.13 * k, 0.40 * k, 0), Vector3(0.15 * k, 0.72 * k, 0.15 * k), cloth_mat))
	root.add_child(_limb("FootL", Vector3(-0.13 * k, 0.05 * k, 0.05), Vector3(0.16 * k, 0.09 * k, 0.30 * k), FxFactory.mat(Color(0.2, 0.2, 0.2))))
	root.add_child(_limb("FootR", Vector3(0.13 * k, 0.05 * k, 0.05), Vector3(0.16 * k, 0.09 * k, 0.30 * k), FxFactory.mat(Color(0.2, 0.2, 0.2))))
	return root


static func _limb(node_name: String, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = node_name
	m.mesh = _box(size)
	m.material_override = material
	m.position = pos
	return m


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _sphere(radius: float, rings: int = 12, sectors: int = 8, upper_only: bool = false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius if upper_only else radius * 2.0
	s.radial_segments = sectors
	s.rings = rings
	return s


## Текстура пижамы в голубую полоску.
static func _striped_texture(a: Color, b: Color, size: int = 64) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var stripe := int(float(x) / 8.0) % 2 == 0
			var c := a if stripe else b
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Каталог моделей по id — используется спавнером врагов и VN-портретами.
static func build(kind: String, rust: bool = false) -> Node3D:
	match kind:
		"vera":       return vera()
		"lida":       return lida()
		"doctor":     return doctor()
		"mother":     return mother(1.0, false)
		"mother_jar": return mother(1.0, true)
		"nurse":      return nurse_of_stitches(1.0, rust)
		"orderly":    return orderly(1.0, rust)
		"surgeon":    return surgeon()
		"ivanich":    return ivanich()
		"sedoy":      return sedoy(1.0, rust)
		"chorister":  return chorister()
		"mirror":     return mirror_vera()
		"librarian":  return librarian()
	return vera()
