class_name GalaxyMap
extends Node2D
## Galaxy map: background stars, starlanes, stars, fleets, labels and system
## picking, drawn from FOUniverse.get_map_snapshot().
##
## Three spaces:
## - screen-space backdrop (Backdrop/Starfield): drawn once per viewport size
## - world space (Lanes, Stars, Overlay): follows the camera, culled to the view
## - screen-space labels (ScreenOverlay/Labels): no per-label transforms
## Data can also be given directly with set_snapshot(), which the tests use.

signal system_selected(system_id: int)
signal system_hovered(system_id: int)
## Right-click (not drag) on a system, e.g. to order the active fleet there.
signal system_context_requested(system_id: int)

const PICK_RADIUS_PX := 14.0
const GRID_CELL := 64.0
const NO_SYSTEM := -1
## Extra margin around the view when culling, in screen pixels.
const CULL_MARGIN_PX := 32.0

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
var _has_framed := false
var _label_font: Font
var _label_widths := PackedFloat32Array()
var _label_order := PackedInt32Array()
var _star_colors := PackedColorArray()
var _starfield_texture: ImageTexture
var _route := PackedVector2Array()

@onready var camera: GalaxyCamera = $Camera
@onready var _lane_layer: MapLayer = $Lanes
@onready var _stars: MultiMeshInstance2D = $Stars
@onready var _overlay: MapLayer = $Overlay
@onready var _starfield: MapLayer = $"../Backdrop/Starfield"
@onready var _label_layer: MapLayer = $"../ScreenOverlay/Labels"


func _ready() -> void:
	_stars.texture = MapStyle.glow_texture()
	_stars.multimesh = _new_multimesh()
	_lane_layer.draw_callback = _draw_lanes
	_overlay.draw_callback = _draw_overlay
	_starfield.draw_callback = _draw_starfield
	_label_layer.draw_callback = _draw_labels
	_label_font = _load_label_font()
	camera.zoom_changed.connect(_on_zoom_changed)
	camera.view_changed.connect(_on_view_changed)
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
	_rebuild_stars()
	_rebuild_labels()
	if not _has_framed and bounds.has_area():
		_has_framed = true
		camera.fit_rect(bounds)
	_on_zoom_changed(camera.zoom_level())
	_on_view_changed()


func system_count() -> int:
	return _system_ids.size()


func system_position(system_id: int) -> Vector2:
	var index: int = _index_by_id.get(system_id, NO_SYSTEM)
	return _positions[index] if index != NO_SYSTEM else Vector2.ZERO


func selected_system_id() -> int:
	return _system_ids[_selected] if _selected != NO_SYSTEM else NO_SYSTEM


## Show a fleet route: \a start (the fleet's position) through the systems in
## \a system_ids. An empty array clears it.
func set_route(start: Vector2, system_ids: PackedInt32Array) -> void:
	_route = PackedVector2Array()
	if not system_ids.is_empty():
		_route.push_back(start)
		for system_id in system_ids:
			if _index_by_id.has(system_id):
				_route.push_back(_positions[_index_by_id[system_id]])
	_overlay.queue_redraw()


func route_points() -> PackedVector2Array:
	return _route


## Hover highlight and name chip for \a system_id (-1 clears); the mouse
## normally drives this, tests and screenshots call it directly.
func hover_system(system_id: int) -> void:
	var index: int = _index_by_id.get(system_id, NO_SYSTEM)
	if index == _hovered:
		return
	_hovered = index
	_overlay.queue_redraw()
	_label_layer.queue_redraw()
	system_hovered.emit(system_id)


func select_system(system_id: int) -> void:
	var index: int = _index_by_id.get(system_id, NO_SYSTEM)
	if index == _selected:
		return
	_selected = index
	_rebuild_labels()
	_overlay.queue_redraw()
	_label_layer.queue_redraw()
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


## World-space rectangle currently on screen, plus the cull margin.
func visible_world_rect() -> Rect2:
	var px := 1.0 / camera.zoom_level()
	var size := get_viewport_rect().size * px
	return Rect2(camera.screen_to_world(Vector2.ZERO), size).grow(CULL_MARGIN_PX * px)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hovered_id := pick_system(camera.screen_to_world(event.position))
		var index: int = _index_by_id.get(hovered_id, NO_SYSTEM)
		if index != _hovered:
			_hovered = index
			_overlay.queue_redraw()
			_label_layer.queue_redraw()
			system_hovered.emit(hovered_id)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			select_system(pick_system(camera.screen_to_world(button.position)))
			get_viewport().set_input_as_handled()
		elif (
			button.button_index == MOUSE_BUTTON_RIGHT and not button.pressed and camera.was_click()
		):
			var system_id := pick_system(camera.screen_to_world(button.position))
			if system_id != NO_SYSTEM:
				system_context_requested.emit(system_id)
				get_viewport().set_input_as_handled()


