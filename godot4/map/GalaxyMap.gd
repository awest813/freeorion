class_name GalaxyMap
extends Node2D
## Galaxy map MVP: background stars, starlanes, stars, fleets, labels and
## system picking, drawn from FOUniverse.get_map_snapshot().
##
## Data can also be given directly with set_snapshot(), which the tests use.

signal system_selected(system_id: int)
signal system_hovered(system_id: int)

const PICK_RADIUS_PX := 14.0
const GRID_CELL := 64.0
const NO_SYSTEM := -1

var bounds := Rect2()

var _system_ids := PackedInt32Array()
var _positions := PackedVector2Array()
var _star_types := PackedInt32Array()
var _names := PackedStringArray()
var _lanes := PackedInt32Array()
var _fleet_positions := PackedVector2Array()
var _fleet_colors := PackedColorArray()
var _fleet_stack := PackedInt32Array()
var _index_by_id := {}
var _grid := {}
var _selected := NO_SYSTEM
var _hovered := NO_SYSTEM
var _background_points := PackedVector2Array()
var _has_framed := false
var _label_font: Font
var _label_widths := PackedFloat32Array()
var _label_order := PackedInt32Array()

@onready var camera: GalaxyCamera = $Camera
@onready var _background: MultiMeshInstance2D = $Background
@onready var _lane_layer: MapLayer = $Lanes
@onready var _stars: MultiMeshInstance2D = $Stars
@onready var _overlay: MapLayer = $Overlay


func _ready() -> void:
	var glow := MapStyle.glow_texture()
	_background.texture = glow
	_stars.texture = glow
	_background.multimesh = _new_multimesh()
	_stars.multimesh = _new_multimesh()
	_lane_layer.draw_callback = _draw_lanes
	_overlay.draw_callback = _draw_overlay
	_label_font = _load_label_font()
	camera.zoom_changed.connect(_on_zoom_changed)
	get_viewport().size_changed.connect(_on_viewport_resized)


## Reload everything from the client's known universe.
func load_from_universe() -> void:
	var snapshot: Dictionary = FOUniverse.get_map_snapshot()
	var names := PackedStringArray()
	for system_id in snapshot["system_ids"]:
		var system: FOSystem = FOUniverse.get_system(system_id)
		names.push_back(system.get_name() if system else "")
	var colors := PackedColorArray()
	var color_by_owner := {}
	for owner_id in snapshot["fleet_owner_ids"]:
		if not color_by_owner.has(owner_id):
			color_by_owner[owner_id] = FOUniverse.get_empire_color(owner_id)
		colors.push_back(color_by_owner[owner_id])
	set_snapshot(snapshot, names, colors)


## Replace the map data. \a snapshot has the layout of FOUniverse.get_map_snapshot().
func set_snapshot(
	snapshot: Dictionary, names: PackedStringArray, fleet_colors: PackedColorArray
) -> void:
	var previous_selection := selected_system_id()
	_system_ids = snapshot.get("system_ids", PackedInt32Array())
	_positions = snapshot.get("system_positions", PackedVector2Array())
	_star_types = snapshot.get("system_star_types", PackedInt32Array())
	_lanes = snapshot.get("lanes", PackedInt32Array())
	_fleet_positions = snapshot.get("fleet_positions", PackedVector2Array())
	_names = names
	_fleet_colors = fleet_colors

	_index_by_id.clear()
	for i in _system_ids.size():
		_index_by_id[_system_ids[i]] = i
	_selected = _index_by_id.get(previous_selection, NO_SYSTEM)
	_hovered = NO_SYSTEM

	_rebuild_bounds()
	_rebuild_grid()
	_rebuild_fleet_stacks()
	_rebuild_background()
	_rebuild_stars()
	_rebuild_labels()
	if not _has_framed and bounds.has_area():
		_has_framed = true
		camera.fit_rect(bounds)
	_refresh_zoom_dependent()


func system_count() -> int:
	return _system_ids.size()


func selected_system_id() -> int:
	return _system_ids[_selected] if _selected != NO_SYSTEM else NO_SYSTEM


func select_system(system_id: int) -> void:
	var index: int = _index_by_id.get(system_id, NO_SYSTEM)
	if index == _selected:
		return
	_selected = index
	_rebuild_labels()
	_overlay.queue_redraw()
	system_selected.emit(selected_system_id())


