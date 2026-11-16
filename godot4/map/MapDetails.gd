class_name MapDetails
extends RefCounted
## Details GalaxyMap draws on its layers, as GG's map does: supply that
## can't go on along a lane (a dashed half lane in the empire's colour from
## where it stops), systems owned by several empires (their ring split
## between the owners' colours) and fields out of sight (scanlines).

## Screen pixels between scanlines over fields out of sight.
const SCANLINE_PX := 4.0
const SCANLINE_COLOR := Color(0, 0, 0, 0.16)
## The most scanlines over one field (big fields when zoomed out).
const SCANLINES_MAX := 80
## Snapshot owner id lists and the colour lists made from them.
const COLOR_KEYS := [
	["fleet_owner_ids", "fleet_colors"],
	["system_owner_ids", "system_owner_colors"],
	["detection_owner_ids", "detection_colors"],
	["supply_lane_owners", "supply_lane_colors"],
	["supply_system_owners", "supply_system_colors"],
	["supply_obstructed_owners", "supply_obstructed_colors"],
]

## Pairs of system indices: from where supply stops, toward where.
var obstructed := PackedInt32Array()
var obstructed_colors := PackedColorArray()
## Per system: its owners' colours when there are several, else empty.
var owner_sets: Array = []
## Per field: 1 when out of sight.
var field_stale := PackedByteArray()


## Add each owner id list's colours (\a color_of(owner_id) -> Color) to
## \a snapshot (FOUniverse.get_map_snapshot()); unowned systems get none.
static func add_colors(snapshot: Dictionary, color_of: Callable) -> void:
	for key in COLOR_KEYS:
		var colors := PackedColorArray()
		for owner_id: int in snapshot.get(key[0], PackedInt32Array()):
			var unowned: bool = owner_id < 0 and key[0] == "system_owner_ids"
			colors.push_back(Color(0, 0, 0, 0) if unowned else color_of.call(owner_id))
		snapshot[key[1]] = colors
	var sets := []
	for owners: PackedInt32Array in snapshot.get("system_owner_sets", []):
		sets.push_back(PackedColorArray(Array(owners).map(color_of)))
	snapshot["system_owner_set_colors"] = sets


func set_snapshot(snapshot: Dictionary) -> void:
	obstructed = snapshot.get("supply_obstructed", PackedInt32Array())
	obstructed_colors = snapshot.get("supply_obstructed_colors", PackedColorArray())
	owner_sets = snapshot.get("system_owner_set_colors", [])
	field_stale = snapshot.get("field_stale", PackedByteArray())


## Half lanes where supply is obstructed, \a width wide, in \a view.
func draw_obstructed(
	layer: CanvasItem, positions: PackedVector2Array, view: Rect2, width: float
) -> void:
	for i in range(0, obstructed.size() - 1, 2):
		var a := positions[obstructed[i]]
		var middle := a.lerp(positions[obstructed[i + 1]], 0.5)
		if not view.intersects(Rect2(a, Vector2.ZERO).expand(middle)):
			continue
		var owner := i / 2
		var color := obstructed_colors[owner] if owner < obstructed_colors.size() else Color.WHITE
		layer.draw_dashed_line(a, middle, Color(color, 0.8), width * 0.5, width * 1.5, true, true)


## Owned systems ringed in their owner's colour, split between the owners
## where there are several (GG's system circles).
func draw_owner_rings(
	layer: CanvasItem,
	positions: PackedVector2Array,
	owner_colors: PackedColorArray,
	view: Rect2,
	radius: float,
	px: float
) -> void:
	for i in mini(positions.size(), owner_colors.size()):
		if owner_colors[i].a <= 0.0 or not view.has_point(positions[i]):
			continue
		var colors: PackedColorArray = owner_sets[i] if i < owner_sets.size() else []
		if colors.size() < 2:
			layer.draw_arc(positions[i], radius, 0, TAU, 24, owner_colors[i], 2.0 * px, true)
			continue
		var share := TAU / colors.size()
		for k in colors.size():
			var start := -PI / 2.0 + share * k
			layer.draw_arc(
				positions[i], radius, start, start + share, 12, colors[k], 2.0 * px, true
			)


## Scanlines over the fields out of sight (\a centers, \a radii), \a px
## world units to the screen pixel.
func draw_scanlines(
	layer: CanvasItem,
	centers: PackedVector2Array,
	radii: PackedFloat32Array,
	view: Rect2,
	px: float
) -> void:
	for i in mini(field_stale.size(), centers.size()):
		var radius := radii[i]
		if field_stale[i] == 0 or radius <= 0.0 or not view.grow(radius).has_point(centers[i]):
			continue
		var step := maxf(SCANLINE_PX * px, radius * 2.0 / SCANLINES_MAX)
		var y := -radius + step / 2.0
		while y < radius:
			var half := sqrt(radius * radius - y * y)
			var at := centers[i] + Vector2(0, y)
			layer.draw_line(at - Vector2(half, 0), at + Vector2(half, 0), SCANLINE_COLOR, px)
			y += step


## \a map's own detection ranges, opaque (the group around the layer
## fades them).
func draw_own_detection(layer: CanvasItem, map: GalaxyMap) -> void:
	var view := map.visible_world_rect()
	var color := MapStyle.DETECTION_COLOR
	for i in map._detection_positions.size():
		if not _own_detection(map, i):
			continue
		var center := map._detection_positions[i]
		var radius := map._detection_radii[i]
		if view.grow(radius).has_point(center):
			layer.draw_circle(center, radius, color)


# Whether \a map's detection circle \a i is the player's (all are, without
# owners).
func _own_detection(map: GalaxyMap, i: int) -> bool:
	return i >= map._detection_owners.size() or map._detection_owners[i] == map.own_empire_id


## Other empires' detection ranges in \a map, ringed in their colours (where
## they can see the player's ships), as GG's map shows them.
func draw_other_detection(layer: CanvasItem, map: GalaxyMap, px: float, view: Rect2) -> void:
	if not (map.show_detection or map.map_mode == "detection"):
		return
	for i in map._detection_positions.size():
		if _own_detection(map, i):
			continue
		var center := map._detection_positions[i]
		var radius := map._detection_radii[i]
		if not view.grow(radius).has_point(center):
			continue
		var color: Color = (
			map._detection_colors[i] if i < map._detection_colors.size() else Color.WHITE
		)
		layer.draw_circle(center, radius, Color(color, 0.06))
		layer.draw_arc(center, radius, 0, TAU, 64, Color(color, 0.55), 1.5 * px, true)


## Dashes along \a points (a route) moving towards its end: \a dash long,
## as long gaps, shifted by \a phase (0 to 1 of a dash and gap), in \a color.
func draw_flow(
	layer: CanvasItem,
	points: PackedVector2Array,
	color: Color,
	width: float,
	dash: float,
	phase: float
) -> void:
	var period := dash * 2.0
	var shift := fposmod(phase, 1.0) * period
	var walked := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var length := a.distance_to(points[i + 1])
		if length <= 0.0:
			continue
		var direction := (points[i + 1] - a) / length
		# Dashes start at shift + k * period along the whole route.
		var d := floorf((walked - shift) / period) * period + shift
		while d < walked + length:
			var from := maxf(d, walked) - walked
			var to := minf(d + dash, walked + length) - walked
			if to > from:
				layer.draw_line(a + direction * from, a + direction * to, color, width, true)
			d += period
		walked += length
