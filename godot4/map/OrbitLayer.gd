class_name OrbitLayer
extends Node2D
## Zoomed in on the galaxy map: each system's known planets as small worlds
## in their type's colour, sized by planet size, slowly going round their
## star on faint orbits (still with reduced motion). Nothing is drawn
## zoomed out, where systems are too close for it.

## Screen pixels between systems from which orbits are drawn.
const MIN_SPACING_PX := 220.0
## The first orbit's radius, in screen px: clear of the star and its fleets.
const ORBIT_FIRST_PX := 30.0
## The outermost orbit reaches this share of the distance between systems.
const ORBIT_REACH := 0.3
## Most screen px between two orbits.
const ORBIT_STEP_MAX_PX := 16.0
## Planet type -> its colour on the map.
const TYPE_COLORS := {
	"PT_SWAMP": Color(0.45, 0.6, 0.35),
	"PT_TOXIC": Color(0.65, 0.75, 0.25),
	"PT_INFERNO": Color(0.85, 0.35, 0.2),
	"PT_RADIATED": Color(0.8, 0.85, 0.35),
	"PT_BARREN": Color(0.6, 0.58, 0.55),
	"PT_TUNDRA": Color(0.8, 0.88, 0.95),
	"PT_DESERT": Color(0.9, 0.75, 0.45),
	"PT_TERRAN": Color(0.4, 0.7, 0.45),
	"PT_OCEAN": Color(0.3, 0.55, 0.95),
	"PT_GASGIANT": Color(0.9, 0.78, 0.55),
	"PT_ASTEROIDS": Color(0.55, 0.52, 0.5),
}
## Planet size -> dot radius in screen px.
const SIZE_PX := {
	"SZ_TINY": 1.6,
	"SZ_SMALL": 2.0,
	"SZ_MEDIUM": 2.5,
	"SZ_LARGE": 3.0,
	"SZ_HUGE": 3.6,
	"SZ_GASGIANT": 3.8,
	"SZ_ASTEROIDS": 1.4,
}

var map: GalaxyMap
## System id -> [[type, size, seed]] of its known planets.
var _planets := {}


## Forget what's known of the planets (a new snapshot).
func reset() -> void:
	_planets.clear()
	queue_redraw()


func _process(_delta: float) -> void:
	if not FOUi.reduce_motion and is_visible_in_tree() and _zoomed_in():
		queue_redraw()


func _draw() -> void:
	if map == null or not _zoomed_in():
		return
	var px := 1.0 / map.camera.zoom_level()
	var view := map.visible_world_rect()
	var now := 0.0 if FOUi.reduce_motion else Time.get_ticks_msec() / 1000.0
	var ring := Color(1, 1, 1, 0.14)
	var reach := map._typical_spacing() * map.camera.zoom_level() * ORBIT_REACH
	for i in map.system_count():
		var center := map._positions[i]
		if not view.has_point(center):
			continue
		var planets := _planets_of(map._system_ids[i])
		var step := (reach - ORBIT_FIRST_PX) / maxf(planets.size() - 1, 1)
		step = clampf(step, 4.0, ORBIT_STEP_MAX_PX)
		for k in planets.size():
			var radius := (ORBIT_FIRST_PX + k * step) * px
			draw_arc(center, radius, 0, TAU, 48, ring, 1.0 * px, true)
			var entry: Array = planets[k]
			# Inner worlds go round faster.
			var angle := float(entry[2] % 628) / 100.0 + now * 0.25 / (k + 1)
			var at := center + Vector2.from_angle(angle) * radius
			var color: Color = TYPE_COLORS.get(entry[0], Color.GRAY)
			var dot: float = SIZE_PX.get(entry[1], 2.0) * 1.4 * px
			draw_circle(at, dot * 1.8, Color(color, 0.18))
			draw_circle(at, dot, color)


func _zoomed_in() -> bool:
	return map != null and map._typical_spacing() * map.camera.zoom_level() >= MIN_SPACING_PX


func _planets_of(system_id: int) -> Array:
	if _planets.has(system_id):
		return _planets[system_id]
	var list := []
	var system: FOSystem = FOUniverse.get_system(system_id)
	if system:
		for planet_id in system.get_planet_ids():
			var planet: FOPlanet = FOUniverse.get_planet(planet_id)
			if planet:
				list.push_back([planet.get_planet_type(), planet.get_planet_size(), planet_id])
	_planets[system_id] = list
	return list