## Nearest system within the pick radius of a world position, or NO_SYSTEM.
func pick_system(world_pos: Vector2) -> int:
	var radius := PICK_RADIUS_PX / camera.zoom_level()
	var best := NO_SYSTEM
	var best_dist := radius * radius
	var cell_min := _cell(world_pos - Vector2(radius, radius))
	var cell_max := _cell(world_pos + Vector2(radius, radius))
	for cx in range(cell_min.x, cell_max.x + 1):
		for cy in range(cell_min.y, cell_max.y + 1):
			for index in _grid.get(Vector2i(cx, cy), PackedInt32Array()):
				var dist := _positions[index].distance_squared_to(world_pos)
				if dist <= best_dist:
					best_dist = dist
					best = index
	return _system_ids[best] if best != NO_SYSTEM else NO_SYSTEM


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hovered_id := pick_system(camera.screen_to_world(event.position))
		var index: int = _index_by_id.get(hovered_id, NO_SYSTEM)
		if index != _hovered:
			_hovered = index
			_overlay.queue_redraw()
			system_hovered.emit(hovered_id)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			select_system(pick_system(camera.screen_to_world(button.position)))
			get_viewport().set_input_as_handled()


func _on_zoom_changed(_zoom_level: float) -> void:
	_refresh_zoom_dependent()


func _on_viewport_resized() -> void:
	if bounds.has_area() and not camera.user_moved:
		camera.fit_rect(bounds)


func _refresh_zoom_dependent() -> void:
	var px := 1.0 / camera.zoom_level()
	_update_star_sizes(_stars.multimesh, _positions, px)
	_update_background_sizes(px)
	_lane_layer.queue_redraw()
	_overlay.queue_redraw()


func _draw_lanes(layer: CanvasItem) -> void:
	if _lanes.is_empty():
		return
	var points := PackedVector2Array()
	points.resize(_lanes.size())
	for i in _lanes.size():
		points[i] = _positions[_lanes[i]]
	var width := MapStyle.LANE_PX / camera.zoom_level()
	layer.draw_multiline(points, MapStyle.LANE_COLOR, width, true)


func _draw_overlay(layer: CanvasItem) -> void:
	var px := 1.0 / camera.zoom_level()
	_draw_unexplored_rings(layer, px)
	_draw_fleets(layer, px)
	_draw_labels(layer, px)
	var accent: Color = FOUi.tokens.accent if FOUi.tokens else Color.WHITE
	if _hovered != NO_SYSTEM and _hovered != _selected:
		var dim := Color(accent, 0.5)
		layer.draw_arc(
			_positions[_hovered], MapStyle.SELECTION_RING_PX * px, 0, TAU, 32, dim, 1.5 * px, true
		)
	if _selected != NO_SYSTEM:
		layer.draw_arc(
			_positions[_selected],
			MapStyle.SELECTION_RING_PX * px,
			0,
			TAU,
			40,
			accent,
			2.0 * px,
			true
		)


func _draw_unexplored_rings(layer: CanvasItem, px: float) -> void:
	var radius := MapStyle.UNEXPLORED_RING_PX * px
	for i in _positions.size():
		if i < _star_types.size() and _star_types[i] < 0:
			layer.draw_arc(
				_positions[i], radius, 0, TAU, 24, MapStyle.UNKNOWN_STAR_COLOR, 1.2 * px, true
			)


func _draw_fleets(layer: CanvasItem, px: float) -> void:
	var size := MapStyle.FLEET_PX * px
	for i in _fleet_positions.size():
		# Fleets at the same spot are stacked to the upper right of the star.
		var origin := _fleet_positions[i] + Vector2(12.0, -10.0 + 9.0 * _fleet_stack[i]) * px
		var triangle := PackedVector2Array(
			[
				origin + Vector2(size, 0),
				origin + Vector2(-size * 0.6, -size * 0.6),
				origin + Vector2(-size * 0.6, size * 0.6)
			]
		)
		var color: Color = _fleet_colors[i] if i < _fleet_colors.size() else Color.WHITE
		layer.draw_colored_polygon(triangle, color)


func _draw_labels(layer: CanvasItem, px: float) -> void:
	if _label_font == null or _names.is_empty():
		return
	# Far out, systems crowd together and no label would fit.
	if _typical_spacing() / px < MapStyle.LABEL_MIN_SPACING_PX:
		return
	var text_color: Color = FOUi.tokens.text_secondary if FOUi.tokens else Color(0.8, 0.8, 0.8)
	var size := MapStyle.LABEL_FONT_SIZE
	var view_size := get_viewport_rect().size
	var screen := Rect2(Vector2.ZERO, view_size)
	var placed := _LabelGrid.new()
	for i in _label_order:
		var at := camera.world_to_screen(_positions[i])
		if not screen.has_point(at):
			continue
		var width := _label_widths[i]
		var rect := Rect2(
			at + Vector2(-width * 0.5, MapStyle.LABEL_OFFSET_PX.y), Vector2(width, size * 1.25)
		)
		if not placed.try_place(rect.grow(MapStyle.LABEL_PADDING_PX)):
			continue
		layer.draw_set_transform(
			_positions[i] + MapStyle.LABEL_OFFSET_PX * px, 0.0, Vector2(px, px)
		)
		layer.draw_string(
			_label_font,
			Vector2(-width * 0.5, size),
			_names[i],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			size,
			text_color
		)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Label priority: selected system, then explored systems, then the rest.
