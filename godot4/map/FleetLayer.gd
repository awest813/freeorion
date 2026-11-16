class_name FleetLayer
extends Node2D
## The galaxy map's fleets, for GalaxyMap: a marker each in its owner's
## colour (stacked beside the star when several share a place), the paths of
## fleets under way with a dot where each turn ends (GG's movement lines),
## and the route a selected fleet would take to the hovered system. Picks
## the fleet under the cursor.

## The previewed route or the places to settle changed (their labels and
## edge pointers are drawn with the map's labels).
signal preview_changed

## Screen pixels around a marker that still pick it.
const PICK_PX := 10.0
## Fleet icons (GG's FleetButton art): head by role, tail by size.
const ICON_DIR := "icons/fleet/med-"
## Screen size of a fleet icon, and the step between fleets stacked at one
## place.
const ICON_PX := 20.0
const STACK_PX := 18.0

## Turn-end markers: radius and number size, in screen pixels.
const MARK_PX := 7.0
const MARK_FONT := 10
## Text size of the places-to-settle marks.
const SETTLE_FONT := 12
var map: GalaxyMap
## The selected fleet, ringed (-1 for none).
var selected_fleet := -1:
	set(value):
		selected_fleet = value
		queue_redraw()
## Draw the paths of moving fleets (GG's ui.map.fleet.eta.shown).
var show_paths := true:
	set(value):
		show_paths = value
		queue_redraw()

var _positions := PackedVector2Array()
var _ids := PackedInt32Array()
var _owners := PackedInt32Array()
var _colors := PackedColorArray()
var _stack := PackedInt32Array()
var _paths: Array = []
var _blockaded := PackedByteArray()
var _heads := PackedStringArray()
var _ship_counts := PackedInt32Array()
var _stale := PackedByteArray()
var _turn_ends: Array = []
## Per fleet, per turn end: the turn it gets there, and 1 (blockade stops
## it) or 2 (out of supply by then), as GG's ETA markers.
var _turn_etas: Array = []
var _turn_flags: Array = []
## Fleets marked as selected together (box selection): id -> true.
var _marked := {}
var _preview := PackedVector2Array()
var _preview_turn_ends := PackedVector2Array()
var _preview_label := ""
var _preview_etas := PackedInt32Array()
var _preview_flags := PackedInt32Array()
## The previewed route can't get there (no route, or out of fuel range).
var _preview_warning := false
## Places the selected colony fleet could settle: [{position, text}].
var _settle_marks: Array = []


func _init() -> void:
	name = "Fleets"


## Take the fleets of \a snapshot (GalaxyMap.set_snapshot()), drawn in \a colors.
func set_fleets(snapshot: Dictionary, colors: PackedColorArray) -> void:
	_positions = snapshot.get("fleet_positions", PackedVector2Array())
	_ids = snapshot.get("fleet_ids", PackedInt32Array())
	_owners = snapshot.get("fleet_owner_ids", PackedInt32Array())
	_paths = snapshot.get("fleet_paths", [])
	_turn_ends = snapshot.get("fleet_turn_ends", [])
	_turn_etas = snapshot.get("fleet_turn_etas", [])
	_turn_flags = snapshot.get("fleet_turn_flags", [])
	_blockaded = snapshot.get("fleet_blockaded", PackedByteArray())
	_heads = snapshot.get("fleet_heads", PackedStringArray())
	_ship_counts = snapshot.get("fleet_ship_counts", PackedInt32Array())
	_stale = snapshot.get("fleet_stale", PackedByteArray())
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
	return _positions[index] + Vector2(20.0, -14.0 + STACK_PX * stack) * px


## The world position of fleet \a fleet_id's marker (tests), or INF.
func marker_of(fleet_id: int, px: float) -> Vector2:
	var index := _ids.find(fleet_id)
	return marker_origin(index, px) if index >= 0 else Vector2.INF


