extends GutTest
## Tooltips: they wrap when long, and Esc still reaches the game while one
## shows (Godot's viewport would keep it to close the tooltip).

const LISTENER := """extends Node
var escapes := 0
func _unhandled_key_input(event):
	if event.is_action_pressed("ui_cancel"):
		escapes += 1
"""

const CUSTOM_TIP := """extends Button
func _make_custom_tooltip(for_text):
	var label := Label.new()
	label.text = for_text
	return label
"""


func _key(keycode: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.physical_keycode = keycode
	key.pressed = true
	return key


func test_escape_reaches_the_game_while_a_tooltip_shows():
	await _escape_with_tooltip(Button.new())


func test_escape_reaches_the_game_past_a_custom_tooltip():
	var script := GDScript.new()
	script.source_code = CUSTOM_TIP
	script.reload()
	await _escape_with_tooltip(script.new())


func _escape_with_tooltip(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		pending("Tooltips only show with a display (run with xvfb)")
		return
	button.text = "Hover me"
	button.tooltip_text = "A tip"
	button.position = Vector2(100, 100)
	button.size = Vector2(120, 40)
	add_child_autofree(button)
	var script := GDScript.new()
	script.source_code = LISTENER
	script.reload()
	var listener: Node = script.new()
	add_child_autofree(listener)
	await wait_process_frames(2)
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	motion.global_position = motion.position
	get_viewport().push_input(motion)
	await wait_seconds(1.2)
	var tips := get_tree().root.find_children("*", "PopupPanel", true, false)
	assert_false(tips.is_empty(), "the tooltip shows")
	get_viewport().push_input(_key(KEY_ESCAPE))
	await wait_process_frames(3)
	assert_eq(listener.escapes, 1, "one Esc closes the tooltip and reaches the game")
