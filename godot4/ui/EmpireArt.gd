class_name EmpireArt
extends RefCounted
## Art for empires and species: each empire's flag, composed from GG's flag
## art (a field shape in the empire's colour with an emblem on it, both picked
## from its name, so every player sees the same flag), and species portraits
## (the large painting where there is one, else the species icon).

const FLAG_DIR := "res://assets/art/icons/flags/"
const PORTRAIT_DIR := "species/"

static var _flags := {}
static var _fields: PackedStringArray = []
static var _emblems: PackedStringArray = []


## The flag of the empire called \a empire_name in \a color, \a size px.
static func flag(empire_name: String, color: Color, size: int) -> Texture2D:
	var key := "%s|%s|%d" % [empire_name, color.to_html(), size]
	if _flags.has(key):
		return _flags[key]
	_load_parts()
	if _fields.is_empty() or _emblems.is_empty():
		return null
	var h := absi(empire_name.hash())
	var field := _mask(FLAG_DIR + "field/" + _fields[h % _fields.size()], size)
	var emblem_size := roundi(size * 0.58)
	var emblem := _mask(FLAG_DIR + "emblem/" + _emblems[(h / 7) % _emblems.size()], emblem_size)
	if field == null or emblem == null:
		return null
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var body := Color(color, 1.0).darkened(0.15)
	var rim := Color(color, 1.0).lightened(0.35)
	var mark := Color(color, 1.0).lightened(0.75)
	var offset := Vector2i((size - emblem.get_width()) / 2, (size - emblem.get_height()) / 2)
	for y in size:
		for x in size:
			var a := field.get_pixel(x, y).a
			if a <= 0.0:
				continue
			# A lighter rim where the field's edge is.
			var inner := minf(
				minf(_alpha(field, x - 2, y), _alpha(field, x + 2, y)),
				minf(_alpha(field, x, y - 2), _alpha(field, x, y + 2))
			)
			var c := rim.lerp(body, inner)
			var e := _alpha(emblem, x - offset.x, y - offset.y)
			c = c.lerp(mark, e)
			image.set_pixel(x, y, Color(c, a))
	var texture := ImageTexture.create_from_image(image)
	_flags[key] = texture
	return texture


## A portrait for species \a species ("SP_ABADDONI"): its painting if there
## is one, else \a graphic (its icon, as the game data names it).
static func species_portrait(species: String, graphic := "") -> Texture2D:
	var painting := FOArt.icon(PORTRAIT_DIR + species.trim_prefix("SP_").to_lower() + ".png")
	if painting:
		return painting
	if not graphic.is_empty():
		return FOArt.icon(graphic)
	return FOArt.icon("icons/species/" + species.trim_prefix("SP_").to_lower() + ".png")


static func _load_parts() -> void:
	if not _fields.is_empty():
		return
	for part in ["field", "emblem"]:
		var names := PackedStringArray()
		var dir := DirAccess.open(FLAG_DIR + part)
		if dir == null:
			continue
		for file in dir.get_files():
			# Exported builds list the imported names.
			var name := file.trim_suffix(".import")
			if name.ends_with(".png") and not names.has(name):
				names.push_back(name)
		names.sort()
		if part == "field":
			_fields = names
		else:
			_emblems = names


# The alpha mask at \a path, fitted into \a size px (aspect kept).
static func _mask(path: String, size: int) -> Image:
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if texture == null:
		return null
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var scale := float(size) / maxf(image.get_width(), image.get_height())
	image.resize(
		maxi(1, roundi(image.get_width() * scale)),
		maxi(1, roundi(image.get_height() * scale)),
		Image.INTERPOLATE_LANCZOS
	)
	return image


static func _alpha(image: Image, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return 0.0
	return image.get_pixel(x, y).a
