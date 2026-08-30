class_name TexFactory
## Procedural texture factory: colored albedo + generated normal maps,
## all runtime-built, no external assets (PRD §9 web-light).
## Each maker returns {"a": albedo ImageTexture, "n": normal ImageTexture}.

static func _noise(seed_v: int, freq: float, octaves: int,
		ntype := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = ntype
	n.frequency = freq
	n.fractal_octaves = octaves
	return n

static func _tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func _normal(height: Image, strength: float) -> ImageTexture:
	var b: Image = height.duplicate()
	b.bump_map_to_normal_map(strength)
	b.generate_mipmaps()
	return ImageTexture.create_from_image(b)

static func _new_rgb(s: Vector2i) -> Image:
	return Image.create(s.x, s.y, false, Image.FORMAT_RGB8)

## Two-tone carpet tiles with fiber speckle. Mean brightness ~0.21.
static func carpet() -> Dictionary:
	var s := 128
	var n := _noise(7, 0.16, 4)
	var img := _new_rgb(Vector2i(s, s))
	var hgt := _new_rgb(Vector2i(s, s))
	var a := Color(0.185, 0.20, 0.235)
	var b := Color(0.235, 0.25, 0.30)
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	for y in s:
		for x in s:
			var v := clampf(n.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, a.lerp(b, v))
			var h := 0.5 + (v - 0.5) * 0.5
			hgt.set_pixel(x, y, Color(h, h, h))
	for i in 420:
		var x := rng.randi_range(0, s - 1)
		var y := rng.randi_range(0, s - 1)
		img.set_pixel(x, y, Color(0.30, 0.32, 0.38))
	for i in [0, s / 2]:
		img.fill_rect(Rect2i(i, 0, 2, s), Color(0.145, 0.15, 0.17))
		img.fill_rect(Rect2i(0, i, s, 2), Color(0.145, 0.15, 0.17))
		hgt.fill_rect(Rect2i(i, 0, 2, s), Color(0.30, 0.30, 0.30))
		hgt.fill_rect(Rect2i(0, i, s, 2), Color(0.30, 0.30, 0.30))
	return {"a": _tex(img), "n": _normal(hgt, 3.0)}

## Plaster wall panels: per-panel tint, vertical seams, dark baseboard.
## Mean ~0.31; image row 0 sits at the floor line (uv1_scale.y = 1/wall_h).
static func wall(wall_h: float) -> Dictionary:
	var s := 128
	var n := _noise(11, 0.05, 3)
	var img := _new_rgb(Vector2i(s, s))
	var hgt := _new_rgb(Vector2i(s, s))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var panel_tint: Array = []
	for x in s:
		if x % 43 == 0:
			panel_tint.append(rng.randf_range(0.95, 1.05))
	for y in s:
		for x in s:
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var tint: float = panel_tint[x / 43]
			var base := 0.315 * (0.94 + v * 0.12) * tint
			img.set_pixel(x, y, Color(base, base, base * 1.05))
			var h := 0.5 + (v - 0.5) * 0.25
			hgt.set_pixel(x, y, Color(h, h, h))
	var base_px := int(0.16 / wall_h * s)
	img.fill_rect(Rect2i(0, 0, s, base_px), Color(0.09, 0.09, 0.10))
	img.fill_rect(Rect2i(0, base_px, s, 1), Color(0.15, 0.15, 0.16))
	hgt.fill_rect(Rect2i(0, 0, s, base_px), Color(0.65, 0.65, 0.65))
	for x in range(0, s, 43):
		img.fill_rect(Rect2i(x, base_px, 1, s - base_px), Color(0.22, 0.22, 0.24))
		hgt.fill_rect(Rect2i(x, base_px, 1, s - base_px), Color(0.35, 0.35, 0.35))
	return {"a": _tex(img), "n": _normal(hgt, 2.5)}

## Acoustic ceiling tiles with T-bar seams. Mean ~0.21.
static func ceiling() -> Dictionary:
	var s := 128
	var n := _noise(23, 0.55, 2)
	var img := _new_rgb(Vector2i(s, s))
	var hgt := _new_rgb(Vector2i(s, s))
	for y in s:
		for x in s:
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var base := 0.21 * (0.9 + v * 0.25)
			img.set_pixel(x, y, Color(base, base, base * 1.04))
			var h := 0.5 + (v - 0.5) * 0.3
			hgt.set_pixel(x, y, Color(h, h, h))
	for i in [0, s / 2]:
		img.fill_rect(Rect2i(i, 0, 3, s), Color(0.10, 0.10, 0.11))
		img.fill_rect(Rect2i(0, i, s, 3), Color(0.10, 0.10, 0.11))
		hgt.fill_rect(Rect2i(i, 0, 3, s), Color(0.2, 0.2, 0.2))
		hgt.fill_rect(Rect2i(0, i, s, 3), Color(0.2, 0.2, 0.2))
	return {"a": _tex(img), "n": _normal(hgt, 2.0)}

## Wood with warped grain rings. Mean ~0.30.
static func wood() -> Dictionary:
	var w := 256
	var h := 64
	var warp := _noise(31, 0.06, 3)
	var fine := _noise(33, 0.5, 2)
	var img := _new_rgb(Vector2i(w, h))
	var hgt := _new_rgb(Vector2i(w, h))
	var dark := Color(0.24, 0.165, 0.10)
	var light := Color(0.37, 0.27, 0.17)
	for y in h:
		for x in w:
			var ring := 0.5 + 0.5 * sin(x * 0.30 + warp.get_noise_2d(x, y * 3) * 6.0)
			var f := fine.get_noise_2d(x, y) * 0.04
			var c := dark.lerp(light, ring)
			img.set_pixel(x, y, Color(c.r + f, c.g + f, c.b + f))
			var hv := 0.5 + (ring - 0.5) * 0.4
			hgt.set_pixel(x, y, Color(hv, hv, hv))
	return {"a": _tex(img), "n": _normal(hgt, 2.0)}

## Cubicle fabric: woven cross-hatch. Mean ~0.30.
static func fabric() -> Dictionary:
	var s := 96
	var n := _noise(43, 0.45, 2)
	var img := _new_rgb(Vector2i(s, s))
	var hgt := _new_rgb(Vector2i(s, s))
	for y in s:
		for x in s:
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var weave := 0.03 if (x / 2 + y / 2) % 2 == 0 else -0.03
			var base := 0.29 * (0.92 + v * 0.16) + weave * 0.3
			img.set_pixel(x, y, Color(base * 0.95, base, base * 1.22))
			var hv := 0.5 + weave * 2.0
			hgt.set_pixel(x, y, Color(hv, hv, hv))
	return {"a": _tex(img), "n": _normal(hgt, 1.5)}

## Painted / brushed metal: vertical streaks. Mean ~0.28.
static func metal() -> Dictionary:
	var n := _noise(53, 0.15, 3, FastNoiseLite.TYPE_VALUE)
	var img := _new_rgb(Vector2i(32, 256))
	for y in 256:
		for x in 32:
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var base := 0.28 * (0.92 + v * 0.16)
			img.set_pixel(x, y, Color(base, base * 1.02, base * 1.06))
	return {"a": _tex(img), "n": null}

## Night-city window: dark blue gradient with scattered distant lights.
static func night_window() -> ImageTexture:
	var img := _new_rgb(Vector2i(64, 64))
	for y in 64:
		var t := float(y) / 63.0
		var c := Color(0.02, 0.04, 0.09).lerp(Color(0.07, 0.10, 0.18), t)
		for x in 64:
			img.set_pixel(x, y, c)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 46:
		var x := rng.randi_range(1, 62)
		var y := rng.randi_range(30, 62)
		var warm := rng.randf() < 0.6
		img.set_pixel(x, y, Color(0.95, 0.78, 0.42) if warm else Color(0.55, 0.72, 0.95))
	return _tex(img)

## Muted corporate poster (abstract blocks), tinted per instance.
static func poster(seed_v: int) -> ImageTexture:
	var img := _new_rgb(Vector2i(48, 64))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var palettes := [
		[Color(0.20, 0.30, 0.32), Color(0.55, 0.60, 0.55), Color(0.75, 0.60, 0.30)],
		[Color(0.30, 0.24, 0.30), Color(0.60, 0.50, 0.45), Color(0.35, 0.50, 0.60)],
		[Color(0.24, 0.28, 0.38), Color(0.65, 0.65, 0.60), Color(0.60, 0.35, 0.30)],
	]
	var pal: Array = palettes[rng.randi_range(0, palettes.size() - 1)]
	img.fill(pal[0])
	for i in rng.randi_range(3, 6):
		var w := rng.randi_range(8, 30)
		var h := rng.randi_range(4, 20)
		img.fill_rect(Rect2i(rng.randi_range(0, 47 - w), rng.randi_range(0, 63 - h), w, h),
			pal[rng.randi_range(1, 2)] * rng.randf_range(0.7, 1.1))
	img.fill_rect(Rect2i(0, 54, 48, 2), pal[1] * 0.6)
	img.fill_rect(Rect2i(4, 58, 24, 2), pal[1] * 0.8)
	return _tex(img)
