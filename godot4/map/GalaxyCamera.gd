class_name GalaxyCamera
extends Camera2D
## Galaxy map camera: smooth zoom anchored at the cursor, drag and keyboard pan.

signal zoom_changed(zoom_level: float)
## Emitted once per frame in which the camera moved or zoomed.
signal view_changed

const WHEEL_FACTOR := 1.2
const KEY_ZOOM_FACTOR := 1.5
const SMOOTHING := 14.0
const KEY_PAN_SPEED_PX := 900.0
const FIT_MARGIN := 0.08
const CLICK_SLOP_PX := 4.0

const ACTIONS := {
	"map_pan_left": [KEY_A, KEY_LEFT],
	"map_pan_right": [KEY_D, KEY_RIGHT],
	"map_pan_up": [KEY_W, KEY_UP],
	"map_pan_down": [KEY_S, KEY_DOWN],
	"map_zoom_in": [KEY_EQUAL, KEY_KP_ADD],
	"map_zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
	"map_home": [KEY_HOME],
}

var min_zoom := 0.02
var max_zoom := 8.0
## True once the player zoomed or panned; until then the map re-frames on resize.
var user_moved := false
## Pixels the mouse moved during the current or last right/middle drag; a
## release under CLICK_SLOP_PX counts as a click (GalaxyMap uses it for orders).
var drag_distance := 0.0
## Screen pixels covered by UI on each side (left, top, right, bottom), kept
## out of the area fit_rect frames.
var frame_margins := Vector4.ZERO

var _target_zoom := 1.0
var _anchor_screen := Vector2.ZERO
var _anchor_world := Vector2.ZERO
var _anchored := false
var _dragging := false
var _home_rect := Rect2()
var _pan_tween: Tween
var _last_position := Vector2.INF
var _last_zoom := -1.0


func _ready() -> void:
	ignore_rotation = true
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	_target_zoom = zoom.x
	_ensure_actions()


## Glide to \a world_pos (instantly when motion is reduced).
func center_on(world_pos: Vector2) -> void:
	user_moved = true
	_anchored = false
	if _pan_tween:
		_pan_tween.kill()
	if FOUi.reduce_motion:
		position = world_pos
		return
	_pan_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pan_tween.tween_property(self, "position", world_pos, FOUi.tokens.motion * 2.0)


## Jump to \a world_center at \a zoom (within the zoom limits), e.g. a
## view saved with the game.
func set_view(world_center: Vector2, zoom_value: float) -> void:
	user_moved = true
	_anchored = false
	if _pan_tween:
		_pan_tween.kill()
	position = world_center
	_target_zoom = clampf(zoom_value, min_zoom, max_zoom)
	_set_zoom_now(_target_zoom)
	_notify_view_change()


## True if the last right/middle button press-release moved less than the slop.
func was_click() -> bool:
	return drag_distance < CLICK_SLOP_PX


func zoom_level() -> float:
	return zoom.x


## Frame \a rect in the view and set the zoom limits around it.
func fit_rect(rect: Rect2) -> void:
	_home_rect = rect
	user_moved = false
	var view := get_viewport_rect().size
	# Frame inside the part of the view not covered by UI (frame_margins).
	var area := view - Vector2(frame_margins.x + frame_margins.z, frame_margins.y + frame_margins.w)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or area.x <= 0.0 or area.y <= 0.0:
		return
	var fit := minf(
		area.x / (rect.size.x * (1.0 + FIT_MARGIN)), area.y / (rect.size.y * (1.0 + FIT_MARGIN))
	)
	min_zoom = fit * 0.5
	max_zoom = maxf(fit * 40.0, 4.0)
	_anchored = false
	var area_offset := (
		Vector2(frame_margins.x - frame_margins.z, frame_margins.y - frame_margins.w) * 0.5
	)
	position = rect.get_center() - area_offset / fit
	_target_zoom = fit
	_set_zoom_now(fit)
	_notify_view_change()


## Zoom by \a factor keeping the world point under \a screen_pos fixed.
func zoom_at(factor: float, screen_pos: Vector2) -> void:
	user_moved = true
	_anchor_screen = screen_pos
	_anchor_world = screen_to_world(screen_pos)
	_anchored = true
	_target_zoom = clampf(_target_zoom * factor, min_zoom, max_zoom)


func screen_to_world(screen_pos: Vector2) -> Vector2:
	return position + (screen_pos - get_viewport_rect().size * 0.5) / zoom.x


func world_to_screen(world_pos: Vector2) -> Vector2:
	return (world_pos - position) * zoom.x + get_viewport_rect().size * 0.5


func _process(delta: float) -> void:
	if _keyboard_free():
		var pan := Input.get_vector("map_pan_left", "map_pan_right", "map_pan_up", "map_pan_down")
		if pan != Vector2.ZERO:
			user_moved = true
			position += pan * KEY_PAN_SPEED_PX * delta / zoom.x
			if _anchored:
				_anchor_world = screen_to_world(_anchor_screen)

	if not is_equal_approx(zoom.x, _target_zoom):
		var z := lerpf(zoom.x, _target_zoom, 1.0 - exp(-SMOOTHING * delta))
		if absf(z - _target_zoom) < _target_zoom * 0.001:
			z = _target_zoom
		_set_zoom_now(z)
	_notify_view_change()


func _notify_view_change() -> void:
	if position != _last_position or zoom.x != _last_zoom:
		_last_position = position
		_last_zoom = zoom.x
		view_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP when button.pressed:
				zoom_at(WHEEL_FACTOR, button.position)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN when button.pressed:
				zoom_at(1.0 / WHEEL_FACTOR, button.position)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_dragging = button.pressed
				if button.pressed:
					drag_distance = 0.0
	elif event is InputEventMouseMotion and _dragging:
		var relative := (event as InputEventMouseMotion).relative
		drag_distance += relative.length()
		position -= relative / zoom.x
		_anchored = false
		user_moved = true
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		user_moved = true
		position += (event as InputEventPanGesture).delta * 20.0 / zoom.x
	elif event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		zoom_at(magnify.factor, magnify.position)
	elif _keyboard_free():
		var center := get_viewport_rect().size * 0.5
		if event.is_action_pressed("map_zoom_in"):
			zoom_at(KEY_ZOOM_FACTOR, center)
		elif event.is_action_pressed("map_zoom_out"):
			zoom_at(1.0 / KEY_ZOOM_FACTOR, center)
		elif event.is_action_pressed("map_home") and _home_rect.has_area():
			fit_rect(_home_rect)


func _set_zoom_now(z: float) -> void:
	zoom = Vector2(z, z)
	if _anchored:
		position = _anchor_world - (_anchor_screen - get_viewport_rect().size * 0.5) / z
	zoom_changed.emit(z)


# Keyboard panning must not fire while the player types into a text field.
func _keyboard_free() -> bool:
	var root_focus := get_tree().root.gui_get_focus_owner()
	return not (root_focus is LineEdit or root_focus is TextEdit)


static func _ensure_actions() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in ACTIONS[action]:
			var key := InputEventKey.new()
			key.physical_keycode = keycode
			InputMap.action_add_event(action, key)
