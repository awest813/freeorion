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
## New map data was set (each turn).
signal snapshot_changed
## A system was left-clicked (also when it was selected already).
signal system_clicked(system_id: int)
## A box was dragged from empty space: \a fleet_ids are the fleets inside.
signal fleets_boxed(fleet_ids: PackedInt32Array)
## A system was double-clicked (to build there).
signal system_activated(system_id: int)
## A fleet's marker was clicked.
signal fleet_clicked(fleet_id: int)
## The pointer moved onto a fleet marker (-1: off them).
signal fleet_hovered(fleet_id: int)
## Right-click (not drag) on a system, e.g. to order the active fleet there.
signal system_context_requested(system_id: int)
## Right-click (not drag) on empty space: the map's options menu.
signal map_context_requested(screen_pos: Vector2)
## A field (no system under the cursor) was clicked: its type, for the Pedia.
signal field_activated(field_type: String)

const PICK_RADIUS_PX := 14.0
const GRID_CELL := 64.0
const NO_SYSTEM := -1
## Extra margin around the view when culling, in screen pixels.
const CULL_MARGIN_PX := 32.0
## Map modes: "standard", or a view that brings one thing forward.
const MODES := ["standard", "political", "supply", "detection", "resources", "threat"]
## Screen pixels the mouse must move before a press becomes a box.
const BOX_SLOP_PX := 6.0

var bounds := Rect2()
## Show the player's detection ranges (option ui.map.detection.shown).
## The map mode (a MODES entry); mode_values feeds it.
var map_mode := "standard":
	set(value):
		map_mode = value if value in MODES else "standard"
		if is_node_ready():
			_apply_mode()
## Per system for the mode: {system_id: {color} (political), {industry,
## research} (resources) or {threat}}.
var mode_values := {}:
	set(value):
		mode_values = value
		if is_node_ready():
			_mode_layer.values = value
## Draw a circle as wide as the scale legend around the selected system, to
## judge distances (GG's scale circle).
var show_scale_circle := false:
	set(value):
		show_scale_circle = value
		if is_node_ready():
			_overlay.queue_redraw()
## Only this empire's fleets are box-selected (-2: any).
var own_empire_id := -2
## The fleets: markers, movement lines, the route preview.
var fleets: FleetLayer
## Supply half lanes, split owner rings, scanlines (as GG draws them).
var details := MapDetails.new()
## Twinkling stars, territory borders, nebulae, empire names.
var ambience := MapAmbience.new()
## Pointers to targets off screen (the shell sets their free_area).
var edge_pointers := EdgePointers.new()
## The map options (GG's map menu): owner-coloured system circles, fields,
## background stars, supply.
var show_system_circles := true:
	set(value):
		show_system_circles = value
		if is_node_ready():
			_overlay.queue_redraw()
var show_fields := true:
	set(value):
		show_fields = value
		if is_node_ready():
			_field_layer.visible = value
var show_starfield := true:
	set(value):
		show_starfield = value
		if is_node_ready():
			_starfield.queue_redraw()
var show_supply := true:
	set(value):
		show_supply = value
		if is_node_ready():
			_supply_group.visible = value
## Supplied lanes as bands in the supplier's colour.
var show_supply_lanes := true:
	set(value):
		show_supply_lanes = value
		if is_node_ready():
			_lane_layer.queue_redraw()
var show_detection := false:
	set(value):
		show_detection = value
		if _detection_layer:
			_detection_layer.get_parent().visible = value or map_mode == "detection"
			_detection_layer.queue_redraw()
			_overlay.queue_redraw()  # other empires' ranges

