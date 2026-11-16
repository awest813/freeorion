extends GutTest
## Fleets on the map: markers picked by clicking (beside the star, stacked),
## the paths of moving fleets, and a route preview.

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
				"fleet_ids": PackedInt32Array([10, 11, 12]),
				"fleet_positions":
				PackedVector2Array([Vector2(0, 0), Vector2(0, 0), Vector2(300, 0)]),
				"fleet_owner_ids": PackedInt32Array([1, 2, 1]),
				"fleet_paths":
				[
					PackedVector2Array(),
					PackedVector2Array(),
					PackedVector2Array([Vector2(300, 0), Vector2(450, 0), Vector2(600, 0)]),
				],
				"fleet_turn_ends":
				[PackedVector2Array(), PackedVector2Array(), PackedVector2Array([Vector2(450, 0)])],
			},
			PackedStringArray(["A", "B"]),
			PackedColorArray([Color.BLUE, Color.RED, Color.BLUE])
		)
	)


func _px() -> float:
	return 1.0 / shell.map_view.map.camera.zoom_level()


func _click(world: Vector2) -> void:
	var map := shell.map_view.map
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = map.camera.world_to_screen(world)
	map._unhandled_input(press)


func test_stacked_markers_are_picked_apart():
	var fleets := shell.map_view.map.fleets
	assert_eq(fleets.fleet_count(), 3)
	var first := fleets.marker_of(10, _px())
	var second := fleets.marker_of(11, _px())
	assert_ne(first, second, "fleets at one star are stacked")
	assert_eq(fleets.pick(first, _px()), 10)
	assert_eq(fleets.pick(second, _px()), 11)
	assert_eq(fleets.pick(Vector2(200, 200), _px()), -1)


func test_clicking_a_marker_emits_not_the_system():
	var map := shell.map_view.map
	watch_signals(map)
	_click(map.fleets.marker_of(11, _px()))
	assert_signal_emitted_with_parameters(map, "fleet_clicked", [11])
	assert_signal_not_emitted(map, "system_clicked")
	_click(Vector2(0, 0) + Vector2(-6, 6) * _px())
	assert_signal_emitted_with_parameters(map, "system_clicked", [1])


func test_moving_fleets_have_paths():
	var fleets := shell.map_view.map.fleets
	assert_eq(fleets.path_of(12).size(), 3)
	assert_true(fleets.path_of(10).is_empty())


func test_route_preview():
	var fleets := shell.map_view.map.fleets
	fleets.set_preview(
		PackedVector2Array([Vector2(0, 0), Vector2(600, 0)]), PackedVector2Array(), "3 turns"
	)
	assert_eq(fleets.preview_label(), "3 turns")
	fleets.set_preview(PackedVector2Array(), PackedVector2Array(), "x")
	assert_eq(fleets.preview_label(), "", "no label without a path")
	assert_false(fleets.is_preview_warning())
	fleets.set_preview(
		PackedVector2Array([Vector2(0, 0), Vector2(600, 0)]),
		PackedVector2Array(),
		tr("MOVE_PROBLEM_NO_ROUTE_SHORT"),
		PackedInt32Array(),
		PackedInt32Array(),
		true
	)
	assert_true(fleets.is_preview_warning(), "drawn in the warning colour")
	assert_eq(fleets.preview_label(), tr("MOVE_PROBLEM_NO_ROUTE_SHORT"))


func test_selected_and_box_marked_fleets():
	var fleets := shell.map_view.map.fleets
	fleets.selected_fleet = 12
	shell.map_view.map.set_marked_fleets(PackedInt32Array([10]))
	assert_true(fleets._marked.has(10))
	assert_eq(
		shell.map_view.map.fleets_in_rect(Rect2(-10, -10, 400, 20), 1), PackedInt32Array([10, 12])
	)


func test_places_to_settle_are_marked():
	var fleets := shell.map_view.map.fleets
	fleets.set_settle_marks([{"position": Vector2(10, 10), "text": "population 8.0 · 3 turns"}])
	assert_eq(fleets.settle_marks().size(), 1)
	await wait_process_frames(1)  # draws without errors
	fleets.set_settle_marks([])
	assert_eq(fleets.settle_marks(), [])
