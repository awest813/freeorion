class_name MapAmbience
extends RefCounted
## The living look of GalaxyMap (premium phase 1): stars with hot cores that
## twinkle, territories with crisp borders, nebulae drifting behind the
## galaxy at a slower pace than it (parallax), and, zoomed out, each empire's
## name over its territory in the display face. Reduced motion stills the
## twinkle.

const STAR_SHADER := preload("res://map/shaders/star_twinkle.gdshader")
const TERRITORY_SHADER := preload("res://map/shaders/territory.gdshader")
## Nebula art (art/nebulae/nebulaN.png, N from 1).
const NEBULA_COUNT := 20
## How many nebulae lie behind a galaxy, and how fast they follow the camera.
const NEBULAE := 9
const PARALLAX := 0.45
const NEBULA_ALPHA := 0.38
## Empire names: least supplied systems for a name, and its size on screen.
const NAME_MIN_SYSTEMS := 3
const NAME_PX_MIN := 18.0
const NAME_PX_MAX := 46.0

var star_material := ShaderMaterial.new()
var territory_material := ShaderMaterial.new()
## Supplied systems' owners, by the map's supply system order.
var supply_owners := PackedInt32Array()

var _backdrop: CanvasLayer
var _nebula_root: Node2D
var _names := {}
var _name_font: Font


## Give \a map's stars and territories their shaders and add the backdrop
## behind it (in \a map's viewport).
func setup(map: GalaxyMap, stars: CanvasItem, territories: CanvasItem) -> void:
	star_material.shader = STAR_SHADER
	star_material.set_shader_parameter("twinkle", 0.0 if FOUi.reduce_motion else 0.14)
	stars.material = star_material
	territory_material.shader = TERRITORY_SHADER
	territories.material = territory_material
	_backdrop = CanvasLayer.new()
	_backdrop.name = "Nebulae"
	_backdrop.layer = -1
	_backdrop.follow_viewport_enabled = true
	_backdrop.follow_viewport_scale = PARALLAX
	_nebula_root = Node2D.new()
	_backdrop.add_child(_nebula_root)
	map.get_parent().add_child.call_deferred(_backdrop)
	if FOUi.tokens:
		_name_font = FOThemeBuilder.display_font(FOUi.tokens, FOUi.tokens.caps_spacing * 3)


## Lay nebulae behind galaxy \a bounds (world), the same for the same galaxy.
func layout(bounds: Rect2) -> void:
	if _nebula_root == null or not bounds.has_area():
		return
	for child in _nebula_root.get_children():
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(bounds.size))
	var span := maxf(bounds.size.x, bounds.size.y)
	for i in NEBULAE:
		var texture := FOArt.icon("nebulae/nebula%d.png" % rng.randi_range(1, NEBULA_COUNT))
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = texture
		var at := bounds.position + Vector2(rng.randf(), rng.randf()) * bounds.size
		sprite.position = at * PARALLAX
		sprite.rotation = rng.randf() * TAU
		var size := span * rng.randf_range(0.45, 0.9) * PARALLAX
		sprite.scale = Vector2.ONE * size / maxf(texture.get_width(), 1.0)
		sprite.modulate = Color(1, 1, 1, NEBULA_ALPHA * rng.randf_range(0.6, 1.0))
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sprite.material = additive
		_nebula_root.add_child(sprite)


## Zoomed out (\a map's system labels hidden): each empire's name over its
## territory, on \a layer (screen space).
func draw_empire_names(layer: CanvasItem, map: GalaxyMap) -> void:
	if _name_font == null:
		return
	var by_owner := {}
	for k in mini(supply_owners.size(), map._supply_systems.size()):
		var owner := supply_owners[k]
		if not by_owner.has(owner):
			by_owner[owner] = []
		by_owner[owner].push_back(map._positions[map._supply_systems[k]])
	for owner: int in by_owner:
		var points: Array = by_owner[owner]
		if points.size() < NAME_MIN_SYSTEMS or owner < 0:
			continue
		var area := Rect2(points[0], Vector2.ZERO)
		var center := Vector2.ZERO
		for p: Vector2 in points:
			area = area.expand(p)
			center += p
		center /= points.size()
		var screen_width := area.size.x * map.camera.zoom_level()
		var size := int(clampf(screen_width * 0.12, NAME_PX_MIN, NAME_PX_MAX))
		var name := _empire_name(owner).to_upper()
		var width := _name_font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var at := map.camera.world_to_screen(center) - Vector2(width / 2.0, -size / 3.0)
		var color := Color(FOUniverse.get_empire_color(owner).lightened(0.35), 0.75)
		layer.draw_string_outline(
			_name_font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.6)
		)
		layer.draw_string(_name_font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _empire_name(owner: int) -> String:
	if not _names.has(owner):
		_names[owner] = FOUniverse.get_empire_name(owner)
	return _names[owner]
