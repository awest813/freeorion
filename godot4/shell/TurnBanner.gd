class_name TurnBanner
extends Control
## A new turn, announced across the middle of the map: the empire's flag
## and "TURN 12" in the display face, in and out within about two seconds,
## never in the way of the pointer. Not shown with reduced motion.

## Seconds: coming in, staying, going.
const IN := 0.25
const HOLD := 0.9
const OUT := 0.6

var _flag: TextureRect
var _title: Label
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	_flag = ScreenKit.icon("", FOUi.tokens.icon_large)
	_flag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_flag)
	_title = ScreenKit.label("", "DisplayTitle")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.uppercase = true
	_title.add_theme_constant_override("outline_size", FOUi.tokens.space_1)
	_title.add_theme_color_override("font_outline_color", FOUi.tokens.shadow)
	column.add_child(_title)


## Announce turn \a turn of the empire whose \a flag it is (or none).
func announce(turn: int, flag: Texture2D) -> void:
	if FOUi.reduce_motion or turn < 1:
		return
	_title.text = tr("MAP_BTN_TURN_UPDATE").replace("%1%", str(turn))
	_flag.texture = flag
	_flag.visible = flag != null
	visible = true
	modulate.a = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, IN)
	_tween.tween_interval(HOLD)
	_tween.tween_property(self, "modulate:a", 0.0, OUT)
	_tween.tween_callback(func(): visible = false)