func _on_zoom_changed(zoom_level: float) -> void:
	_update_star_sizes(1.0 / zoom_level)


func _on_view_changed() -> void:
	_lane_layer.queue_redraw()
	_overlay.queue_redraw()
	_label_layer.queue_redraw()


func _on_viewport_resized() -> void:
	_starfield.queue_redraw()
	if bounds.has_area() and not camera.user_moved:
		camera.fit_rect(bounds)


func _draw_starfield(layer: CanvasItem) -> void:
	var size := Vector2i(get_viewport_rect().size)
	if size.x <= 0 or size.y <= 0:
		return
	if _starfield_texture == null or _starfield_texture.get_size() != Vector2(size):
		_starfield_texture = _bake_starfield(size)
	layer.draw_texture(_starfield_texture, Vector2.ZERO)


# Opaque screen-space backdrop (space colour plus static stars) baked into one
# texture per viewport size, so the whole background is a single quad.
# Deterministic so screenshots are stable.
static func _bake_starfield(size: Vector2i) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	image.fill(MapStyle.SPACE_COLOR)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919
	var count := int(size.x * size.y / MapStyle.BACKGROUND_PX_PER_STAR)
	for i in count:
		var shade := rng.randf_range(0.25, 0.7)
		var star := Color(shade, shade, shade * 1.1)
		var color := MapStyle.SPACE_COLOR.lerp(star, rng.randf_range(0.4, 0.9))
		var x := rng.randi_range(0, size.x - 2)
		var y := rng.randi_range(0, size.y - 2)
		image.set_pixel(x, y, color)
		if rng.randf() < 0.25:
			# A few brighter, two-pixel stars.
			var halo := MapStyle.SPACE_COLOR.lerp(color, 0.5)
			image.set_pixel(x + 1, y, halo)
			image.set_pixel(x, y + 1, halo)
	return ImageTexture.create_from_image(image)


func _draw_lanes(layer: CanvasItem) -> void:
	if _lanes.is_empty():
		return
	var view := visible_world_rect()
	var points := PackedVector2Array()
	for i in range(0, _lanes.size() - 1, 2):
		var a := _positions[_lanes[i]]
		var b := _positions[_lanes[i + 1]]
		if view.intersects(Rect2(a, Vector2.ZERO).expand(b)):
			points.push_back(a)
			points.push_back(b)
	if points.is_empty():
		return
	var width := MapStyle.LANE_PX / camera.zoom_level()
	layer.draw_multiline(points, MapStyle.LANE_COLOR, width, true)


func _draw_overlay(layer: CanvasItem) -> void:
	var px := 1.0 / camera.zoom_level()
	var view := visible_world_rect()
	_draw_unexplored_rings(layer, px, view)
	_draw_route(layer, px)
	_draw_fleets(layer, px, view)
	var accent: Color = FOUi.tokens.accent if FOUi.tokens else Color.WHITE
	var ring := MapStyle.SELECTION_RING_PX * px
	if _hovered != NO_SYSTEM and _hovered != _selected:
		layer.draw_arc(_positions[_hovered], ring, 0, TAU, 32, Color(accent, 0.5), 1.5 * px, true)
	if _selected != NO_SYSTEM:
		layer.draw_arc(_positions[_selected], ring, 0, TAU, 40, accent, 2.0 * px, true)


func _draw_route(layer: CanvasItem, px: float) -> void:
	if _route.size() < 2:
		return
	var accent: Color = FOUi.tokens.accent if FOUi.tokens else Color.WHITE
	for i in _route.size() - 1:
		layer.draw_dashed_line(
			_route[i], _route[i + 1], accent, 2.0 * px, MapStyle.ROUTE_DASH_PX * px, true, true
		)
	layer.draw_circle(_route[_route.size() - 1], 4.0 * px, accent)


func _draw_unexplored_rings(layer: CanvasItem, px: float, view: Rect2) -> void:
	var radius := MapStyle.UNEXPLORED_RING_PX * px
	for i in _positions.size():
		if i < _star_types.size() and _star_types[i] < 0 and view.has_point(_positions[i]):
			layer.draw_arc(
				_positions[i], radius, 0, TAU, 16, MapStyle.UNKNOWN_STAR_COLOR, 1.2 * px, true
			)


