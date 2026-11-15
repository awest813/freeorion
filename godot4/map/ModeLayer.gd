class_name ModeLayer
extends Node2D
## What a map mode adds over the lanes: owned systems tinted in their
## owner's colour (political), the player's industry and research as half
## disks (resources), and the strength of hostile fleets (threat). The
## supply and detection modes only change other layers (GalaxyMap).

var map: GalaxyMap
## A GalaxyMap.MODES entry.
var mode := "standard":
	set(value):
		mode = value
		queue_redraw()
## Per system: {color} (political), {industry, research} (resources) or
## {threat}.
var values := {}:
	set(value):
		values = value
		queue_redraw()


func _init() -> void:
	name = "Mode"


## Screen radius for \a value (0 for nothing): grows with its square root.
static func radius_for(value: float, px_per_root: float) -> float:
	if value <= 0.0:
		return 0.0
	return clampf(sqrt(value) * px_per_root, MapStyle.MODE_MIN_PX, MapStyle.MODE_MAX_PX)


func _draw() -> void:
	if not map or values.is_empty() or not mode in ["political", "resources", "threat"]:
		return
	var px := 1.0 / map.camera.zoom_level()
	var view := map.visible_world_rect()
	var positions: PackedVector2Array = map.overview()["positions"]
	var spacing_radius := map._typical_spacing() * MapStyle.SUPPLY_SYSTEM_RADIUS
	for system_id in values:
		var index: int = map._index_by_id.get(system_id, GalaxyMap.NO_SYSTEM)
		if index == GalaxyMap.NO_SYSTEM:
			continue
		var center := positions[index]
		var entry: Dictionary = values[system_id]
		match mode:
			"political":
				if is_finite(spacing_radius) and view.grow(spacing_radius).has_point(center):
					_draw_owner(center, entry.get("color", Color.WHITE), spacing_radius, px)
			"resources":
				if view.has_point(center):
					_draw_half_disk(
						center, entry.get("industry", 0.0), PI * 0.5, MapStyle.INDUSTRY_COLOR, px
					)
					_draw_half_disk(
						center, entry.get("research", 0.0), -PI * 0.5, MapStyle.RESEARCH_COLOR, px
					)
			"threat":
				if view.has_point(center):
					_draw_threat(center, entry.get("threat", 0.0), px)


func _draw_owner(center: Vector2, color: Color, radius: float, px: float) -> void:
	draw_circle(center, radius, Color(color, MapStyle.POLITICAL_ALPHA))
	draw_arc(center, radius, 0, TAU, 40, color, 1.5 * px, true)


func _draw_threat(center: Vector2, threat: float, px: float) -> void:
	var radius := radius_for(threat, MapStyle.THREAT_PX_PER_ROOT) * px
	if radius > 0.0:
		draw_circle(center, radius, Color(MapStyle.THREAT_COLOR, 0.3))
		draw_arc(center, radius, 0, TAU, 32, MapStyle.THREAT_COLOR, 1.5 * px, true)


# Half a disk sized by \a value with its flat side vertical through
# \a center: from \a start, the left half for industry, the right one for
# research.
func _draw_half_disk(center: Vector2, value: float, start: float, color: Color, px: float) -> void:
	var radius := radius_for(value, MapStyle.RESOURCE_PX_PER_ROOT) * px
	if radius <= 0.0:
		return
	var points := PackedVector2Array([center])
	for i in 17:
		var angle := start + PI * i / 16.0
		points.push_back(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, Color(color, 0.75))
