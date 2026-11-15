class_name Toast
extends PanelContainer
## A short note at the bottom middle of the screen that goes away by
## itself (after SHOW_SECONDS, longer while the pointer is on it); clicking
## it emits `pressed` (e.g. to open where the full text is). A newer note
## replaces the shown one, so notes never stack.

signal pressed

## Seconds a note stays.
const SHOW_SECONDS := 6.0
const WIDTH := 420.0

var _label: Label
var _left := 0.0


func _init() -> void:
	theme_type_variation = "OverlayPanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size.x = WIDTH
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = WIDTH - 32.0
	add_child(_label)
	set_process(false)


## Show \a text (replacing any note shown).
func show_text(text: String) -> void:
	_label.text = text
	_left = SHOW_SECONDS
	visible = true
	reset_size()
	_place.call_deferred()
	FOUi.fade_in(self)
	set_process(true)


func text() -> String:
	return _label.text if visible else ""


func _process(delta: float) -> void:
	if get_global_rect().has_point(get_global_mouse_position()):
		return
	_left -= delta
	if _left <= 0.0:
		visible = false
		set_process(false)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		visible = false
		set_process(false)
		pressed.emit()
		accept_event()


# Bottom middle of the parent, clear of the map's bottom bar.
func _place() -> void:
	var parent := get_parent_control()
	if parent == null:
		return
	var gap: float = FOUi.tokens.space_8 if FOUi.tokens else 32.0
	position = Vector2((parent.size.x - size.x) / 2.0, parent.size.y - size.y - gap * 3.0)