func _draw_fleets(layer: CanvasItem, px: float, view: Rect2) -> void:
	var size := MapStyle.FLEET_PX * px
	var tip := Vector2(size, 0)
	var top := Vector2(-size * 0.6, -size * 0.6)
	var bottom := Vector2(-size * 0.6, size * 0.6)
	for i in _fleet_positions.size():
		if not view.has_point(_fleet_positions[i]):
			continue
		# Fleets at the same spot are stacked to the upper right of the star.
		var origin := _fleet_positions[i] + Vector2(12.0, -10.0 + 9.0 * _fleet_stack[i]) * px
		var color: Color = _fleet_colors[i] if i < _fleet_colors.size() else Color.WHITE
		layer.draw_primitive(
			PackedVector2Array([origin + tip, origin + top, origin + bottom]),
			PackedColorArray([color, color, color]),
			PackedVector2Array()
		)


func _draw_labels(layer: CanvasItem) -> void:
	if _label_font == null or _names.is_empty():
		return
	var px := 1.0 / camera.zoom_level()
	# Far out, systems crowd together and no label would fit.
	if _typical_spacing() / px < MapStyle.LABEL_MIN_SPACING_PX:
		return
	var text_color: Color = FOUi.tokens.text_secondary if FOUi.tokens else Color(0.8, 0.8, 0.8)
	var size := MapStyle.LABEL_FONT_SIZE
	var screen := Rect2(Vector2.ZERO, get_viewport_rect().size)
	var placed := _LabelGrid.new()
	_draw_hover_chip(layer, placed)
	for i in _label_order:
		if i == _hovered:
			continue
		var at := camera.world_to_screen(_positions[i])
		if not screen.has_point(at):
			continue
		var width := _label_widths[i]
		var top_left := at + Vector2(-width * 0.5, MapStyle.LABEL_OFFSET_PX.y)
		var rect := Rect2(top_left, Vector2(width, size * 1.25))
		if not placed.try_place(rect.grow(MapStyle.LABEL_PADDING_PX)):
			continue
		layer.draw_string(
			_label_font,
			(top_left + Vector2(0, size)).round(),
			_names[i],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			size,
			text_color
		)


# The hovered system always gets its name, as a chip that also reserves its
# space so regular labels avoid it.
func _draw_hover_chip(layer: CanvasItem, placed: _LabelGrid) -> void:
	if _hovered == NO_SYSTEM or _hovered >= _names.size() or _names[_hovered].is_empty():
		return
	var tokens: FOTokens = FOUi.tokens
	var size := MapStyle.LABEL_FONT_SIZE
	var width := _label_widths[_hovered]
	var at := camera.world_to_screen(_positions[_hovered])
	var pad := Vector2(tokens.space_2, tokens.space_1) if tokens else Vector2(8, 4)
	var top_left := at + Vector2(-width * 0.5, MapStyle.LABEL_OFFSET_PX.y)
	var chip := Rect2(top_left - pad, Vector2(width, size * 1.25) + pad * 2.0).abs()
	chip.position = chip.position.round()
	placed.try_place(chip)
	var background := tokens.surface_overlay if tokens else Color(0.1, 0.1, 0.12)
	var border := tokens.border_strong if tokens else Color.GRAY
	layer.draw_rect(chip, Color(background, 0.92))
	layer.draw_rect(chip, border, false, 1.0)
	var text_color: Color = tokens.text_primary if tokens else Color.WHITE
	layer.draw_string(
		_label_font,
		(top_left + Vector2(0, size)).round(),
		_names[_hovered],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		text_color
	)


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
	_star_colors.resize(_positions.size())
	for i in _positions.size():
		_star_colors[i] = MapStyle.star_color(_star_type(i))
	_stars.multimesh.instance_count = _positions.size()


# Star quads keep a constant on-screen size, so every zoom step rewrites all
# instances; build the whole buffer (TRANSFORM_2D + color = 12 floats per
# instance) and upload it in one call.
func _update_star_sizes(px: float) -> void:
	var count := _positions.size()
	if count == 0:
		return
	var buffer := PackedFloat32Array()
	buffer.resize(count * 12)
	var base := MapStyle.STAR_PX * px
	for i in count:
		var size := base * MapStyle.star_size(_star_type(i))
		var color := _star_colors[i]
		var o := i * 12
		buffer[o] = size
		buffer[o + 3] = _positions[i].x
		buffer[o + 5] = size
		buffer[o + 7] = _positions[i].y
		buffer[o + 8] = color.r
		buffer[o + 9] = color.g
		buffer[o + 10] = color.b
		buffer[o + 11] = color.a
	_stars.multimesh.buffer = buffer


func _star_type(index: int) -> int:
	return _star_types[index] if index < _star_types.size() else -1


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