## Show where a fleet would go: its move path \a points, the turn ends on it,
## and \a label (the ETA) by its end. Empty points clear it.
func set_preview(
	points: PackedVector2Array,
	turn_ends: PackedVector2Array,
	label := "",
	etas := PackedInt32Array(),
	flags := PackedInt32Array(),
	warning := false
) -> void:
	_preview_warning = warning
	_preview = points
	_preview_turn_ends = turn_ends
	_preview_etas = etas
	_preview_flags = flags
	_preview_label = label if points.size() > 1 else ""
	queue_redraw()
	preview_changed.emit()


func preview_points() -> PackedVector2Array:
	return _preview


func preview_label() -> String:
	return _preview_label


func is_preview_warning() -> bool:
	return _preview_warning


## Mark \a marks ([{position (world), text}]) on the map: the places the
## selected colony or outpost fleet could settle (none: clear them).
func set_settle_marks(marks: Array) -> void:
	_settle_marks = marks
	queue_redraw()
	preview_changed.emit()


func settle_marks() -> Array:
	return _settle_marks


func is_blockaded(fleet_id: int) -> bool:
	var index := _ids.find(fleet_id)
	return index >= 0 and index < _blockaded.size() and _blockaded[index] == 1


## The path fleet \a fleet_id is on (empty if not moving).
func path_of(fleet_id: int) -> PackedVector2Array:
	var index := _ids.find(fleet_id)
	return _paths[index] if index >= 0 and index < _paths.size() else PackedVector2Array()


func _draw() -> void:
	if map == null:
		return
	var px := 1.0 / map.camera.zoom_level()
	var view := map.visible_world_rect()
	if show_paths:
		_draw_paths(px, view)
	_draw_preview(px)
	_draw_settle_marks(px)
	_draw_markers(px, view)


# A dashed ring in the positive colour around each place to settle, with
# what grows there and how far, below the star's name.
func _draw_settle_marks(px: float) -> void:
	if _settle_marks.is_empty() or FOUi.tokens == null:
		return
	var color: Color = FOUi.tokens.positive
	var font := ThemeDB.fallback_font
	for mark: Dictionary in _settle_marks:
		var at: Vector2 = mark.get("position", Vector2.ZERO)
		for n in 16:
			if n % 2 == 0:
				var from := n * TAU / 16.0
				draw_arc(at, 16.0 * px, from, from + TAU / 16.0, 4, color, 2.0 * px, true)
		var text: String = mark.get("text", "")
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SETTLE_FONT).x
		draw_set_transform(at + Vector2(0, 30.0 * px), 0.0, Vector2.ONE * px)
		draw_string(
			font,
			Vector2(-width / 2.0, font.get_ascent(SETTLE_FONT)),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			SETTLE_FONT,
			color
		)
		draw_set_transform(Vector2.ZERO)


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
			var ends: PackedVector2Array = _turn_ends[i]
			var etas: PackedInt32Array = (
				_turn_etas[i] if i < _turn_etas.size() else PackedInt32Array()
			)
			var flags: PackedInt32Array = (
				_turn_flags[i] if i < _turn_flags.size() else PackedInt32Array()
			)
			for k in ends.size():
				if k < etas.size():
					_draw_turn_mark(
						ends[k], etas[k], flags[k] if k < flags.size() else 0, color, px
					)
				else:
					draw_circle(ends[k], 2.5 * px, line)


func _draw_preview(px: float) -> void:
	if _preview.size() < 2:
		return
	var accent: Color = FOUi.tokens.accent if FOUi.tokens else Color.WHITE
	if _preview_warning and FOUi.tokens:
		accent = FOUi.tokens.negative
	var line := Color(accent, 0.7)
	for i in _preview.size() - 1:
		draw_dashed_line(
			_preview[i], _preview[i + 1], line, 2.0 * px, MapStyle.ROUTE_DASH_PX * px, true, true
		)
	for k in _preview_turn_ends.size():
		if k < _preview_etas.size():
			var flag := _preview_flags[k] if k < _preview_flags.size() else 0
			_draw_turn_mark(_preview_turn_ends[k], _preview_etas[k], flag, accent, px)
		else:
			draw_circle(_preview_turn_ends[k], 3.0 * px, line)
	draw_arc(_preview[_preview.size() - 1], 5.0 * px, 0, TAU, 20, accent, 1.5 * px, true)


