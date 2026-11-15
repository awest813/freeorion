extends GutTest
## Placing production on the map from the production screen.

const FakeSource := preload("res://test/unit/fake_production_source.gd")


func test_place_on_ringed_systems():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(2)
	(
		shell
		. map_view
		. map
		. set_snapshot(
			{
				"system_ids": PackedInt32Array([11, 12, 13]),
				"system_positions":
				PackedVector2Array([Vector2.ZERO, Vector2(200, 0), Vector2(400, 0)]),
				"system_star_types": PackedInt32Array([1, 2, 3]),
				"lanes": PackedInt32Array([0, 1, 1, 2]),
			},
			PackedStringArray(["A", "B", "C"]),
			PackedColorArray()
		)
	)
	var fake := FakeSource.new()
	shell.production_screen.source = fake
	var item: Dictionary = fake.buildable[2]
	shell.show_screen("production")
	shell.map_modes.start_placement(item, fake.get_item_locations(item))
	assert_eq(shell.active_screen, "", "Back on the map")
	assert_true(shell.map_modes.banner.visible)
	assert_true(shell.map_view.map.is_highlighted(12))
	shell.map_view.map.system_clicked.emit(12)
	shell.map_view.map.system_clicked.emit(12)
	assert_eq(fake.calls, [["enqueue", "Scout", 102], ["enqueue", "Scout", 102]])
	assert_string_contains(shell.map_modes.banner_text(), "2")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	shell._unhandled_key_input(escape)
	assert_false(shell.map_modes.is_placing())
	assert_false(shell.map_view.map.is_highlighted(12))
	assert_eq(shell.active_screen, "production", "Back to the queue after queuing")


func test_other_screens_end_placing():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(2)
	shell.map_modes.start_placement({"label": "Scout", "build_type": "ship"}, [])
	shell.show_screen("research")
	assert_false(shell.map_modes.is_placing())
	assert_false(shell.map_modes.banner.visible)
