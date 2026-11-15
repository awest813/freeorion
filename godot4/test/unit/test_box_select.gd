extends GutTest
## Dragging a box on the map selects own fleets together.

var shell: GameShell


func before_each():
	shell = GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(2)
	(
		shell
		. map_view
		. map
		. set_snapshot(
			{
				"system_ids": PackedInt32Array([1, 2]),
				"system_positions": PackedVector2Array([Vector2(0, 0), Vector2(600, 0)]),
				"system_star_types": PackedInt32Array([1, 2]),
				"lanes": PackedInt32Array([0, 1]),
				"fleet_ids": PackedInt32Array([10, 11, 12, 13]),
				"fleet_positions":
				PackedVector2Array(
					[Vector2(0, 0), Vector2(0, 0), Vector2(300, 40), Vector2(600, 0)]
				),
				"fleet_owner_ids": PackedInt32Array([1, 1, 2, 1]),
			},
			PackedStringArray(["A", "B"]),
			PackedColorArray([Color.BLUE, Color.BLUE, Color.RED, Color.BLUE])
		)
	)
	shell.map_view.map.own_empire_id = 1


func _drag(from_world: Vector2, to_world: Vector2) -> void:
	var map := shell.map_view.map
	var from := map.camera.world_to_screen(from_world)
	var to := map.camera.world_to_screen(to_world)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	map._unhandled_input(press)
	for step in [0.5, 1.0]:
		var motion := InputEventMouseMotion.new()
		motion.position = from.lerp(to, step)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		map._unhandled_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = to
	map._unhandled_input(release)


func test_fleets_in_rect_and_ownership():
	var map := shell.map_view.map
	assert_eq(map.fleets_in_rect(Rect2(-10, -10, 400, 100)), PackedInt32Array([10, 11, 12]))
	assert_eq(map.fleets_in_rect(Rect2(-10, -10, 400, 100), 1), PackedInt32Array([10, 11]))


func test_box_selects_own_fleets_and_esc_clears():
	_drag(Vector2(-200, -150), Vector2(400, 150))
	assert_eq(shell.map_modes.selected_fleets, PackedInt32Array([10, 11]), "Not the other empire's")
	assert_true(shell.map_view.map.fleets._marked.has(10))
	assert_true(shell.map_modes.banner.visible)
	assert_string_contains(shell.map_modes.banner_text(), "2")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	shell._unhandled_key_input(escape)
	assert_eq(shell.map_modes.selected_fleets.size(), 0)
	assert_false(shell.map_modes.banner.visible)


func test_a_short_press_is_no_box():
	var map := shell.map_view.map
	watch_signals(map)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = map.camera.world_to_screen(Vector2(300, -200))
	map._unhandled_input(press)
	var release := press.duplicate()
	release.pressed = false
	map._unhandled_input(release)
	assert_signal_not_emitted(map, "fleets_boxed")


func test_a_box_can_start_over_a_field():
	var map := shell.map_view.map
	var snapshot := {
		"system_ids": PackedInt32Array([1]),
		"system_positions": PackedVector2Array([Vector2(0, 0)]),
		"system_star_types": PackedInt32Array([1]),
		"lanes": PackedInt32Array(),
		"fleet_ids": PackedInt32Array([10]),
		"fleet_positions": PackedVector2Array([Vector2(0, 0)]),
		"fleet_owner_ids": PackedInt32Array([1]),
		"field_ids": PackedInt32Array([7]),
		"field_positions": PackedVector2Array([Vector2(0, 0)]),
		"field_radii": PackedFloat32Array([400.0]),
		"field_types": PackedStringArray(["FLD_NEBULA_1"]),
	}
	map.set_snapshot(snapshot, PackedStringArray(["A"]), PackedColorArray([Color.BLUE]))
	watch_signals(map)
	_drag(Vector2(-200, -150), Vector2(150, 150))
	assert_signal_not_emitted(map, "field_activated")
	assert_signal_emitted(map, "fleets_boxed")