var _system_ids := PackedInt32Array()
var _positions := PackedVector2Array()
var _star_types := PackedInt32Array()
var _names := PackedStringArray()
var _lanes := PackedInt32Array()
## Box selection: where the press started (screen), and whether it's a box.
var _box_from := Vector2.INF
var _box_to := Vector2.ZERO
var _boxing := false
## Field under a left press away from systems: opened on release unless the
## press became a box.
var _pressed_field := -1
## Per system: its owner's colour (alpha 0 for none).
var _owner_colors := PackedColorArray()
var _supply_lanes := PackedInt32Array()
var _supply_lane_colors := PackedColorArray()
var _supply_systems := PackedInt32Array()
var _supply_system_colors := PackedColorArray()
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
var _route_label := ""
var _supply_area: MapLayer
var _field_layer: MapLayer
var _field_positions := PackedVector2Array()
var _field_radii := PackedFloat32Array()
var _field_ids := PackedInt32Array()
var _field_graphics := PackedStringArray()
var _field_types := PackedStringArray()
var _hovered_field := -1
var _hovered_fleet := -1
var _hover_point := Vector2()
var _detection_layer: MapLayer
var _mode_layer: ModeLayer
var _supply_group: CanvasGroup
var _detection_group: CanvasGroup
var _detection_positions := PackedVector2Array()
var _detection_radii := PackedFloat32Array()
## Each circle's owner and colour (own ones are filled, others ringed).
var _detection_owners := PackedInt32Array()
var _detection_colors := PackedColorArray()
## Systems ringed for the player to pick (e.g. where something can be built).
var _highlighted := {}

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
	# Supplied areas: opaque disks in a group faded as a whole, so where the
	# disks overlap the tint stays even.
	var supply_group := CanvasGroup.new()
	supply_group.name = "Supply"
	supply_group.self_modulate = Color(1, 1, 1, MapStyle.SUPPLY_SYSTEM_ALPHA)
	_supply_group = supply_group
	_supply_area = MapLayer.new()
	_supply_area.draw_callback = _draw_supply_area
	supply_group.add_child(_supply_area)
	add_child(supply_group)
	move_child(supply_group, _lane_layer.get_index())
	ambience.setup(self, _stars, supply_group)
	# Detection ranges: one even tint as supply, above it; hidden by default.
	var detection_group := CanvasGroup.new()
	detection_group.name = "Detection"
	detection_group.self_modulate = Color(1, 1, 1, MapStyle.DETECTION_ALPHA)
	detection_group.visible = show_detection
	_detection_group = detection_group
	_detection_layer = MapLayer.new()
	_detection_layer.draw_callback = func(layer): details.draw_own_detection(layer, self)
	detection_group.add_child(_detection_layer)
	add_child(detection_group)
	move_child(detection_group, _lane_layer.get_index())
	# Fields lie under everything else of the map.
	_field_layer = MapLayer.new()
	_field_layer.name = "Fields"
	_field_layer.draw_callback = _draw_fields
	add_child(_field_layer)
	move_child(_field_layer, supply_group.get_index())
	# Map modes draw above the lanes, under fleets and selection.
	_mode_layer = ModeLayer.new()
	_mode_layer.map = self
	add_child(_mode_layer)
	move_child(_mode_layer, _lane_layer.get_index() + 1)
	# Fleets above the overlay (selection, routes).
	var orbits := OrbitLayer.new()
	orbits.map = self
	snapshot_changed.connect(orbits.reset)
	add_child(orbits)
	fleets = FleetLayer.new()
	fleets.map = self
	fleets.preview_changed.connect(_label_layer.queue_redraw)
	add_child(fleets)
	move_child(fleets, _overlay.get_index() + 1)
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
	var color_by_owner := {}
	MapDetails.add_colors(
		snapshot,
		func(owner_id: int) -> Color:
			if not color_by_owner.has(owner_id):
				color_by_owner[owner_id] = FOUniverse.get_empire_color(owner_id)
			return color_by_owner[owner_id]
	)
	set_snapshot(snapshot, names, snapshot["fleet_colors"])


