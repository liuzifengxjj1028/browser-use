class_name TexFactory
## Procedural placeholder textures (no external assets, PRD §9 web-light).
## All textures are near-mid-grey; hue and brightness come from the
## material's albedo_color, which multiplies the texture.

static func _noise_img(seed_v: int, freq: float, octaves: int, size: Vector2i,
		ntype := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = ntype
	n.frequency = freq
	n.fractal_octaves = octaves
	# normalize=false keeps values clustered around mid-grey (soft mottle)
	var img := n.get_image(size.x, size.y, false, false, false)
	img.convert(Image.FORMAT_RGB8)
	return img

static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)

## Compress the noise toward mid-grey so surfaces read as subtle mottle,
## not static. strength 0.1 = barely visible, 0.3 = pronounced grain.
static func _soften(img: Image, strength: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var v := 0.5 + (img.get_pixel(x, y).r - 0.5) * strength
			img.set_pixel(x, y, Color(v, v, v))

## Office carpet tiles: soft mottle + dark seams every half texture (1 m).
static func carpet() -> ImageTexture:
	var s := 128
	var img := _noise_img(7, 0.16, 4, Vector2i(s, s))
	_soften(img, 0.16)
	for i in [0, s / 2]:
		img.fill_rect(Rect2i(i, 0, 2, s), Color(0.41, 0.41, 0.43))
		img.fill_rect(Rect2i(0, i, s, 2), Color(0.41, 0.41, 0.43))
	return _tex(img)

## Plaster wall panels: vertical seams + dark baseboard at world y≈0.
## Mapped triplanar with uv1_scale.y = 1/wall_height so image row 0 sits
## at the floor line.
static func wall(wall_h: float) -> ImageTexture:
	var s := 128
	var img := _noise_img(11, 0.05, 3, Vector2i(s, s))
	_soften(img, 0.09)
	var base_px := int(0.16 / wall_h * s)  # 16 cm baseboard
	img.fill_rect(Rect2i(0, 0, s, base_px), Color(0.22, 0.22, 0.24))
	img.fill_rect(Rect2i(0, base_px, s, 1), Color(0.30, 0.30, 0.32))
	for x in range(0, s, 43):
		img.fill_rect(Rect2i(x, base_px, 1, s - base_px), Color(0.42, 0.42, 0.44))
	return _tex(img)

## Suspended-ceiling acoustic tiles with dark T-bar seams.
static func ceiling() -> ImageTexture:
	var s := 128
	var img := _noise_img(23, 0.30, 2, Vector2i(s, s))
	_soften(img, 0.20)
	for i in [0, s / 2]:
		img.fill_rect(Rect2i(i, 0, 3, s), Color(0.25, 0.25, 0.27))
		img.fill_rect(Rect2i(0, i, s, 3), Color(0.25, 0.25, 0.27))
	return _tex(img)

## Wood grain: anisotropic noise, stretched further by the material uv scale.
static func wood() -> ImageTexture:
	var img := _noise_img(31, 0.22, 5, Vector2i(256, 64), FastNoiseLite.TYPE_VALUE)
	_soften(img, 0.28)
	return _tex(img)

## Cubicle fabric: fine high-frequency weave.
static func fabric() -> ImageTexture:
	var img := _noise_img(43, 0.45, 2, Vector2i(96, 96))
	_soften(img, 0.14)
	return _tex(img)

## Painted / brushed metal: subtle vertical streaks.
static func metal() -> ImageTexture:
	var img := _noise_img(53, 0.15, 3, Vector2i(32, 256), FastNoiseLite.TYPE_VALUE)
	_soften(img, 0.12)
	return _tex(img)
