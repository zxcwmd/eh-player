class_name FxFactory
extends RefCounted
## Процедурные материалы и текстуры. В проекте нет ни одного импортированного
## ассета — всё генерируется кодом (PS1-эстетика: vertex-color + маткап).

static func mat(color: Color, opts: Dictionary = {}) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.vertex_color_use_as_albedo = true
	m.roughness = float(opts.get("roughness", 0.78))
	m.metallic = float(opts.get("metallic", 0.02))
	if opts.get("unshaded", false):
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if opts.get("emission", false):
		m.emission_enabled = true
		m.emission = Color(opts.get("emission_color", color))
		m.emission_energy_multiplier = float(opts.get("emission_energy", 1.6))
	if opts.get("transparent", false):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if opts.get("cull_disabled", false):
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if opts.get("billboard", false):
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.particles_anim_h_frames = 1
		m.particles_anim_v_frames = 1
		m.particles_anim_loop = false
	if opts.has("texture"):
		m.albedo_texture = opts["texture"]
	return m


static func noise_texture(size: int, seedv: int, contrast: float, tint: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seedv
	for y in size:
		for x in size:
			var n := rng.randf()
			n = pow(absf(n * 2.0 - 1.0), contrast)
			img.set_pixel(x, y, Color(tint.r * n, tint.g * n, tint.b * n, 1.0))
	return ImageTexture.create_from_image(img)


## Кафель приёмного отделения: белые квадраты, тёмная затирка, трещины.
static func tile_texture(size: int = 256, tiles: int = 8, base := Color(0.90, 0.93, 0.91), grout := Color(0.42, 0.48, 0.46)) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var cell := float(size) / float(tiles)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1993
	for y in size:
		for x in size:
			var fx := fmod(float(x), cell)
			var fy := fmod(float(y), cell)
			var c: Color
			if fx < 2.0 or fy < 2.0:
				c = grout
			else:
				var d := rng.randf_range(-0.035, 0.035)
				c = Color(base.r + d, base.g + d, base.b + d)
			img.set_pixel(x, y, c)
	# трещины
	for i in 6:
		var cx := rng.randi_range(0, size - 1)
		var cy := rng.randi_range(0, size - 1)
		for s in 40:
			cx = clampi(cx + rng.randi_range(-2, 2), 0, size - 1)
			cy = clampi(cy + rng.randi_range(-1, 2), 0, size - 1)
			img.set_pixel(cx, cy, Color(0.25, 0.27, 0.26))
	return ImageTexture.create_from_image(img)


## Линолеум в крапинку (детский корпус).
static func linoleum_texture(size: int = 256, base := Color(0.55, 0.62, 0.58)) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4141
	for y in size:
		for x in size:
			var n := rng.randf()
			var d: float = (n - 0.5) * 0.16
			var c := Color(base.r + d, base.g + d, base.b + d)
			if n > 0.985:
				c = Color(0.28, 0.30, 0.29)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Ржавое мясо (ржавый слой).
static func rust_texture(size: int = 256) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20170314
	for y in size:
		for x in size:
			var n := rng.randf()
			var v := pow(n, 1.7)
			img.set_pixel(x, y, Color(0.18 + v * 0.62, 0.07 + v * 0.24, 0.05 + v * 0.11))
	return ImageTexture.create_from_image(img)


## Лист бумаги (анамнез, записки, картотека).
static func paper_texture(size: int = 128, lines: bool = true) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for y in size:
		for x in size:
			var n := rng.randf_range(-0.03, 0.03)
			var c := Color(0.93 + n, 0.91 + n, 0.84 + n)
			if lines and int(float(y) / (size / 14.0)) % 2 == 1 and y % int(size / 14.0) < 1:
				c = Color(0.55, 0.62, 0.72)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Портрет-заглушка: силуэт на фоне. Используется VN-боксом, пока нет PNG.
static func portrait_placeholder(size: int, bg: Color, fg: Color, kind: String) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	var c := Vector2(size * 0.5, size * 0.55)
	var r_head := size * 0.16
	var r_body := size * 0.30
	for y in size:
		for x in size:
			var p := Vector2(x, y)
			var in_head := p.distance_to(Vector2(c.x, c.y - size * 0.20)) < r_head
			var in_body := p.distance_to(Vector2(c.x, c.y + size * 0.22)) < r_body and p.y > c.y
			if in_head or in_body:
				img.set_pixel(x, y, fg)
	match kind:
		"doctor":
			for x in range(int(size * 0.30), int(size * 0.70)):
				for y in range(int(size * 0.30), int(size * 0.34)):
					img.set_pixel(x, y, Color(1, 1, 1))
		"mother":
			for x in range(int(size * 0.34), int(size * 0.66)):
				for y in range(int(size * 0.44), int(size * 0.46)):
					img.set_pixel(x, y, Color(0.85, 0.85, 0.9))
		"sister":
			for x in range(int(size * 0.36), int(size * 0.64)):
				for y in range(int(size * 0.36), int(size * 0.40)):
					img.set_pixel(x, y, Color(0.15, 0.05, 0.05))
	return ImageTexture.create_from_image(img)
