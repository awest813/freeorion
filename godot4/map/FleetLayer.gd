class_name FleetLayer
extends Node2D
## The galaxy map's fleets, for GalaxyMap: a marker each in its owner's
## colour (stacked beside the star when several share a place), the paths of
## fleets under way with a dot where each turn ends (GG's movement lines),
## and the route a selected fleet would take to the hovered system. Picks
## the fleet under the cursor.

## Screen pixels around a marker that still pick it.
const PICK_PX := 8.0

var map: GalaxyMap
## The selected fleet, ringed (-1 for none).
var selected_fleet := -1:
	set(value):
		selected_fleet = value
		queue_redraw()

var _positions := PackedVector2Array()
var _ids := PackedInt32Array()
var _owners := PackedInt32Array()
var _colors := PackedColorArray()
var _stack := PackedInt32Array()
var _paths: Array = []
var _turn_ends: Array = []
## Fleets marked as selected together (box selection): id -> true.
var _marked := {}
var _preview := PackedVector2Array()
var _preview_turn_ends := PackedVector2Array()
var _preview_label := ""


func _init() -> void:
	name = "Fleets"


## Take the fleets of \a snapshot (GalaxyMap.set_snapshot()), drawn in \a colors.
func set_fleets(snapshot: Dictionary, colors: PackedColorArray) -> void:
	_positions = snapshot.get("fleet_positions", PackedVector2Array())
	_ids = snapshot.get("fleet_ids", PackedInt32Array())
	_owners = snapshot.get("fleet_owner_ids", PackedInt32Array())
	_paths = snapshot.get("fleet_paths", [])
	_turn_ends = snapshot.get("fleet_turn_ends", [])
	_colors = colors
	_stack.resize(_positions.size())
	var count_at := {}
	for i in _positions.size():
		var key := Vector2i(roundi(_positions[i].x), roundi(_positions[i].y))
		var n: int = count_at.get(key, 0)
		_stack[i] = n
		count_at[key] = n + 1
	queue_redraw()


func fleet_count() -> int:
	return _ids.size()


## Fleets whose position lies in world rectangle \a rect, optionally only
## those of empire \a owner_id (-2: any).
func fleets_in_rect(rect: Rect2, owner_id := -2) -> PackedInt32Array:
	var result := PackedInt32Array()
	for i in mini(_ids.size(), _positions.size()):
		if not rect.abs().grow(0.001).has_point(_positions[i]):
			continue
		if owner_id != -2 and (i >= _owners.size() or _owners[i] != owner_id):
			continue
		result.push_back(_ids[i])
	return result


## Ring the markers of \a fleet_ids (fleets selected together).
func set_marked(fleet_ids: PackedInt32Array) -> void:
	_marked.clear()
	for fleet_id in fleet_ids:
		_marked[fleet_id] = true
	queue_redraw()


## The fleet whose marker is at \a world_pos (-1 for none), at \a px world
## units per screen pixel.
func pick(world_pos: Vector2, px: float) -> int:
	var best := -1
	var best_dist := INF
	var reach := PICK_PX * px
	for i in mini(_ids.size(), _positions.size()):
		var dist := marker_origin(i, px).distance_to(world_pos)
		if dist <= reach and dist < best_dist:
			best = _ids[i]
			best_dist = dist
	return best


## Where fleet number \a index's marker is drawn: to the upper right of its
## position, the next fleet at the same place below it.
func marker_origin(index: int, px: float) -> Vector2:
	var stack := _stack[index] if index < _stack.size() else 0
	return _positions[index] + Vector2(12.0, -10.0 + 9.0 * stack) * px


## The world position of fleet \a fleet_id's marker (tests), or INF.
func marker_of(fleet_id: int, px: float) -> Vector2:
	var index := _ids.find(fleet_id)
	return marker_origin(index, px) if index >= 0 else Vector2.INF


## Show where a fleet would go: its move path \a points, the turn ends on it,
## and \a label (the ETA) by its end. Empty points clear it.
func set_preview(points: PackedVector2Array, turn_ends: PackedVector2Array, label := "") -> void:
	_preview = points
	_preview_turn_ends = turn_ends
	_preview_label = label if points.size() > 1 else ""
	queue_redraw()


func preview_points() -> PackedVector2Array:
	return _preview


func preview_label() -> String:
	return _preview_label


## The path fleet \a fleet_id is on (empty if not moving).
func path_of(fleet_id: int) -> PackedVector2Array:
	var index := _ids.find(fleet_id)
	return _paths[index] if index >= 0 and index < _paths.size() else PackedVector2Array()


func _draw() -> void:
	if map == null:
		return
	var px := 1.0 / map.camera.zoom_level()
	var view := map.visible_world_rect()
	_draw_paths(px, view)
	_draw_preview(px)
	_draw_markers(px, view)


# Each moving fleet's path in its owner's colour, faint, with turn ends.
func _draw_paths(px: float, view: Rect2) -> void:
	for i in mini(_paths.size(), _ids.size()):
		var points: PackedVector2Array = _paths[i]
		if points.size() < 2:
			continue
		var bounds := Rect2(points[0], Vector2.ZERO)
		for point in points:
			bounds = bounds.expand(point)
		if not view.intersects(bounds):
			continue
		var color: Color = _colors[i] if i < _colors.size() else Color.WHITE
		var line := Color(color, 0.55)
		for j in points.size() - 1:
			draw_dashed_line(
				points[j], points[j + 1], line, 1.5 * px, MapStyle.ROUTE_DASH_PX * px, true, true
			)
		if i < _turn_ends.size():
			for point: Vector2 in _turn_ends[i]:
				draw_circle(point, 2.5 * px, line)


func _draw_preview(px: float) -> void:
	if _preview.size() < 2:
		return
	var accent: Color = FOUi.tokens.accent if FOUi.tokens else Color.WHITE
	var line := Color(accent, 0.7)
	for i in _preview.size() - 1:
		draw_dashed_line(
			_preview[i], _preview[i + 1], line, 2.0 * px, MapStyle.ROUTE_DASH_PX * px, true, true
		)
	for point in _preview_turn_ends:
		draw_circle(point, 3.0 * px, line)
	draw_arc(_preview[_preview.size() - 1], 5.0 * px, 0, TAU, 20, accent, 1.5 * px, true)


func _draw_markers(px: float, view: Rect2) -> void:
	var size := MapStyle.FLEET_PX * px
	var tip := Vector2(size, 0)
	var top := Vector2(-size * 0.6, -size * 0.6)
	var bottom := Vector2(-size * 0.6, size * 0.6)
	var accent: Color = FOUi.tokens.accent if FOUi.tokens else Color.WHITE
	for i in _positions.size():
		if not view.has_point(_positions[i]):
			continue
		var origin := marker_origin(i, px)
		var color: Color = _colors[i] if i < _colors.size() else Color.WHITE
		var fleet_id := _ids[i] if i < _ids.size() else -1
		if _marked.has(fleet_id) or fleet_id == selected_fleet:
			draw_arc(origin, size * 1.1, 0, TAU, 20, accent, 1.5 * px, true)
		draw_primitive(
			PackedVector2Array([origin + tip, origin + top, origin + bottom]),
			PackedColorArray([color, color, color]),
			PackedVector2Array()
		)