## Replace the map data. \a snapshot has the layout of FOUniverse.get_map_snapshot().
func set_snapshot(
	snapshot: Dictionary, names: PackedStringArray, fleet_colors: PackedColorArray
) -> void:
	var previous_selection := selected_system_id()
	_system_ids = snapshot.get("system_ids", PackedInt32Array())
	_positions = snapshot.get("system_positions", PackedVector2Array())
	_star_types = snapshot.get("system_star_types", PackedInt32Array())
	_lanes = snapshot.get("lanes", PackedInt32Array())
	fleets.set_fleets(snapshot, fleet_colors)
	_field_ids = snapshot.get("field_ids", PackedInt32Array())
	_field_positions = snapshot.get("field_positions", PackedVector2Array())
	_field_radii = snapshot.get("field_radii", PackedFloat32Array())
	_field_graphics = snapshot.get("field_graphics", PackedStringArray())
	_field_types = snapshot.get("field_types", PackedStringArray())
	_detection_positions = snapshot.get("detection_positions", PackedVector2Array())
	_detection_radii = snapshot.get("detection_radii", PackedFloat32Array())
	_detection_owners = snapshot.get("detection_owner_ids", PackedInt32Array())
	_detection_colors = snapshot.get("detection_colors", PackedColorArray())
	_hovered_field = -1
	_supply_lanes = snapshot.get("supply_lanes", PackedInt32Array())
	_supply_lane_colors = snapshot.get("supply_lane_colors", PackedColorArray())
	_supply_systems = snapshot.get("supply_systems", PackedInt32Array())
	_supply_system_colors = snapshot.get("supply_system_colors", PackedColorArray())
	ambience.supply_owners = snapshot.get("supply_system_owners", PackedInt32Array())
	_names = names
	_owner_colors = snapshot.get("system_owner_colors", PackedColorArray())
	details.set_snapshot(snapshot)

	_index_by_id.clear()
	for i in _system_ids.size():
		_index_by_id[_system_ids[i]] = i
	_selected = _index_by_id.get(previous_selection, NO_SYSTEM)
	_hovered = NO_SYSTEM

	_rebuild_bounds()
	ambience.layout(bounds)
	_rebuild_grid()
	_rebuild_stars()
	_rebuild_labels()
	if not _has_framed and bounds.has_area():
		_has_framed = true
		camera.fit_rect(bounds)
	_on_zoom_changed(camera.zoom_level())
	_on_view_changed()
	snapshot_changed.emit()


func system_count() -> int:
	return _system_ids.size()


func system_position(system_id: int) -> Vector2:
	var index: int = _index_by_id.get(system_id, NO_SYSTEM)
	return _positions[index] if index != NO_SYSTEM else Vector2.ZERO


## What the minimap draws: {positions, lanes (index pairs), colors}.
func overview() -> Dictionary:
	return {"positions": _positions, "lanes": _lanes, "colors": _star_colors}


## Radius of the scale circle: the scale legend's length at this zoom.
func scale_circle_radius() -> float:
	return MapScale.nice_length(MapScale.MAX_BAR_PX / camera.zoom_level())


## Ring \a system_ids for the player to pick from; empty clears the rings.
func set_highlighted(system_ids: PackedInt32Array) -> void:
	_highlighted.clear()
	for system_id in system_ids:
		if _index_by_id.has(system_id):
			_highlighted[system_id] = true
	_overlay.queue_redraw()


## Fleets whose position lies in world rectangle \a rect, optionally only
## those of empire \a owner_id.
func fleets_in_rect(rect: Rect2, owner_id := -2) -> PackedInt32Array:
	return fleets.fleets_in_rect(rect, owner_id)


## Ring the markers of \a fleet_ids (fleets selected together).
func set_marked_fleets(fleet_ids: PackedInt32Array) -> void:
	fleets.set_marked(fleet_ids)


func is_highlighted(system_id: int) -> bool:
	return _highlighted.has(system_id)


func selected_system_id() -> int:
	return _system_ids[_selected] if _selected != NO_SYSTEM else NO_SYSTEM


## Show a fleet route: \a start (the fleet's position) through the systems in
## \a system_ids. An empty array clears it.
func set_route(start: Vector2, system_ids: PackedInt32Array, label := "") -> void:
	_route_label = label
	_route = PackedVector2Array()
	if not system_ids.is_empty():
		_route.push_back(start)
		for system_id in system_ids:
			if _index_by_id.has(system_id):
				_route.push_back(_positions[_index_by_id[system_id]])
	_overlay.queue_redraw()
	_label_layer.queue_redraw()


func route_points() -> PackedVector2Array:
	return _route


## Hover highlight and name chip for \a system_id (-1 clears); the mouse
## normally drives this, tests and screenshots call it directly.
## Index of the field covering \a world_pos (the smallest one if several),
## or -1.
func pick_field(world_pos: Vector2) -> int:
	var best := -1
	for i in _field_positions.size():
		var radius := _field_radii[i] if i < _field_radii.size() else 0.0
		if world_pos.distance_to(_field_positions[i]) <= radius:
			if best < 0 or radius < _field_radii[best]:
				best = i
	return best