# A turn end as GG marks it: a disc in \a color with the turn number, ringed
# in red and black where a blockade stops the fleet, yellow and black where
# it's out of supply.
func _draw_turn_mark(at: Vector2, eta: int, flag: int, color: Color, px: float) -> void:
	var radius := MARK_PX * px
	if flag > 0:
		var ring := Color.RED if flag == 1 else Color.YELLOW
		for n in 12:
			var from := n * TAU / 12.0
			draw_arc(
				at,
				radius + 2.0 * px,
				from,
				from + TAU / 12.0,
				4,
				ring if n % 2 else Color.BLACK,
				2.5 * px
			)
	draw_circle(at, radius, Color(color.darkened(0.35), 0.9))
	var font := ThemeDB.fallback_font
	var text := str(eta)
	draw_set_transform(at, 0.0, Vector2.ONE * px)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, MARK_FONT).x
	draw_string(
		font,
		Vector2(-width / 2.0, font.get_ascent(MARK_FONT) / 2.0 - 1.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		MARK_FONT,
		Color.WHITE
	)
	draw_set_transform(Vector2.ZERO)


## Index of GG's size mark for \a ships ships: 0 for one, one more for
## each doubling, at most 7.
static func size_mark(ships: int) -> int:
	var mark := 0
	var count := maxi(ships, 1)
	while count >= 2 and mark < 7:
		count /= 2
		mark += 1
	return mark


# The selected fleet's ring: four arcs turning slowly (still with reduced
# motion).
func _draw_selection_ring(origin: Vector2, radius: float, color: Color, px: float) -> void:
	var turn := 0.0 if FOUi.reduce_motion else Time.get_ticks_msec() / 1000.0 * 0.9
	for k in 4:
		var from := turn + k * TAU / 4.0
		draw_arc(origin, radius, from, from + TAU / 6.0, 8, color, 2.0 * px, true)


func _process(_delta: float) -> void:
	# The selection ring turns.
	if selected_fleet >= 0 and not FOUi.reduce_motion and is_visible_in_tree():
		queue_redraw()


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
		# Fleets not seen this turn (sensor ghosts) are drawn faded.
		if i < _stale.size() and _stale[i]:
			color.a = 0.35
		var fleet_id := _ids[i] if i < _ids.size() else -1
		# A blockaded fleet gets a bar across its marker.
		if i < _blockaded.size() and _blockaded[i]:
			var bar := Vector2(0, size * 0.9)
			draw_line(
				origin - bar + Vector2(size * 1.1, 0),
				origin + bar + Vector2(size * 1.1, 0),
				MapStyle.BLOCKADE_COLOR,
				2.0 * px,
				true
			)
		# A soft glow in the owner's colour under each fleet seen now.
		if color.a > 0.5:
			draw_circle(origin, ICON_PX * 0.55 * px, Color(color, 0.18))
		if fleet_id == selected_fleet:
			_draw_selection_ring(origin, ICON_PX * 0.66 * px, accent, px)
		elif _marked.has(fleet_id):
			draw_arc(origin, ICON_PX * 0.62 * px, 0, TAU, 24, accent, 1.5 * px, true)
		var head: Texture2D = (
			FOArt.icon(ICON_DIR + "head-" + _heads[i] + ".png") if i < _heads.size() else null
		)
		if head == null:
			draw_primitive(
				PackedVector2Array([origin + tip, origin + top, origin + bottom]),
				PackedColorArray([color, color, color]),
				PackedVector2Array()
			)
			continue
		# Pointing where the fleet goes (right when it stays).
		var path: PackedVector2Array = _paths[i] if i < _paths.size() else PackedVector2Array()
		var angle := (path[1] - path[0]).angle() if path.size() > 1 else 0.0
		var rect := Rect2(Vector2.ONE * -ICON_PX * 0.5 * px, Vector2.ONE * ICON_PX * px)
		draw_set_transform(origin, angle)
		var ships := _ship_counts[i] if i < _ship_counts.size() else 1
		var tail := FOArt.icon(ICON_DIR + "tail-%d.png" % size_mark(ships))
		if tail:
			draw_texture_rect(tail, rect, false, color)
		draw_texture_rect(head, rect, false, color)
		draw_set_transform(Vector2.ZERO)
