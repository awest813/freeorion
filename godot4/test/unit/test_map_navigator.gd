extends GutTest
## MapNavigator with fixed targets.

var nav: MapNavigator


func before_each():
	nav = MapNavigator.new()
	nav.targets_provider = func(kind: String) -> Array:
		return (
			[
				{"system_id": 1, "fleet_id": -1, "position": Vector2.ZERO},
				{"system_id": 2, "fleet_id": -1, "position": Vector2.ONE},
				{"system_id": 3, "fleet_id": -1, "position": Vector2(2, 2)},
			]
			if kind == "system"
			else []
		)


func test_steps_forward_and_back_with_wrap_around():
	assert_eq(nav.step("system", 1)["system_id"], 1)
	assert_eq(nav.step("system", 1)["system_id"], 2)
	assert_eq(nav.step("system", -1)["system_id"], 1)
	assert_eq(nav.step("system", -1)["system_id"], 3, "Wraps around")


func test_starting_backwards_gives_the_last():
	assert_eq(nav.step("system", -1)["system_id"], 3)


func test_no_targets():
	assert_eq(nav.step("idle", 1), {})


func test_keys():
	assert_eq(MapNavigator.match_hotkey(FOHotkeys.match_event(_key("Ctrl+Period"))), ["system", 1])
	assert_eq(
		MapNavigator.match_hotkey(FOHotkeys.match_event(_key("Shift+Ctrl+Period"))), ["owned", 1]
	)
	assert_eq(MapNavigator.match_hotkey(FOHotkeys.match_event(_key("Alt+F"))), ["idle", -1])
	assert_eq(MapNavigator.match_hotkey(FOHotkeys.match_event(_key("X"))), [])


func _key(text: String) -> InputEventKey:
	var key := FOHotkeys.parse(text)
	key.pressed = true
	return key


func test_shell_goes_to_targets_and_toggles_detection():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(2)
	var snapshot := {
		"system_ids": PackedInt32Array([5, 6]),
		"system_positions": PackedVector2Array([Vector2.ZERO, Vector2(300, 0)]),
		"system_star_types": PackedInt32Array([1, 2]),
		"lanes": PackedInt32Array([0, 1]),
	}
	shell.map_view.map.set_snapshot(snapshot, PackedStringArray(["A", "B"]), PackedColorArray())
	shell.go_to({"system_id": 6, "fleet_id": -1, "position": Vector2(300, 0)})
	assert_eq(shell.map_view.map.selected_system_id(), 6)
	var key := InputEventKey.new()
	key.keycode = KEY_D
	key.ctrl_pressed = true
	key.pressed = true
	shell._unhandled_key_input(key)
	assert_true(shell.map_view.map.show_detection)
	assert_true(shell.map_view.map.get_node("Detection").visible)