## The system under the pointer (NO_SYSTEM if none).
func hovered_system_id() -> int:
	return _system_ids[_hovered] if _hovered >= 0 and _hovered < _system_ids.size() else NO_SYSTEM


func hover_system(system_id: int) -> void:
	var index: int = _index_by_id.get(system_id, NO_SYSTEM)
	if index == _hovered:
		return
	_hovered = index
	_overlay.queue_redraw()
	_label_layer.queue_redraw()
	system_hovered.emit(system_id)


## Select \a system_id and glide the camera to it.
func focus_system(system_id: int) -> void:
	if not _index_by_id.has(system_id):
		return
	select_system(system_id)
	camera.center_on(_positions[_index_by_id[system_id]])


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
	if event is InputEventMouseMotion and _box_from != Vector2.INF:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_box_to = event.position
			if not _boxing and _box_from.distance_to(_box_to) > BOX_SLOP_PX:
				_boxing = true
			if _boxing:
				_overlay.queue_redraw()
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and _box_from != Vector2.INF:
			var was_boxing := _boxing
			var rect := Rect2(camera.screen_to_world(_box_from), Vector2.ZERO).expand(
				camera.screen_to_world(event.position)
			)
			_box_from = Vector2.INF
			_boxing = false
			var field := _pressed_field
			_pressed_field = -1
			if was_boxing:
				_overlay.queue_redraw()
				fleets_boxed.emit(fleets_in_rect(rect, own_empire_id))
				get_viewport().set_input_as_handled()
				return
			if field >= 0 and field < _field_types.size():
				field_activated.emit(_field_types[field])
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseMotion:
		var world := camera.screen_to_world(event.position)
		var hovered_id := pick_system(world)
		var fleet_id := fleets.pick(world, 1.0 / camera.zoom_level())
		if fleet_id != _hovered_fleet:
			_hovered_fleet = fleet_id
			fleet_hovered.emit(fleet_id)
		var index: int = _index_by_id.get(hovered_id, NO_SYSTEM)
		if index != _hovered:
			_hovered = index
			_overlay.queue_redraw()
			_label_layer.queue_redraw()
			system_hovered.emit(hovered_id)
		# Away from systems, a field under the cursor gets a name chip.
		var field := pick_field(world) if index == NO_SYSTEM else -1
		if field != _hovered_field or field >= 0:
			_hovered_field = field
			_hover_point = world
			_label_layer.queue_redraw()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			if edge_pointers.follow(self, button.position):
				get_viewport().set_input_as_handled()
				return
			var world := camera.screen_to_world(button.position)
			# A fleet marker beside a star wins over the star.
			var fleet_id := fleets.pick(world, 1.0 / camera.zoom_level())
			if fleet_id >= 0:
				fleet_clicked.emit(fleet_id)
				get_viewport().set_input_as_handled()
				return
			var system_id := pick_system(world)
			# Away from systems a press may become a selection box; if it
			# doesn't, a field there opens on release.
			if system_id == NO_SYSTEM:
				_box_from = button.position
				_box_to = button.position
				_pressed_field = pick_field(world)
				if _pressed_field < 0:
					select_system(NO_SYSTEM)
			else:
				select_system(system_id)
				system_clicked.emit(system_id)
				if button.double_click:
					system_activated.emit(system_id)
			get_viewport().set_input_as_handled()
		elif (
			button.button_index == MOUSE_BUTTON_RIGHT and not button.pressed and camera.was_click()
		):
			var system_id := pick_system(camera.screen_to_world(button.position))
			if system_id != NO_SYSTEM:
				system_context_requested.emit(system_id)
			else:
				map_context_requested.emit(button.position)
			get_viewport().set_input_as_handled()


func _on_zoom_changed(zoom_level: float) -> void:
	_update_star_sizes(1.0 / zoom_level)


func _on_view_changed() -> void:
	_field_layer.queue_redraw()
	_mode_layer.queue_redraw()
	if show_detection:
		_detection_layer.queue_redraw()
	_supply_area.queue_redraw()
	_lane_layer.queue_redraw()
	_overlay.queue_redraw()
	fleets.queue_redraw()
	_label_layer.queue_redraw()