func _rebuild_labels() -> void:
	_label_widths.resize(_positions.size())
	var explored: Array[int] = []
	var unexplored: Array[int] = []
	for i in _positions.size():
		var label := _names[i] if i < _names.size() else ""
		_label_widths[i] = (
			(
				_label_font
				. get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, MapStyle.LABEL_FONT_SIZE)
				. x
			)
			if _label_font
			else 0.0
		)
		if label.is_empty() or i == _selected:
			continue
		if i < _star_types.size() and _star_types[i] >= 0:
			explored.push_back(i)
		else:
			unexplored.push_back(i)
	_label_order = PackedInt32Array()
	if _selected != NO_SYSTEM and _selected < _names.size() and not _names[_selected].is_empty():
		_label_order.push_back(_selected)
	_label_order.append_array(PackedInt32Array(explored))
	_label_order.append_array(PackedInt32Array(unexplored))


## Screen-space occupancy grid for greedy label placement.
class _LabelGrid:
	const CELL := 64.0
	var _cells := {}

	func try_place(rect: Rect2) -> bool:
		var keys := _keys(rect)
		for key in keys:
			for other: Rect2 in _cells.get(key, []):
				if other.intersects(rect):
					return false
		for key in keys:
			if not _cells.has(key):
				_cells[key] = []
			_cells[key].push_back(rect)
		return true

	func _keys(rect: Rect2) -> Array[Vector2i]:
		var keys: Array[Vector2i] = []
		for cx in range(floori(rect.position.x / CELL), floori(rect.end.x / CELL) + 1):
			for cy in range(floori(rect.position.y / CELL), floori(rect.end.y / CELL) + 1):
				keys.push_back(Vector2i(cx, cy))
		return keys


func _typical_spacing() -> float:
	if _positions.size() < 2 or not bounds.has_area():
		return INF
	return sqrt(bounds.get_area() / _positions.size())


func _rebuild_bounds() -> void:
	if _positions.is_empty():
		bounds = Rect2()
		return
	bounds = Rect2(_positions[0], Vector2.ZERO)
	for p in _positions:
		bounds = bounds.expand(p)
	bounds = bounds.grow(maxf(bounds.size.x, bounds.size.y) * 0.02 + 1.0)


func _rebuild_grid() -> void:
	_grid.clear()
	for i in _positions.size():
		var cell := _cell(_positions[i])
		if not _grid.has(cell):
			_grid[cell] = PackedInt32Array()
		var members: PackedInt32Array = _grid[cell]
		members.push_back(i)
		_grid[cell] = members


func _rebuild_fleet_stacks() -> void:
	_fleet_stack.resize(_fleet_positions.size())
	var count_at := {}
	for i in _fleet_positions.size():
		var key := Vector2i(roundi(_fleet_positions[i].x), roundi(_fleet_positions[i].y))
		var n: int = count_at.get(key, 0)
		_fleet_stack[i] = n
		count_at[key] = n + 1


func _rebuild_stars() -> void:
	var mm := _stars.multimesh
	mm.instance_count = _positions.size()
	for i in _positions.size():
		mm.set_instance_color(
			i, MapStyle.star_color(_star_types[i] if i < _star_types.size() else -1)
		)


func _rebuild_background() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + _positions.size()
	var area := (
		bounds.grow(maxf(bounds.size.x, bounds.size.y) * 0.5) if bounds.has_area() else Rect2()
	)
	_background_points.resize(MapStyle.BACKGROUND_STAR_COUNT if area.has_area() else 0)
	var mm := _background.multimesh
	mm.instance_count = _background_points.size()
	for i in _background_points.size():
		_background_points[i] = Vector2(
			rng.randf_range(area.position.x, area.end.x),
			rng.randf_range(area.position.y, area.end.y)
		)
		var shade := rng.randf_range(0.25, 0.7)
		mm.set_instance_color(i, Color(shade, shade, shade * 1.1, rng.randf_range(0.4, 0.9)))


func _update_star_sizes(mm: MultiMesh, positions: PackedVector2Array, px: float) -> void:
	for i in mm.instance_count:
		var size := (
			MapStyle.STAR_PX
			* px
			* MapStyle.star_size(_star_types[i] if i < _star_types.size() else -1)
		)
		mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2(size, size), 0.0, positions[i]))


func _update_background_sizes(px: float) -> void:
	var mm := _background.multimesh
	var size := MapStyle.BACKGROUND_STAR_PX * px
	for i in mm.instance_count:
		mm.set_instance_transform_2d(
			i, Transform2D(0.0, Vector2(size, size), 0.0, _background_points[i])
		)


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / GRID_CELL), floori(p.y / GRID_CELL))


static func _new_multimesh() -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	return mm


static func _load_label_font() -> Font:
	var path := "res://assets/fonts/Roboto-Regular.ttf"
	if ResourceLoader.exists(path):
		return load(path)
	return ThemeDB.fallback_font
