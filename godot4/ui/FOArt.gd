class_name FOArt
extends RefCounted
## Cached lookups of FreeOrion art by game identifiers. Returns null when the
## file doesn't exist, so callers can fall back to text.

const ART_DIR := "res://assets/art/"

static var _cache := {}


## Icon for a PlanetType name such as "PT_GASGIANT".
static func planet_type_icon(planet_type: String) -> Texture2D:
	return _icon("icons/planet/%s.png" % planet_type.trim_prefix("PT_").to_lower())


## Icon for a focus name such as "FOCUS_INDUSTRY".
static func focus_icon(focus: String) -> Texture2D:
	return _icon("icons/focus/%s.png" % focus.trim_prefix("FOCUS_").to_lower())


## Icon for a meter file name such as "pop", "industry", "research".
static func meter_icon(meter: String) -> Texture2D:
	return _icon("icons/meter/%s.png" % meter)


static func _icon(relative_path: String) -> Texture2D:
	if _cache.has(relative_path):
		return _cache[relative_path]
	var path := ART_DIR + relative_path
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[relative_path] = texture
	return texture