func _on_viewport_resized() -> void:
	_starfield.queue_redraw()
	if bounds.has_area() and not camera.user_moved:
		camera.fit_rect(bounds)


func _draw_starfield(layer: CanvasItem) -> void:
	var size := Vector2i(get_viewport_rect().size)
	if size.x <= 0 or size.y <= 0:
		return
	if not show_starfield:
		layer.draw_rect(Rect2(Vector2.ZERO, Vector2(size)), MapStyle.SPACE_COLOR)
		return
	if _starfield_texture == null or _starfield_texture.get_size() != Vector2(size):
		_starfield_texture = MapStyle.bake_starfield(size)
	layer.draw_texture(_starfield_texture, Vector2.ZERO)


func _draw_lanes(layer: CanvasItem) -> void:
	if _lanes.is_empty():
		return
	var view := visible_world_rect()
	if show_supply_lanes:
		_draw_supply(layer, view)
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
	# A soft glow under each lane.
	layer.draw_multiline(points, Color(MapStyle.LANE_COLOR, 0.08), width * 4.0, true)
	layer.draw_multiline(points, MapStyle.LANE_COLOR, width, true)


# Fields: their art over their radius, each turned by an angle of its own
# so neighbouring storms don't look alike.
func _draw_fields(layer: CanvasItem) -> void:
	var view := visible_world_rect()
	for i in _field_positions.size():
		var center := _field_positions[i]
		var radius := _field_radii[i]
		if radius <= 0.0 or not view.grow(radius).has_point(center):
			continue
		var texture := FOArt.icon(_field_graphics[i]) if i < _field_graphics.size() else null
		if texture == null:
			continue
		var angle := fmod(float(_field_ids[i]) * 2.39996, TAU) if i < _field_ids.size() else 0.0
		layer.draw_set_transform(center, angle)
		layer.draw_texture_rect(
			texture,
			Rect2(-radius, -radius, radius * 2.0, radius * 2.0),
			false,
			Color(1, 1, 1, MapStyle.FIELD_ALPHA)
		)
	layer.draw_set_transform(Vector2.ZERO)
	details.draw_scanlines(layer, _field_positions, _field_radii, view, 1.0 / camera.zoom_level())


# Supplied systems: a disk each in the supplying empire's colour, opaque
# (the group around this layer fades it).
func _apply_mode() -> void:
	var supply_alpha := MapStyle.SUPPLY_SYSTEM_ALPHA
	match map_mode:
		"supply":
			supply_alpha = MapStyle.SUPPLY_MODE_ALPHA
		"political", "resources", "threat":
			supply_alpha = MapStyle.SUPPLY_FADED_ALPHA
	_supply_group.self_modulate = Color(1, 1, 1, supply_alpha)
	_detection_group.visible = show_detection or map_mode == "detection"
	if _detection_group.visible:
		_detection_layer.queue_redraw()
	_mode_layer.mode = map_mode


func _draw_supply_area(layer: CanvasItem) -> void:
	var radius := _typical_spacing() * MapStyle.SUPPLY_SYSTEM_RADIUS
	if not is_finite(radius):
		return
	var grown := visible_world_rect().grow(radius)
	for i in _supply_systems.size():
		var center := _positions[_supply_systems[i]]
		if grown.has_point(center):
			var color := (
				_supply_system_colors[i] if i < _supply_system_colors.size() else Color.WHITE
			)
			layer.draw_circle(center, radius, color)


# Supplied lanes under the lanes: a band in the supplying empire's colour.
func _draw_supply(layer: CanvasItem, view: Rect2) -> void:
	var width := MapStyle.SUPPLY_LANE_PX / camera.zoom_level()
	for i in range(0, _supply_lanes.size() - 1, 2):
		var a := _positions[_supply_lanes[i]]
		var b := _positions[_supply_lanes[i + 1]]
		if not view.intersects(Rect2(a, Vector2.ZERO).expand(b)):
			continue
		var owner := i / 2
		var color := (
			_supply_lane_colors[owner] if owner < _supply_lane_colors.size() else Color.WHITE
		)
		layer.draw_line(a, b, Color(color, MapStyle.SUPPLY_LANE_ALPHA), width, true)
	details.draw_obstructed(layer, _positions, view, width)


