class_name PlanetView
extends Control
## A planet as a lit, slowly turning sphere (planet_sphere.gdshader): the
## surface art of its type (one of several, picked by \a seed so each planet
## keeps its look), an atmosphere in the type's colour, lit from the side in
## its star's colour. Types without surface art (asteroids, unknown) show
## their icon. Turning stops with reduced motion.

const SHADER := preload("res://ui/theme/planet_sphere.gdshader")
## Planet type -> surface art (art/planets/<name><nn>.png, nn from 01).
const SURFACES := {
	"PT_SWAMP": ["Swamp", 3],
	"PT_TOXIC": ["Toxic", 3],
	"PT_INFERNO": ["Inferno", 4],
	"PT_RADIATED": ["Radiated", 3],
	"PT_BARREN": ["Barren", 3],
	"PT_TUNDRA": ["Tundra", 3],
	"PT_DESERT": ["Desert", 3],
	"PT_TERRAN": ["Terran", 4],
	"PT_OCEAN": ["Ocean", 3],
	"PT_GASGIANT": ["GasGiant", 11],
}
## Planet type -> atmosphere colour (alpha: how much).
const ATMOSPHERES := {
	"PT_SWAMP": Color(0.55, 0.85, 0.45, 0.7),
	"PT_TOXIC": Color(0.75, 0.9, 0.3, 0.75),
	"PT_INFERNO": Color(1.0, 0.5, 0.25, 0.75),
	"PT_RADIATED": Color(0.9, 0.95, 0.4, 0.6),
	"PT_BARREN": Color(0.8, 0.8, 0.85, 0.15),
	"PT_TUNDRA": Color(0.85, 0.92, 1.0, 0.55),
	"PT_DESERT": Color(1.0, 0.85, 0.55, 0.5),
	"PT_TERRAN": Color(0.45, 0.7, 1.0, 0.8),
	"PT_OCEAN": Color(0.4, 0.65, 1.0, 0.85),
	"PT_GASGIANT": Color(1.0, 0.9, 0.7, 0.6),
}
## Star type -> the light it casts (GG's GLStars colours).
const STAR_LIGHT := {
	"STAR_BLUE": Color(0.75, 0.75, 1.00),
	"STAR_WHITE": Color(1.00, 1.00, 1.00),
	"STAR_YELLOW": Color(1.00, 1.00, 0.75),
	"STAR_ORANGE": Color(1.00, 0.75, 0.63),
	"STAR_RED": Color(1.00, 0.75, 0.75),
	"STAR_NEUTRON": Color(0.63, 0.82, 0.75),
	"STAR_BLACK": Color(0.38, 0.63, 0.63),
	"STAR_NONE": Color(0.38, 0.38, 0.38),
}

## Planet size -> the sphere's share of the view (bigger worlds fill more).
const SIZE_RADIUS := {
	"SZ_TINY": 0.55,
	"SZ_SMALL": 0.66,
	"SZ_MEDIUM": 0.76,
	"SZ_LARGE": 0.86,
	"SZ_HUGE": 0.94,
	"SZ_GASGIANT": 0.94,
}

var _icon: TextureRect


## A view of a planet of \a planet_type ("PT_TERRAN"), \a size px square,
## its look picked by \a seed (the planet id), lit by a \a star_type star.
func _init(
	planet_type := "", seed := 0, size := 48, star_type := "STAR_YELLOW", planet_size := ""
) -> void:
	custom_minimum_size = Vector2(size, size)
	mouse_filter = Control.MOUSE_FILTER_PASS
	show_planet(planet_type, seed, star_type, planet_size)


## Show a planet of \a planet_type, picked by \a seed, lit by \a star_type;
## \a planet_size ("SZ_LARGE") sets how much of the view it fills.
func show_planet(
	planet_type: String, seed := 0, star_type := "STAR_YELLOW", planet_size := ""
) -> void:
	var surface := surface_texture(planet_type, seed)
	if surface == null:
		material = null
		if _icon == null:
			_icon = TextureRect.new()
			_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_icon)
		_icon.texture = FOArt.planet_type_icon(planet_type)
		_icon.visible = true
		queue_redraw()
		return
	if _icon:
		_icon.visible = false
	var shader := ShaderMaterial.new()
	shader.shader = SHADER
	shader.set_shader_parameter("surface", surface)
	shader.set_shader_parameter("atmosphere", ATMOSPHERES.get(planet_type, Color(1, 1, 1, 0.3)))
	shader.set_shader_parameter("light_color", STAR_LIGHT.get(star_type, Color.WHITE))
	shader.set_shader_parameter("radius", SIZE_RADIUS.get(planet_size, 0.86))
	shader.set_shader_parameter("phase", float(seed % 628) / 100.0)
	shader.set_shader_parameter("spin", 0.0 if FOUi.reduce_motion else 0.06 + (seed % 5) * 0.01)
	material = shader
	queue_redraw()


## The surface art for a planet of \a planet_type picked by \a seed, or null.
static func surface_texture(planet_type: String, seed: int) -> Texture2D:
	if not SURFACES.has(planet_type):
		return null
	var entry: Array = SURFACES[planet_type]
	return FOArt.icon("planets/%s%02d.png" % [entry[0], posmod(seed, entry[1]) + 1])


func _draw() -> void:
	if material != null:
		draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
