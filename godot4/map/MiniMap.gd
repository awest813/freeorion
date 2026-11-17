class_name MiniMap
extends PanelContainer
## Overview of the whole galaxy: lanes, systems (with a halo in the colour
## of the empire that supplies them), the selected system and the part the
## map shows. Clicking or dragging on it moves the map there.

const SIZE := Vector2(220, 160)
const PAD := 8.0
## Halo round a supplied system, and its opacity.
const SUPPLY_HALO_PX := 4.0
const SUPPLY_HALO_ALPHA := 0.4

var map: GalaxyMap:
	set(value):
		map = value
		if map:
			map.camera.view_changed.connect(_canvas.queue_redraw)
			map.snapshot_changed.connect(_canvas.queue_redraw)
			map.system_selected.connect(func(_id): _canvas.queue_redraw())
		_canvas.queue_redraw()

var _canvas := Control.new()


func _init() -> void:
	theme_type_variation = "OverlayPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.custom_minimum_size = SIZE
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)
	tooltip_text = tr("MINIMAP_TIP")


## Galaxy point shown at \a local (a point in the canvas).
func to_world(local: Vector2) -> Vector2:
	var frame := _frame()
	var bounds := map.bounds
	var t := (local - frame.position) / frame.size
	return bounds.position + t * bounds.size


## Canvas point for galaxy point \a world.
func to_local(world: Vector2) -> Vector2:
	var frame := _frame()
	var bounds := map.bounds
	return frame.position + (world - bounds.position) / bounds.size * frame.size


# The galaxy's bounds fitted into the canvas, keeping their shape.
func _frame() -> Rect2:
	var room := _canvas.size - Vector2.ONE * PAD * 2.0
	var bounds_size := map.bounds.size if map and map.bounds.has_area() else Vector2.ONE
	var scale := minf(room.x / bounds_size.x, room.y / bounds_size.y)
	var size := bounds_size * scale
	return Rect2(Vector2.ONE * PAD + (room - size) / 2.0, size)


func _gui_input(event: InputEvent) -> void:
	if not map or not map.bounds.has_area():
		return
	var press: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
	var drag: bool = (
		event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	)
	if (press and event.pressed) or drag:
		var local: Vector2 = event.position - _canvas.position
		map.camera.set_view(to_world(local), map.camera.zoom_level())
		map.camera.user_moved = true
		accept_event()


func _draw_map() -> void:
	if not map or not map.bounds.has_area():
		return
	var tokens := FOUi.tokens
	var overview := map.overview()
	var positions: PackedVector2Array = overview["positions"]
	var lanes: PackedInt32Array = overview["lanes"]
	var lane_color := Color(tokens.text_secondary, 0.35)
	for i in range(0, lanes.size() - 1, 2):
		_canvas.draw_line(
			to_local(positions[lanes[i]]), to_local(positions[lanes[i + 1]]), lane_color, 1.0
		)
	# Who holds what: a halo in the supplying empire's colour.
	var supplied: PackedInt32Array = overview.get("supply_systems", PackedInt32Array())
	var supply_colors: PackedColorArray = overview.get("supply_colors", PackedColorArray())
	for k in supplied.size():
		if supplied[k] < positions.size() and k < supply_colors.size():
			_canvas.draw_circle(
				to_local(positions[supplied[k]]),
				SUPPLY_HALO_PX,
				Color(supply_colors[k], SUPPLY_HALO_ALPHA)
			)
	var colors: PackedColorArray = overview["colors"]
	for i in positions.size():
		var color: Color = colors[i] if i < colors.size() else Color.WHITE
		_canvas.draw_circle(to_local(positions[i]), 1.6, color)
	var selected: int = overview.get("selected", -1)
	if selected >= 0 and selected < positions.size():
		_canvas.draw_arc(to_local(positions[selected]), 4.5, 0.0, TAU, 16, tokens.accent, 1.5, true)
	var view := map.visible_world_rect().grow(-GalaxyMap.CULL_MARGIN_PX / map.camera.zoom_level())
	var rect := Rect2(to_local(view.position), Vector2.ZERO).expand(to_local(view.end))
	rect = rect.intersection(Rect2(Vector2.ZERO, _canvas.size))
	_canvas.draw_rect(rect, Color(tokens.accent, 0.12))
	_canvas.draw_rect(rect, tokens.accent, false, 1.5)