func _draw_overlay(layer: CanvasItem) -> void:
	var px := 1.0 / camera.zoom_level()
	var view := visible_world_rect()
	_draw_unexplored_rings(layer, px, view)
	details.draw_other_detection(layer, self, px, view)
	if show_system_circles:
		_draw_owner_circles(layer, px, view)
	_draw_highlights(layer, px, view)
	_draw_route(layer, px)
	_draw_box(layer, px)
	var accent: Color = FOUi.tokens.accent if FOUi.tokens else Color.WHITE
	var ring := MapStyle.SELECTION_RING_PX * px
	if _hovered != NO_SYSTEM and _hovered != _selected:
		layer.draw_arc(_positions[_hovered], ring, 0, TAU, 32, Color(accent, 0.5), 1.5 * px, true)
	if _selected != NO_SYSTEM:
		layer.draw_arc(_positions[_selected], ring, 0, TAU, 40, accent, 2.0 * px, true)
		if show_scale_circle:
			layer.draw_arc(
				_positions[_selected],
				scale_circle_radius(),
				0,
				TAU,
				96,
				Color(accent, 0.6),
				1.5 * px,
				true
			)


func _draw_highlights(layer: CanvasItem, px: float, view: Rect2) -> void:
	var color: Color = FOUi.tokens.positive if FOUi.tokens else Color.GREEN
	var radius := MapStyle.SELECTION_RING_PX * 1.4 * px
	for system_id in _highlighted:
		var index: int = _index_by_id.get(system_id, NO_SYSTEM)
		if index == NO_SYSTEM:
			continue
		var position := _positions[index]
		if view.has_point(position):
			layer.draw_circle(position, radius, Color(color, 0.12))
			layer.draw_arc(position, radius, 0, TAU, 40, color, 2.0 * px, true)


func _draw_route(layer: CanvasItem, px: float) -> void:
	if _route.size() < 2:
		return
	var accent: Color = FOUi.tokens.accent if FOUi.tokens else Color.WHITE
	# The dashes flow towards the destination (still with reduced motion).
	var phase := 0.0 if FOUi.reduce_motion else Time.get_ticks_msec() / 1000.0 * 0.6
	details.draw_flow(layer, _route, accent, 2.0 * px, MapStyle.ROUTE_DASH_PX * px, phase)
	layer.draw_circle(_route[_route.size() - 1], 4.0 * px, accent)


# Owned systems ringed in their owners' colours (GG's system circles).
func _draw_owner_circles(layer: CanvasItem, px: float, view: Rect2) -> void:
	var radius := MapStyle.UNEXPLORED_RING_PX * 1.4 * px
	details.draw_owner_rings(layer, _positions, _owner_colors, view, radius, px)


func _draw_unexplored_rings(layer: CanvasItem, px: float, view: Rect2) -> void:
	var radius := MapStyle.UNEXPLORED_RING_PX * px
	for i in _positions.size():
		if i < _star_types.size() and _star_types[i] < 0 and view.has_point(_positions[i]):
			layer.draw_arc(
				_positions[i], radius, 0, TAU, 16, MapStyle.UNKNOWN_STAR_COLOR, 1.2 * px, true
			)


func _draw_box(layer: CanvasItem, px: float) -> void:
	if not _boxing:
		return
	var accent: Color = FOUi.tokens.accent if FOUi.tokens else Color.WHITE
	var rect := Rect2(camera.screen_to_world(_box_from), Vector2.ZERO).expand(
		camera.screen_to_world(_box_to)
	)
	layer.draw_rect(rect, Color(accent, 0.1))
	layer.draw_rect(rect, accent, false, 1.5 * px)


func _draw_labels(layer: CanvasItem) -> void:
	if _label_font == null or _names.is_empty():
		return
	edge_pointers.draw(layer, self, _label_font)
	var px := 1.0 / camera.zoom_level()
	# Far out, systems crowd together and no label would fit.
	if _typical_spacing() / px < MapStyle.LABEL_MIN_SPACING_PX:
		ambience.draw_empire_names(layer, self)
		return
	var text_color: Color = FOUi.tokens.text_secondary if FOUi.tokens else Color(0.8, 0.8, 0.8)
	var size := MapStyle.LABEL_FONT_SIZE
	var screen := Rect2(Vector2.ZERO, get_viewport_rect().size)
	var placed := LabelGrid.new()
	_draw_route_chip(layer, placed)
	_draw_preview_chip(layer, placed)
	_draw_hover_chip(layer, placed)
	_draw_field_chip(layer, placed)
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
		# Owned systems' names in their owner's colour, lightened to read.
		var color := text_color
		if i < _owner_colors.size() and _owner_colors[i].a > 0.0:
			color = _owner_colors[i].lerp(Color.WHITE, 0.35)
		layer.draw_string(
			_label_font, (top_left + Vector2(0, size)).round(), _names[i], 0, -1, size, color
		)


# ETA (or other route text) next to the end of the planned route.
func _draw_route_chip(layer: CanvasItem, placed: LabelGrid) -> void:
	if _route.size() < 2 or _route_label.is_empty():
		return
	var tokens: FOTokens = FOUi.tokens
	var size := MapStyle.LABEL_FONT_SIZE
	var width := _label_font.get_string_size(_route_label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var end := camera.world_to_screen(_route[_route.size() - 1])
	var pad := Vector2(tokens.space_2, tokens.space_1)
	var top_left := (end + Vector2(MapStyle.SELECTION_RING_PX + pad.x, -size * 0.6)).round()
	var chip := Rect2(top_left - pad, Vector2(width, size * 1.25) + pad * 2.0)
	placed.try_place(chip)
	layer.draw_rect(chip, Color(tokens.accent, 0.9))
	layer.draw_string(
		_label_font,
		top_left + Vector2(0, size),
		_route_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		tokens.text_on_accent
	)


# ETA of the route a fleet would take, beside its end; in the warning colour
# when it can't get there (the label says why).
func _draw_preview_chip(layer: CanvasItem, placed: LabelGrid) -> void:
	var points := fleets.preview_points()
	if points.size() < 2 or fleets.preview_label().is_empty():
		return
	var at := camera.world_to_screen(points[points.size() - 1])
	var warning := fleets.is_preview_warning() and FOUi.tokens != null
	_draw_chip(
		layer,
		placed,
		fleets.preview_label(),
		at + Vector2(0, -MapStyle.LABEL_FONT_SIZE * 2.4),
		FOUi.tokens.negative if warning else Color.TRANSPARENT
	)


# The hovered system always gets its name, as a chip that also reserves its
# space so regular labels avoid it.
func _draw_hover_chip(layer: CanvasItem, placed: LabelGrid) -> void:
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


# Name of the field under the cursor, just below it.
func _draw_field_chip(layer: CanvasItem, placed: LabelGrid) -> void:
	if _hovered != NO_SYSTEM or _hovered_field < 0 or _hovered_field >= _field_types.size():
		return
	var text := TranslationServer.translate(_field_types[_hovered_field])
	var at := camera.world_to_screen(_hover_point) + Vector2(0, MapStyle.LABEL_OFFSET_PX.y + 8)
	_draw_chip(layer, placed, text, at)


# A text chip centred horizontally on \a at (its top edge).
func _draw_chip(
	layer: CanvasItem, placed: LabelGrid, text: String, at: Vector2, border := Color.TRANSPARENT
) -> void:
	var tokens: FOTokens = FOUi.tokens
	var size := MapStyle.LABEL_FONT_SIZE
	var width := _label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pad := Vector2(tokens.space_2, tokens.space_1) if tokens else Vector2(8, 4)
	var top_left := at + Vector2(-width * 0.5, 0)
	var chip := Rect2(top_left - pad, Vector2(width, size * 1.25) + pad * 2.0).abs()
	chip.position = chip.position.round()
	placed.try_place(chip)
	layer.draw_rect(chip, Color(tokens.surface_overlay if tokens else Color(0.1, 0.1, 0.12), 0.92))
	var edge: Color = tokens.border_strong if tokens else Color.GRAY
	layer.draw_rect(chip, border if border.a > 0.0 else edge, false, 2.0 if border.a > 0.0 else 1.0)
	layer.draw_string(
		_label_font,
		(top_left + Vector2(0, size)).round(),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		tokens.text_primary if tokens else Color.WHITE
	)


# The player's detection ranges, opaque (the group around this layer fades
# them), with their rims drawn a little stronger.
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
